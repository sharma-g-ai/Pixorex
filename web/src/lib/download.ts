/** Saves text as a file in the browser's downloads (used for small CSV exports). */
export function downloadText(fileName: string, text: string, type = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob([text], { type }))
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  link.click()
  URL.revokeObjectURL(url)
}

/** "pixorex-scans-2026-10-05.csv" */
export function exportFileName(kind: string, now: Date = new Date()): string {
  return `pixorex-${kind.replace('_', '-')}-${now.toISOString().slice(0, 10)}.csv`
}
