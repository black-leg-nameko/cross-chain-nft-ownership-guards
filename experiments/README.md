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

Outputs:

- `results/operation_matrix.json`
- `results/experiment_summary.json`
- `results/replay_report.json`
- `results/state_access_overhead.json`
- `figures/operation_matrix.svg`
- `figures/pending_window_timeline.svg`
- `figures/state_access_overhead.svg`
- `reports/experiment_report.md`
