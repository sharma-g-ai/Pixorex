import { useState } from 'react'
import { useEquipmentTypes, type EquipmentType } from '../../api/equipmentTypes'
import { useDashboard } from '../../app/DashboardContext'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { AiAssistDialog } from './AiAssistDialog'
import { typeStatus, typeSummary } from './fieldRules'
import { NewTypeDialog } from './NewTypeDialog'
import { TypeDetail } from './TypeDetail'

/** BU-02 Equipment types of the current unit (canvas BU 24; contracts 2.10–2.20). */
export function EquipmentTypesPage() {
  const { unit } = useDashboard()
  if (!unit?.bu_id) return null
  return <TypesOfUnit key={unit.bu_id} buId={unit.bu_id} unitName={unit.name ?? ''} />
}

function TypesOfUnit({ buId, unitName }: { buId: string; unitName: string }) {
  const types = useEquipmentTypes(buId)
  const [selected, setSelected] = useState<string | null>(null)
  const [dialog, setDialog] = useState<'new' | 'ai' | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const list = types.data ?? []
  const current = list.find((t) => t.type_id === selected) ?? list[0]
  const created = (type: EquipmentType) => {
    setDialog(null)
    setSelected(type.type_id)
    setNotice(`${type.name} was created as Not published. Add and check its fields, then publish.`)
  }

  return (
    <>
      <PageHeader
        title="Equipment types"
        subtitle={`What technicians in ${unitName} can scan`}
        actions={
          <>
            <Button variant="secondary" onClick={() => setDialog('ai')}>
              AI-assist from a photo
            </Button>
            <Button onClick={() => setDialog('new')}>+ New type</Button>
          </>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        {types.isPending && <Card>Loading equipment types…</Card>}
        {types.isError && <Card>We couldn't load the equipment types. Please refresh.</Card>}
        {types.data && list.length === 0 && (
          <Card title="No equipment types yet">
            <p className="text-body text-ink-muted">
              Create the first type, blank or from a photo with AI-assist. Technicians in {unitName}{' '}
              can scan once a type is published.
            </p>
          </Card>
        )}
        {current && (
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
            <Card title={`Register · ${list.length}`} className="w-full shrink-0 lg:w-80">
              <ul className="flex flex-col gap-1">
                {list.map((t) => {
                  const status = typeStatus(t)
                  const active = t.type_id === current.type_id
                  return (
                    <li key={t.type_id}>
                      <button
                        type="button"
                        aria-current={active ? 'true' : undefined}
                        onClick={() => setSelected(t.type_id)}
                        className={`flex w-full items-center gap-2 rounded-lg px-3 py-2.5 text-left ${active ? 'bg-brand-navy-tint' : 'hover:bg-page'}`}
                      >
                        <span className="min-w-0 grow">
                          <span className="block truncate text-body font-semibold">{t.name}</span>
                          <span className="block text-xs text-ink-subtle">{typeSummary(t)}</span>
                        </span>
                        <Badge tone={status.tone}>
                          {t.status === 'published' ? 'Published' : 'Draft'}
                        </Badge>
                      </button>
                    </li>
                  )
                })}
              </ul>
            </Card>
            <TypeDetail
              key={current.type_id}
              buId={buId}
              unitName={unitName}
              typeId={current.type_id}
              onDeleted={(name) => {
                setSelected(null)
                setNotice(`${name} was deleted.`)
              }}
            />
          </div>
        )}
      </div>

      {dialog === 'new' && (
        <NewTypeDialog
          buId={buId}
          types={list}
          onClose={() => setDialog(null)}
          onCreated={created}
        />
      )}
      {dialog === 'ai' && (
        <AiAssistDialog
          buId={buId}
          types={list}
          onClose={() => setDialog(null)}
          onCreated={created}
        />
      )}
    </>
  )
}
