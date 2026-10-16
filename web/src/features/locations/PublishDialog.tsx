import { useState } from 'react'
import { errorMessage } from '../../api/client'
import { usePublishCheck, usePublishLocations, type LocationSetup } from '../../api/locations'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Dialog } from '../../components/Dialog'
import { countsByLevel } from './locationTree'

interface PublishDialogProps {
  buId: string
  unitName: string
  setup: LocationSetup
  onClose: () => void
  onPublished: () => void
}

/** Review & publish (canvas EA 19; contracts 2.7–2.8). Publishing is one-way. */
export function PublishDialog({ buId, unitName, setup, onClose, onPublished }: PublishDialogProps) {
  const check = usePublishCheck(buId, true)
  const publish = usePublishLocations(buId)
  const [error, setError] = useState<string | null>(null)

  // Counts come from the tree itself; the contract's counts field has no fixed shape yet.
  const counts = countsByLevel(setup.levels, setup.nodes).filter(
    (c) => c.level.requirement !== 'off',
  )
  const placeholders = check.data?.placeholders_left ?? 0
  const emptyBranches = check.data?.empty_branches.length ?? 0
  const checks = [
    {
      ok: placeholders === 0,
      text:
        placeholders === 0
          ? 'No placeholders left'
          : `Name the placeholders first (${placeholders} left)`,
    },
    {
      ok: emptyBranches === 0,
      text:
        emptyBranches === 0
          ? 'Every branch ends where technicians scan'
          : `${emptyBranches} branches end before a technician can scan`,
    },
  ]

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
        <p>Checking the tree…</p>
      ) : check.isError ? (
        <Alert tone="danger">{errorMessage(check.error)}</Alert>
      ) : (
        <div className="flex flex-col gap-4">
          <section aria-label="What technicians will see">
            <h3 className="mb-2 text-small font-semibold text-ink-muted">
              What technicians will see
            </h3>
            <div className="flex flex-wrap gap-2.5">
              {counts.map(({ level, count }) => (
                <div key={level.level_id} className="rounded-lg bg-page px-3 py-2">
                  <div className="text-xl font-bold text-ink">{count}</div>
                  <div className="text-meta">{level.level_name}</div>
                </div>
              ))}
            </div>
          </section>
          <section aria-label="Checks">
            <h3 className="mb-2 text-small font-semibold text-ink-muted">Checks</h3>
            <ul className="flex flex-col gap-1.5">
              {checks.map((c) => (
                <li key={c.text} className={c.ok ? 'text-success' : 'text-danger'}>
                  {c.ok ? '✓' : '✕'} {c.text}
                </li>
              ))}
            </ul>
          </section>
          {check.data?.sample_path && (
            <p>
              A technician will pick <b className="text-ink">{check.data.sample_path}</b>
            </p>
          )}
          <Alert tone="info">
            Technicians get this tree on their next sync. It's published once: after this, nothing
            in this unit's levels or locations can be added, edited or deleted.
          </Alert>
          {error && <Alert tone="danger">{error}</Alert>}
        </div>
      )}
    </Dialog>
  )
}
