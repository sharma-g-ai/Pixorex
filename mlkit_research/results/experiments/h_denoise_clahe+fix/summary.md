# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 6/10 | 75.4% | 96.3% | 95.2% | 730 | 797 | 470 |
| shadow | 10 | 8/10 | 75.8% | 96.3% | 100.0% | 739 | 860 | 473 |
| glare | 10 | 8/10 | 74.6% | 96.3% | 95.2% | 724 | 837 | 465 |
| crumpled | 10 | 7/10 | 76.2% | 96.3% | 95.2% | 727 | 827 | 466 |
| low_light | 10 | 3/10 | 56.5% | 77.8% | 85.7% | 712 | 802 | 454 |
| ALL | 50 | 32/50 | 71.7% | 92.6% | 94.3% | 730 | 860 | 465 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
