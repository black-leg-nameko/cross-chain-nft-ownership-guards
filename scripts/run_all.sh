#!/usr/bin/env sh
set -eu

node scripts/run_scenarios.js
node scripts/run_experiments.js
solc --stop-after parsing src/BaselineNFT.sol src/SafeCrossChainNFT.sol src/MockMarketplace.sol
