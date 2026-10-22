import { Link } from 'react-router'
import { DataTable } from '../../components/DataTable'
import { Mono, Muted } from '../../components/Page'
import { TransactionBadge } from '../../components/StockBadges'
import type { Transaction } from '../../data/model'
import { itemByArticle, liters, userById, vesselById } from '../../data/queries'
import { formatDateTime, formatLiters } from '../../lib/format'

/** The audit trail (FR-12): user, time, device and source of every transaction. */
export function ActivityTable({
  rows,
  showVessel = true,
}: {
  rows: Transaction[]
  showVessel?: boolean
}) {
  return (
    <DataTable
      label="Activity"
      rows={rows}
      rowKey={(t) => t.id}
      empty="No transactions match these filters"
      columns={[
        {
          header: 'Recorded',
          width: 1.3,
          cell: (t) => (
            <div>
              <div>{formatDateTime(t.recordedAt)}</div>
              <Muted>Synced {formatDateTime(t.syncedAt)}</Muted>
            </div>
          ),
        },
        ...(showVessel
          ? [
              {
                header: 'Vessel',
                width: 1.2,
                cell: (t: Transaction) => (
                  <Link className="text-brand hover:underline" to={`/sea-stock?vessel=${t.vessel}`}>
                    {vesselById(t.vessel)?.name}
                  </Link>
                ),
              },
            ]
          : []),
        { header: 'Type', width: 0.9, cell: (t) => <TransactionBadge type={t.type} /> },
        {
          header: 'Item',
          width: 1.7,
          cell: (t) => {
            const item = itemByArticle(t.articleNo)
            return (
              <div className="min-w-0">
                <div className="truncate font-semibold">
                  {item?.product}{' '}
                  {item?.shade && <span className="font-normal">· {item.shade}</span>}
                </div>
                <Muted>
                  <Mono>{t.articleNo}</Mono> · {item?.componentType} · {item?.packSize}
                </Muted>
              </div>
            )
          },
        },
        {
          header: 'Change',
          align: 'right',
          width: 0.9,
          cell: (t) => (
            <div>
              <div className={`font-semibold ${t.cans < 0 ? 'text-warning' : 'text-success'}`}>
                {t.cans > 0 ? '+' : ''}
                {t.cans} cans
              </div>
              <Muted>{formatLiters(liters(t.articleNo, t.cans))}</Muted>
            </div>
          ),
        },
        {
          header: 'By / device',
          width: 1.2,
          cell: (t) => (
            <div className="min-w-0">
              <div className="truncate">{userById(t.user)?.name}</div>
              <Muted>
                <Mono>{t.device}</Mono>
              </Muted>
            </div>
          ),
        },
        {
          header: 'Source / reason',
          width: 1.7,
          cell: (t) => (
            <div className="min-w-0">
              <div>
                {t.source}
                {t.dn && (
                  <>
                    {' · '}
                    <Link className="text-brand hover:underline" to={`?dn=${t.dn}`}>
                      DN {t.dn}
                    </Link>
                  </>
                )}
              </div>
              {t.reason && <div className="text-small text-ink-muted">{t.reason}</div>}
            </div>
          ),
        },
      ]}
    />
  )
}
