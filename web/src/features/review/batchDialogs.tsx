import { useState } from 'react'
import { useBatch, useReassignBatch, useTakeBackBatch, type Batch } from '../../api/review'
import { ConfirmDialog } from '../../components/ConfirmDialog'
import { TextAreaField } from '../../components/TextAreaField'
import { DelegateDialog } from './DelegateDialog'

/** Give a batch's open scans to another technician (contract 3.12). */
export function ReassignDialog({
  buId,
  batch,
  onClose,
  onDone,
}: {
  buId: string
  batch: Batch
  onClose: () => void
  onDone: () => void
}) {
  const detail = useBatch(batch.batch_id)
  const reassign = useReassignBatch(batch.batch_id)
  const open = (detail.data?.assignments ?? [])
    .filter((a) => a.status === 'assigned')
    .map((a) => a.scan_id)
  if (detail.isPending) return null
  return (
    <DelegateDialog
      buId={buId}
      scanIds={open}
      title={`Reassign batch ${batch.batch_no}`}
      intro={`${open.length} ${open.length === 1 ? 'scan is' : 'scans are'} not reviewed yet. Pick who takes over from ${batch.assigned_to_name}.`}
      confirmText={(name, count) =>
        `Reassign ${count} ${count === 1 ? 'scan' : 'scans'} to ${name}`
      }
      onClose={onClose}
      onSubmit={async (delegate) => {
        await reassign.mutateAsync(delegate.user_id)
        onDone()
      }}
    />
  )
}

/** Return a batch's open scans to the review queue, with an optional message (contract 3.13). */
export function TakeBackDialog({
  batch,
  onClose,
  onDone,
}: {
  batch: Batch
  onClose: () => void
  onDone: () => void
}) {
  const takeBack = useTakeBackBatch(batch.batch_id)
  const [message, setMessage] = useState('')
  const left = batch.scan_count - batch.decided_count
  return (
    <ConfirmDialog
      title={`Take back batch ${batch.batch_no}?`}
      confirmLabel={`Take back ${left} ${left === 1 ? 'scan' : 'scans'}`}
      onClose={onClose}
      onConfirm={async () => {
        await takeBack.mutateAsync(message.trim())
        onDone()
      }}
    >
      <ul className="mb-3 flex list-inside list-disc flex-col gap-2">
        <li>
          The <b className="text-ink">{left} scans not reviewed yet</b> go back to your review
          queue.
        </li>
        <li>
          {batch.assigned_to_name} loses them from the app straight away and is told. Decisions
          already made stay.
        </li>
      </ul>
      <TextAreaField
        label={`Message to ${batch.assigned_to_name} (optional)`}
        value={message}
        onChange={(e) => setMessage(e.target.value)}
      />
    </ConfirmDialog>
  )
}
