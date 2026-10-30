import { useState } from 'react'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { SectionBar } from './SectionBar'
import { Card, Mono, Note } from '../../components/Page'
import { SelectField } from '../../components/SelectField'
import { TextAreaField } from '../../components/TextAreaField'
import type { LabelField } from '../../data/model'
import { userById } from '../../data/queries'
import { labelSchema } from '../../data/sample'
import { publishLabelSchema, useStore } from '../../data/store'
import { useViewer } from '../../app/viewer'
import { formatDateTime } from '../../lib/format'

/** FR-26: the fields read from a can label and their rules, changed without a code change. */
export function LabelSchemaPage() {
  useStore()
  const { user } = useViewer()
  const [fields, setFields] = useState<LabelField[]>(labelSchema.fields)
  const [editing, setEditing] = useState<LabelField | null>(null)
  const changed = fields.some((f, i) => JSON.stringify(f) !== JSON.stringify(labelSchema.fields[i]))

  return (
    <>
      <SectionBar
        title="Label schema"
        subtitle={`Version ${labelSchema.version} · published ${formatDateTime(labelSchema.publishedOn)} by ${userById(labelSchema.publishedBy)?.name}`}
        actions={
          <>
            {changed && <Badge tone="warning">Unpublished changes</Badge>}
            <Button
              variant="secondary"
              disabled={!changed}
              onClick={() => setFields(labelSchema.fields)}
            >
              Discard
            </Button>
            <Button disabled={!changed} onClick={() => publishLabelSchema(fields, user)}>
              Publish version {labelSchema.version + 1}
            </Button>
          </>
        }
      />
      <>
        <Card
          title="Fields read from the label"
          subtitle="FR-06: product, shade, component type, pack volume, article number and batch number"
          flush
        >
          <div className="p-4">
            <DataTable
              label="Label fields"
              rows={fields}
              rowKey={(f) => f.key}
              empty="No fields"
              columns={[
                {
                  header: 'Field',
                  width: 1.2,
                  cell: (f) => (
                    <div>
                      <div className="font-semibold">{f.label}</div>
                      <Mono>{f.key}</Mono>
                    </div>
                  ),
                },
                {
                  header: 'Required',
                  width: 0.9,
                  cell: (f) => (
                    <Badge tone={f.required === 'Always' ? 'success' : 'neutral'}>
                      {f.required}
                    </Badge>
                  ),
                },
                {
                  header: 'Used for',
                  width: 2,
                  cell: (f) => <span className="text-body-sm">{f.purpose}</span>,
                },
                {
                  header: 'Rule',
                  width: 1.6,
                  cell: (f) => <span className="text-body-sm">{f.rule}</span>,
                },
                {
                  header: '',
                  width: 0.4,
                  align: 'right',
                  cell: (f) => (
                    <Button variant="link" onClick={() => setEditing(f)}>
                      Edit
                    </Button>
                  ),
                },
              ]}
            />
          </div>
        </Card>

        <Card title="Component-type rules" subtitle="Open item D-10, as answered by PPG">
          <ul className="flex flex-col gap-2.5">
            {labelSchema.componentRules.map((r) => (
              <li key={r.when} className="flex flex-wrap items-center gap-2 text-body">
                <span className="rounded-md bg-page px-2 py-1 font-semibold">If</span>
                {r.when}
                <span className="rounded-md bg-brand-soft px-2 py-1 font-semibold text-brand">
                  then
                </span>
                {r.then}
              </li>
            ))}
          </ul>
        </Card>

        <Note>
          Matching (A-02): the article number ties a label to the delivery-note line and the master
          item list. If it cannot be read, product and shade are used instead; if neither matches,
          the scan is held for review rather than discarded. Three-component products are not
          expected (BRD §10).
        </Note>
      </>
      {editing && (
        <FieldDialog
          field={editing}
          onClose={() => setEditing(null)}
          onSave={(f) => {
            setFields((all) => all.map((x) => (x.key === f.key ? f : x)))
            setEditing(null)
          }}
        />
      )}
    </>
  )
}

function FieldDialog({
  field,
  onClose,
  onSave,
}: {
  field: LabelField
  onClose: () => void
  onSave: (f: LabelField) => void
}) {
  const [required, setRequired] = useState(field.required)
  const [rule, setRule] = useState(field.rule)
  return (
    <Dialog
      title={`Edit ${field.label}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => onSave({ ...field, required, rule: rule.trim() })}>
            Save to draft
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <SelectField
          label="Required"
          value={required}
          onChange={(e) => setRequired(e.target.value as LabelField['required'])}
          options={[
            { value: 'Always', label: 'Always' },
            { value: 'Where present', label: 'Where present' },
            { value: 'Base and 1K only', label: 'Base and 1K only' },
          ]}
        />
        <TextAreaField label="Rule" value={rule} onChange={(e) => setRule(e.target.value)} />
        <p className="text-small">
          Changes go live for every tablet when the new version is published.
        </p>
      </div>
    </Dialog>
  )
}
