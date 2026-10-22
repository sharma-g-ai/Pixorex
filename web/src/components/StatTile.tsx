import { Link } from 'react-router'

interface StatTileProps {
  value: number | string
  label: string
  /** Makes the tile a link, e.g. to the Sea Stock page. */
  to?: string
  tone?: 'default' | 'warning'
}

/** Big number with a caption. */
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
  const box = 'block rounded-xl border border-line bg-surface px-4.5 py-4'
  return to ? (
    <Link to={to} className={`${box} hover:border-line-strong`}>
      {body}
    </Link>
  ) : (
    <div className={box}>{body}</div>
  )
}
