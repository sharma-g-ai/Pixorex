# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 9/10 | 89.2% | 100.0% | 95.2% | 886 | 1009 | 602 |
| shadow | 10 | 9/10 | 86.9% | 100.0% | 95.2% | 876 | 999 | 576 |
| glare | 10 | 9/10 | 86.5% | 100.0% | 95.2% | 878 | 1005 | 578 |
| crumpled | 10 | 9/10 | 90.0% | 100.0% | 95.2% | 876 | 1037 | 580 |
| low_light | 10 | 5/10 | 62.3% | 85.2% | 85.7% | 830 | 953 | 547 |
| ALL | 50 | 41/50 | 83.0% | 97.0% | 93.3% | 872 | 1009 | 576 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
