import { useState } from 'react'
import {
  useDeleteField,
  useDeleteType,
  useEquipmentType,
  usePublishType,
  useRenameType,
  useReorderFields,
  useUpdateField,
  type Field,
} from '../../api/equipmentTypes'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { DataTable, type Column } from '../../components/DataTable'
import { TextField } from '../../components/TextField'
import { FieldDialog } from './FieldDialog'
import { dataTypeLabels, moved, percent, typeStatus } from './fieldRules'

type Open =
  | { kind: 'field'; field?: Field }
  | { kind: 'delete-field'; field: Field }
  | { kind: 'rename' | 'delete' | 'publish' }
  | null

interface TypeDetailProps {
  buId: string
  unitName: string
  typeId: string
  onDeleted: (name: string) => void
}

/** One equipment type with its fields (canvas BU 24, right side; contracts 2.12–2.19). */
export function TypeDetail({ buId, unitName, typeId, onDeleted }: TypeDetailProps) {
  const type = useEquipmentType(typeId)
  const updateField = useUpdateField(buId, typeId)
  const deleteField = useDeleteField(buId, typeId)
  const reorder = useReorderFields(buId, typeId)
  const rename = useRenameType(buId, typeId)
  const deleteType = useDeleteType(buId, typeId)
  const publish = usePublishType(buId, typeId)
  const [open, setOpen] = useState<Open>(null)
  const [newName, setNewName] = useState('')
  const [notice, setNotice] = useState<string | null>(null)

  if (type.isPending) return <Card>Loading type…</Card>
  if (type.isError) return <Card>We couldn't load this type. Please refresh.</Card>

  const t = type.data
  const fields = [...(t.fields ?? [])].sort((a, b) => a.sort_order - b.sort_order)
  const locked = t.status === 'published'
  const status = typeStatus(t)
  const done = (text: string) => {
    setOpen(null)
    setNotice(text)
  }

  const toggle = (label: string, pressed: boolean, onClick: () => void) => (
    <button
      type="button"
      aria-pressed={pressed}
      disabled={locked || updateField.isPending}
      className={`rounded-full px-2.5 py-0.5 text-meta font-bold ${pressed ? 'bg-brand-navy-soft text-brand-navy' : 'bg-page text-ink-muted'} disabled:cursor-default`}
      onClick={onClick}
    >
      {label}
    </button>
  )

  const columns: Column<Field>[] = [
    {
      header: 'Order',
      width: 0.5,
      cell: (f) => <span className="font-mono text-small">{fields.indexOf(f) + 1}</span>,
    },
    {
      header: 'Field',
      width: 2,
      cell: (f) => (
        <div className="min-w-0">
          <div className="truncate font-semibold">{f.label}</div>
          <div className="text-xs text-ink-subtle">
            {dataTypeLabels[f.data_type]}
            {f.options?.length ? ` · ${f.options.join(', ')}` : ''}
          </div>
        </div>
      ),
    },
    {
      header: 'Required',
      width: 1,
      cell: (f) =>
        toggle(f.is_required ? 'Required' : 'Optional', f.is_required, () =>
          updateField.mutate({ fieldId: f.field_id, is_required: !f.is_required }),
        ),
    },
    {
      header: 'Critical',
      width: 1,
      cell: (f) =>
        toggle(f.is_critical ? 'Critical' : 'Not critical', f.is_critical, () =>
          updateField.mutate({ fieldId: f.field_id, is_critical: !f.is_critical }),
        ),
    },
    {
      header: 'Format check',
      width: 1.2,
      cell: (f) => f.format_rule ?? <span className="text-ink-subtle">—</span>,
    },
    { header: 'Flag', width: 0.6, cell: (f) => `< ${percent(f.flag_below_confidence)}` },
    ...(locked
      ? []
      : [
          {
            header: 'Actions',
            width: 1.8,
            align: 'right' as const,
            cell: (f: Field) => {
              const i = fields.indexOf(f)
              const ids = fields.map((x) => x.field_id)
              return (
                <div className="flex justify-end gap-2.5">
                  <button
                    type="button"
                    className={buttonClasses('link')}
                    disabled={i === 0}
                    aria-label={`Move ${f.label} up`}
                    onClick={() => reorder.mutate(moved(ids, i, -1))}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    className={buttonClasses('link')}
                    disabled={i === fields.length - 1}
                    aria-label={`Move ${f.label} down`}
                    onClick={() => reorder.mutate(moved(ids, i, 1))}
                  >
                    ↓
                  </button>
                  <button
                    type="button"
                    className={buttonClasses('link')}
                    aria-label={`Edit ${f.label}`}
                    onClick={() => setOpen({ kind: 'field', field: f })}
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    className={buttonClasses('danger-link')}
                    aria-label={`Delete ${f.label}`}
                    onClick={() => setOpen({ kind: 'delete-field', field: f })}
                  >
                    Delete
                  </button>
                </div>
              )
            },
          },
        ]),
  ]

  return (
    <div className="flex min-w-0 grow flex-col gap-4">
      <Card>
        <div className="flex flex-wrap items-center gap-3">
          <div className="min-w-0 grow">
            <div className="flex items-center gap-2.5">
              <h2 className="truncate text-lg font-bold">{t.name}</h2>
              <Badge tone={status.tone}>{status.label}</Badge>
            </div>
            <p className="text-small text-ink-muted">
              {t.created_via === 'ai_assist'
                ? 'Started with AI-assist'
                : t.created_via === 'copy'
                  ? 'Started as a copy'
                  : 'Started blank'}{' '}
              · version {t.version_no}
            </p>
          </div>
          {!locked && (
            <>
              <Button
                variant="secondary"
                onClick={() => {
                  setNewName(t.name)
                  setOpen({ kind: 'rename' })
                }}
              >
                Rename type
              </Button>
              <Button variant="secondary" onClick={() => setOpen({ kind: 'delete' })}>
                Delete type
              </Button>
              <Button disabled={fields.length === 0} onClick={() => setOpen({ kind: 'publish' })}>
                Publish
              </Button>
            </>
          )}
        </div>
        <Alert tone="info" className="mt-3">
          {locked ? (
            <>
              <b>Published and locked.</b> Technicians in {unitName} pick this type. Its fields
              can't be edited and the type can't be deleted. Need something different? Create a new
              type.
            </>
          ) : (
            <>
              <b>Not published yet.</b> Add, edit, reorder or delete anything, then publish. Once
              published, this type can't be edited or deleted.
            </>
          )}
        </Alert>
      </Card>

      {notice && (
        <Alert tone="info" role="status">
          {notice}
        </Alert>
      )}

      <Card
        title={`Fields · ${fields.length}`}
        action={!locked && <Button onClick={() => setOpen({ kind: 'field' })}>+ Add field</Button>}
      >
        <DataTable
          label={`Fields of ${t.name}`}
          columns={columns}
          rows={fields}
          rowKey={(f) => f.field_id}
          empty="No fields yet. Add the fields technicians should capture from this label. Technicians can pick this type once it has at least one field."
        />
        <p className="mt-3 text-xs text-ink-subtle">
          <b>Required</b> — the technician must fill it. <b>Critical</b> — always flagged for review
          when the AI isn’t sure. <b>Flag</b> — AI confidence under this number is flagged.
        </p>
      </Card>

      {open?.kind === 'field' && (
        <FieldDialog
          buId={buId}
          typeId={typeId}
          typeName={t.name}
          fields={fields}
          field={open.field}
          onClose={() => setOpen(null)}
          onSaved={(label) =>
            done(
              open.field ? `${label} was updated.` : `${label} was added at the end of the list.`,
            )
          }
        />
      )}
      {open?.kind === 'delete-field' && (
        <ConfirmDialog
          title={`Delete ${open.field.label}?`}
          confirmLabel="Yes, delete"
          danger
          onClose={() => setOpen(null)}
          onConfirm={async () => {
            await deleteField.mutateAsync(open.field.field_id)
            done(`${open.field.label} was deleted.`)
          }}
        >
          The type isn't published yet, so no technician has used this field.
        </ConfirmDialog>
      )}
      {open?.kind === 'rename' && (
        <ConfirmDialog
          title="Rename type"
          confirmLabel="Save name"
          disabled={!newName.trim()}
          onClose={() => setOpen(null)}
          onConfirm={async () => {
            await rename.mutateAsync(newName.trim())
            done(`Renamed to ${newName.trim()}.`)
          }}
        >
          <TextField
            label="Name technicians see"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
          />
          <p className="mt-2 text-xs text-ink-subtle">
            You can rename it until the type is published.
          </p>
        </ConfirmDialog>
      )}
      {open?.kind === 'delete' && (
        <ConfirmDialog
          title={`Delete ${t.name}?`}
          confirmLabel="Yes, delete type"
          danger
          onClose={() => setOpen(null)}
          onConfirm={async () => {
            await deleteType.mutateAsync(undefined)
            onDeleted(t.name)
          }}
        >
          <ul className="flex list-inside list-disc flex-col gap-2">
            <li>
              {t.name} and its {fields.length} {fields.length === 1 ? 'field' : 'fields'} are
              removed.
            </li>
            <li>It was never published, so no technician has used it.</li>
            <li>This can’t be undone.</li>
          </ul>
        </ConfirmDialog>
      )}
      {open?.kind === 'publish' && (
        <ConfirmDialog
          title={`Publish ${t.name}?`}
          confirmLabel="Publish and lock"
          cancelLabel="Keep editing"
          onClose={() => setOpen(null)}
          onConfirm={async () => {
            await publish.mutateAsync(undefined)
            done(
              `${t.name} is published. Technicians in ${unitName} can pick it after their next sync.`,
            )
          }}
        >
          <p className="mb-2">
            Technicians will fill:{' '}
            <b className="text-ink">{fields.map((f) => f.label).join(', ')}</b>
          </p>
          <ul className="flex list-inside list-disc flex-col gap-2">
            <li>Technicians in {unitName} can pick it after their next sync.</li>
            <li>
              <b className="text-ink">It's locked once published:</b> no renaming, no field changes
              and no deleting.
            </li>
          </ul>
        </ConfirmDialog>
      )}
    </div>
  )
}
