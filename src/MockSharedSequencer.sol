// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import "./ISharedSequencer.sol";

contract MockSharedSequencer is ISharedSequencer {

    mapping(bytes32 => ConfirmationReceipt) private receipts;
    SequencerMetadata private _metadata;

    uint256 public constant MIN_SUBMISSION_FEE = 0.001 ether;
    address public immutable owner;
    bool public paused;

    error InsufficientFee(uint256 required, uint256 provided);
    error SequencerPaused();
    error ReceiptNotFound(bytes32 transactionId);
    error MalformedTransaction();

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    modifier whenNotPaused() { if (paused) revert SequencerPaused(); _; }

    constructor() {
        owner = msg.sender;
        _metadata = SequencerMetadata({
            version: "1.0.0",
            supportedL2s: new address[](0),
            minConfirmationTime: 1 minutes,
            maxTxSize: 128 * 1024
        });
    }

    function submitTransaction(bytes calldata transactionData) external payable whenNotPaused returns (bytes32 transactionId) {
        if (transactionData.length == 0) revert MalformedTransaction();
        if (msg.value < MIN_SUBMISSION_FEE) revert InsufficientFee(MIN_SUBMISSION_FEE, msg.value);
        transactionId = keccak256(abi.encodePacked(msg.sender, transactionData, block.timestamp, block.number));
        receipts[transactionId] = ConfirmationReceipt({
            timestamp: uint64(block.timestamp),
            l1TxHash: bytes32(0),
            l2TxHash: transactionId,
            status: 0,
            errorReason: ""
        });
        emit TransactionSubmitted(msg.sender, transactionId, msg.value);
    }

    function getConfirmationReceipt(bytes32 transactionId) external view returns (ConfirmationReceipt memory) {
        ConfirmationReceipt memory r = receipts[transactionId];
        if (r.timestamp == 0) revert ReceiptNotFound(transactionId);
        return r;
    }

    function estimateSubmissionCost(bytes calldata transactionData) external view returns (uint256) {
        uint256 baseFee = block.basefee > 0 ? block.basefee : 1 gwei;
        return MIN_SUBMISSION_FEE + (transactionData.length * 16 * baseFee);
    }

    function getSequencerMetadata() external view returns (SequencerMetadata memory) {
        return _metadata;
    }

    function confirmTransaction(bytes32 transactionId, bytes32 l1TxHash) external onlyOwner {
        ConfirmationReceipt storage r = receipts[transactionId];
        if (r.timestamp == 0) revert ReceiptNotFound(transactionId);
        r.l1TxHash = l1TxHash;
        r.status = 1;
        emit TransactionConfirmed(transactionId, l1TxHash, r.l2TxHash);
    }

    function failTransaction(bytes32 transactionId, string calldata reason) external onlyOwner {
        ConfirmationReceipt storage r = receipts[transactionId];
        if (r.timestamp == 0) revert ReceiptNotFound(transactionId);
        r.status = 2;
        r.errorReason = reason;
        emit TransactionFailed(transactionId, reason);
    }

    function setPaused(bool _paused) external onlyOwner { paused = _paused; }

    function withdrawFees(address payable to) external onlyOwner { to.transfer(address(this).balance); }
}
