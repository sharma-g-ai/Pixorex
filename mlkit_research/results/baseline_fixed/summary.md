# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3849 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 9/10 | 95.0% | 100.0% | 95.2% | 756 | 927 | 490 |
| shadow | 10 | 8/10 | 93.8% | 100.0% | 95.2% | 782 | 927 | 488 |
| glare | 10 | 8/10 | 94.2% | 100.0% | 100.0% | 798 | 864 | 497 |
| crumpled | 10 | 10/10 | 95.0% | 100.0% | 100.0% | 774 | 945 | 494 |
| low_light | 10 | 4/10 | 66.5% | 81.5% | 90.5% | 710 | 799 | 458 |
| ALL | 50 | 39/50 | 88.9% | 96.3% | 96.2% | 752 | 927 | 481 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
