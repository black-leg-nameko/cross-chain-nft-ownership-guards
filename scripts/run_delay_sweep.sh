#!/usr/bin/env sh
set -eu

DELAYS="${DELAYS:-0 1 3 10}"
summary_csv="results/delay_sweep_summary.csv"
summary_report="reports/delay_sweep_report.md"

mkdir -p results reports
printf "relay_delay_seconds,baseline_pending_allowed,proposal_pending_rejected,baseline_destination_finalized,proposal_destination_finalized,proposal_replay_rejected\n" > "$summary_csv"
printf "# Two-chain Delay Sweep\n\n" > "$summary_report"
printf "Each row was produced by launching two local Anvil chains with Docker Compose, deploying the baseline and proposal contracts, exercising the relay window on chain A, and finalizing on chain B.\n\n" >> "$summary_report"
printf "| Relay delay (s) | Baseline pending allowed | Proposal pending rejected | Baseline destination finalized | Proposal destination finalized | Proposal replay rejected |\n" >> "$summary_report"
printf "| ---: | --- | --- | --- | --- | --- |\n" >> "$summary_report"

for delay in $DELAYS; do
  project="fitnft-delay-${delay}"
  results_dir="results/multichain_delay_${delay}s"
  report_dir="reports/multichain_delay_${delay}s"

  printf "running two-chain delay sweep for RELAY_DELAY_SECONDS=%s\n" "$delay"
  status=0
  RESULTS_DIR="$results_dir" REPORTS_DIR="$report_dir" RELAY_DELAY_SECONDS="$delay" \
    docker compose -p "$project" up --abort-on-container-exit --exit-code-from multichain multichain || status=$?
  RESULTS_DIR="$results_dir" REPORTS_DIR="$report_dir" RELAY_DELAY_SECONDS="$delay" \
    docker compose -p "$project" down -v || true
  if [ "$status" -ne 0 ]; then
    exit "$status"
  fi
  node -e 'const fs=require("fs"); const [summaryPath,csvPath,reportPath]=process.argv.slice(1); const s=JSON.parse(fs.readFileSync(summaryPath,"utf8")); fs.appendFileSync(csvPath, `${s.relayDelaySeconds},${s.baselinePendingAllowed},${s.proposalPendingRejected},${s.baselineDestinationFinalizedOperations},${s.proposalDestinationFinalizedOperations},${s.proposalReplayRejected}\n`); fs.appendFileSync(reportPath, `| ${s.relayDelaySeconds} | ${s.baselinePendingAllowed} | ${s.proposalPendingRejected} | ${s.baselineDestinationFinalizedOperations} | ${s.proposalDestinationFinalizedOperations} | ${s.proposalReplayRejected} |\n`);' "$results_dir/summary.json" "$summary_csv" "$summary_report"
done
