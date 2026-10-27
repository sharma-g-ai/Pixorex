# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 2912 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 10/10 | 97.7% | 100.0% | 100.0% | 726 | 813 | 619 |
| shadow | 10 | 10/10 | 97.7% | 100.0% | 100.0% | 733 | 841 | 604 |
| glare | 10 | 8/10 | 97.3% | 100.0% | 95.2% | 757 | 847 | 630 |
| crumpled | 10 | 9/10 | 98.1% | 100.0% | 100.0% | 716 | 888 | 618 |
| low_light | 10 | 9/10 | 67.7% | 92.6% | 90.5% | 707 | 778 | 602 |
| ALL | 50 | 46/50 | 91.7% | 98.5% | 97.1% | 724 | 847 | 614 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
