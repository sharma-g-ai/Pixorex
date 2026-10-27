# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 10/10 | 91.2% | 100.0% | 100.0% | 934 | 1051 | 625 |
| shadow | 10 | 10/10 | 91.2% | 100.0% | 100.0% | 984 | 1151 | 626 |
| glare | 10 | 8/10 | 91.2% | 100.0% | 95.2% | 933 | 1085 | 620 |
| crumpled | 10 | 9/10 | 91.9% | 100.0% | 100.0% | 918 | 1127 | 619 |
| low_light | 10 | 9/10 | 62.7% | 92.6% | 90.5% | 881 | 1000 | 590 |
| ALL | 50 | 46/50 | 85.6% | 98.5% | 97.1% | 923 | 1127 | 619 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
