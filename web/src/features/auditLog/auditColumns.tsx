import type { AuditEntry } from '../../api/auditLog'
import type { Column } from '../../components/DataTable'
import { actorName, auditCategoryLabels, auditTime } from './auditLabels'

/** When · Who · What happened · Unit · Type (canvas EA 22, EA 25 recent activity). */
export const auditColumns: Column<AuditEntry>[] = [
  {
    header: 'When',
    width: 0.9,
    cell: (e) => <span className="font-mono text-meta">{auditTime(e.occurred_at)}</span>,
  },
  { header: 'Who', width: 0.9, cell: (e) => actorName(e) },
  { header: 'What happened', width: 3, cell: (e) => e.summary },
  { header: 'Unit', width: 0.8, cell: (e) => e.bu_name ?? 'All units' },
  { header: 'Type', width: 0.9, cell: (e) => auditCategoryLabels[e.category] },
]
