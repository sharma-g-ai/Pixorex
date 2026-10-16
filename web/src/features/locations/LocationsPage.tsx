import { useState } from 'react'
import { useLocation, useSearchParams } from 'react-router'
import { useBusinessUnits } from '../../api/businessUnits'
import { useLocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { SelectField } from '../../components/SelectField'
import { Tabs } from '../../components/Tabs'
import { LevelsEditor } from './LevelsEditor'
import { LocationTreeView } from './LocationTreeView'
import { PublishDialog } from './PublishDialog'

type TabKey = 'levels' | 'locations'

/** EA-02 Locations setup for one unit (canvas EA 12, 19; contracts 2.1–2.8). */
export function LocationsPage() {
  const units = useBusinessUnits()
  const [params, setParams] = useSearchParams()
  const created = (useLocation().state as { createdUnit?: string } | null)?.createdUnit
  const list = units.data ?? []
  const buId = params.get('unit') ?? list[0]?.bu_id

  return (
    <>
      <PageHeader
        title="Locations"
        subtitle="Levels and locations technicians pick from when they scan"
        actions={
          list.length > 0 && (
            <SelectField
              label="Business unit"
              hideLabel
              className="w-72"
              options={list.map((u) => ({ value: u.bu_id, label: u.name }))}
              value={buId}
              onChange={(e) => setParams({ unit: e.target.value })}
            />
          )
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8">
        {created && (
          <Alert tone="info" role="status">
            <b>{created}</b> was created. Next, set up its locations.
          </Alert>
        )}
        {units.isPending && <Card>Loading units…</Card>}
        {units.data && list.length === 0 && (
          <Card title="No business units yet">Create a unit on the Overview page first.</Card>
        )}
        {buId && (
          <UnitLocations
            key={buId}
            buId={buId}
            unitName={list.find((u) => u.bu_id === buId)?.name ?? ''}
          />
        )}
      </div>
    </>
  )
}

function UnitLocations({ buId, unitName }: { buId: string; unitName: string }) {
  const setup = useLocationSetup(buId)
  const [tab, setTab] = useState<TabKey>('levels')
  const [publishing, setPublishing] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  if (setup.isPending) return <Card>Loading locations…</Card>
  if (setup.isError) return <Card>We couldn't load this unit's locations. Please refresh.</Card>

  const data = setup.data
  const live = data.status === 'published'

  return (
    <>
      <Alert tone="info" role={notice ? 'status' : undefined}>
        <div className="flex flex-wrap items-center gap-3">
          <span className="grow">
            {notice ??
              (live
                ? 'Published — locked to protect scan history. Levels and locations can’t be added, edited or deleted.'
                : 'Being set up · not published. Add, rename, move or delete anything until you publish. Publishing locks the unit.')}
          </span>
          {!live && data.nodes.length > 0 && (
            <Button onClick={() => setPublishing(true)}>Review &amp; publish</Button>
          )}
        </div>
      </Alert>

      <Tabs<TabKey>
        label="Location setup"
        tabs={[
          { key: 'levels', label: '1 · Levels', count: data.levels.length },
          { key: 'locations', label: '2 · Locations', count: data.nodes.length },
        ]}
        current={tab}
        onChange={setTab}
      />

      {tab === 'levels' ? (
        <LevelsEditor
          key={JSON.stringify(data.levels)}
          buId={buId}
          setup={data}
          onDone={() => setTab('locations')}
        />
      ) : (
        <LocationTreeView buId={buId} setup={data} onEditLevels={() => setTab('levels')} />
      )}

      {publishing && (
        <PublishDialog
          buId={buId}
          unitName={unitName}
          setup={data}
          onClose={() => setPublishing(false)}
          onPublished={() => {
            setPublishing(false)
            setNotice(`${unitName} is published. Technicians get the tree on their next sync.`)
          }}
        />
      )}
    </>
  )
}
