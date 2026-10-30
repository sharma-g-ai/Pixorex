import { DataTable } from '../../components/DataTable'
import { Mono, Muted } from '../../components/Page'
import type { AuditEntry } from '../../data/model'
import { userById } from '../../data/queries'
import { formatDateTime } from '../../lib/format'

export const auditCategories: Record<AuditEntry['category'], string> = {
  users: 'Users',
  customers_vessels: 'Customers & vessels',
  devices: 'Tablets',
  articles: 'Products',
  label_schema: 'Label schema',
  delivery_notes: 'Delivery notes',
  inventory: 'Stock',
  sync: 'Sync',
}

/** Who did what, when, from which account or tablet (data model Domain 6). */
export function AuditLogTable({ rows }: { rows: AuditEntry[] }) {
  return (
    <DataTable
      label="Audit log"
      rows={rows}
      rowKey={(a) => a.id}
      empty="Nothing recorded for these filters"
      columns={[
        { header: 'When', width: 1, cell: (a) => formatDateTime(a.at) },
        {
          header: 'Who',
          width: 1.1,
          cell: (a) =>
            a.actorType === 'user' ? (
              <div className="min-w-0">
                <div className="truncate">{userById(a.actor ?? '')?.name ?? 'User'}</div>
                <Muted>Portal</Muted>
              </div>
            ) : a.actorType === 'device' ? (
              <div className="min-w-0">
                <Mono>{a.actor}</Mono>
                <div>
                  <Muted>Tablet</Muted>
                </div>
              </div>
            ) : (
              <Muted>System</Muted>
            ),
        },
        { header: 'Area', width: 0.9, cell: (a) => auditCategories[a.category] },
        { header: 'What happened', width: 3, cell: (a) => <span className="text-body-sm">{a.summary}</span> },
      ]}
    />
  )
}
