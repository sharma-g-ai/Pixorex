interface ProgressBarProps {
  done: number
  total: number
  /** Text under the bar, e.g. "18 of 30 reviewed". */
  label: string
}

/** Thin bar showing how much of something is done; green when complete. */
export function ProgressBar({ done, total, label }: ProgressBarProps) {
  const percent = total > 0 ? Math.min(100, Math.round((done / total) * 100)) : 0
  return (
    <div className="flex flex-col gap-1.5">
      <div
        role="progressbar"
        aria-valuenow={done}
        aria-valuemin={0}
        aria-valuemax={total}
        aria-label={label}
        className="h-2 overflow-hidden rounded-full bg-page"
      >
        <div
          className={`h-full rounded-full ${percent === 100 ? 'bg-success' : 'bg-brand-navy'}`}
          style={{ width: `${percent}%` }}
        />
      </div>
      <div className="text-xs text-ink-muted">{label}</div>
    </div>
  )
}
