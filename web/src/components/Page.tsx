import type { ReactNode } from 'react'

/** Scrolling page content under the PageHeader. */
export function PageBody({ children }: { children: ReactNode }) {
  return (
    <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
      {children}
    </div>
  )
}

interface CardProps {
  title?: string
  subtitle?: string
  actions?: ReactNode
  children: ReactNode
  /** No inner padding, e.g. for a table that runs to the edges. */
  flush?: boolean
}

/** White panel with an optional title row. */
export function Card({ title, subtitle, actions, children, flush = false }: CardProps) {
  return (
    <section className="rounded-xl border border-line bg-surface">
      {(title || actions) && (
        <div className="flex items-start gap-4 border-b border-line-soft px-5 py-4">
          <div className="min-w-0 grow">
            {title && <h2 className="text-card-title font-bold">{title}</h2>}
            {subtitle && <p className="mt-0.5 text-small text-ink-muted">{subtitle}</p>}
          </div>
          {actions}
        </div>
      )}
      <div className={flush ? '' : 'p-5'}>{children}</div>
    </section>
  )
}

/** Grey note box, e.g. to explain a BRD rule on a screen. */
export function Note({
  children,
  tone = 'info',
}: {
  children: ReactNode
  tone?: 'info' | 'warning'
}) {
  const look =
    tone === 'info'
      ? 'border-brand-soft bg-brand-tint text-ink-muted'
      : 'border-warning-soft bg-warning-soft/60 text-warning'
  return (
    <div className={`rounded-lg border px-4 py-3 text-small leading-relaxed ${look}`}>
      {children}
    </div>
  )
}

/** Label and value pair in a details grid. */
export function Detail({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <div className="text-label font-bold tracking-wider text-ink-subtle uppercase">{label}</div>
      <div className="mt-1 truncate text-body">{children}</div>
    </div>
  )
}

export function Mono({ children }: { children: ReactNode }) {
  return <span className="font-mono text-body-sm">{children}</span>
}

export function Muted({ children }: { children: ReactNode }) {
  return <span className="text-small text-ink-muted">{children}</span>
}
