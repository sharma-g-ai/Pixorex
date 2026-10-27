# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 9/10 | 90.8% | 100.0% | 100.0% | 874 | 997 | 564 |
| shadow | 10 | 10/10 | 90.8% | 100.0% | 100.0% | 868 | 982 | 590 |
| glare | 10 | 10/10 | 92.3% | 100.0% | 100.0% | 842 | 1030 | 568 |
| crumpled | 10 | 9/10 | 91.5% | 100.0% | 100.0% | 871 | 990 | 581 |
| low_light | 10 | 4/10 | 63.1% | 85.2% | 95.2% | 808 | 946 | 541 |
| ALL | 50 | 42/50 | 85.7% | 97.0% | 99.0% | 850 | 1030 | 568 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
