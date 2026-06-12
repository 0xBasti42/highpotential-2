// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";

import { HPDepositConverter } from "@src/wallets/HPDepositConverter.sol";
import { HPDepositRouter } from "@src/wallets/HPDepositRouter.sol";
import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { IAerodromeRouter } from "@src/wallets/interfaces/IAerodromeRouter.sol";

import { MockERC20 } from "./HPDepositRouter.t.sol";
import { MockEntryPoint } from "./HPPaymaster.t.sol";
import { WalletTestBase } from "./WalletTestBase.sol";

/// @dev Mimics the real Aerodrome Router's observable behavior for `swapExactTokensForETH`:
///      pulls `amountIn` of the route's first token from the caller, enforces `amountOutMin`,
///      and sends ETH (priced at a configurable rate) to `to`. Reverts on a WETH-terminal
///      violation like the real router does.
contract MockAerodromeRouter is IAerodromeRouter {
    address public immutable weth;

    /// @dev ETH wei sent per whole 1e18 unit of input token.
    uint256 public rateWeiPerToken;

    error InsufficientOutputAmount();
    error InvalidPath();

    constructor(address weth_) {
        weth = weth_;
    }

    receive() external payable { }

    function setRate(uint256 weiPerToken) external {
        rateWeiPerToken = weiPerToken;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        if (routes[routes.length - 1].to != weth) revert InvalidPath();

        uint256 ethOut = (amountIn * rateWeiPerToken) / 1e18;
        if (ethOut < amountOutMin) revert InsufficientOutputAmount();

        ERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        (bool ok,) = to.call{ value: ethOut }("");
        require(ok, "eth transfer failed");

        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        amounts[routes.length] = ethOut;
    }
}

/// @dev Mimics Spark's PSM3 for the USDS -> USDC leg: 1:1 value conversion with the 18 -> 6
///      decimal rescale (divide by 1e12), pushed to `receiver`.
contract MockPSM3 {
    uint256 internal constant DECIMAL_SCALE = 1e12;

    function swapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        uint256
    ) external returns (uint256 amountOut) {
        amountOut = amountIn / DECIMAL_SCALE;
        require(amountOut >= minAmountOut, "PSM3/amountOut-too-low");

        ERC20(assetIn).transferFrom(msg.sender, address(this), amountIn);
        if (amountOut != 0) {
            ERC20(assetOut).transfer(receiver, amountOut);
        }
    }
}

/// @dev USDC-style 6-decimal mock for the PSM leg's output side.
contract MockERC20Dec6 is ERC20 {
    constructor() ERC20("USD Coin", "USDC") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract HPDepositConverterTest is WalletTestBase {
    uint256 internal constant SKIM_BPS = 50; // 0.5%
    uint256 internal constant AERO_RATE = 0.0005 ether; // wei per 1e18 input units

    HPDepositConverter internal converter;
    MockAerodromeRouter internal aero;
    MockPSM3 internal psm;

    MockERC20 internal cbbtcToken; // pure Aerodrome single-hop
    MockERC20 internal tgbpToken; //  pure Aerodrome multi-hop (TGBP -> USDC -> WETH)
    MockERC20 internal usdsToken; //  PSM pre-hop (USDS -> USDC), then Aerodrome
    MockERC20Dec6 internal usdcToken;

    address internal routerStub = makeAddr("routerStub");
    address internal wethAddr;

    function setUp() public override {
        super.setUp();

        wethAddr = weth; // base harness placeholder; only used as a route terminal marker

        converter = new HPDepositConverter(address(provider));
        aero = new MockAerodromeRouter(wethAddr);
        psm = new MockPSM3();

        cbbtcToken = new MockERC20("Coinbase Wrapped BTC", "cbBTC");
        tgbpToken = new MockERC20("TrueGBP", "TGBP");
        usdsToken = new MockERC20("Sky USD", "USDS");
        usdcToken = new MockERC20Dec6();

        vm.startPrank(admin);
        provider.registerName("AERODROME_ROUTER", address(aero));
        provider.registerName("PSM3", address(psm));
        provider.registerName("DEPOSIT_ROUTER", routerStub);
        vm.stopPrank();

        aero.setRate(AERO_RATE);
        vm.deal(address(aero), 1000 ether);
        // PSM holds USDC inventory to push out on swaps (1e12 USDC at 6 decimals).
        usdcToken.mint(address(psm), 1e18);

        // Routes: cbBTC -> WETH | TGBP -> USDC -> WETH | USDS --PSM--> USDC -> WETH
        vm.startPrank(admin);
        converter.setRoute(address(cbbtcToken), address(0), _singleHop(address(cbbtcToken)));
        converter.setRoute(address(tgbpToken), address(0), _twoHop(address(tgbpToken), address(usdcToken)));
        converter.setRoute(address(usdsToken), address(usdcToken), _singleHop(address(usdcToken)));
        vm.stopPrank();
    }

    // --------------------------------------------
    //  Route helpers
    // --------------------------------------------

    function _singleHop(address from) internal view returns (IAerodromeRouter.Route[] memory routes) {
        routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route(from, wethAddr, false, address(0));
    }

    function _twoHop(address from, address mid) internal view returns (IAerodromeRouter.Route[] memory routes) {
        routes = new IAerodromeRouter.Route[](2);
        routes[0] = IAerodromeRouter.Route(from, mid, false, address(0));
        routes[1] = IAerodromeRouter.Route(mid, wethAddr, false, address(0));
    }

    function _convertAs(
        address caller,
        address token,
        uint256 amount,
        uint256 minEthOut
    ) internal returns (uint256 ethOut) {
        vm.startPrank(caller);
        ERC20(token).approve(address(converter), amount);
        ethOut = converter.convertToEth(token, amount, minEthOut);
        vm.stopPrank();
    }

    // --------------------------------------------
    //  Conversion paths
    // --------------------------------------------

    function test_convertToEth_pureAerodromePath() public {
        uint256 amount = 10e18;
        uint256 expectedEth = (amount * AERO_RATE) / 1e18;

        cbbtcToken.mint(routerStub, amount);
        uint256 ethOut = _convertAs(routerStub, address(cbbtcToken), amount, expectedEth);

        assertEq(ethOut, expectedEth);
        assertEq(routerStub.balance, expectedEth);
        // No value rests in the converter, approvals fully reset.
        assertEq(address(converter).balance, 0);
        assertEq(cbbtcToken.balanceOf(address(converter)), 0);
        assertEq(cbbtcToken.allowance(address(converter), address(aero)), 0);
    }

    function test_convertToEth_multiHopRoutePullsFirstToken() public {
        uint256 amount = 200e18;

        tgbpToken.mint(routerStub, amount);
        uint256 ethOut = _convertAs(routerStub, address(tgbpToken), amount, 0);

        assertEq(ethOut, (amount * AERO_RATE) / 1e18);
        assertEq(tgbpToken.balanceOf(address(aero)), amount);
    }

    function test_convertToEth_psmPathConvertsThenSwaps() public {
        uint256 amount = 1000e18; // USDS, 18 decimals
        uint256 usdcOut = amount / 1e12; // 1000e6 USDC
        uint256 expectedEth = (usdcOut * AERO_RATE) / 1e18;

        usdsToken.mint(routerStub, amount);
        uint256 ethOut = _convertAs(routerStub, address(usdsToken), amount, expectedEth);

        assertEq(ethOut, expectedEth);
        assertEq(routerStub.balance, expectedEth);
        // USDS consumed by the PSM, USDC consumed by Aerodrome, both approvals reset.
        assertEq(usdsToken.balanceOf(address(psm)), amount);
        assertEq(usdcToken.balanceOf(address(aero)), usdcOut);
        assertEq(usdcToken.balanceOf(address(converter)), 0);
        assertEq(usdsToken.allowance(address(converter), address(psm)), 0);
        assertEq(usdcToken.allowance(address(converter), address(aero)), 0);
    }

    function test_convertToEth_psmDustRoundsToZeroAndSkipsSwap() public {
        uint256 amount = 1e11; // below the 1e12 USDS->USDC rescale: PSM outputs zero USDC

        usdsToken.mint(routerStub, amount);
        uint256 ethOut = _convertAs(routerStub, address(usdsToken), amount, 0);

        assertEq(ethOut, 0);
        assertEq(routerStub.balance, 0);
    }

    function test_convertToEth_slippageBubblesFromAerodrome() public {
        uint256 amount = 10e18;
        uint256 fairEth = (amount * AERO_RATE) / 1e18;

        cbbtcToken.mint(routerStub, amount);
        vm.startPrank(routerStub);
        cbbtcToken.approve(address(converter), amount);
        vm.expectRevert(MockAerodromeRouter.InsufficientOutputAmount.selector);
        converter.convertToEth(address(cbbtcToken), amount, fairEth + 1);
        vm.stopPrank();
    }

    // --------------------------------------------
    //  Guards
    // --------------------------------------------

    function test_convertToEth_revertsForNonRouterCaller() public {
        cbbtcToken.mint(address(this), 1e18);
        cbbtcToken.approve(address(converter), 1e18);

        vm.expectRevert(HPDepositConverter.NotDepositRouter.selector);
        converter.convertToEth(address(cbbtcToken), 1e18, 0);
    }

    function test_convertToEth_revertsForUnroutedToken() public {
        MockERC20 rogue = new MockERC20("Rogue", "RGE");
        rogue.mint(routerStub, 1e18);

        vm.startPrank(routerStub);
        rogue.approve(address(converter), 1e18);
        vm.expectRevert(abi.encodeWithSelector(HPDepositConverter.RouteNotConfigured.selector, address(rogue)));
        converter.convertToEth(address(rogue), 1e18, 0);
        vm.stopPrank();
    }

    function test_convertToEth_revertsForZeroAmount() public {
        vm.prank(routerStub);
        vm.expectRevert(HPDepositConverter.ZeroAmount.selector);
        converter.convertToEth(address(cbbtcToken), 0, 0);
    }

    // --------------------------------------------
    //  Route administration
    // --------------------------------------------

    function test_setRoute_adminOnly() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(HPDepositConverter.NotAdmin.selector);
        converter.setRoute(address(cbbtcToken), address(0), _singleHop(address(cbbtcToken)));
    }

    function test_setRoute_validatesShape() public {
        vm.startPrank(admin);

        vm.expectRevert(HPDepositConverter.ZeroToken.selector);
        converter.setRoute(address(0), address(0), _singleHop(address(cbbtcToken)));

        vm.expectRevert(HPDepositConverter.RouteMismatch.selector);
        converter.setRoute(address(usdsToken), address(usdsToken), _singleHop(address(usdsToken)));

        vm.expectRevert(HPDepositConverter.EmptyRoute.selector);
        converter.setRoute(address(cbbtcToken), address(0), new IAerodromeRouter.Route[](0));

        // First hop must start from the token (or the psmAsset when one is set).
        vm.expectRevert(HPDepositConverter.RouteMismatch.selector);
        converter.setRoute(address(cbbtcToken), address(0), _singleHop(address(tgbpToken)));

        // Final hop must end in WETH.
        IAerodromeRouter.Route[] memory notWeth = new IAerodromeRouter.Route[](1);
        notWeth[0] = IAerodromeRouter.Route(address(cbbtcToken), address(usdcToken), false, address(0));
        vm.expectRevert(HPDepositConverter.RouteMismatch.selector);
        converter.setRoute(address(cbbtcToken), address(0), notWeth);

        // Hops must be contiguous.
        IAerodromeRouter.Route[] memory broken = new IAerodromeRouter.Route[](2);
        broken[0] = IAerodromeRouter.Route(address(cbbtcToken), address(usdcToken), false, address(0));
        broken[1] = IAerodromeRouter.Route(address(tgbpToken), wethAddr, false, address(0));
        vm.expectRevert(HPDepositConverter.RouteMismatch.selector);
        converter.setRoute(address(cbbtcToken), address(0), broken);

        vm.stopPrank();
    }

    function test_setRoute_replacesExistingRoute() public {
        vm.prank(admin);
        converter.setRoute(address(cbbtcToken), address(0), _twoHop(address(cbbtcToken), address(usdcToken)));

        (bool enabled, address psmAsset, IAerodromeRouter.Route[] memory route) =
            converter.getRoute(address(cbbtcToken));
        assertTrue(enabled);
        assertEq(psmAsset, address(0));
        assertEq(route.length, 2);
        assertEq(route[1].from, address(usdcToken));
    }

    function test_removeRoute_delists() public {
        assertTrue(converter.isConvertible(address(cbbtcToken)));

        vm.prank(admin);
        converter.removeRoute(address(cbbtcToken));

        assertFalse(converter.isConvertible(address(cbbtcToken)));
        (bool enabled,, IAerodromeRouter.Route[] memory route) = converter.getRoute(address(cbbtcToken));
        assertFalse(enabled);
        assertEq(route.length, 0);
    }

    // --------------------------------------------
    //  End-to-end through the real deposit router
    // --------------------------------------------

    /// @dev Full pipeline with the real router + paymaster: depositToken(USDS) -> converter
    ///      (PSM leg + Aerodrome leg) -> paymaster gas credit, principal forwarded in-kind.
    function test_endToEnd_usdsDepositCreditsGasViaPsmAndAerodrome() public {
        MockEntryPoint entryPoint = new MockEntryPoint();
        HPPaymaster paymaster = new HPPaymaster(address(provider), address(entryPoint));
        HPDepositRouter router = new HPDepositRouter(address(provider), SKIM_BPS);

        vm.startPrank(admin);
        provider.registerName("PAYMASTER", address(paymaster));
        provider.registerName("DEPOSIT_CONVERTER", address(converter));
        provider.setName("DEPOSIT_ROUTER", address(router));
        vm.stopPrank();

        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        address user = makeAddr("user");

        uint256 amount = 10_000e18;
        uint256 skim = (amount * SKIM_BPS) / 10_000; // 50e18 USDS
        uint256 expectedEth = ((skim / 1e12) * AERO_RATE) / 1e18;

        usdsToken.mint(user, amount);
        vm.startPrank(user);
        usdsToken.approve(address(router), amount);
        router.depositToken(address(usdsToken), amount, address(wallet), expectedEth);
        vm.stopPrank();

        assertEq(paymaster.gasCredit(address(wallet)), expectedEth);
        assertEq(usdsToken.balanceOf(address(wallet)), amount - skim);
        assertEq(address(converter).balance, 0);
        assertEq(usdsToken.balanceOf(address(converter)), 0);
    }
}
