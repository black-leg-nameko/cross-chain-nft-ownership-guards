# Experiments

Run the full dependency-free experiment suite:

```bash
sh scripts/run_all.sh
```

Run only the publication figures and aggregate report:

```bash
node scripts/run_experiments.js
```

With Docker Desktop and WSL integration enabled:

```bash
docker compose run --rm experiments
```

Run the actual two-chain local EVM experiment:

```bash
docker compose up --abort-on-container-exit --exit-code-from multichain multichain
```

This starts two Anvil chains (`chain-a`, `chain-b`), deploys source/destination
NFT contracts, emulates a delayed relay window, attempts hazardous operations on
chain A during the delay, finalizes on chain B, and writes
`reports/multichain_experiment_report.md`.

The two-chain run is the primary evidence for the cross-chain claim. The Node
experiment is still useful for paper figures and the full pending-state matrix,
but it is an executable model rather than a multi-chain execution.

Outputs:

- `results/operation_matrix.json`
- `results/experiment_summary.json`
- `results/replay_report.json`
- `results/state_access_overhead.json`
- `figures/operation_matrix.svg`
- `figures/pending_window_timeline.svg`
- `figures/state_access_overhead.svg`
- `reports/experiment_report.md`
- `reports/multichain_experiment_report.md`
- `reports/foundry_gas_report.txt`
- `results/multichain/summary.json`
- `results/multichain/operation_results.csv`
