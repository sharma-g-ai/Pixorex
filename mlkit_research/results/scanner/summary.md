# MLKit baseline results

- Device: android RMX3710
- Cold start (first call, model load): -1 ms
- Runs per image: 1 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| ALL | 7 | 6/7 | 99.3% | 100.0% | 100.0% | 691 | 864 | 608 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
