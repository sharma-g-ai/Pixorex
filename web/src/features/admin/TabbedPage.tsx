import type { ReactNode } from 'react'
import { useSearchParams } from 'react-router'
import { useViewer } from '../../app/viewer'
import { PageHeader } from '../../components/layout/PageHeader'
import { PageBody } from '../../components/Page'
import { Tabs } from '../../components/Tabs'
import { can, type Permission } from '../../data/roles'

export interface PageTab {
  key: string
  label: string
  /** Shown if the user has any of these. */
  needs: Permission[]
  content: ReactNode
}

/** One admin screen made of tabs; ?tab=<key> opens a tab directly. */
export function TabbedPage({
  title,
  subtitle,
  tabs,
}: {
  title: string
  subtitle: string
  tabs: PageTab[]
}) {
  const { user } = useViewer()
  const [params, setParams] = useSearchParams()
  const allowed = tabs.filter((t) => t.needs.some((p) => can(user, p)))
  const current = allowed.find((t) => t.key === params.get('tab')) ?? allowed[0]
  return (
    <>
      <PageHeader title={title} subtitle={subtitle} />
      <PageBody>
        {allowed.length > 1 && (
          <Tabs
            label={title}
            current={current?.key ?? ''}
            onChange={(key) => setParams({ tab: key })}
            tabs={allowed.map((t) => ({ key: t.key, label: t.label }))}
          />
        )}
        {current && (
          <div key={current.key} className="flex flex-col gap-5 *:shrink-0">
            {current.content}
          </div>
        )}
      </PageBody>
    </>
  )
}
