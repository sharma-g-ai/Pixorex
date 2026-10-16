import { PageHeader } from '../../components/layout/PageHeader'
import { contextLine, useDashboard } from '../DashboardContext'

interface PlaceholderPageProps {
  title: string
  task: string
}

/** Stands in for a screen until its task builds it. */
export function PlaceholderPage({ title, task }: PlaceholderPageProps) {
  const dashboard = useDashboard()
  return (
    <>
      <PageHeader title={title} subtitle={contextLine(dashboard)} />
      <div className="grow overflow-y-auto px-8 pt-6 pb-8">
        <div className="rounded-xl border border-dashed border-line bg-surface p-8 text-center text-body text-ink-muted">
          This screen is built in <span className="font-semibold text-ink">{task}</span>.
        </div>
      </div>
    </>
  )
}
