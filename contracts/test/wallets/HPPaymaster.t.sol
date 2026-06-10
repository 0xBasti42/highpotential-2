// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { HPPaymaster } from "@src/wallets/HPPaymaster.sol";
import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPWalletRegistry } from "@src/wallets/HPWalletRegistry.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

/// @dev Minimal v0.6 EntryPoint stand-in: real deposit/stake bookkeeping, no userOp pipeline.
contract MockEntryPoint {
    mapping(address account => uint256 amount) public balanceOf;

    uint256 public stake;
    uint32 public lastUnstakeDelaySec;
    bool public stakeUnlocked;

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function addStake(uint32 unstakeDelaySec) external payable {
        stake += msg.value;
        lastUnstakeDelaySec = unstakeDelaySec;
        stakeUnlocked = false;
    }

    function unlockStake() external {
        stakeUnlocked = true;
    }

    function withdrawStake(address payable to) external {
        uint256 amount = stake;
        stake = 0;
        (bool ok,) = to.call{ value: amount }("");
        require(ok, "stake transfer failed");
    }

    function withdrawTo(address payable to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        (bool ok,) = to.call{ value: amount }("");
        require(ok, "withdraw transfer failed");
    }
}

contract HPPaymasterTest is WalletTestBase {
    MockEntryPoint internal mockEntryPoint;
    HPPaymaster internal paymaster;
    HPSmartWallet internal wallet;

    address internal funder = makeAddr("funder");

    event GasCreditDeposited(address indexed funder, address indexed wallet, uint256 amount);
    event GasCreditUsed(address indexed wallet, uint256 amount);
    event SurplusWithdrawn(address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        mockEntryPoint = new MockEntryPoint();
        paymaster = new HPPaymaster(address(provider), address(mockEntryPoint));

        vm.prank(admin);
        provider.registerName("PAYMASTER", address(paymaster));

        wallet = _createWallet(ownerEOA, 0);
        vm.deal(funder, 100 ether);
    }

    function _sponsoredOp(address sender, uint256 maxFeePerGas) internal pure returns (UserOperation06 memory op) {
        op = _baseUserOp(sender, 0);
        op.maxFeePerGas = maxFeePerGas;
        op.paymasterAndData = "";
    }

    /// @dev Credit needed for `maxCost` at `maxFeePerGas`, including the postOp margin.
    function _required(uint256 maxCost, uint256 maxFeePerGas) internal view returns (uint256) {
        return maxCost + paymaster.POST_OP_GAS() * maxFeePerGas;
    }

    // --------------------------------------------
    //  Construction / wiring
    // --------------------------------------------

    function test_constructor_revertsForZeroEntryPoint() public {
        vm.expectRevert(HPPaymaster.ZeroEntryPoint.selector);
        new HPPaymaster(address(provider), address(0));
    }

    function test_constructor_cachesRegistry() public view {
        assertEq(address(paymaster.registry()), address(registry));
    }

    function test_syncRegistry_followsAddressProvider() public {
        HPWalletRegistry newRegistry = new HPWalletRegistry(address(provider));
        vm.prank(admin);
        provider.setName("WALLET_REGISTRY", address(newRegistry));

        paymaster.syncRegistry();

        assertEq(address(paymaster.registry()), address(newRegistry));
    }

    // --------------------------------------------
    //  Funding
    // --------------------------------------------

    function test_depositFor_creditsWalletAndFundsEntryPoint() public {
        vm.expectEmit(true, true, false, true, address(paymaster));
        emit GasCreditDeposited(funder, address(wallet), 1 ether);

        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        assertEq(paymaster.gasCredit(address(wallet)), 1 ether);
        assertEq(paymaster.totalGasCredit(), 1 ether);
        assertEq(mockEntryPoint.balanceOf(address(paymaster)), 1 ether);
    }

    function test_depositFor_worksForCounterfactualWallet() public {
        // Credits can be funded before the wallet is deployed (address from factory.getAddress).
        address counterfactual = factory.getAddress(_singleOwner(makeAddr("futureUser")), 0);

        vm.prank(funder);
        paymaster.depositFor{ value: 0.5 ether }(counterfactual);

        assertEq(paymaster.gasCredit(counterfactual), 0.5 ether);
    }

    function test_depositFor_revertsForZeroWalletOrValue() public {
        vm.prank(funder);
        vm.expectRevert(HPPaymaster.ZeroWallet.selector);
        paymaster.depositFor{ value: 1 ether }(address(0));

        vm.prank(funder);
        vm.expectRevert(HPPaymaster.ZeroDeposit.selector);
        paymaster.depositFor(address(wallet));
    }

    // --------------------------------------------
    //  validatePaymasterUserOp
    // --------------------------------------------

    function test_validate_acceptsFundedRegisteredWallet() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        UserOperation06 memory op = _sponsoredOp(address(wallet), 1 gwei);

        vm.prank(address(mockEntryPoint));
        (bytes memory context, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), 0.01 ether);

        assertEq(validationData, 0);
        assertEq(abi.decode(context, (address)), address(wallet));
    }

    function test_validate_revertsWhenNotEntryPoint() public {
        UserOperation06 memory op = _sponsoredOp(address(wallet), 1 gwei);

        vm.expectRevert(HPPaymaster.NotEntryPoint.selector);
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0.01 ether);
    }

    function test_validate_revertsForUnregisteredWallet() public {
        address stranger = makeAddr("strangerWallet");
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(stranger);

        UserOperation06 memory op = _sponsoredOp(stranger, 1 gwei);

        vm.prank(address(mockEntryPoint));
        vm.expectRevert(abi.encodeWithSelector(HPPaymaster.WalletNotRegistered.selector, stranger));
        paymaster.validatePaymasterUserOp(op, bytes32(0), 0.01 ether);
    }

    function test_validate_revertsOnInsufficientCredit() public {
        uint256 maxCost = 0.01 ether;
        uint256 maxFeePerGas = 1 gwei;
        uint256 required = _required(maxCost, maxFeePerGas);

        // Fund just below the requirement (maxCost + postOp margin).
        vm.prank(funder);
        paymaster.depositFor{ value: required - 1 }(address(wallet));

        UserOperation06 memory op = _sponsoredOp(address(wallet), maxFeePerGas);

        vm.prank(address(mockEntryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                HPPaymaster.InsufficientGasCredit.selector, address(wallet), required - 1, required
            )
        );
        paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
    }

    function test_validate_acceptsExactRequiredCredit() public {
        uint256 maxCost = 0.01 ether;
        uint256 maxFeePerGas = 1 gwei;
        uint256 required = _required(maxCost, maxFeePerGas);

        vm.prank(funder);
        paymaster.depositFor{ value: required }(address(wallet));

        UserOperation06 memory op = _sponsoredOp(address(wallet), maxFeePerGas);

        vm.prank(address(mockEntryPoint));
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);

        assertEq(validationData, 0);
    }

    // --------------------------------------------
    //  postOp accounting
    // --------------------------------------------

    function test_postOp_deductsActualCostPlusMargin() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        uint256 gasPrice = 1 gwei;
        uint256 actualGasCost = 0.001 ether;
        uint256 expectedCharge = actualGasCost + paymaster.POST_OP_GAS() * gasPrice;

        vm.txGasPrice(gasPrice);
        vm.expectEmit(true, false, false, true, address(paymaster));
        emit GasCreditUsed(address(wallet), expectedCharge);

        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, abi.encode(address(wallet)), actualGasCost);

        assertEq(paymaster.gasCredit(address(wallet)), 1 ether - expectedCharge);
        assertEq(paymaster.totalGasCredit(), 1 ether - expectedCharge);
    }

    function test_postOp_clampsToRemainingCredit() public {
        vm.prank(funder);
        paymaster.depositFor{ value: 0.0001 ether }(address(wallet));

        vm.txGasPrice(1 gwei);
        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, abi.encode(address(wallet)), 1 ether);

        assertEq(paymaster.gasCredit(address(wallet)), 0);
        assertEq(paymaster.totalGasCredit(), 0);
    }

    function test_postOp_revertsWhenNotEntryPoint() public {
        vm.expectRevert(HPPaymaster.NotEntryPoint.selector);
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, abi.encode(address(wallet)), 1);
    }

    // --------------------------------------------
    //  Stake / surplus administration
    // --------------------------------------------

    function test_stakeManagement_adminOnlyAndForwarded() public {
        vm.deal(admin, 10 ether);

        vm.prank(admin);
        paymaster.addStake{ value: 2 ether }(86_400);
        assertEq(mockEntryPoint.stake(), 2 ether);
        assertEq(mockEntryPoint.lastUnstakeDelaySec(), 86_400);

        vm.prank(admin);
        paymaster.unlockStake();
        assertTrue(mockEntryPoint.stakeUnlocked());

        address payable treasury = payable(makeAddr("treasury"));
        vm.prank(admin);
        paymaster.withdrawStake(treasury);
        assertEq(treasury.balance, 2 ether);
    }

    function test_stakeManagement_revertsForNonAdmin() public {
        address stranger = makeAddr("stranger");
        vm.deal(stranger, 1 ether);

        vm.startPrank(stranger);
        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.addStake{ value: 1 ether }(86_400);

        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.unlockStake();

        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.withdrawStake(payable(stranger));

        vm.expectRevert(HPPaymaster.NotAdmin.selector);
        paymaster.withdrawSurplus(payable(stranger), 1);
        vm.stopPrank();
    }

    function test_withdrawSurplus_onlyAboveUserCredits() public {
        // 1 ether of user credit + 0.5 ether of accumulated margin (simulated via postOp clamp profits).
        vm.prank(funder);
        paymaster.depositFor{ value: 1 ether }(address(wallet));

        // Burn 0.5 ether of credit without the EntryPoint deposit decreasing (mock keeps deposit constant),
        // mimicking postOp margins accruing as surplus.
        vm.txGasPrice(0);
        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, abi.encode(address(wallet)), 0.5 ether);

        assertEq(paymaster.surplus(), 0.5 ether);

        // Withdrawing more than the surplus reverts: user credits are untouchable.
        address payable treasury = payable(makeAddr("treasury"));
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(HPPaymaster.WithdrawExceedsSurplus.selector, 0.6 ether, 0.5 ether)
        );
        paymaster.withdrawSurplus(treasury, 0.6 ether);

        vm.prank(admin);
        paymaster.withdrawSurplus(treasury, 0.5 ether);
        assertEq(treasury.balance, 0.5 ether);
        assertEq(paymaster.surplus(), 0);
    }

    // --------------------------------------------
    //  End-to-end sponsorship shape
    // --------------------------------------------

    function test_fullSponsorshipFlow() public {
        // 1. Deposit-skim leg funds the user's gas credit.
        vm.prank(funder);
        paymaster.depositFor{ value: 0.1 ether }(address(wallet));

        // 2. Bundler-side validation succeeds.
        UserOperation06 memory op = _sponsoredOp(address(wallet), 1 gwei);
        uint256 maxCost = 0.005 ether;

        vm.prank(address(mockEntryPoint));
        (bytes memory context,) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);

        // 3. Post-execution accounting charges actual cost (less than maxCost) plus margin.
        uint256 actualGasCost = 0.002 ether;
        vm.txGasPrice(1 gwei);
        vm.prank(address(mockEntryPoint));
        paymaster.postOp(IPaymaster06.PostOpMode.opSucceeded, context, actualGasCost);

        uint256 charged = actualGasCost + paymaster.POST_OP_GAS() * 1 gwei;
        assertEq(paymaster.gasCredit(address(wallet)), 0.1 ether - charged);

        // 4. Remaining credit still sponsors future ops.
        vm.prank(address(mockEntryPoint));
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), maxCost);
        assertEq(validationData, 0);
    }
}
