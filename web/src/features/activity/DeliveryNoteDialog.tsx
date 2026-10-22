import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Card, Detail, Mono, Muted } from '../../components/Page'
import { ComponentBadge, LineResultBadge } from '../../components/StockBadges'
import type { DeliveryNote, DeliveryNoteLine } from '../../data/model'
import { customerById, itemByArticle, liters, userById, vesselById } from '../../data/queries'
import { formatDate, formatDateTime, formatLiters } from '../../lib/format'
import { differences, receivedCans } from './DeliveryNotesTable'

/** One delivery note: header as read from the DN (FR-01) and the line-by-line tally (FR-04, FR-05). */
export function DeliveryNoteDialog({ dn, onClose }: { dn: DeliveryNote; onClose: () => void }) {
  const vessel = vesselById(dn.vessel)
  const customer = vessel && customerById(vessel.customer)

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
            <Detail label="Vessel (IMO)">{vessel?.imo}</Detail>
            <Detail label="Vessel name">{vessel?.name}</Detail>
            <Detail label="Customer">{customer?.name}</Detail>
            <Detail label="Customer reference">
              <Mono>{dn.customerReference}</Mono>
            </Detail>
            <Detail label="Received by">{userById(dn.capturedBy)?.name}</Detail>
            <Detail label="Confirmed on tablet">{formatDateTime(dn.capturedAt)}</Detail>
            <Detail label="Synced">{formatDateTime(dn.syncedAt)}</Detail>
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
              rowKey={(l) => l.articleNo}
              empty="No lines"
              columns={[
                { header: 'Article no.', width: 0.8, cell: (l) => <Mono>{l.articleNo}</Mono> },
                {
                  header: 'Item',
                  width: 1.9,
                  cell: (l) => {
                    const item = itemByArticle(l.articleNo)
                    return (
                      <div className="flex min-w-0 items-center gap-2">
                        <div className="min-w-0">
                          <div className="truncate font-semibold">{item?.product}</div>
                          <Muted>
                            {item?.shade || 'No shade'} · {item?.packSize}
                          </Muted>
                        </div>
                        {item && <ComponentBadge type={item.componentType} />}
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
                    const d = l.receivedCans - l.dnCans
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
                  cell: (l) => formatLiters(liters(l.articleNo, l.receivedCans)),
                },
                {
                  header: 'Result',
                  width: 0.9,
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
