# Page and source profile contracts

## Shared identity and value layers

- `delivery_note_number` is stored as a string. Every submitted page must carry an operator-verified delivery number matching its session.
- Printed page number and declared total are verified against the saved page source. Capture order does not define printed order.
- Each quantity-bearing printed occurrence retains its own occurrence ID and source page. An article number is not a row key.
- Preserve three layers: raw OCR observation, verified document value, and physically counted value. Corrections change the verified value, not the raw observation. Physical counts do not change document quantities.
- Quantity-less set headings remain context with no receiving quantity. Batch Qty is not an additional product occurrence when a main Total Qty is present.
- A missing/ambiguous required article or main quantity remains unresolved. It is never replaced with zero, inferred remainder, a sample value, or a quantity from a nearby batch block.

## Colombo PPG Delivery Note (supported profile)

| Page role | Required identity/evidence | Receiving fields | Exclusions / notes |
|---|---|---|---|
| Summary page | Printed delivery number, printed page/total; optional summary `Piece` | No receiving rows | S1 and S2 page 1 are summary-only. The summary is optional. A readable mismatch requires explicit review, never row balancing. |
| Product page | Same delivery identity and printed page/total | Printed `Article`, main `Total Qty`, unit `PC`, occurrence/source page | Exclude Batch Qty as separate receipt values. Keep quantity-less set headings as context. |
| Continuation page | Same identity and printed page/total | Every printed main Article/Total Qty occurrence | Preserve repeated identifiers as distinct rows; page may contain components without new Item sequence labels. |
| Short final page | Same identity and printed page/total | Printed receiving occurrences | Do not require a minimum row count or a full-height table. |

Fixture references: S1 `5319364114` (4 printed pages, 7 occurrences, 62 PC); S2 `5319358250` (6 pages, 14 occurrences, 13 distinct identifiers, 100 PC). These are manual source transcriptions used as deterministic parser test inputs, not OCR measurements.

## Panama Picking List (mapping pending; profile unsupported in app)

Observed source labels are `Material #`, `Order Qty`, and `Batch Qty`. The business mapping from Material # to Article and from Order Qty to Document Quantity remains **pending approval**. The current parser rejects the Picking List layout. It does not yet expose the candidate values in a source-review/draft screen. No Picking List page can be submitted as a mapped receiving form.

The proposal's S3 contains two different deliveries in one PDF. A PDF capture batch is not a single-delivery identity. The app must keep `5324642228` pages separate from the one-page `5324642249` delivery if this profile is implemented. Page 1 is not globally treated as a summary page. Detached batch entries remain excluded until association is explicitly established by the source profile.

No approval artifact for the business mapping was found in the supplied repository/proposal inputs. Do not infer or encode one.

## Summary-count review rule

The printed `Piece`/footer summary is optional. If unreadable, the app may still finalize after all required page and item checks pass. If readable and different from the sum of document quantities, show the discrepancy and require operator acknowledgment. Acknowledgment is audited and retains the printed summary and all item rows as-is. Editing or adding document rows clears a prior mismatch acknowledgment when the document total changes.
