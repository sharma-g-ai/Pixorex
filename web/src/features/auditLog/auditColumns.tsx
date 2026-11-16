import type { AuditEntry } from '../../api/auditLog'
import type { Column } from '../../components/DataTable'
import { actorName, auditCategoryColors, auditCategoryLabels, auditTime } from './auditLabels'

/** When · Who · What happened · Unit · Type (canvas EA 22, EA 25 recent activity). */
export const auditColumns: Column<AuditEntry>[] = [
  {
    header: 'When',
    width: 0.9,
    cell: (e) => <span className="font-mono text-meta">{auditTime(e.occurred_at)}</span>,
  },
  { header: 'Who', width: 0.9, cell: (e) => actorName(e) },
  {
    header: 'What happened',
    width: 3,
    cell: (e) => (
      <span className="flex items-baseline gap-2">
        <span
          aria-hidden="true"
          className={`size-2 shrink-0 translate-y-px rounded-full ${auditCategoryColors[e.category].dot}`}
        />
        <span className="min-w-0">{e.summary}</span>
      </span>
    ),
  },
  { header: 'Unit', width: 0.8, cell: (e) => e.bu_name ?? 'All units' },
  {
    header: 'Type',
    width: 0.9,
    cell: (e) => (
      <span
        className={`inline-block rounded-full px-2.5 py-0.5 text-meta font-bold whitespace-nowrap ${auditCategoryColors[e.category].pill}`}
      >
        {auditCategoryLabels[e.category]}
      </span>
    ),
  },
]
