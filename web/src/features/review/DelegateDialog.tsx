import { useState } from 'react'
import { useDelegates, type Delegate } from '../../api/review'
import { Alert } from '../../components/Alert'
import { ChoiceCard } from '../../components/ChoiceCard'
import { ConfirmDialog } from '../../components/ConfirmDialog'

interface DelegateDialogProps {
  buId: string
  /** Scans being handed over (or the open scans of a batch being reassigned). */
  scanIds: string[]
  title: string
  intro: string
  /** Button text for the picked technician and how many scans they get. */
  confirmText: (name: string, count: number) => string
  /** Technician to leave out, e.g. the current holder of a batch. */
  exclude?: string
  onSubmit: (delegate: Delegate) => Promise<unknown>
  onClose: () => void
}

/**
 * Pick a technician for a batch (canvas BU 09, 11, 15; contracts 3.8 + 3.9 / 3.12).
 * Scans the technician captured are left out automatically: nobody reviews their own scan.
 */
export function DelegateDialog({
  buId,
  scanIds,
  title,
  intro,
  confirmText,
  exclude,
  onSubmit,
  onClose,
}: DelegateDialogProps) {
  const delegates = useDelegates(buId, scanIds)
  const [picked, setPicked] = useState<Delegate | null>(null)
  const list = (delegates.data ?? []).filter((d) => d.user_id !== exclude)
  const gets = picked ? scanIds.length - picked.own_scans_in_selection : 0

  return (
    <ConfirmDialog
      title={title}
      confirmLabel={picked ? confirmText(picked.full_name, gets) : 'Pick a technician'}
      disabled={!picked || gets === 0}
      onClose={onClose}
      onConfirm={() => (picked ? onSubmit(picked) : Promise.resolve())}
    >
      <div className="flex flex-col gap-3">
        <p>{intro}</p>
        {delegates.isPending ? (
          <p>Loading technicians…</p>
        ) : list.length === 0 ? (
          <p>No technicians in this unit can take these scans.</p>
        ) : (
          <fieldset className="flex max-h-64 flex-col gap-2 overflow-y-auto">
            <legend className="sr-only">Technician</legend>
            {list.map((d) => (
              <ChoiceCard
                key={d.user_id}
                name="delegate"
                title={d.full_name}
                description={describe(d, scanIds.length)}
                checked={picked?.user_id === d.user_id}
                onChange={() => setPicked(d)}
              />
            ))}
          </fieldset>
        )}
        {picked && picked.own_scans_in_selection > 0 && (
          <Alert tone="warning">
            {picked.own_scans_in_selection}{' '}
            {picked.own_scans_in_selection === 1 ? 'scan was' : 'scans were'} excluded because{' '}
            {picked.full_name} submitted {picked.own_scans_in_selection === 1 ? 'it' : 'them'}.
            Nobody can review their own scan — these stay in your review queue.
          </Alert>
        )}
        <p className="text-xs text-ink-subtle">
          No progress after 1 day or 1 week sends you an alert. You can take the batch back or
          reassign it any time.
        </p>
      </div>
    </ConfirmDialog>
  )
}

function describe(d: Delegate, total: number): string {
  const open = `${d.open_review_count} ${d.open_review_count === 1 ? 'scan' : 'scans'} to review right now`
  const own =
    d.own_scans_in_selection === 0
      ? 'submitted none of these'
      : d.own_scans_in_selection === total
        ? 'submitted all of these'
        : `submitted ${d.own_scans_in_selection} of these`
  return `${open} · ${own}`
}
