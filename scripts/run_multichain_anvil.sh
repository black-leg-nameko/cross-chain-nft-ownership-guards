#!/usr/bin/env sh
set -eu

RPC_A="${RPC_A:-http://chain-a:8545}"
RPC_B="${RPC_B:-http://chain-b:8545}"
CHAIN_A_ID="${CHAIN_A_ID:-31337}"
CHAIN_B_ID="${CHAIN_B_ID:-31338}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
ALICE="${ALICE:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
BOB="${BOB:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
MALLORY="${MALLORY:-0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC}"
OPERATOR="${OPERATOR:-0x90F79bf6EB2c4f870365E785982E1f101E93b906}"
RELAY_DELAY_SECONDS="${RELAY_DELAY_SECONDS:-3}"

RESULTS_DIR="${RESULTS_DIR:-results/multichain}"
FIGURES_DIR="${FIGURES_DIR:-figures}"
REPORTS_DIR="${REPORTS_DIR:-reports}"

mkdir -p "$RESULTS_DIR" "$FIGURES_DIR" "$REPORTS_DIR"
CSV="$RESULTS_DIR/operation_results.csv"
JSONL="$RESULTS_DIR/operation_results.jsonl"
SUMMARY="$RESULTS_DIR/summary.json"
REPORT="$REPORTS_DIR/multichain_experiment_report.md"

: > "$JSONL"
printf "system,chain,state,operation,expected,actual,ok,tx_or_error\n" > "$CSV"

log() {
  printf "%s\n" "$*"
}

wait_rpc() {
  name="$1"
  rpc="$2"
  log "waiting for $name at $rpc"
  i=0
  until cast block-number --rpc-url "$rpc" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
      log "timeout waiting for $name"
      exit 1
    fi
    sleep 1
  done
}

deploy() {
  rpc="$1"
  contract="$2"
  logfile="$RESULTS_DIR/deploy_$(basename "$contract" | tr ':/' '__').log"
  forge create "$contract" \
    --rpc-url "$rpc" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --json > "$logfile" 2>&1
  address="$(sed -n 's/.*"deployedTo"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]*\)".*/\1/p' "$logfile" | tail -n 1)"
  if [ -z "$address" ]; then
    log "failed to parse deployment address for $contract"
    cat "$logfile"
    exit 1
  fi
  printf "%s" "$address"
}

tx() {
  rpc="$1"
  contract="$2"
  sig="$3"
  shift 3
  cast send "$contract" "$sig" "$@" --rpc-url "$rpc" --private-key "$PRIVATE_KEY" --json
}

tx_hash_from_output() {
  sed -n 's/.*"transactionHash"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]*\)".*/\1/p' | tail -n 1
}

record() {
  system="$1"
  chain="$2"
  state="$3"
  operation="$4"
  expected="$5"
  actual="$6"
  ok="$7"
  detail="$8"
  printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$system" "$chain" "$state" "$operation" "$expected" "$actual" "$ok" "$detail" >> "$CSV"
  printf '{"system":"%s","chain":"%s","state":"%s","operation":"%s","expected":"%s","actual":"%s","ok":%s,"detail":"%s"}\n' \
    "$system" "$chain" "$state" "$operation" "$expected" "$actual" "$ok" "$(printf "%s" "$detail" | tr '"' "'")" >> "$JSONL"
}

expect_success() {
  system="$1"
  chain="$2"
  state="$3"
  operation="$4"
  rpc="$5"
  contract="$6"
  sig="$7"
  shift 7
  output_file="$RESULTS_DIR/${system}_${chain}_${state}_${operation}.json"
  if cast send "$contract" "$sig" "$@" --rpc-url "$rpc" --private-key "$PRIVATE_KEY" --json > "$output_file" 2>&1; then
    hash="$(tx_hash_from_output < "$output_file")"
    record "$system" "$chain" "$state" "$operation" "success" "success" "true" "${hash:-tx-ok}"
  else
    err="$(tail -n 1 "$output_file" | tr ',' ';')"
    record "$system" "$chain" "$state" "$operation" "success" "revert" "false" "$err"
  fi
}

expect_revert() {
  system="$1"
  chain="$2"
  state="$3"
  operation="$4"
  rpc="$5"
  contract="$6"
  sig="$7"
  shift 7
  output_file="$RESULTS_DIR/${system}_${chain}_${state}_${operation}.json"
  if cast send "$contract" "$sig" "$@" --rpc-url "$rpc" --private-key "$PRIVATE_KEY" --json > "$output_file" 2>&1; then
    hash="$(tx_hash_from_output < "$output_file")"
    record "$system" "$chain" "$state" "$operation" "revert" "success" "false" "${hash:-tx-ok}"
  else
    err="$(tail -n 1 "$output_file" | tr ',' ';')"
    record "$system" "$chain" "$state" "$operation" "revert" "revert" "true" "$err"
  fi
}

mint_and_bridge_out() {
  rpc="$1"
  contract="$2"
  token="$3"
  tx "$rpc" "$contract" "mint(address,uint256)" "$ALICE" "$token" >/dev/null
  tx "$rpc" "$contract" "bridgeOut(uint256,uint256)" "$token" "$CHAIN_B_ID" >/dev/null
}

finalize_on_destination() {
  rpc="$1"
  contract="$2"
  token="$3"
  msg_id="$4"
  tx "$rpc" "$contract" "finalizeIn(uint256,address,uint256,bytes32)" "$token" "$ALICE" "$CHAIN_A_ID" "$msg_id" >/dev/null
}

run_pending_matrix() {
  system="$1"
  source="$2"
  market="$3"
  expected="$4"
  token_base="$5"

  mint_and_bridge_out "$RPC_A" "$source" "$((token_base + 1))"
  expect_"$expected" "$system" "chain-a" "PENDING_OUT" "transferFrom" "$RPC_A" "$source" "transferFrom(address,address,uint256)" "$ALICE" "$BOB" "$((token_base + 1))"

  mint_and_bridge_out "$RPC_A" "$source" "$((token_base + 2))"
  expect_"$expected" "$system" "chain-a" "PENDING_OUT" "safeTransferFrom" "$RPC_A" "$source" "safeTransferFrom(address,address,uint256)" "$ALICE" "$BOB" "$((token_base + 2))"

  mint_and_bridge_out "$RPC_A" "$source" "$((token_base + 3))"
  expect_"$expected" "$system" "chain-a" "PENDING_OUT" "approve" "$RPC_A" "$source" "approve(address,uint256)" "$MALLORY" "$((token_base + 3))"

  mint_and_bridge_out "$RPC_A" "$source" "$((token_base + 4))"
  expect_"$expected" "$system" "chain-a" "PENDING_OUT" "setApprovalForAll" "$RPC_A" "$source" "setApprovalForAll(address,bool)" "$OPERATOR" true

  mint_and_bridge_out "$RPC_A" "$source" "$((token_base + 5))"
  expect_"$expected" "$system" "chain-a" "PENDING_OUT" "directList" "$RPC_A" "$source" "list(uint256)" "$((token_base + 5))"

  mint_and_bridge_out "$RPC_A" "$source" "$((token_base + 6))"
  expect_"$expected" "$system" "chain-a" "PENDING_OUT" "marketplaceList" "$RPC_A" "$market" "list(address,uint256)" "$source" "$((token_base + 6))"
}

count_csv() {
  awk -F, -v sys="$1" -v want="$2" 'NR>1 && $1==sys && $7==want { n++ } END { print n+0 }' "$CSV"
}

count_csv_total() {
  awk -F, -v sys="$1" 'NR>1 && $1==sys { n++ } END { print n+0 }' "$CSV"
}

count_match() {
  awk -F, -v sys="$1" -v chain="$2" -v state="$3" -v actual="$4" -v ok="$5" \
    'NR>1 && $1==sys && $2==chain && $3==state && $6==actual && $7==ok { n++ } END { print n+0 }' "$CSV"
}

count_total_match() {
  awk -F, -v sys="$1" -v chain="$2" -v state="$3" \
    'NR>1 && $1==sys && $2==chain && $3==state { n++ } END { print n+0 }' "$CSV"
}

write_summary() {
  baseline_pending_allowed="$(count_match baseline chain-a PENDING_OUT success true)"
  baseline_pending_total="$(count_total_match baseline chain-a PENDING_OUT)"
  proposal_pending_rejected="$(count_match proposal chain-a PENDING_OUT revert true)"
  proposal_pending_total="$(count_total_match proposal chain-a PENDING_OUT)"
  baseline_destination_ok="$(count_match baseline chain-b FINALIZED success true)"
  proposal_destination_ok="$(count_match proposal chain-b FINALIZED success true)"
  proposal_replay_rejected="$(awk -F, 'NR>1 && $1=="proposal" && $2=="chain-b" && $4=="replayFinalize" && $6=="revert" && $7=="true" { n++ } END { print n+0 }' "$CSV")"
  cat > "$SUMMARY" <<EOF
{
  "environment": "docker-compose anvil x 2",
  "rpcA": "$RPC_A",
  "rpcB": "$RPC_B",
  "chainAId": $CHAIN_A_ID,
  "chainBId": $CHAIN_B_ID,
  "relayDelaySeconds": $RELAY_DELAY_SECONDS,
  "baselinePendingAllowed": "$baseline_pending_allowed/$baseline_pending_total",
  "proposalPendingRejected": "$proposal_pending_rejected/$proposal_pending_total",
  "baselineDestinationFinalizedOperations": "$baseline_destination_ok/1",
  "proposalDestinationFinalizedOperations": "$proposal_destination_ok/1",
  "proposalReplayRejected": "$proposal_replay_rejected/1",
  "sourceBaseline": "$BASELINE_A",
  "destinationBaseline": "$BASELINE_B",
  "sourceProposal": "$SAFE_A",
  "destinationProposal": "$SAFE_B"
}
EOF
}

write_report() {
  cat > "$REPORT" <<EOF
# Multi-chain Anvil Experiment Report

This report is generated by \`scripts/run_multichain_anvil.sh\`.

## Environment

- chain A: Anvil, chain id $CHAIN_A_ID, RPC $RPC_A
- chain B: Anvil, chain id $CHAIN_B_ID, RPC $RPC_B
- relay delay: $RELAY_DELAY_SECONDS seconds

## Deployed Contracts

| Role | Address |
| --- | --- |
| Baseline source NFT on chain A | \`$BASELINE_A\` |
| Baseline destination NFT on chain B | \`$BASELINE_B\` |
| Proposal source NFT on chain A | \`$SAFE_A\` |
| Proposal destination NFT on chain B | \`$SAFE_B\` |
| Baseline marketplace on chain A | \`$MARKET_BASELINE_A\` |
| Proposal marketplace on chain A | \`$MARKET_SAFE_A\` |

Addresses are interpreted together with the chain id. Anvil uses deterministic
accounts and nonces, so the same address may appear on chain A and chain B while
still referring to different chain-local contracts.

## Result Summary

\`\`\`json
$(cat "$SUMMARY")
\`\`\`

## Operation Results

\`\`\`csv
$(cat "$CSV")
\`\`\`

## Interpretation

The baseline source NFT remains operational during the relay delay after \`bridgeOut\`.
The proposal source NFT enters \`PENDING_OUT\` and rejects ownership-dependent
operations during the relay delay. Destination-chain finalization is executed
on chain B, and the destination NFT then permits normal transfer. The experiment
therefore exercises two local chains and an asynchronous relay window, while
still abstracting bridge proof verification and any source-side post-finalization
acknowledgement.
EOF
}

wait_rpc "chain-a" "$RPC_A"
wait_rpc "chain-b" "$RPC_B"

log "building contracts"
forge build >/dev/null

log "deploying contracts"
BASELINE_A="$(deploy "$RPC_A" "src/BaselineNFT.sol:BaselineNFT")"
BASELINE_B="$(deploy "$RPC_B" "src/BaselineNFT.sol:BaselineNFT")"
SAFE_A="$(deploy "$RPC_A" "src/SafeCrossChainNFT.sol:SafeCrossChainNFT")"
SAFE_B="$(deploy "$RPC_B" "src/SafeCrossChainNFT.sol:SafeCrossChainNFT")"
MARKET_BASELINE_A="$(deploy "$RPC_A" "src/MockMarketplace.sol:MockMarketplace")"
MARKET_SAFE_A="$(deploy "$RPC_A" "src/MockMarketplace.sol:MockMarketplace")"

log "running pending-window hazardous operations on chain A"
run_pending_matrix "baseline" "$BASELINE_A" "$MARKET_BASELINE_A" "success" 100
run_pending_matrix "proposal" "$SAFE_A" "$MARKET_SAFE_A" "revert" 200

log "sleeping to emulate asynchronous relay delay: ${RELAY_DELAY_SECONDS}s"
sleep "$RELAY_DELAY_SECONDS"

log "finalizing destination NFTs on chain B"
MSG_BASELINE="0x$(printf '%064x' 1001)"
MSG_SAFE="0x$(printf '%064x' 2001)"
finalize_on_destination "$RPC_B" "$BASELINE_B" 1001 "$MSG_BASELINE"
finalize_on_destination "$RPC_B" "$SAFE_B" 2001 "$MSG_SAFE"

expect_success "baseline" "chain-b" "FINALIZED" "destinationTransfer" "$RPC_B" "$BASELINE_B" "transferFrom(address,address,uint256)" "$ALICE" "$BOB" 1001
expect_success "proposal" "chain-b" "FINALIZED" "destinationTransfer" "$RPC_B" "$SAFE_B" "transferFrom(address,address,uint256)" "$ALICE" "$BOB" 2001
expect_revert "proposal" "chain-b" "FINALIZED" "replayFinalize" "$RPC_B" "$SAFE_B" "finalizeIn(uint256,address,uint256,bytes32)" 2001 "$ALICE" "$CHAIN_A_ID" "$MSG_SAFE"

write_summary
write_report

log "multi-chain experiment complete"
cat "$SUMMARY"
