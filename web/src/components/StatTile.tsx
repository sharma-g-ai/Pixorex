import { Link } from 'react-router'

interface StatTileProps {
  value: number | string
  label: string
  /** Makes the tile a link, e.g. "waiting review →" to the review queue. */
  to?: string
  tone?: 'default' | 'warning'
}

/** Big number with a caption (canvas BU 03 and EA 25 stat row). */
export function StatTile({ value, label, to, tone = 'default' }: StatTileProps) {
  const body = (
    <>
      <div className={`text-stat font-bold ${tone === 'warning' ? 'text-warning' : ''}`}>
        {value}
      </div>
      <div className="text-small text-ink-muted">
        {label}
        {to && ' →'}
      </div>
    </>
  )
  const box = `block rounded-xl border px-4.5 py-4 ${
    tone === 'warning' ? 'border-warning-line bg-warning-soft' : 'border-line bg-surface'
  }`
  return to ? (
    <Link to={to} className={`${box} hover:border-line-strong`}>
      {body}
    </Link>
  ) : (
    <div className={box}>{body}</div>
  )
}
