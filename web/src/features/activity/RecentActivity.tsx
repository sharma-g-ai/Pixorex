import { TransactionBadge } from '../../components/StockBadges'
import { itemByArticle, transactionsFor, vesselById } from '../../data/queries'
import { formatDateTime, formatLiters } from '../../lib/format'
import { liters } from '../../data/queries'

/** Short list of the latest synced transactions. */
export function RecentActivity({ vesselIds, limit }: { vesselIds: string[]; limit: number }) {
  const rows = transactionsFor(vesselIds).slice(0, limit)
  if (rows.length === 0) return <p className="text-body text-ink-muted">Nothing synced yet.</p>
  return (
    <ul className="flex flex-col divide-y divide-line-soft">
      {rows.map((t) => {
        const item = itemByArticle(t.articleNo)
        return (
          <li
            key={t.id}
            className="grid grid-cols-[7.5rem_minmax(0,1fr)_5rem] items-center gap-3 py-2.5 first:pt-0 last:pb-0"
          >
            <div>
              <TransactionBadge type={t.type} />
            </div>
            <div className="min-w-0">
              <div className="truncate text-body-sm font-semibold">
                {t.cans > 0 ? '+' : ''}
                {t.cans} × {item?.product} {item?.shade || item?.componentType}
              </div>
              <div className="truncate text-caption text-ink-muted">
                {vesselById(t.vessel)?.name} · {formatDateTime(t.recordedAt)}
              </div>
            </div>
            <div className="text-right text-body-sm font-semibold whitespace-nowrap">
              {formatLiters(liters(t.articleNo, t.cans))}
            </div>
          </li>
        )
      })}
    </ul>
  )
}
