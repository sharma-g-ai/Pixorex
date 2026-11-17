import { useMemo, useState } from 'react'
import { useLocation, useSearchParams } from 'react-router'
import { useBusinessUnits } from '../../api/businessUnits'
import { useLocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { SelectField } from '../../components/SelectField'
import { LocationTreeView } from './LocationTreeView'
import { PublishDialog } from './PublishDialog'
import { toFix, treeRows } from './locationTree'

/**
 * EA-02 Locations setup for one unit (contracts 2.1–2.8), on one screen: kinds and places
 * together, then Review & publish (decision 2026-11-16 in STATE.md).
 */
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
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {units.isPending && <Card>Loading units…</Card>}
        {units.data && list.length === 0 && (
          <Card title="No business units yet">Create a unit on the Overview page first.</Card>
        )}
        {buId && (
          <UnitLocations
            key={buId}
            buId={buId}
            unitName={list.find((u) => u.bu_id === buId)?.name ?? ''}
            siteName={list.find((u) => u.bu_id === buId)?.facility_name ?? ''}
            created={created}
          />
        )}
      </div>
    </>
  )
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/** The banner: what is left before publishing (temporary names block it). */
function notPublishedText(
  { placeholders, empty }: { placeholders: number; empty: number },
  siteName: string,
  places: number,
) {
  // The facility alone is not a setup: there is nothing for a technician to pick.
  if (places <= 1) return `Not published yet. Add the first places inside ${siteName}.`
  if (placeholders > 0)
    return `Not published yet. Rename ${plural(placeholders, 'temporary name', 'temporary names')} before you can publish.`
  if (empty > 0)
    return `Not published yet. ${plural(empty, 'place has', 'places have')} nothing inside yet, so technicians can't scan there. You can still publish.`
  return 'Not published yet. Everything is ready. After publishing, nothing here can be changed.'
}

function UnitLocations({
  buId,
  unitName,
  siteName,
  created,
}: {
  buId: string
  unitName: string
  siteName: string
  /** The unit's name when the admin has just created it and landed here. */
  created?: string
}) {
  const setup = useLocationSetup(buId)
  const [publishing, setPublishing] = useState(false)
  const [focusId, setFocusId] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const left = useMemo(
    () =>
      setup.data ? toFix(setup.data.levels, treeRows(setup.data.levels, setup.data.nodes)) : null,
    [setup.data],
  )

  if (setup.isPending) return <Card>Loading locations…</Card>
  if (setup.isError) return <Card>We couldn't load this unit's locations. Please refresh.</Card>

  const data = setup.data
  const live = data.status === 'published'

  return (
    <>
      {/* One bar: where the unit stands, and under it what the last change did. */}
      <Alert tone="info">
        <div className="flex flex-wrap items-center gap-3">
          <div className="grow">
            <p>
              {created && data.nodes.length <= 1 && (
                <>
                  <b>{created}</b> was created.{' '}
                </>
              )}
              {live
                ? 'Published — locked to protect scan history. Kinds and places can’t be added, renamed or deleted.'
                : notPublishedText(
                    left ?? { placeholders: 0, empty: 0 },
                    siteName,
                    data.nodes.length,
                  )}
            </p>
            {notice && (
              <p role="status" className="mt-0.5 text-small">
                {notice}
              </p>
            )}
          </div>
          {!live && data.nodes.length > 1 && (
            <Button onClick={() => setPublishing(true)}>Review &amp; publish</Button>
          )}
        </div>
      </Alert>

      {/* A new key on "Show me": the tree opens fully, with no search, so the place is in view. */}
      <LocationTreeView
        key={`${siteName}:${focusId ?? ''}`}
        buId={buId}
        setup={data}
        siteName={siteName}
        focusId={focusId}
        onNotice={setNotice}
      />

      {publishing && (
        <PublishDialog
          buId={buId}
          unitName={unitName}
          setup={data}
          onClose={() => setPublishing(false)}
          onShow={(nodeId) => {
            setPublishing(false)
            setFocusId(nodeId)
          }}
          onPublished={() => {
            setPublishing(false)
            setNotice(`${unitName} is published. Technicians get the tree on their next sync.`)
          }}
        />
      )}
    </>
  )
}
