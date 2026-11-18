import { useState } from 'react'
import { useCreateBatch } from '../../api/review'
import { DelegateDialog } from './DelegateDialog'
import { MAX_BATCH } from './SelectionBar'

interface DelegateBatchDialogProps {
  buId: string
  scanIds: string[]
  /** e.g. "Plant 07 · " in front of the intro when an EA delegates for a unit. */
  introPrefix?: string
  onClose: () => void
  /** Called with the message to show, e.g. "Batch B-16 delegated to T. Nguyen." */
  onDone: (message: string) => void
}

/** Hand picked scans to one technician as a new batch (canvas BU 09, EA 31; contract 3.9). */
export function DelegateBatchDialog({
  buId,
  scanIds,
  introPrefix = '',
  onClose,
  onDone,
}: DelegateBatchDialogProps) {
  const createBatch = useCreateBatch(buId)
  const [idempotencyKey] = useState(() => crypto.randomUUID())
  const all = scanIds.slice(0, MAX_BATCH)
  const plural = (n: number) => `${n} ${n === 1 ? 'scan' : 'scans'}`

  return (
    <DelegateDialog
      buId={buId}
      scanIds={all}
      title={`Delegate ${plural(all.length)}`}
      intro={`${introPrefix}Pick the technician who will review these in their app.`}
      confirmText={(name, count) => `Delegate ${plural(count)} to ${name}`}
      onClose={onClose}
      onSubmit={async (delegate) => {
        const batch = await createBatch.mutateAsync({
          assignedTo: delegate.user_id,
          scanIds: all,
          idempotencyKey,
        })
        onDone(`Batch ${batch.batch_no} delegated to ${delegate.full_name}.`)
      }}
    />
  )
}
