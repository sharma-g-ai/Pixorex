import { useState } from 'react'
import { useDelegates, type Delegate } from '../../api/review'
import { Alert } from '../../components/Alert'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { SearchSelect } from '../../components/SearchSelect'

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
 * Pick one technician for a batch (canvas BU 09, 11, 15; contracts 3.8 + 3.9 / 3.12).
 * Found by typing a name, so the list never grows into a wall of cards. Scans the technician
 * captured are left out automatically: nobody reviews their own scan.
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
  const [pickedId, setPickedId] = useState<string | null>(null)
  const list = (delegates.data ?? []).filter((d) => d.user_id !== exclude)
  // Looked up again whenever the scans change, so the "left out" count stays right.
  const picked = list.find((d) => d.user_id === pickedId) ?? null
  const gets = picked ? scanIds.length - picked.own_scans_in_selection : 0

  return (
    <ConfirmDialog
      title={title}
      confirmLabel={picked ? confirmText(picked.full_name, gets) : 'Pick a technician'}
      disabled={!picked || gets === 0}
      onClose={onClose}
      onConfirm={() => (picked ? onSubmit(picked) : Promise.resolve())}
    >
      <div className="flex flex-col gap-4">
        <p>{intro}</p>
        {scanIds.length === 0 ? (
          <p className="text-ink-muted">There are no scans to hand over.</p>
        ) : delegates.isPending ? (
          <p className="text-ink-muted">Loading technicians…</p>
        ) : list.length === 0 ? (
          <p>No technicians in this unit can take these scans.</p>
        ) : (
          <SearchSelect
            label="Technician"
            placeholder="Search technicians by name"
            idleText="Type a name to find a technician."
            options={list.map((d) => ({
              value: d.user_id,
              label: d.full_name,
              hint: `${d.open_review_count} to review right now`,
            }))}
            value={picked?.user_id ?? null}
            onChange={setPickedId}
          />
        )}
        {picked && picked.own_scans_in_selection > 0 && (
          <Alert tone="warning">
            {picked.own_scans_in_selection}{' '}
            {picked.own_scans_in_selection === 1 ? 'scan was' : 'scans were'} excluded because{' '}
            {picked.full_name} submitted {picked.own_scans_in_selection === 1 ? 'it' : 'them'}.
            Nobody can review their own scan — these stay in your review queue.
          </Alert>
        )}
      </div>
    </ConfirmDialog>
  )
}
