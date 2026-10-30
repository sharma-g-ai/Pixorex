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
 * Static screens: whatever file is picked, the preview is the sample the caller passes in.
 */
export function ImportDialog({
  title,
  intro,
  counts,
  problems,
  toLoad,
  noun,
  onLoad,
  onClose,
}: {
  title: string
  intro: ReactNode
  counts: ImportCount[]
  /** Rows skipped, one line each. */
  problems: string[]
  toLoad: number
  /** Plural, e.g. "items". */
  noun: string
  onLoad: () => void
  onClose: () => void
}) {
  const [file, setFile] = useState<string | null>(null)
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
            disabled={!file || toLoad === 0}
            onClick={() => {
              onLoad()
              onClose()
            }}
          >
            {toLoad === 0 ? 'Nothing to load' : `Load ${toLoad} ${noun}`}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>{intro}</p>
        <FilePicker accept=".xlsx,.csv" hint=".xlsx or .csv" fileName={file} onPick={(f) => setFile(f.name)} />
        {file && (
          <div className="flex flex-col gap-2">
            {counts.map((c) => (
              <div key={c.label} className="flex items-center justify-between">
                <span>{c.label}</span>
                <Badge tone={c.tone}>{c.count}</Badge>
              </div>
            ))}
            {problems.length > 0 && (
              <div className="flex items-center justify-between">
                <span>Rows with errors — skipped</span>
                <Badge tone="danger">{problems.length}</Badge>
              </div>
            )}
            {problems.map((p) => (
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
