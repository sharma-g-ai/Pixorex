import { useMemo, useState } from 'react'
import { useLocation, useSearchParams } from 'react-router'
import { useBusinessUnits } from '../../api/businessUnits'
import { errorMessage } from '../../api/client'
import {
  useCreateSkeleton,
  useLocationSetup,
  useSetLevels,
  useUpdateNode,
  type LocationSetup,
} from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { SelectField } from '../../components/SelectField'
import { LevelsEditor } from './LevelsEditor'
import { LocationTreeView } from './LocationTreeView'
import { PublishDialog } from './PublishDialog'
import { SetupGuide } from './SetupGuide'
import { toFix, treeRows } from './locationTree'
import { guideLevels, guideRenames, setupScreen, type GuidePart } from './guideRules'

/**
 * EA-02 Locations setup for one unit (contracts 2.1–2.8). Guided setup until the first place
 * exists, then the working page (decision 2026-11-13, docs/proposals/location-setup-flow-plan.md).
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
            siteName={list.find((u) => u.bu_id === buId)?.facility_name ?? ''}
          />
        )}
      </div>
    </>
  )
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/** The working page's banner: what is left before publishing (placeholders block it). */
function notPublishedText({ placeholders, empty }: { placeholders: number; empty: number }) {
  if (placeholders > 0)
    return `Not published yet. Rename ${plural(placeholders, 'temporary name', 'temporary names')} before you can publish.`
  if (empty > 0)
    return `Not published yet. ${plural(empty, 'place has', 'places have')} nothing inside yet, so technicians can't scan there. You can still publish.`
  return 'Not published yet. Everything is ready. After publishing, nothing here can be changed.'
}

const KEPT_PLACEHOLDERS =
  'Some places kept a temporary name and are marked Placeholder below. Rename them to continue.'

/**
 * Create from the guided setup with the existing calls only (plan D1): the kinds (2.2), the
 * skeleton (2.3), then one rename (2.5) per place, which also clears its placeholder flag.
 */
function useCreateFromGuide(buId: string, setup: LocationSetup) {
  const setLevels = useSetLevels(buId)
  const skeleton = useCreateSkeleton(buId)
  const rename = useUpdateNode(buId)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const create = async (parts: GuidePart[]) => {
    setBusy(true)
    setError(null)
    let treeMade = false
    try {
      await setLevels.mutateAsync(guideLevels(parts, setup.levels))
      const tree = await skeleton.mutateAsync(undefined)
      treeMade = true
      const renames = guideRenames(parts, tree)
      if (!renames) return setError(KEPT_PLACEHOLDERS)
      for (const r of renames) await rename.mutateAsync({ nodeId: r.node_id, name: r.name })
    } catch (err) {
      setError(treeMade ? `${KEPT_PLACEHOLDERS} (${errorMessage(err)})` : errorMessage(err))
    } finally {
      setBusy(false)
    }
  }
  return { create, busy, error }
}

function UnitLocations({
  buId,
  unitName,
  siteName,
}: {
  buId: string
  unitName: string
  siteName: string
}) {
  const setup = useLocationSetup(buId)
  const [editingKinds, setEditingKinds] = useState(false)
  const [publishing, setPublishing] = useState(false)
  const [previewId, setPreviewId] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const guide = useCreateFromGuide(buId, setup.data ?? emptySetup)
  const left = useMemo(
    () =>
      setup.data ? toFix(setup.data.levels, treeRows(setup.data.levels, setup.data.nodes)) : null,
    [setup.data],
  )

  if (setup.isPending) return <Card>Loading locations…</Card>
  if (setup.isError) return <Card>We couldn't load this unit's locations. Please refresh.</Card>

  const data = setup.data
  const live = data.status === 'published'

  if (setupScreen(data) === 'guide' || guide.busy) {
    return (
      <SetupGuide
        key={siteName}
        levels={data.levels}
        siteName={siteName}
        busy={guide.busy}
        error={guide.error}
        onCreate={(parts) => void guide.create(parts)}
      />
    )
  }

  return (
    <>
      <Alert tone="info" role={notice ? 'status' : undefined}>
        <div className="flex flex-wrap items-center gap-3">
          <span className="grow">
            {notice ??
              (live
                ? 'Published — locked to protect scan history. Levels and locations can’t be added, edited or deleted.'
                : notPublishedText(left ?? { placeholders: 0, empty: 0 }))}
          </span>
          <Button variant="secondary" onClick={() => setEditingKinds((on) => !on)}>
            {editingKinds ? 'Back to places' : live ? 'View kinds' : 'Edit kinds'}
          </Button>
          {!live && <Button onClick={() => setPublishing(true)}>Review &amp; publish</Button>}
        </div>
      </Alert>
      {guide.error && (left?.placeholders ?? 0) > 0 && <Alert tone="danger">{guide.error}</Alert>}

      {editingKinds ? (
        <LevelsEditor
          key={JSON.stringify(data.levels)}
          buId={buId}
          setup={data}
          onDone={() => setEditingKinds(false)}
        />
      ) : (
        <LocationTreeView buId={buId} setup={data} previewId={previewId} onPreview={setPreviewId} />
      )}

      {publishing && (
        <PublishDialog
          buId={buId}
          unitName={unitName}
          setup={data}
          onClose={() => setPublishing(false)}
          onShow={(nodeId) => {
            setPublishing(false)
            setEditingKinds(false)
            setPreviewId(nodeId)
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

const emptySetup: LocationSetup = { version_id: '', status: 'not_published', levels: [], nodes: [] }
