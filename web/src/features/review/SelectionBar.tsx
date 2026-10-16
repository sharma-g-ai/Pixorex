import { Button } from '../../components/Button'

/** Most scans one batch can hold (contract 3.9). */
export const MAX_BATCH = 50

interface SelectionBarProps {
  count: number
  hint: string
  onClear: () => void
  onDelegate: () => void
}

/** Navy bar over a scan list once scans are picked (canvas BU 06, EA 30). */
export function SelectionBar({ count, hint, onClear, onDelegate }: SelectionBarProps) {
  if (count === 0) return null
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-xl bg-brand-navy px-4 py-2.5 text-white">
      <b className="text-body">{count} selected</b>
      <span className="grow text-small text-white/70">{hint}</span>
      <Button variant="inverse-outline" onClick={onClear}>
        Clear
      </Button>
      <Button variant="inverse" onClick={onDelegate}>
        Delegate to technicians
      </Button>
    </div>
  )
}
