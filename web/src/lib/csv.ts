/**
 * The page's host when it runs as a published Claude artifact (the role demos). Only `use` is
 * promised; a page anywhere else has no `window.claude`.
 */
interface ArtifactHost {
  use(name: 'downloads'): Promise<{
    save(request: { filename: string; data: string }): Promise<unknown>
  } | null>
}

/** Builds a CSV file from rows and offers it to the viewer (FR-25 export). */
export function downloadCsv(filename: string, header: string[], rows: (string | number)[][]): void {
  const cell = (value: string | number) => {
    const text = String(value)
    return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
  }
  const body = [header, ...rows].map((row) => row.map(cell).join(',')).join('\n')
  const host = (window as unknown as { claude?: ArtifactHost }).claude
  if (host) {
    // An artifact may not download by itself: the viewer is asked to accept the file.
    // Declining is the viewer's choice, so nothing more is shown.
    void host
      .use('downloads')
      .then((downloads) => downloads?.save({ filename, data: body }))
      .catch(() => undefined)
    return
  }
  const url = URL.createObjectURL(new Blob([body], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.click()
  URL.revokeObjectURL(url)
}
