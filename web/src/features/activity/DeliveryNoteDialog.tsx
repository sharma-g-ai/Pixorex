import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Card, Detail, Mono, Muted } from '../../components/Page'
import { ComponentBadge, ImoCheckBadge, LineResultBadge } from '../../components/StockBadges'
import type { DeliveryNote, DeliveryNoteLine } from '../../data/model'
import { customerById, imoLabel, itemByArticle, scanForLine, vesselById } from '../../data/queries'
import { formatDate, formatDateTime, formatLiters } from '../../lib/format'
import { differences, receivedCans } from './DeliveryNotesTable'

/** One delivery note: header as read from the DN (FR-01) and the line-by-line tally (FR-04, FR-05). */
export function DeliveryNoteDialog({ dn, onClose }: { dn: DeliveryNote; onClose: () => void }) {
  const vessel = vesselById(dn.vessel)
  const customer = vessel && customerById(vessel.customer)
  // A line not in the master list stays as scanned; it shows an article only once a PPG Admin matches it.
  const itemOf = (l: DeliveryNoteLine) => {
    const scan = scanForLine(dn.dnNumber, l.articleNo)
    return itemByArticle(scan ? (scan.matchedArticle ?? '') : l.articleNo)
  }

  return (
    <Dialog
      wide
      title={`Delivery note ${dn.dnNumber} · ${vessel?.name}`}
      onClose={onClose}
      footer={
        <Button variant="secondary" onClick={onClose}>
          Close
        </Button>
      }
    >
      <div className="flex max-h-[70vh] flex-col gap-4 overflow-y-auto text-ink">
        <Card title="Header" subtitle="As read from the delivery note">
          <div className="grid grid-cols-2 gap-5 md:grid-cols-3 xl:grid-cols-6">
            <Detail label="DN number">
              <Mono>{dn.dnNumber}</Mono>
            </Detail>
            <Detail label="DN date">{formatDate(dn.dnDate)}</Detail>
            <Detail label="Vessel">
              {vessel?.name} · {vessel && imoLabel(vessel.imo)}
            </Detail>
            <Detail label="IMO on the note">
              {dn.imoOnNote ?? '—'} <ImoCheckBadge check={dn.imoCheck} />
            </Detail>
            <Detail label="Vessel name on the note">{dn.vesselNameOnNote ?? '—'}</Detail>
            <Detail label="Customer">{customer?.name}</Detail>
            <Detail label="Customer reference">
              <Mono>{dn.customerReference}</Mono>
            </Detail>
            <Detail label="Tablet">
              <Mono>{dn.device}</Mono>
            </Detail>
            <Detail label="Confirmed on tablet">{formatDateTime(dn.confirmedAt)}</Detail>
            <Detail label="Received">{formatDateTime(dn.receivedAt)}</Detail>
            <Detail label="Lines">{dn.lines.length}</Detail>
            <Detail label="Cans into the locker">{receivedCans(dn)}</Detail>
            <Detail label="Differences">{differences(dn)}</Detail>
          </div>
        </Card>

        <Card title="Tally" subtitle="Cans scanned into the locker against the delivery note" flush>
          <div className="p-4">
            <DataTable<DeliveryNoteLine>
              label="Tally"
              rows={dn.lines}
              rowKey={(l) => String(dn.lines.indexOf(l))}
              empty="No lines"
              columns={[
                { header: 'Article no.', width: 0.8, cell: (l) => <Mono>{l.articleNo}</Mono> },
                {
                  header: 'Item',
                  width: 1.9,
                  cell: (l) => {
                    const item = itemOf(l)
                    if (!item) return <Muted>Not in the master list; held for a PPG Admin</Muted>
                    return (
                      <div className="flex min-w-0 items-center gap-2">
                        <div className="min-w-0">
                          <div className="truncate font-semibold">{item.product}</div>
                          <Muted>
                            {item.shade || 'No shade'} · {item.packSize}
                            {item.articleNo !== l.articleNo && ` · matched to ${item.articleNo}`}
                          </Muted>
                        </div>
                        <ComponentBadge type={item.componentType} />
                      </div>
                    )
                  },
                },
                {
                  header: 'On DN',
                  width: 0.6,
                  align: 'right',
                  cell: (l) => (l.result === 'not-on-note' ? '—' : l.dnCans),
                },
                {
                  header: 'Received',
                  width: 0.7,
                  align: 'right',
                  cell: (l) => <b>{l.receivedCans}</b>,
                },
                {
                  header: 'Difference',
                  width: 0.7,
                  align: 'right',
                  cell: (l) => {
                    const d = l.receivedCans - (l.dnCans ?? 0)
                    return (
                      <span className={d === 0 ? 'text-ink-subtle' : 'font-semibold text-warning'}>
                        {d > 0 ? `+${d}` : d}
                      </span>
                    )
                  },
                },
                {
                  header: 'Liters in',
                  width: 0.7,
                  align: 'right',
                  cell: (l) => {
                    const item = itemOf(l)
                    return item ? formatLiters(l.receivedCans * item.unitVolume) : '—'
                  },
                },
                {
                  header: 'Result',
                  width: 1.3,
                  cell: (l) => <LineResultBadge result={l.result} />,
                },
                {
                  header: 'Reason',
                  width: 2,
                  cell: (l) => <span className="text-small text-ink-muted">{l.reason ?? '—'}</span>,
                },
              ]}
            />
          </div>
        </Card>
      </div>
    </Dialog>
  )
}
