import { useContext, type ReactNode } from 'react'
import { HeaderExtrasContext } from './headerExtras'

interface PageHeaderProps {
  title: string
  subtitle?: string
  /** Buttons on the right, e.g. "+ Create unit". */
  actions?: ReactNode
}

/** The white bar at the top of every page (canvas: 72 px header). */
export function PageHeader({ title,  actions }: PageHeaderProps) {
  const extras = useContext(HeaderExtrasContext)
  return (
    <header className="flex h-18 shrink-0 items-center gap-4 border-b border-line bg-surface px-8">
      <div className="min-w-0 grow">
        <h1 className="truncate text-page-title font-bold">{title}</h1>
      </div>
      {actions}
      {extras}
    </header>
  )
}
