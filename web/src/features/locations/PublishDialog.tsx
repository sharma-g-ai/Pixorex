import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { usePublishCheck, usePublishLocations, type LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Dialog } from '../../components/Dialog'
import { countsByLevel } from './locationTree'

interface PublishDialogProps {
  buId: string
  unitName: string
  setup: LocationSetup
  onClose: () => void
  onPublished: () => void
  /** "Show me": closes the dialog and previews that place. */
  onShow: (nodeId: string) => void
}

const SHOWN_PROBLEMS = 5
const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/**
 * Review & publish (contracts 2.7–2.8). Publishing is one-way, so that comes first. Only
 * placeholders block it (the API's can_publish); empty places are named as warnings (plan D2).
 */
export function PublishDialog({
  buId,
  unitName,
  setup,
  onClose,
  onPublished,
  onShow,
}: PublishDialogProps) {
  const check = usePublishCheck(buId, true)
  const publish = usePublishLocations(buId)
  const [error, setError] = useState<string | null>(null)

  const counts = countsByLevel(setup.levels, setup.nodes).filter(
    (c) => c.level.requirement !== 'off',
  )
  const placeholders = check.data?.placeholders_left ?? 0
  const empty = check.data?.empty_branches ?? []

  const confirm = () =>
    publish
      .mutateAsync()
      .then(onPublished)
      .catch((err: unknown) => setError(errorMessage(err)))

  return (
    <Dialog
      title={`Publish ${unitName}?`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Keep editing
          </Button>
          <Button
            disabled={!check.data?.can_publish || publish.isPending}
            onClick={() => void confirm()}
          >
            {publish.isPending ? 'Publishing…' : 'Publish and lock'}
          </Button>
        </>
      }
    >
      {check.isPending ? (
        <p>Checking the places…</p>
      ) : check.isError ? (
        <Alert tone="danger">{errorMessage(check.error)}</Alert>
      ) : (
        <div className="flex flex-col gap-4">
          <Alert tone="danger">
            <b>This can't be undone.</b> After publishing, nothing in this unit's kinds or places
            can be added, renamed or deleted.
          </Alert>
          <section aria-label="You are publishing">
            <h3 className="mb-2 text-small font-semibold text-ink-muted">You are publishing</h3>
            <dl className="flex flex-wrap gap-2.5">
              {counts.map(({ level, count }) => (
                <div
                  key={level.level_id}
                  className="flex flex-col-reverse rounded-lg bg-page px-3 py-2"
                >
                  <dt className="text-meta">{level.level_name}</dt>
                  <dd className="text-xl font-bold text-ink">{count}</dd>
                </div>
              ))}
            </dl>
          </section>
          <section aria-label="Checks">
            <h3 className="mb-2 text-small font-semibold text-ink-muted">Checks</h3>
            <ul className="flex flex-col gap-1.5">
              <li className={placeholders === 0 ? 'text-success' : 'text-danger'}>
                {placeholders === 0
                  ? '✓ No temporary names left'
                  : `✕ Rename ${plural(placeholders, 'temporary name', 'temporary names')} first`}
              </li>
              {empty.length === 0 && (
                <li className="text-success">✓ Every place goes down to where technicians scan</li>
              )}
              {empty.slice(0, SHOWN_PROBLEMS).map((branch) => (
                <li key={branch.node_id} className="flex flex-wrap items-center gap-2 text-warning">
                  <span>
                    ! {branch.path} has nothing inside yet, so technicians can't scan there
                  </span>
                  <button
                    type="button"
                    className={buttonClasses('link')}
                    aria-label={`Show me ${branch.path}`}
                    onClick={() => onShow(branch.node_id)}
                  >
                    Show me
                  </button>
                </li>
              ))}
              {empty.length > SHOWN_PROBLEMS && (
                <li className="text-warning">
                  {`and ${plural(empty.length - SHOWN_PROBLEMS, 'more place', 'more places')}`}
                </li>
              )}
            </ul>
          </section>
          {check.data?.sample_path && (
            <p>
              A technician will pick <b className="text-ink">{check.data.sample_path}</b>
            </p>
          )}
          <p className="text-small text-ink-muted">
            Technicians get these places on their next sync.
          </p>
          {error && <Alert tone="danger">{error}</Alert>}
        </div>
      )}
    </Dialog>
  )
}
