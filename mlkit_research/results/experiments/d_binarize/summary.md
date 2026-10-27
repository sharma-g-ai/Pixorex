# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 7/10 | 68.5% | 88.9% | 95.2% | 747 | 822 | 496 |
| shadow | 10 | 7/10 | 71.2% | 92.6% | 100.0% | 764 | 831 | 508 |
| glare | 10 | 6/10 | 65.8% | 92.6% | 95.2% | 742 | 805 | 489 |
| crumpled | 10 | 4/10 | 65.8% | 81.5% | 90.5% | 762 | 859 | 498 |
| low_light | 10 | 2/10 | 21.5% | 7.4% | 71.4% | 580 | 661 | 423 |
| ALL | 50 | 26/50 | 58.5% | 72.6% | 90.5% | 730 | 831 | 493 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
