import { useMemo, useState } from 'react'
import { useCreateBatch, useWaitingScans } from '../../api/review'
import { SearchSelect } from '../../components/SearchSelect'
import { DelegateDialog } from './DelegateDialog'
import { binsOf } from './reviewRules'
import { MAX_BATCH } from './SelectionBar'

interface DelegateBatchDialogProps {
  buId: string
  scanIds: string[]
  /** e.g. "Plant 07 · " in front of the intro when an EA delegates for a unit. */
  introPrefix?: string
  /** Let the BU Admin add every waiting scan of chosen bins to the batch. */
  allowBins?: boolean
  onClose: () => void
  /** Called with the message to show, e.g. "Batch B-16 delegated to T. Nguyen." */
  onDone: (message: string) => void
}

/** Hand picked scans to one technician as a new batch (canvas BU 09, EA 31; contract 3.9). */
export function DelegateBatchDialog({
  buId,
  scanIds,
  introPrefix = '',
  allowBins = false,
  onClose,
  onDone,
}: DelegateBatchDialogProps) {
  const createBatch = useCreateBatch(buId)
  const [idempotencyKey, setIdempotencyKey] = useState(() => crypto.randomUUID())
  const waiting = useWaitingScans(buId, allowBins)
  const bins = useMemo(() => binsOf(waiting.data ?? []), [waiting.data])
  const [binPaths, setBinPaths] = useState<string[]>([])

  const fromBins = bins.filter((b) => binPaths.includes(b.path)).flatMap((b) => b.scanIds)
  const wanted = [...new Set([...scanIds, ...fromBins])]
  const all = wanted.slice(0, MAX_BATCH)
  const plural = (n: number) => `${n} ${n === 1 ? 'scan' : 'scans'}`
  const changeBins = (paths: string[]) => {
    setBinPaths(paths)
    setIdempotencyKey(crypto.randomUUID()) // a different set of scans is a different request
  }

  const extra = allowBins && (
    <div className="flex flex-col gap-2">
      <SearchSelect
        label="Add scans by bin"
        placeholder="Search bins"
        idleText="Optional: add every waiting scan from a bin."
        options={bins
          .filter((b) => !binPaths.includes(b.path))
          .map((b) => ({
            value: b.path,
            label: b.path,
            hint: plural(b.scanIds.length) + ' waiting',
          }))}
        value={null}
        onChange={(path) => path && changeBins([...binPaths, path])}
      />
      {binPaths.length > 0 && (
        <ul className="flex flex-wrap gap-2" aria-label="Bins added">
          {binPaths.map((path) => (
            <li
              key={path}
              className="flex items-center gap-1.5 rounded-full bg-brand-navy-soft py-0.5 pr-1 pl-3 text-meta font-semibold text-brand-navy"
            >
              {path} · {bins.find((b) => b.path === path)?.scanIds.length ?? 0}
              <button
                type="button"
                className="grid size-5 place-items-center rounded-full hover:bg-brand-navy/10"
                aria-label={`Remove ${path}`}
                onClick={() => changeBins(binPaths.filter((p) => p !== path))}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      {wanted.length > MAX_BATCH && (
        <p className="text-meta text-warning">
          One batch holds {MAX_BATCH} scans. The {wanted.length - MAX_BATCH} oldest-waiting extras
          stay in the queue for the next batch.
        </p>
      )}
    </div>
  )

  return (
    <DelegateDialog
      buId={buId}
      scanIds={all}
      title={`Delegate ${plural(all.length)}`}
      intro={`${introPrefix}Pick the technician who will review these in their app.`}
      extra={extra}
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
