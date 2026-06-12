// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "@solady/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { AddressBook } from "@core/AddressBook.sol";

import { IAerodromeRouter } from "./interfaces/IAerodromeRouter.sol";
import { IDepositConverter } from "./interfaces/IDepositConverter.sol";
import { IPSM3 } from "./interfaces/IPSM3.sol";

/// @title HPDepositConverter
/// @notice Aerodrome-backed implementation of the deposit router's swap leg. Converts allowlisted
///         ERC-20s into native ETH via admin-configured routes, with an optional PSM3 pre-hop for
///         assets whose canonical liquidity path is a 1:1 peg module rather than a DEX pool
///         (e.g. USDS -> USDC via Spark's PSM3, then USDC -> ETH via Aerodrome).
/// @dev Trust model: the route table here is the platform's Swap-class allowlist (the router asks
///      `isConvertible` during classification), but the converter is NOT trusted for output
///      accounting — HPDepositRouter re-verifies `minEthOut` against its own balance delta. Listing
///      a new token (e.g. a future IGBP/SGBP stablecoin) is a `setRoute` call; no redeploys.
///
///      Per-call hygiene: allowances granted to the PSM/Aerodrome are reset to zero before
///      returning, and the full ETH balance is forwarded to the caller so no value rests here
///      between calls. `convertToEth` is gated to the registered DEPOSIT_ROUTER so the route
///      config and approvals cannot be borrowed as a public swap utility.
contract HPDepositConverter is IDepositConverter, AddressBook, ReentrancyGuard {
    using SafeTransferLib for address;

    // --------------------------------------------
    //  Route configuration
    // --------------------------------------------

    struct RouteConfig {
        bool enabled;
        /// @dev Non-zero enables a PSM3 pre-hop: `token` is first swapped 1:1 into `psmAsset`
        ///      (e.g. USDS -> USDC), and the Aerodrome route then starts from `psmAsset`.
        address psmAsset;
        /// @dev Aerodrome classic route. Final hop's `to` must be WETH — enforced at config time —
        ///      because `swapExactTokensForETH` unwraps the WETH leg into native ETH itself.
        IAerodromeRouter.Route[] aeroRoute;
    }

    mapping(address token => RouteConfig) internal _routes;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event RouteConfigured(address indexed token, address indexed psmAsset, uint256 hops);
    event RouteRemoved(address indexed token);

    error NotAdmin();
    error NotDepositRouter();
    error ZeroToken();
    error ZeroAmount();
    error RouteNotConfigured(address token);
    error EmptyRoute();
    error RouteMismatch();
    error EthTransferFailed();

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    /// @dev Admin = holder of the AddressProvider's DEFAULT_ADMIN_ROLE (same pattern as the router
    ///      and paymaster).
    modifier onlyAdmin() {
        if (!addressProvider.hasRole(bytes32(0), msg.sender)) revert NotAdmin();
        _;
    }

    constructor(address addressProvider_) AddressBook(addressProvider_) { }

    /// @dev Receives native ETH from Aerodrome's `swapExactTokensForETH` unwrap.
    receive() external payable { }

    // --------------------------------------------
    //  Conversion
    // --------------------------------------------

    /// @inheritdoc IDepositConverter
    /// @dev The PSM leg passes `minAmountOut = 0` deliberately: PSM3 is a slippage-free 1:1 module,
    ///      and the terminal slippage bound is enforced twice downstream — `minEthOut` is passed to
    ///      Aerodrome here AND independently re-checked by the router via balance delta — so an
    ///      intermediate bound would add a revert surface without adding protection.
    function convertToEth(
        address token,
        uint256 amount,
        uint256 minEthOut
    ) external nonReentrant returns (uint256 ethOut) {
        if (msg.sender != _getAddress(_addressKey("DEPOSIT_ROUTER"))) revert NotDepositRouter();
        if (amount == 0) revert ZeroAmount();

        RouteConfig storage config = _routes[token];
        if (!config.enabled) revert RouteNotConfigured(token);

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 swapIn = amount;
        address swapToken = token;

        if (config.psmAsset != address(0)) {
            address psm = _getAddress(_addressKey("PSM3"));
            token.safeApprove(psm, amount);
            swapIn = IPSM3(psm).swapExactIn(token, config.psmAsset, amount, 0, address(this), 0);
            token.safeApprove(psm, 0);
            swapToken = config.psmAsset;
        }

        // `swapIn` can round to zero through the PSM on dust amounts (e.g. sub-1e12 wei of
        // 18-decimal USDS rescaled to 6-decimal USDC). Skip the swap rather than revert; the
        // router treats a zero delta as "nothing to credit" (and still enforces minEthOut).
        if (swapIn != 0) {
            address aero = _getAddress(_addressKey("AERODROME_ROUTER"));
            swapToken.safeApprove(aero, swapIn);
            IAerodromeRouter(aero)
                .swapExactTokensForETH(swapIn, minEthOut, config.aeroRoute, address(this), block.timestamp);
            swapToken.safeApprove(aero, 0);
        }

        // Forward the full balance (not just this conversion's output) so no ETH ever rests here.
        // Stray donations end up as extra gas credit for the depositing wallet — harmless.
        ethOut = address(this).balance;
        if (ethOut != 0) {
            (bool ok,) = msg.sender.call{ value: ethOut }("");
            if (!ok) revert EthTransferFailed();
        }
    }

    // --------------------------------------------
    //  Views
    // --------------------------------------------

    /// @inheritdoc IDepositConverter
    function isConvertible(address token) external view returns (bool) {
        return _routes[token].enabled;
    }

    function getRoute(address token)
        external
        view
        returns (bool enabled, address psmAsset, IAerodromeRouter.Route[] memory aeroRoute)
    {
        RouteConfig storage config = _routes[token];
        return (config.enabled, config.psmAsset, config.aeroRoute);
    }

    // --------------------------------------------
    //  Administration
    // --------------------------------------------

    /// @notice Configures (or replaces) the conversion route for `token`. Listing here is what makes
    ///         a token Swap-class in the deposit router.
    /// @param psmAsset Zero for a pure Aerodrome route; non-zero to first convert `token` into
    ///        `psmAsset` through PSM3 (the Aerodrome route must then start from `psmAsset`).
    /// @param aeroRoute Aerodrome hops. Validated for continuity, correct starting token, and a
    ///        WETH-terminal hop (required by `swapExactTokensForETH`).
    function setRoute(address token, address psmAsset, IAerodromeRouter.Route[] calldata aeroRoute) external onlyAdmin {
        if (token == address(0)) revert ZeroToken();
        if (psmAsset == token) revert RouteMismatch();
        if (aeroRoute.length == 0) revert EmptyRoute();

        address expectedStart = psmAsset == address(0) ? token : psmAsset;
        if (aeroRoute[0].from != expectedStart) revert RouteMismatch();
        if (aeroRoute[aeroRoute.length - 1].to != _getAddress(_addressKey("WETH"))) revert RouteMismatch();
        for (uint256 i = 1; i < aeroRoute.length; ++i) {
            if (aeroRoute[i].from != aeroRoute[i - 1].to) revert RouteMismatch();
        }

        RouteConfig storage config = _routes[token];
        config.enabled = true;
        config.psmAsset = psmAsset;
        delete config.aeroRoute;
        for (uint256 i; i < aeroRoute.length; ++i) {
            config.aeroRoute.push(aeroRoute[i]);
        }

        emit RouteConfigured(token, psmAsset, aeroRoute.length);
    }

    /// @notice Delists `token` from the deposit allowlist and clears its route.
    function removeRoute(address token) external onlyAdmin {
        delete _routes[token];
        emit RouteRemoved(token);
    }
}
