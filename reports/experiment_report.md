# FIT2026 Experiment Report

Generated at: 2026-05-18T04:51:23.047Z

## Headline Result

baseline permits 12/12 pending hazardous operations; proposal rejects 12/12 and restores 6/6 after finalization.

Evidence levels: the matrix and figures are generated from an executable model matching the intended Solidity behavior; `test/ScenarioMatrix.t.sol` provides EVM-level checks when run with Foundry; the overhead figure is a storage-access model, not a measured gas benchmark.

| Metric | Result |
| --- | ---: |
| Baseline pending hazardous operations allowed | 12/12 |
| Proposal pending hazardous operations rejected | 12/12 |
| Proposal ACTIVE operations allowed | 6/6 |
| Proposal post-finalization operations allowed | 6/6 |
| Baseline replay finalization accepted | yes |
| Proposal replay finalization rejected | yes |

## Figures

- `figures/operation_matrix.svg`: baseline/proposal operation matrix.
- `figures/pending_window_timeline.svg`: pending-window attack timeline.
- `figures/state_access_overhead.svg`: state-access overhead model.

## Operation Matrix

| System | State | Operation | Outcome | Error |
| --- | --- | --- | --- | --- |
| baseline | ACTIVE | transferFrom | allow |  |
| baseline | ACTIVE | safeTransferFrom | allow |  |
| baseline | ACTIVE | approve | allow |  |
| baseline | ACTIVE | setApprovalForAll | allow |  |
| baseline | ACTIVE | directList | allow |  |
| baseline | ACTIVE | marketplaceList | allow |  |
| baseline | PENDING_OUT | transferFrom | allow |  |
| baseline | PENDING_OUT | safeTransferFrom | allow |  |
| baseline | PENDING_OUT | approve | allow |  |
| baseline | PENDING_OUT | setApprovalForAll | allow |  |
| baseline | PENDING_OUT | directList | allow |  |
| baseline | PENDING_OUT | marketplaceList | allow |  |
| baseline | PENDING_IN | transferFrom | allow |  |
| baseline | PENDING_IN | safeTransferFrom | allow |  |
| baseline | PENDING_IN | approve | allow |  |
| baseline | PENDING_IN | setApprovalForAll | allow |  |
| baseline | PENDING_IN | directList | allow |  |
| baseline | PENDING_IN | marketplaceList | allow |  |
| baseline | FINALIZED_ACTIVE | transferFrom | allow |  |
| baseline | FINALIZED_ACTIVE | safeTransferFrom | allow |  |
| baseline | FINALIZED_ACTIVE | approve | allow |  |
| baseline | FINALIZED_ACTIVE | setApprovalForAll | allow |  |
| baseline | FINALIZED_ACTIVE | directList | allow |  |
| baseline | FINALIZED_ACTIVE | marketplaceList | allow |  |
| proposal | ACTIVE | transferFrom | allow |  |
| proposal | ACTIVE | safeTransferFrom | allow |  |
| proposal | ACTIVE | approve | allow |  |
| proposal | ACTIVE | setApprovalForAll | allow |  |
| proposal | ACTIVE | directList | allow |  |
| proposal | ACTIVE | marketplaceList | allow |  |
| proposal | PENDING_OUT | transferFrom | reject | HazardousOperationWhilePending |
| proposal | PENDING_OUT | safeTransferFrom | reject | HazardousOperationWhilePending |
| proposal | PENDING_OUT | approve | reject | HazardousOperationWhilePending |
| proposal | PENDING_OUT | setApprovalForAll | reject | OperatorApprovalWhileOwnerHasPendingTokens |
| proposal | PENDING_OUT | directList | reject | HazardousOperationWhilePending |
| proposal | PENDING_OUT | marketplaceList | reject | HazardousOperationWhilePending |
| proposal | PENDING_IN | transferFrom | reject | HazardousOperationWhilePending |
| proposal | PENDING_IN | safeTransferFrom | reject | HazardousOperationWhilePending |
| proposal | PENDING_IN | approve | reject | HazardousOperationWhilePending |
| proposal | PENDING_IN | setApprovalForAll | reject | OperatorApprovalWhileOwnerHasPendingTokens |
| proposal | PENDING_IN | directList | reject | HazardousOperationWhilePending |
| proposal | PENDING_IN | marketplaceList | reject | HazardousOperationWhilePending |
| proposal | FINALIZED_ACTIVE | transferFrom | allow |  |
| proposal | FINALIZED_ACTIVE | safeTransferFrom | allow |  |
| proposal | FINALIZED_ACTIVE | approve | allow |  |
| proposal | FINALIZED_ACTIVE | setApprovalForAll | allow |  |
| proposal | FINALIZED_ACTIVE | directList | allow |  |
| proposal | FINALIZED_ACTIVE | marketplaceList | allow |  |

## Replay Finalization

- Baseline: accepted
- Proposal: rejected (MessageAlreadyFinalized)

## State-Access Overhead Model

This is a storage-access model, not a chain-specific gas benchmark. The executable Solidity tests are in `test/ScenarioMatrix.t.sol` and can be run with `forge test --gas-report` or `docker compose run --rm foundry`.

| Operation | Extra reads | Extra writes | Explanation |
| --- | ---: | ---: | --- |
| transferFrom | 1 | 0 | bridgeState[tokenId] read before owner/approval checks |
| safeTransferFrom | 1 | 0 | same guard as transferFrom |
| approve | 1 | 0 | bridgeState[tokenId] read before approval |
| setApprovalForAll | 1 | 0 | pendingTokenCount[msg.sender] read |
| list | 1 | 0 | bridgeState[tokenId] read before listing |
| bridgeOut | 1 | 2 | bridgeState write and pendingTokenCount write |
| finalizeIn | 1 | 3 | message replay guard, state restore, pending count update |

