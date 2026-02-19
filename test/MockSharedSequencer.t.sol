// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/Test.sol";
import "./MockSharedSequencer.sol";

contract MockSharedSequencerTest is Test {
    MockSharedSequencer sequencer;
    address owner = address(0x123);
    address user = address(0x456);
    address nonOwner = address(0x789);
    bytes sampleData = "0x1234";
    uint256 constant MIN_FEE = 0.001 ether;

    function setUp() public {
        vm.startPrank(owner);
        sequencer = new MockSharedSequencer();
        vm.stopPrank();
    }

    // Unit Tests
    function test_submitTransaction_success() public {
        vm.startPrank(user);
        uint256 fee = sequencer.estimateSubmissionCost(sampleData);
        bytes32 txId = sequencer.submitTransaction{value: fee}(sampleData);
        assertTrue(txId != bytes32(0));
        
        ISharedSequencer.ConfirmationReceipt memory receipt = sequencer.getConfirmationReceipt(txId);
        assertEq(receipt.timestamp, block.timestamp);
        assertEq(receipt.status, 0); // Pending
        vm.stopPrank();
    }

    function test_submitTransaction_insufficientFee_reverts() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(MockSharedSequencer.InsufficientFee.selector, MIN_FEE, MIN_FEE - 1));
        sequencer.submitTransaction{value: MIN_FEE - 1}(sampleData);
        vm.stopPrank();
    }

    function test_submitTransaction_emptyData_reverts() public {
        vm.startPrank(user);
        bytes memory empty;
        vm.expectRevert(MockSharedSequencer.MalformedTransaction.selector);
        sequencer.submitTransaction{value: MIN_FEE}(empty);
        vm.stopPrank();
    }

    function test_submitTransaction_whenPaused_reverts() public {
        vm.startPrank(owner);
        sequencer.setPaused(true);
        vm.stopPrank();
        
        vm.startPrank(user);
        vm.expectRevert(MockSharedSequencer.SequencerPaused.selector);
        sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        vm.stopPrank();
    }

    function test_getConfirmationReceipt_pending() public {
        vm.startPrank(user);
        bytes32 txId = sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        ISharedSequencer.ConfirmationReceipt memory receipt = sequencer.getConfirmationReceipt(txId);
        assertEq(receipt.status, 0);
        vm.stopPrank();
    }

    function test_getConfirmationReceipt_notFound_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(MockSharedSequencer.ReceiptNotFound.selector, bytes32("nonexistent")));
        sequencer.getConfirmationReceipt(bytes32("nonexistent"));
    }

    function test_confirmTransaction_success() public {
        vm.startPrank(user);
        bytes32 txId = sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        vm.stopPrank();
        
        vm.startPrank(owner);
        bytes32 l1Hash = keccak256("confirmed");
        vm.expectEmit(true, true, true, true);
        emit ISharedSequencer.TransactionConfirmed(txId, l1Hash, txId);
        sequencer.confirmTransaction(txId, l1Hash);
        
        ISharedSequencer.ConfirmationReceipt memory receipt = sequencer.getConfirmationReceipt(txId);
        assertEq(receipt.status, 1);
        assertEq(receipt.l1TxHash, l1Hash);
        vm.stopPrank();
    }

    function test_confirmTransaction_onlyOwner() public {
        vm.startPrank(user);
        bytes32 txId = sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        vm.stopPrank();
        
        vm.startPrank(nonOwner);
        vm.expectRevert("Not owner");
        sequencer.confirmTransaction(txId, keccak256("test"));
        vm.stopPrank();
    }

    function test_failTransaction_success() public {
        vm.startPrank(user);
        bytes32 txId = sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        vm.stopPrank();
        
        vm.startPrank(owner);
        string memory reason = "Reverted on L2";
        vm.expectEmit(true, true, true, true);
        emit ISharedSequencer.TransactionFailed(txId, reason);
        sequencer.failTransaction(txId, reason);
        
        ISharedSequencer.ConfirmationReceipt memory receipt = sequencer.getConfirmationReceipt(txId);
        assertEq(receipt.status, 2);
        assertEq(receipt.errorReason, reason);
        vm.stopPrank();
    }

    function test_estimateSubmissionCost_returnsNonZero() public view {
        uint256 cost = sequencer.estimateSubmissionCost(sampleData);
        assertGt(cost, 0);
        assertGe(cost, MIN_FEE);
    }

    function test_getSequencerMetadata() public view {
        ISharedSequencer.SequencerMetadata memory meta = sequencer.getSequencerMetadata();
        assertEq(meta.version, "1.0.0");
        assertEq(meta.minConfirmationTime, 1 minutes);
        assertEq(meta.maxTxSize, 128 * 1024);
    }

    function test_withdrawFees_onlyOwner() public {
        // First submit to get fees
        vm.startPrank(user);
        sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        vm.stopPrank();
        
        uint256 balanceBefore = address(owner).balance;
        uint256 contractBalance = address(sequencer).balance;
        
        vm.startPrank(owner);
        sequencer.withdrawFees(payable(owner));
        vm.stopPrank();
        
        assertEq(address(sequencer).balance, 0);
        assertEq(address(owner).balance, balanceBefore + contractBalance);
        
        // Non-owner cannot withdraw
        vm.startPrank(nonOwner);
        vm.expectRevert("Not owner");
        sequencer.withdrawFees(payable(nonOwner));
        vm.stopPrank();
    }

    // Fuzz Test
    function fuzz_submitTransaction_anyCost(uint256 payment, bytes calldata data) public {
        vm.assume(data.length > 0);
        vm.assume(payment >= MIN_FEE);
        vm.assume(payment < type(uint128).max); // Keep reasonable
        
        vm.startPrank(user);
        bytes32 txId = sequencer.submitTransaction{value: payment}(data);
        assertTrue(txId != bytes32(0));
        vm.stopPrank();
    }

    // Invariant Test
    function invariant_receiptNeverOverwritten() public {
        // Submit two different transactions, verify receipts remain distinct
        vm.startPrank(user);
        bytes32 txId1 = sequencer.submitTransaction{value: MIN_FEE}("tx1");
        bytes32 txId2 = sequencer.submitTransaction{value: MIN_FEE}("tx2");
        vm.stopPrank();
        
        ISharedSequencer.ConfirmationReceipt memory r1 = sequencer.getConfirmationReceipt(txId1);
        ISharedSequencer.ConfirmationReceipt memory r2 = sequencer.getConfirmationReceipt(txId2);
        
        assertTrue(txId1 != txId2);
        assertEq(r1.l2TxHash, txId1);
        assertEq(r2.l2TxHash, txId2);
        assertEq(r1.timestamp, r2.timestamp); // Same block
    }

    // Gas Profiling (Foundry reports automatically)
    function test_gas_profile_submitTransaction() public {
        vm.startPrank(user);
        uint256 gasBefore = gasleft();
        sequencer.submitTransaction{value: MIN_FEE}(sampleData);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("submitTransaction gas used", gasUsed);
        vm.stopPrank();
    }

    // Regression Test for AUD-004 (empty data revert)
    function test_regression_AUD004_emptyData() public {
        vm.startPrank(user);
        bytes memory empty;
        vm.expectRevert(MockSharedSequencer.MalformedTransaction.selector);
        sequencer.submitTransaction{value: MIN_FEE}(empty);
        vm.stopPrank();
    }
}
