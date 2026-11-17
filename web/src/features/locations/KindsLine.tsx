import type { Level } from '../../api/locations'
import { sortLevels } from './locationTree'

interface KindsLineProps {
  levels: Level[]
  /** Published: the kinds are shown, not changed. */
  locked: boolean
  busy: boolean
  onToggle: (level: Level, skip: boolean) => void
}

const pill = 'rounded-full border px-2.5 py-0.5 text-meta font-bold'
const asked = 'border-transparent bg-brand-navy-soft text-brand-navy'
const skipped = 'border-dashed border-line-strong bg-page text-ink-muted'

/**
 * What technicians pick on the phone, top to bottom: the unit's kinds below the top one.
 * Clicking a kind switches it between always asked and "can be skipped" (contract 2.2); this
 * line replaces the separate kinds page (decision 2026-11-16).
 */
export function KindsLine({ levels, locked, busy, onToggle }: KindsLineProps) {
  const kinds = sortLevels(levels)
    .slice(1)
    .filter((l) => l.requirement !== 'off')
  if (kinds.length === 0) return null
  return (
    <div className="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1">
      <ul
        aria-label="What technicians pick"
        className="flex flex-wrap items-center gap-1.5 text-small text-ink-muted"
      >
        <li>Technicians will pick:</li>
        {kinds.map((level, i) => {
          const skip = level.requirement === 'optional'
          const label = skip ? `${level.level_name} · can be skipped` : level.level_name
          return (
            <li key={level.level_id} className="flex items-center gap-1.5">
              {i > 0 && <span aria-hidden="true">›</span>}
              {locked ? (
                <span className={`${pill} ${skip ? skipped : asked}`}>{label}</span>
              ) : (
                <button
                  type="button"
                  aria-pressed={skip}
                  disabled={busy}
                  title={
                    skip
                      ? `Make ${level.level_name} always asked`
                      : `Mark ${level.level_name} as "can be skipped"`
                  }
                  className={`${pill} hover:border-brand-navy disabled:cursor-default ${skip ? skipped : asked}`}
                  onClick={() => onToggle(level, !skip)}
                >
                  {label}
                </button>
              )}
            </li>
          )
        })}
      </ul>
      {!locked && (
        <p className="text-xs text-ink-muted">Click a kind if some places don’t have one.</p>
      )}
    </div>
  )
}
