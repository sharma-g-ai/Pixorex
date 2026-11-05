/**
 * A scan ID as people read it: 1000000040 → "100 000 004 0" (9-digit counter, then the
 * check digit). Anything else (older numbers in tests or exports) is shown as it is.
 */
export function formatScanId(recordNo: string): string {
  const m = /^(\d{3})(\d{3})(\d{3})(\d)$/.exec(recordNo)
  return m ? `${m[1]} ${m[2]} ${m[3]} ${m[4]}` : recordNo
}
