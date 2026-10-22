import type { ReactNode } from 'react'

/** Top row of a tab: what it holds on the left, its buttons on the right. */
export function SectionBar({
  subtitle,
  actions,
}: {
  title?: string
  subtitle?: string
  actions?: ReactNode
}) {
  return (
    <div className="flex min-h-10.5 items-center gap-4">
      <p className="grow text-small text-ink-muted">{subtitle}</p>
      {actions && <div className="flex items-center gap-2.5">{actions}</div>}
    </div>
  )
}
