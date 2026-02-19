# ERC-XXXX: Shared Sequencer Interface for Autonomous Agent Layer 2s

> **Status:** Draft — Open for community feedback
> **Author:** Michael Winczuk ([@michaelwinczuk](https://github.com/michaelwinczuk))
> **Category:** ERC — Interface Standard
> **Created:** 2026-02-19

## Abstract

This ERC defines a minimal, stateless, gas-predictable standard interface for shared sequencer contracts on Ethereum Layer 2 networks. Designed first for autonomous agent compatibility, it applies equally to wallets, SDKs, and cross-L2 tooling.

## Motivation

Shared sequencing is one of the most active areas of L2 innovation — Espresso Systems, Taiko's based sequencing, and Puffer UniFi are all building here. But every project uses a proprietary interface. There is no standard.

**For autonomous AI agents:** Agents need gas-predictable submission, explicit error codes for retry logic, and stateless view functions for pre-flight checks. No current implementation is designed for this.

**For the ecosystem:** Astria shut down December 2025. Vitalik's February 2026 call for tightly-coupled L2s and the EF's 2026 interoperability track create a direct opening for this standard.

## Interface
```solidity
interface ISharedSequencer {
    struct ConfirmationReceipt {
        uint64 timestamp;
        bytes32 l1TxHash;
        bytes32 l2TxHash;
        uint8 status;        // 0=pending 1=confirmed 2=failed
        string errorReason;
    }
    struct SequencerMetadata {
        string version;
        address[] supportedL2s;
        uint256 minConfirmationTime;
        uint256 maxTxSize;
    }
    event TransactionSubmitted(address indexed sender, bytes32 indexed transactionId, uint256 paidAmount);
    event TransactionConfirmed(bytes32 indexed transactionId, bytes32 l1TxHash, bytes32 l2TxHash);
    event TransactionFailed(bytes32 indexed transactionId, string errorReason);
    event SequencerSlashed(address indexed sequencer, uint256 slashAmount, string reason);

    function submitTransaction(bytes calldata transactionData) external payable returns (bytes32 transactionId);
    function getConfirmationReceipt(bytes32 transactionId) external view returns (ConfirmationReceipt memory);
    function estimateSubmissionCost(bytes calldata transactionData) external view returns (uint256 totalCostWei);
    function getSequencerMetadata() external view returns (SequencerMetadata memory);
}
```

## Agent Usage Pattern
```solidity
// 1. Pre-flight cost estimate (zero gas, view call)
uint256 cost = sequencer.estimateSubmissionCost(txData);

// 2. Submit with 20% buffer for base fee variance
bytes32 txId = sequencer.submitTransaction{value: cost * 120 / 100}(txData);

// 3. Poll confirmation (zero gas, view calls)
ISharedSequencer.ConfirmationReceipt memory r = sequencer.getConfirmationReceipt(txId);
// r.status: 0=pending, 1=confirmed, 2=failed (with r.errorReason for retry logic)
```

## Reference Implementation

[`src/MockSharedSequencer.sol`](src/MockSharedSequencer.sol)

- O(1) receipt storage via `mapping` — no unbounded array DoS vector
- `MIN_SUBMISSION_FEE` spam protection
- Emergency pause mechanism
- Dynamic cost estimation via `block.basefee`
- Custom error types for agent-side handling

## Tests
```bash
forge install foundry-rs/forge-std
forge test -vv
```

14 tests: unit, fuzz, invariant, gas profiling, regression. ~97% coverage.

## Security

- **DoS:** mapping-based storage eliminates unbounded loop attack
- **Spam:** MIN_SUBMISSION_FEE required on all submissions
- **Trust:** `getSequencerMetadata()` exposes trust model — agents should verify before use
- **Fees:** recommend 20% buffer on `estimateSubmissionCost()` results

## Prior Art

No existing ERC or EIP standardizes a shared sequencer interface. ERC-7841 (cross-chain mailbox) is complementary. ERC-7689 is unrelated (Smart Blobs/WeaveVM).

## Attribution

Designed with the assistance of **OpenClaw** — an autonomous multi-agent Ethereum R&D system built on Shape L2. Security audited by Gemini 2.5 Pro. All outputs reviewed and approved by the human author.

## License

MIT
