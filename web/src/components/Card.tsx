import type { ReactNode } from 'react'

interface CardProps {
  title?: string
  /** Right side of the title row, e.g. a link. */
  action?: ReactNode
  className?: string
  children: ReactNode
}

/** White bordered panel used on every screen. */
export function Card({ title, action, className = '', children }: CardProps) {
  return (
    <section className={`rounded-xl border border-line bg-surface px-5 py-4.5 ${className}`}>
      {(title || action) && (
        <div className="mb-3 flex items-center justify-between gap-3">
          {title && <h2 className="text-card-title font-bold">{title}</h2>}
          {action}
        </div>
      )}
      {children}
    </section>
  )
}
