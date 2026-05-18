# Two-chain Delay Sweep

Each row was produced by launching two local Anvil chains with Docker Compose, deploying the baseline and proposal contracts, exercising the relay window on chain A, and finalizing on chain B.

| Relay delay (s) | Baseline pending allowed | Proposal pending rejected | Baseline destination finalized | Proposal destination finalized | Proposal replay rejected |
| ---: | --- | --- | --- | --- | --- |
| 0 | 6/6 | 6/6 | 1/1 | 1/1 | 1/1 |
| 1 | 6/6 | 6/6 | 1/1 | 1/1 | 1/1 |
| 3 | 6/6 | 6/6 | 1/1 | 1/1 | 1/1 |
| 10 | 6/6 | 6/6 | 1/1 | 1/1 | 1/1 |
