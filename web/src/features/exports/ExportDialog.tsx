import { useState } from 'react'
import type { ExportColumn, ExportInput, ExportJob } from '../../api/exports'
import { useCreateExport } from '../../api/exports'
import { ChoiceCard } from '../../components/ChoiceCard'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { SelectField, type SelectOption } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import { downloadText, exportFileName } from '../../lib/download'
import { MASKED_NOTE } from './exportText'

/** One "Which scans" choice and the filters it stands for. */
export interface ExportScope {
  key: string
  label: string
  filters: NonNullable<ExportInput['filters']>
}

/** The "Include" choices of the canvas (contract 4.1 options.columns, S5 v0.3.1). */
const exportColumns: { key: ExportColumn; label: string }[] = [
  { key: 'field_values', label: 'Extracted field values' },
  { key: 'ai_vs_technician', label: 'AI value next to technician value' },
  { key: 'review_decision', label: 'Review decision and reviewer' },
]

interface ExportDialogProps {
  kind: 'scans' | 'audit_log'
  title: string
  /** Scans: which scans (radio). Audit log: none, pick units and actions instead. */
  scopes?: ExportScope[]
  /** Audit log: unit and action dropdowns. */
  unitOptions?: SelectOption[]
  categoryOptions?: SelectOption[]
  note: string
  onClose: () => void
  /** A large export continues in the background; the page shows its progress. */
  onQueued: (job: ExportJob) => void
  onDownloaded: () => void
}

/** "Export scans to CSV" / "Export audit log" (canvas BU 12, EA 21, EA 23; contract 4.1). */
export function ExportDialog(props: ExportDialogProps) {
  const create = useCreateExport()
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const [scope, setScope] = useState(props.scopes?.[0]?.key ?? '')
  const [unit, setUnit] = useState('')
  const [category, setCategory] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [columns, setColumns] = useState<ExportColumn[]>(exportColumns.map((c) => c.key))
  const [photoLinks, setPhotoLinks] = useState(false)

  const run = async () => {
    const scopeFilters = props.scopes?.find((s) => s.key === scope)?.filters ?? {}
    const body: ExportInput = {
      export_kind: props.kind,
      filters: {
        ...scopeFilters,
        ...(unit ? { bu_id: unit } : {}),
        ...(category ? { category } : {}),
        ...(from ? { from } : {}),
        ...(to ? { to } : {}),
      },
      ...(props.kind === 'scans' ? { options: { columns, include_photo_links: photoLinks } } : {}),
    }
    const result = await create.mutateAsync({ body, idempotencyKey })
    if (result.kind === 'file') {
      downloadText(exportFileName(props.kind), result.csv)
      props.onDownloaded()
    } else {
      props.onQueued(result.job)
    }
  }

  return (
    <ConfirmDialog
      title={props.title}
      confirmLabel="Download CSV"
      disabled={from !== '' && to !== '' && from > to}
      onClose={props.onClose}
      onConfirm={run}
    >
      <div className="flex flex-col gap-4">
        {props.scopes && (
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1.5 text-small font-semibold text-ink-muted">Which scans</legend>
            {props.scopes.map((s) => (
              <ChoiceCard
                key={s.key}
                name="export-scope"
                title={s.label}
                checked={scope === s.key}
                onChange={() => setScope(s.key)}
              />
            ))}
          </fieldset>
        )}
        {(props.unitOptions || props.categoryOptions) && (
          <div className="grid grid-cols-2 gap-3">
            {props.unitOptions && (
              <SelectField
                label="Units"
                options={[{ value: '', label: 'All units' }, ...props.unitOptions]}
                value={unit}
                onChange={(e) => setUnit(e.target.value)}
              />
            )}
            {props.categoryOptions && (
              <SelectField
                label="Type of action"
                options={[{ value: '', label: 'All actions' }, ...props.categoryOptions]}
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              />
            )}
          </div>
        )}
        <div className="grid grid-cols-2 gap-3">
          <TextField
            label="From"
            type="date"
            value={from}
            max={to || undefined}
            onChange={(e) => setFrom(e.target.value)}
          />
          <TextField
            label="To"
            type="date"
            value={to}
            min={from || undefined}
            onChange={(e) => setTo(e.target.value)}
          />
        </div>
        {props.kind === 'scans' && (
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1.5 text-small font-semibold text-ink-muted">Include</legend>
            {exportColumns.map((c) => (
              <ChoiceCard
                key={c.key}
                type="checkbox"
                title={c.label}
                checked={columns.includes(c.key)}
                onChange={(e) =>
                  setColumns((list) =>
                    e.target.checked ? [...list, c.key] : list.filter((k) => k !== c.key),
                  )
                }
              />
            ))}
            <ChoiceCard
              type="checkbox"
              title="Photo links (valid 1 hour)"
              checked={photoLinks}
              onChange={(e) => setPhotoLinks(e.target.checked)}
            />
          </fieldset>
        )}
        <p className="text-small">
          {props.note} {MASKED_NOTE}
        </p>
      </div>
    </ConfirmDialog>
  )
}
