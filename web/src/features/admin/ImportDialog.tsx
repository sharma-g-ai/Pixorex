import { useState, type ReactNode } from 'react'
import { Badge, type BadgeTone } from '../../components/Badge'
import { Button } from '../../components/Button'
import { Dialog } from '../../components/Dialog'
import { FilePicker } from '../../components/FilePicker'
import { Note } from '../../components/Page'

export interface ImportCount {
  label: string
  count: number
  tone: BadgeTone
}

/**
 * Load rows from PPG's Excel file (D-02, D-03): pick a file, see what it would change, then load.
 * Static screens: whatever file is picked, the preview is the sample the caller passes in. With
 * allOrNothing, one bad row refuses the whole file; a file with "error" in its name shows that case.
 */
export function ImportDialog({
  title,
  intro,
  counts,
  problems,
  allOrNothing = false,
  toLoad,
  noun,
  onLoad,
  onClose,
}: {
  title: string
  intro: ReactNode
  counts: ImportCount[]
  /** Bad rows, one line each: skipped, or with allOrNothing they refuse the file. */
  problems: string[]
  allOrNothing?: boolean
  toLoad: number
  /** Plural, e.g. "items". */
  noun: string
  onLoad: () => void
  onClose: () => void
}) {
  const [file, setFile] = useState<string | null>(null)
  const shown = allOrNothing && !/error/i.test(file ?? '') ? [] : problems
  const refused = allOrNothing && shown.length > 0
  return (
    <Dialog
      title={title}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!file || toLoad === 0 || refused}
            onClick={() => {
              onLoad()
              onClose()
            }}
          >
            {refused ? 'File refused' : toLoad === 0 ? 'Nothing to load' : `Load ${toLoad} ${noun}`}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>{intro}</p>
        <FilePicker accept=".xlsx,.csv" hint=".xlsx or .csv" fileName={file} onPick={(f) => setFile(f.name)} />
        {file && (
          <div className="flex flex-col gap-2">
            {!refused &&
              counts.map((c) => (
                <div key={c.label} className="flex items-center justify-between">
                  <span>{c.label}</span>
                  <Badge tone={c.tone}>{c.count}</Badge>
                </div>
              ))}
            {shown.length > 0 && (
              <div className="flex items-center justify-between">
                <span>{refused ? 'File refused — nothing was loaded' : 'Rows with errors — skipped'}</span>
                <Badge tone="danger">{shown.length}</Badge>
              </div>
            )}
            {shown.map((p) => (
              <Note key={p} tone="warning">
                {p}
              </Note>
            ))}
          </div>
        )}
      </div>
    </Dialog>
  )
}
