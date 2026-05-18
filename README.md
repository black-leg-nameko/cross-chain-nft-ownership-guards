# FIT2026 Cross-Chain NFT Operation Guards

This repository contains the proof-of-concept implementation for the FIT2026
paper "Defining and Preventing Hazardous Operations under Ownership
Inconsistency in Cross-chain NFTs".

## Main Result

The baseline permits **12/12** hazardous operations during pending ownership
states. The proposal rejects **12/12** pending hazardous operations, while
restoring **6/6** normal operations after finalization.

Evidence levels:

- `scripts/run_experiments.js` generates the matrix and figures from an executable model matching the intended Solidity behavior.
- `test/ScenarioMatrix.t.sol` checks the Solidity contracts at EVM level when run with Foundry.
- `figures/state_access_overhead.svg` is a storage-access model, not a measured gas benchmark.

![Hazardous operation matrix](figures/operation_matrix.svg)

The experiment is designed to show three properties:

- **Safety:** pending-state transfer, approval, and listing operations are rejected.
- **Availability:** the same operations are allowed in `ACTIVE` and after finalization.
- **Lightweight guard:** normal hazardous operations add one state read; writes occur only on bridge state transitions.

![State-access overhead](figures/state_access_overhead.svg)

The PoC compares:

- `BaselineNFT`: a naive cross-chain NFT that emits bridge events but keeps
  ownership-dependent NFT operations available while a bridge transfer is
  pending.
- `SafeCrossChainNFT`: a state-aware NFT that tracks `ACTIVE`, `PENDING_OUT`,
  and `PENDING_IN` per token and rejects hazardous operations during pending
  states.
- `MockMarketplace`: a minimal bridge-aware marketplace that treats listing as
  an ownership-dependent operation.

## Hazardous Operations

The implementation evaluates six concrete entry points across the three
operation classes used in the paper:

- transfer: `transferFrom`, `safeTransferFrom`
- approval: `approve`, `setApprovalForAll`
- listing: direct `list(tokenId)` and marketplace listing through `canList(tokenId)`

States:

- `ACTIVE`
- `PENDING_OUT`
- `PENDING_IN`
- post-finalization `ACTIVE`

## Reproduce Experiments

Dependency-free local run:

```bash
node scripts/run_experiments.js
```

Full local check:

```bash
sh scripts/run_all.sh
```

With Docker Desktop and WSL integration enabled:

```bash
docker compose run --rm experiments
```

Run the Solidity scenario tests and gas report in Docker:

```bash
docker compose run --rm foundry
```

Generated outputs:

- `reports/experiment_report.md`
- `results/operation_matrix.json`
- `results/experiment_summary.json`
- `results/replay_report.json`
- `results/state_access_overhead.json`
- `figures/operation_matrix.svg`
- `figures/pending_window_timeline.svg`
- `figures/state_access_overhead.svg`

## Solidity Checks

The Node experiment generates the paper figures from a small executable model.
The Solidity contracts themselves are checked separately. At minimum, parse the
contracts with plain `solc`:

```bash
solc --stop-after parsing src/BaselineNFT.sol src/SafeCrossChainNFT.sol src/MockMarketplace.sol test/ScenarioMatrix.t.sol
```

For executable EVM-level tests, use Foundry locally or through Docker:

```bash
forge test --gas-report
```

```bash
docker compose run --rm foundry
```

## Scenario Check

The repository includes a dependency-free Node.js scenario runner that mirrors
the paper's comparison table:

```bash
node scripts/run_scenarios.js
```

It writes `results/scenario_report.json` and prints whether each pending-state
operation succeeds in the baseline and is rejected by the proposal.

## Expected Result

| Scenario | Baseline | Proposal |
| --- | --- | --- |
| pending transfer | succeeds | rejected |
| pending approve | succeeds | rejected |
| pending listing | succeeds | rejected |
| transfer after finalize | succeeds | succeeds |
| replay finalize | accepted | rejected |

This PoC intentionally abstracts bridge signature verification and focuses on
ownership-state semantics and operation guards.
