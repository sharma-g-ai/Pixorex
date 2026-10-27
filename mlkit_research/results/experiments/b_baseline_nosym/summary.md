# MLKit baseline results

- Device: android RMX3710_14.0.0.1900(EX01)
- Cold start (first call, model load): 3334 ms
- Runs per image: 3 (latency = median)

| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |
|---|---|---|---|---|---|---|---|---|
| normal | 10 | 9/10 | 88.8% | 100.0% | 95.2% | 560 | 642 | 488 |
| shadow | 10 | 8/10 | 87.7% | 100.0% | 95.2% | 562 | 645 | 484 |
| glare | 10 | 8/10 | 88.1% | 100.0% | 100.0% | 554 | 626 | 480 |
| crumpled | 10 | 10/10 | 90.8% | 100.0% | 100.0% | 563 | 696 | 475 |
| low_light | 10 | 4/10 | 61.2% | 81.5% | 90.5% | 526 | 581 | 462 |
| ALL | 50 | 39/50 | 83.3% | 96.3% | 96.2% | 548 | 645 | 478 |

Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.
Pages with no item rows (both page 1s) count as usable when the DN number is read.
