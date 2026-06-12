// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";

import { SETH } from "@src/seth/SETH.sol";
import { HPDepositRouter } from "@src/wallets/HPDepositRouter.sol";
import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { IDepositConverter } from "@src/wallets/interfaces/IDepositConverter.sol";

import { MockEntryPoint } from "./HPPaymaster.t.sol";
import { WalletTestBase } from "./WalletTestBase.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{ value: amount }("");
        require(ok, "weth transfer failed");
    }
}

/// @dev Returns a configurable amount of ETH regardless of input — lets tests exercise both fair
///      conversion and a misbehaving converter (router must catch the shortfall itself). The
///      `convertible` mapping mirrors the real converter's route table: the router's `_classify`
///      treats it as the Swap-class allowlist via `isConvertible`.
contract MockConverter is IDepositConverter {
    uint256 public ethOut;
    mapping(address token => bool) public convertible;

    receive() external payable { }

    function setEthOut(uint256 value) external {
        ethOut = value;
    }

    function setConvertible(address token, bool allowed) external {
        convertible[token] = allowed;
    }

    function convertToEth(address token, uint256 amount, uint256) external returns (uint256) {
        ERC20(token).transferFrom(msg.sender, address(this), amount);
        (bool ok,) = msg.sender.call{ value: ethOut }("");
        require(ok, "eth transfer failed");
        return ethOut;
    }

    function isConvertible(address token) external view returns (bool) {
        return convertible[token];
    }
}

contract HPDepositRouterTest is WalletTestBase {
    uint256 internal constant SKIM_BPS = 50; // 0.5%

    MockEntryPoint internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPDepositRouter internal router;
    HPSmartWallet internal wallet;

    MockERC20 internal usdcToken;
    MockERC20 internal tgbpToken;
    MockWETH internal wethToken;
    SETH internal sethToken;
    MockConverter internal converter;

    address internal user = makeAddr("user");

    event DepositProcessed(
        address indexed wallet, address indexed token, uint256 amountIn, uint256 ethSkimmed, uint256 netForwarded
    );

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new MockEntryPoint();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));
        router = new HPDepositRouter(address(provider), SKIM_BPS);
        converter = new MockConverter();

        usdcToken = new MockERC20("USD Coin", "USDC");
        tgbpToken = new MockERC20("TrueGBP", "TGBP");
        wethToken = new MockWETH();
        sethToken = new SETH();

        // Swap the base harness's placeholder token addresses for real mock contracts.
        vm.startPrank(admin);
        provider.setName("USDC", address(usdcToken));
        provider.setName("TGBP", address(tgbpToken));
        provider.setName("WETH", address(wethToken));
        provider.registerName("SETH", address(sethToken));
        provider.registerName("PAYMASTER", address(paymaster));
        provider.registerName("DEPOSIT_CONVERTER", address(converter));
        vm.stopPrank();

        // Swap-class membership now lives in the converter's route table, not the provider keys.
        converter.setConvertible(address(usdcToken), true);
        converter.setConvertible(address(tgbpToken), true);

        wallet = _createWallet(ownerEOA, 0);

        vm.deal(user, 1000 ether);
        vm.deal(address(converter), 100 ether);
    }

    // --------------------------------------------
    //  Native ETH path
    // --------------------------------------------

    function test_depositNative_skimsAndForwards() public {
        uint256 amount = 10 ether;
        uint256 skim = (amount * SKIM_BPS) / 10_000; // 0.05 ether

        vm.expectEmit(true, true, false, true, address(router));
        emit DepositProcessed(address(wallet), address(0), amount, skim, amount - skim);

        vm.prank(user);
        router.depositNative{ value: amount }(address(wallet));

        assertEq(paymaster.gasCredit(address(wallet)), skim);
        assertEq(mockEntryPoint.balanceOf(address(paymaster)), skim);
        assertEq(address(wallet).balance, amount - skim);
        assertEq(address(router).balance, 0);
    }

    function test_depositNative_worksForCounterfactualWallet() public {
        address counterfactual = factory.getAddress(_singleOwner(makeAddr("futureUser")), 0);

        vm.prank(user);
        router.depositNative{ value: 1 ether }(counterfactual);

        assertEq(paymaster.gasCredit(counterfactual), 0.005 ether);
        assertEq(counterfactual.balance, 0.995 ether);
    }

    function test_depositNative_zeroSkimForwardsEverything() public {
        vm.prank(admin);
        router.setSkimBps(0);

        vm.prank(user);
        router.depositNative{ value: 1 ether }(address(wallet));

        assertEq(paymaster.gasCredit(address(wallet)), 0);
        assertEq(address(wallet).balance, 1 ether);
    }

    function test_depositNative_revertsForZeroInputs() public {
        vm.prank(user);
        vm.expectRevert(HPDepositRouter.ZeroWallet.selector);
        router.depositNative{ value: 1 ether }(address(0));

        vm.prank(user);
        vm.expectRevert(HPDepositRouter.ZeroAmount.selector);
        router.depositNative(address(wallet));
    }

    // --------------------------------------------
    //  Swap path (USDC / TGBP via converter)
    // --------------------------------------------

    function test_depositToken_swapPathCreditsConvertedEth() public {
        uint256 amount = 1000e18;
        uint256 skim = (amount * SKIM_BPS) / 10_000; // 5e18 tokens
        uint256 ethFromSwap = 0.002 ether;
        converter.setEthOut(ethFromSwap);

        usdcToken.mint(user, amount);
        vm.startPrank(user);
        usdcToken.approve(address(router), amount);
        router.depositToken(address(usdcToken), amount, address(wallet), ethFromSwap);
        vm.stopPrank();

        assertEq(paymaster.gasCredit(address(wallet)), ethFromSwap);
        assertEq(usdcToken.balanceOf(address(wallet)), amount - skim);
        assertEq(usdcToken.balanceOf(address(converter)), skim);
        // Approval is reset after the swap.
        assertEq(usdcToken.allowance(address(router), address(converter)), 0);
    }

    function test_depositToken_tgbpRoutesThroughConverter() public {
        uint256 amount = 200e18;
        converter.setEthOut(0.0003 ether);

        tgbpToken.mint(user, amount);
        vm.startPrank(user);
        tgbpToken.approve(address(router), amount);
        router.depositToken(address(tgbpToken), amount, address(wallet), 0.0003 ether);
        vm.stopPrank();

        assertEq(paymaster.gasCredit(address(wallet)), 0.0003 ether);
        assertEq(tgbpToken.balanceOf(address(wallet)), amount - (amount * SKIM_BPS) / 10_000);
    }

    function test_depositToken_revertsOnSlippage() public {
        uint256 amount = 1000e18;
        converter.setEthOut(0.001 ether); // below the caller's minimum

        usdcToken.mint(user, amount);
        vm.startPrank(user);
        usdcToken.approve(address(router), amount);
        vm.expectRevert(abi.encodeWithSelector(HPDepositRouter.InsufficientEthOut.selector, 0.001 ether, 0.002 ether));
        router.depositToken(address(usdcToken), amount, address(wallet), 0.002 ether);
        vm.stopPrank();
    }

    // --------------------------------------------
    //  WETH unwrap path
    // --------------------------------------------

    function test_depositToken_wethUnwrapsOneToOne() public {
        uint256 amount = 4 ether;
        uint256 skim = (amount * SKIM_BPS) / 10_000; // 0.02 ether

        vm.startPrank(user);
        wethToken.deposit{ value: amount }();
        wethToken.approve(address(router), amount);
        router.depositToken(address(wethToken), amount, address(wallet), skim);
        vm.stopPrank();

        // Unwrap is deterministic: credit equals the skim exactly, no converter involved.
        assertEq(paymaster.gasCredit(address(wallet)), skim);
        assertEq(wethToken.balanceOf(address(wallet)), amount - skim);
    }

    // --------------------------------------------
    //  SETH redeem path
    // --------------------------------------------

    function test_depositToken_sethRedeemsAtFixedRate() public {
        // 1000 SETH = 10 ETH at the 100:1 rate. Skim 0.5% = 5 SETH = 0.05 ETH.
        uint256 amount = 1000e18;
        uint256 skimSeth = (amount * SKIM_BPS) / 10_000;
        uint256 skimEth = skimSeth / sethToken.EXCHANGE_RATE();

        vm.startPrank(user);
        sethToken.deposit{ value: 10 ether }();
        sethToken.approve(address(router), amount);
        router.depositToken(address(sethToken), amount, address(wallet), skimEth);
        vm.stopPrank();

        assertEq(paymaster.gasCredit(address(wallet)), skimEth);
        assertEq(sethToken.balanceOf(address(wallet)), amount - skimSeth);
    }

    function test_depositToken_sethDustSkimIsWaived() public {
        // Skim of 0.5% on 10_000 wei-units = 50 < EXCHANGE_RATE(100): unredeemable, so waived entirely.
        uint256 amount = 10_000;

        vm.startPrank(user);
        sethToken.deposit{ value: 1 ether }();
        sethToken.approve(address(router), amount);
        router.depositToken(address(sethToken), amount, address(wallet), 0);
        vm.stopPrank();

        assertEq(paymaster.gasCredit(address(wallet)), 0);
        assertEq(sethToken.balanceOf(address(wallet)), amount);
    }

    // --------------------------------------------
    //  Allowlist / administration
    // --------------------------------------------

    function test_depositToken_revertsForUnlistedToken() public {
        MockERC20 rogue = new MockERC20("Rogue", "RGE");
        rogue.mint(user, 100e18);

        vm.startPrank(user);
        rogue.approve(address(router), 100e18);
        vm.expectRevert(abi.encodeWithSelector(HPDepositRouter.TokenNotAllowed.selector, address(rogue)));
        router.depositToken(address(rogue), 100e18, address(wallet), 0);
        vm.stopPrank();
    }

    function test_depositToken_revertsForZeroToken() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(HPDepositRouter.TokenNotAllowed.selector, address(0)));
        router.depositToken(address(0), 100e18, address(wallet), 0);
    }

    /// @dev Provider token keys no longer grant Swap class — only the converter's route table does.
    function test_depositToken_revertsWhenConverterDelistsToken() public {
        converter.setConvertible(address(usdcToken), false);

        usdcToken.mint(user, 100e18);
        vm.startPrank(user);
        usdcToken.approve(address(router), 100e18);
        vm.expectRevert(abi.encodeWithSelector(HPDepositRouter.TokenNotAllowed.selector, address(usdcToken)));
        router.depositToken(address(usdcToken), 100e18, address(wallet), 0);
        vm.stopPrank();
    }

    function test_setSkimBps_adminOnlyAndCapped() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(HPDepositRouter.NotAdmin.selector);
        router.setSkimBps(100);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(HPDepositRouter.SkimTooHigh.selector, 501));
        router.setSkimBps(501);

        vm.prank(admin);
        router.setSkimBps(100);
        assertEq(router.skimBps(), 100);
    }

    function test_constructor_revertsAboveSkimCap() public {
        vm.expectRevert(abi.encodeWithSelector(HPDepositRouter.SkimTooHigh.selector, 600));
        new HPDepositRouter(address(provider), 600);
    }
}
