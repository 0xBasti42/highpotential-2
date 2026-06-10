// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { AddressBook } from "@core/AddressBook.sol";
import { SETH } from "@src/seth/SETH.sol";

import { HPPaymaster } from "./HPPaymaster.sol";
import { IDepositConverter } from "./interfaces/IDepositConverter.sol";

interface IWETH9 {
    function withdraw(uint256 amount) external;
}

/// @title HPDepositRouter
/// @notice Entry point for user deposits. Skims a small admin-configured percentage of every deposit, converts
///         it to native ETH, and funds the user's gas credit in `HPPaymaster`; the remaining principal is
///         forwarded to the user's HPSmartWallet untouched (in the deposited asset).
/// @dev Conversion branches for the skim:
///      - native ETH:        no conversion
///      - WETH9:             unwrap (1:1, riskless)
///      - SETH:              redeem at the wrapper's fixed 100:1 rate (no pool, no slippage)
///      - other allowlisted: swap via the DEPOSIT_CONVERTER (e.g. Uniswap V4 routes; TGBP multi-hops via USDC)
///      The allowlist is the AddressProvider token key set — no duplicated state. `minEthOut` is enforced by
///      the router itself via balance delta, so the converter is not trusted for output accounting.
contract HPDepositRouter is AddressBook {
    using SafeTransferLib for address;

    // --------------------------------------------
    //  Configuration
    // --------------------------------------------

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @dev Hard cap on the skim (5%) so a compromised admin key cannot redirect deposits wholesale.
    uint256 public constant MAX_SKIM_BPS = 500;

    /// @notice Portion of every deposit converted into gas credit, in basis points.
    uint256 public skimBps;

    enum TokenClass {
        Unwrap, // WETH9
        Redeem, // SETH
        Swap // all other allowlisted ERC-20s

    }

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event DepositProcessed(
        address indexed wallet, address indexed token, uint256 amountIn, uint256 ethSkimmed, uint256 netForwarded
    );
    event SkimBpsUpdated(uint256 previous, uint256 current);

    error NotAdmin();
    error ZeroWallet();
    error ZeroAmount();
    error TokenNotAllowed(address token);
    error SkimTooHigh(uint256 bps);
    error InsufficientEthOut(uint256 actual, uint256 minimum);
    error EthTransferFailed();

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    /// @dev Admin = holder of the AddressProvider's DEFAULT_ADMIN_ROLE (same pattern as HPPaymaster).
    modifier onlyAdmin() {
        if (!addressProvider.hasRole(bytes32(0), msg.sender)) revert NotAdmin();
        _;
    }

    constructor(address addressProvider_, uint256 skimBps_) AddressBook(addressProvider_) {
        _setSkimBps(skimBps_);
    }

    /// @dev Receives native ETH from WETH unwraps, SETH redemptions, and converter swaps.
    receive() external payable { }

    // --------------------------------------------
    //  Deposits
    // --------------------------------------------

    /// @notice Native ETH deposit: skim funds gas credit directly, remainder forwarded to `wallet`.
    /// @dev `wallet` may be a counterfactual HPSmartWallet address (both legs work pre-deployment).
    function depositNative(address wallet) external payable {
        if (wallet == address(0)) revert ZeroWallet();
        if (msg.value == 0) revert ZeroAmount();

        uint256 skim = (msg.value * skimBps) / BPS_DENOMINATOR;
        uint256 net = msg.value - skim;

        if (skim != 0) {
            _paymaster().depositFor{ value: skim }(wallet);
        }

        (bool ok,) = wallet.call{ value: net }("");
        if (!ok) revert EthTransferFailed();

        emit DepositProcessed(wallet, address(0), msg.value, skim, net);
    }

    /// @notice ERC-20 deposit: the skim is converted to native ETH (unwrap / redeem / swap depending on the
    ///         token) and funds gas credit; the remaining principal is forwarded to `wallet` in-kind.
    /// @param minEthOut Lower bound on the ETH received for the skim (slippage protection on the swap path;
    ///        pass the UI quote minus tolerance). May be 0 for the deterministic WETH/SETH paths.
    function depositToken(address token, uint256 amount, address wallet, uint256 minEthOut) external {
        if (wallet == address(0)) revert ZeroWallet();
        if (amount == 0) revert ZeroAmount();

        TokenClass class = _classify(token);

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 skim = (amount * skimBps) / BPS_DENOMINATOR;

        // SETH redeems in whole multiples of its exchange rate; a sub-rate skim cannot convert, so waive it.
        if (class == TokenClass.Redeem && skim < SETH(payable(token)).EXCHANGE_RATE()) {
            skim = 0;
        }

        uint256 net = amount - skim;
        uint256 ethOut;

        if (skim != 0) {
            uint256 balanceBefore = address(this).balance;

            if (class == TokenClass.Unwrap) {
                IWETH9(token).withdraw(skim);
            } else if (class == TokenClass.Redeem) {
                SETH(payable(token)).withdraw(skim);
            } else {
                address converter = _getAddress(_addressKey("DEPOSIT_CONVERTER"));
                token.safeApprove(converter, skim);
                IDepositConverter(converter).convertToEth(token, skim, minEthOut);
                token.safeApprove(converter, 0);
            }

            ethOut = address(this).balance - balanceBefore;
            if (ethOut < minEthOut) revert InsufficientEthOut(ethOut, minEthOut);

            if (ethOut != 0) {
                _paymaster().depositFor{ value: ethOut }(wallet);
            }
        }

        token.safeTransfer(wallet, net);

        emit DepositProcessed(wallet, token, amount, ethOut, net);
    }

    // --------------------------------------------
    //  Administration
    // --------------------------------------------

    function setSkimBps(uint256 newSkimBps) external onlyAdmin {
        _setSkimBps(newSkimBps);
    }

    function _setSkimBps(uint256 newSkimBps) internal {
        if (newSkimBps > MAX_SKIM_BPS) revert SkimTooHigh(newSkimBps);
        emit SkimBpsUpdated(skimBps, newSkimBps);
        skimBps = newSkimBps;
    }

    // --------------------------------------------
    //  Internals
    // --------------------------------------------

    function _paymaster() internal view returns (HPPaymaster) {
        return HPPaymaster(_getAddress(_addressKey("PAYMASTER")));
    }

    /// @dev Allowlist = the AddressProvider token key set (single source of truth, no duplicated state).
    ///      Unset keys (e.g. SETH pre-deployment) resolve to zero and simply never match.
    function _classify(address token) internal view returns (TokenClass) {
        if (token == address(0)) revert TokenNotAllowed(token);

        string[] memory names = new string[](7);
        names[0] = "WETH";
        names[1] = "SETH";
        names[2] = "CBBTC";
        names[3] = "TGBP";
        names[4] = "USDC";
        names[5] = "EURC";
        names[6] = "DAI";

        address[] memory addrs = addressProvider.getManyByName(names);

        if (token == addrs[0]) return TokenClass.Unwrap;
        if (token == addrs[1]) return TokenClass.Redeem;
        for (uint256 i = 2; i < 7; ++i) {
            if (token == addrs[i]) return TokenClass.Swap;
        }

        revert TokenNotAllowed(token);
    }
}
