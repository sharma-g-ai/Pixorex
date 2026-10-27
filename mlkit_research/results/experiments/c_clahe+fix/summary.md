# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 9/10 | 94.2% | 100.0% | 95.2% | 720 | 884 | 464 |
| shadow | 10 | 9/10 | 93.1% | 100.0% | 95.2% | 706 | 874 | 458 |
| glare | 10 | 9/10 | 94.6% | 100.0% | 95.2% | 730 | 836 | 456 |
| crumpled | 10 | 8/10 | 90.4% | 96.3% | 95.2% | 728 | 913 | 462 |
| low_light | 10 | 7/10 | 63.8% | 85.2% | 85.7% | 668 | 770 | 422 |
| ALL | 50 | 42/50 | 87.2% | 96.3% | 93.3% | 718 | 898 | 456 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
