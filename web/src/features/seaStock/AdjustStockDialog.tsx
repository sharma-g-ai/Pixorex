import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { Dialog } from '../../components/Dialog'
import { SelectField } from '../../components/SelectField'
import { TextAreaField } from '../../components/TextAreaField'
import { TextField } from '../../components/TextField'
import type { Vessel } from '../../data/model'
import { stockLines } from '../../data/queries'
import { items } from '../../data/sample'
import { adjustStock } from '../../data/store'
import { formatLiters } from '../../lib/format'

/**
 * Correct a vessel's stock from the portal (FR-13): one adjustment with a reason, recorded under
 * the admin's name. Never edits an earlier row. Who may do this is to confirm with PPG.
 */
export function AdjustStockDialog({ vessel, onClose }: { vessel: Vessel; onClose: () => void }) {
  const { user } = useViewer()
  const [articleNo, setArticleNo] = useState('')
  const [direction, setDirection] = useState<'add' | 'remove'>('remove')
  const [cans, setCans] = useState('')
  const [reason, setReason] = useState('')
  const count = Number(cans)
  const valid = Number.isInteger(count) && count > 0
  const item = items.find((i) => i.articleNo === articleNo)
  const onBoard = stockLines([vessel.id]).find((l) => l.item.articleNo === articleNo)?.cans ?? 0
  const change = direction === 'add' ? count : -count
  const ready = item && valid && reason.trim()
  return (
    <Dialog
      title={`Adjust stock · ${vessel.name}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!ready}
            onClick={() => {
              adjustStock(vessel.id, articleNo, change, reason.trim(), user)
              onClose()
            }}
          >
            Save adjustment
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <SelectField
          label="Product"
          value={articleNo}
          onChange={(e) => setArticleNo(e.target.value)}
          options={[
            { value: '', label: 'Choose a product…' },
            ...items.map((i) => ({
              value: i.articleNo,
              label: `${i.articleNo} · ${i.product} ${i.shade || i.componentType} · ${i.packSize}`,
            })),
          ]}
        />
        <div className="grid grid-cols-2 gap-3">
          <SelectField
            label="Change"
            value={direction}
            onChange={(e) => setDirection(e.target.value as 'add' | 'remove')}
            options={[
              { value: 'remove', label: 'Remove cans' },
              { value: 'add', label: 'Add cans' },
            ]}
          />
          <TextField
            label="Number of cans"
            inputMode="numeric"
            value={cans}
            onChange={(e) => setCans(e.target.value.replace(/\D/g, ''))}
            error={cans && !valid ? 'At least 1 can' : undefined}
          />
        </div>
        <TextAreaField
          label="Reason (required)"
          placeholder="e.g. Can found damaged during a locker check"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        {item && valid && (
          <p className="text-small">
            On record now: {onBoard} {onBoard === 1 ? 'can' : 'cans'}. After this: {onBoard + change} (
            {formatLiters((onBoard + change) * item.unitVolume)}).
          </p>
        )}
        <p className="text-small">
          The adjustment is added to the record under your name; earlier rows are never changed.
        </p>
      </div>
    </Dialog>
  )
}
