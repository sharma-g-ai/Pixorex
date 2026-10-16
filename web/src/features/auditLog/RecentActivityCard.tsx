import type { ReactNode } from 'react'
import { useAuditLog } from '../../api/auditLog'
import { Card } from '../../components/Card'
import { DataTable } from '../../components/DataTable'
import { dateRange } from '../../lib/dateRange'
import { auditColumns } from './auditColumns'

interface RecentActivityCardProps {
  buId: string
  title: string
  /** Column headers to leave out, e.g. "Unit" on a page about one unit. */
  hide: string[]
  action?: ReactNode
}

/** The unit's last few audit entries of the past 7 days (canvas EA 25, BU 03 Plant 05). */
export function RecentActivityCard({ buId, title, hide, action }: RecentActivityCardProps) {
  const log = useAuditLog({ bu_id: buId, ...dateRange('7d') })
  return (
    <Card title={title} action={action}>
      <DataTable
        label={title}
        columns={auditColumns.filter((c) => !hide.includes(c.header))}
        rows={log.items.slice(0, 5)}
        rowKey={(e) => String(log.items.indexOf(e))}
        empty={log.isPending ? 'Loading…' : 'No admin actions in the last 7 days.'}
      />
    </Card>
  )
}
