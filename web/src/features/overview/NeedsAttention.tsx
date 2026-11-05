import { useState } from 'react'
import { Link } from 'react-router'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { SelectField } from '../../components/SelectField'
import { ImoCheckBadge, SyncAge, TransactionBadge } from '../../components/StockBadges'
import { TextAreaField } from '../../components/TextAreaField'
import type { QuarantinedEvent, UnrecognisedScan } from '../../data/model'
import {
  activeDevice,
  customerById,
  daysSince,
  imoReviewFor,
  negativeStock,
  openHeldEventsFor,
  unrecognisedFor,
  vesselById,
  visibleVessels,
} from '../../data/queries'
import { can } from '../../data/roles'
import { items } from '../../data/sample'
import { closeHeldEvent, matchScan, useStore } from '../../data/store'
import { formatDate, formatDateTime } from '../../lib/format'

/** Vessels whose tablet has not synced within the usual 1–3 days (A-07). */
export function lateVessels(vesselIds: string[]) {
  return vesselIds
    .map((id) => vesselById(id))
    .filter((v) => v !== undefined)
    .filter((v) => {
      const days = daysSince(v.lastSync)
      return days === null || days > 3
    })
}

function VesselCell({ vesselId }: { vesselId: string }) {
  const v = vesselById(vesselId)
  return (
    <div className="min-w-0">
      <Link to={`/sea-stock?vessel=${vesselId}`} className="font-semibold text-brand hover:underline">
        {v?.name}
      </Link>
      <div>
        <Muted>{customerById(v?.customer ?? '')?.name}</Muted>
      </div>
    </div>
  )
}

const kindToType = { receipt: 'receipt', consumption: 'consumption', baseline: 'baseline' } as const

/**
 * What needs someone's attention: late syncs, negative stock, scans whose article number is not
 * in the master list, uploads the server could not apply, and delivery notes whose IMO does not
 * match the vessel or was not read (BRD §13; data model Domains 2, 4, 5).
 */
export function NeedsAttention() {
  useStore()
  const { user } = useViewer()
  const ids = visibleVessels(user).map((v) => v.id)
  const late = lateVessels(ids)
  const negative = negativeStock(ids)
  const unrecognised = unrecognisedFor(ids)
  const held = openHeldEventsFor(ids)
  const toCheck = imoReviewFor(ids)
  const [matching, setMatching] = useState<UnrecognisedScan | null>(null)
  const [closing, setClosing] = useState<QuarantinedEvent | null>(null)

  return (
    <section id="attention" className="flex flex-col gap-5">
      <Card title="Late or no sync" subtitle="No sync for more than 3 days; vessels usually sync every 1–3 days" flush>
        <div className="p-4">
          <DataTable
            label="Late sync"
            rows={late}
            rowKey={(v) => v.id}
            empty="Every vessel synced in the last 3 days"
            columns={[
              { header: 'Vessel', width: 1.6, cell: (v) => <VesselCell vesselId={v.id} /> },
              { header: 'Tablet', width: 0.9, cell: (v) => <Mono>{activeDevice(v.id)?.id ?? 'None paired'}</Mono> },
              {
                header: 'Opening stock',
                width: 1,
                cell: (v) => (v.baselineOn ? 'Captured' : <span className="text-warning">Not captured</span>),
              },
              { header: 'Last sync', width: 1.2, cell: (v) => <SyncAge at={v.lastSync} /> },
            ]}
          />
        </div>
      </Card>

      <Card
        title="Negative stock"
        subtitle="More cans scanned out than on record: usually a receipt not scanned, a can missed in the opening count, or a can scanned out twice. Correct it with a stock adjustment."
        flush
      >
        <div className="p-4">
          <DataTable
            label="Negative stock"
            rows={negative}
            rowKey={(l) => `${l.vessel}-${l.item.articleNo}`}
            empty="No negative stock"
            columns={[
              { header: 'Vessel', width: 1.4, cell: (l) => <VesselCell vesselId={l.vessel} /> },
              {
                header: 'Item',
                width: 1.8,
                cell: (l) => (
                  <div>
                    <div className="font-semibold">{l.item.product}</div>
                    <Muted>
                      <Mono>{l.item.articleNo}</Mono> · {l.item.componentType} · {l.item.packSize}
                    </Muted>
                  </div>
                ),
              },
              { header: 'On record', width: 0.8, align: 'right', cell: (l) => <b className="text-danger">{l.cans} cans</b> },
              { header: 'Last change', width: 1.1, cell: (l) => formatDateTime(l.lastChange) },
            ]}
          />
        </div>
      </Card>

      <Card title="Unrecognised scans" subtitle="The article number read is not in the master item list. Held aside, not in Sea Stock, until a PPG Admin matches it." flush>
        <div className="p-4">
          <DataTable
            label="Unrecognised scans"
            rows={unrecognised}
            rowKey={(s) => s.id}
            empty="No unrecognised scans"
            columns={[
              { header: 'Vessel', width: 1.3, cell: (s) => <VesselCell vesselId={s.vessel} /> },
              { header: 'Type', width: 0.9, cell: (s) => <TransactionBadge type={kindToType[s.kind]} /> },
              {
                header: 'Read from the label',
                width: 1.8,
                cell: (s) => (
                  <div>
                    <div>
                      Article no. <Mono>{s.rawArticleNo}</Mono>
                    </div>
                    <Muted>{[s.rawLabel.product, s.rawLabel.shade].filter(Boolean).join(' · ')}</Muted>
                  </div>
                ),
              },
              { header: 'Cans', width: 0.5, align: 'right', cell: (s) => s.cans },
              { header: 'Recorded', width: 1.1, cell: (s) => formatDateTime(s.recordedAt) },
              {
                header: '',
                width: 1.2,
                align: 'right',
                cell: (s) =>
                  can(user, 'match-scans') ? (
                    <Button variant="secondary" onClick={() => setMatching(s)}>
                      Match to article
                    </Button>
                  ) : (
                    <Muted>PPG Admin to match</Muted>
                  ),
              },
            ]}
          />
        </div>
      </Card>

      <Card title="Held sync events" subtitle="Uploaded from a tablet but not applied, e.g. a delivery note sent twice. Nothing is lost: each is kept here until an admin closes it." flush>
        <div className="p-4">
          <DataTable
            label="Held sync events"
            rows={held}
            rowKey={(e) => e.id}
            empty="No held events"
            columns={[
              { header: 'Vessel', width: 1.3, cell: (e) => <VesselCell vesselId={e.vessel} /> },
              {
                header: 'What was sent',
                width: 1.8,
                cell: (e) => (
                  <div>
                    <div>{e.summary}</div>
                    <Muted>
                      Tablet <Mono>{e.device}</Mono> · {formatDateTime(e.receivedAt)}
                    </Muted>
                  </div>
                ),
              },
              { header: 'Why it was held', width: 1.8, cell: (e) => <span className="text-small">{e.errorDetail}</span> },
              {
                header: '',
                width: 0.8,
                align: 'right',
                cell: (e) =>
                  can(user, 'close-held-events') ? (
                    <Button variant="secondary" onClick={() => setClosing(e)}>
                      Close
                    </Button>
                  ) : (
                    <Muted>PPG Admin to close</Muted>
                  ),
              },
            ]}
          />
        </div>
      </Card>

      <Card title="Delivery notes to check" subtitle="The IMO on the paper is not this vessel’s, or could not be read. The receipt is still on the tablet’s vessel; check the note." flush>
        <div className="p-4">
          <DataTable
            label="Delivery notes to check"
            rows={toCheck}
            rowKey={(d) => d.dnNumber}
            empty="No delivery notes to check"
            columns={[
              { header: 'Vessel', width: 1.3, cell: (d) => <VesselCell vesselId={d.vessel} /> },
              {
                header: 'Delivery note',
                width: 1.3,
                cell: (d) => (
                  <div>
                    <Link to={`/activity?tab=notes&dn=${d.dnNumber}`} className="font-semibold text-brand hover:underline">
                      DN <Mono>{d.dnNumber}</Mono>
                    </Link>
                    <div>
                      <Muted>Dated {formatDate(d.dnDate)}</Muted>
                    </div>
                  </div>
                ),
              },
              {
                header: 'On the note',
                width: 1.6,
                cell: (d) => (
                  <div>
                    <div>
                      IMO <Mono>{d.imoOnNote ?? '—'}</Mono> <ImoCheckBadge check={d.imoCheck} />
                    </div>
                    <Muted>{d.vesselNameOnNote}</Muted>
                  </div>
                ),
              },
              { header: 'Confirmed', width: 1, cell: (d) => formatDateTime(d.confirmedAt) },
            ]}
          />
        </div>
      </Card>

      {matching && <MatchDialog scan={matching} onClose={() => setMatching(null)} />}
      {closing && <CloseHeldDialog event={closing} onClose={() => setClosing(null)} />}
    </section>
  )
}

function MatchDialog({ scan, onClose }: { scan: UnrecognisedScan; onClose: () => void }) {
  const { user } = useViewer()
  const [article, setArticle] = useState('')
  return (
    <Dialog
      title="Match to article"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!article}
            onClick={() => {
              matchScan(scan, article, user)
              onClose()
            }}
          >
            Match and post
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>
          Read from the label: article no. <Mono>{scan.rawArticleNo}</Mono>
          {scan.rawLabel.product ? `, ${scan.rawLabel.product}` : ''}
          {scan.rawLabel.shade ? `, ${scan.rawLabel.shade}` : ''} — {scan.cans} {scan.cans === 1 ? 'can' : 'cans'}.
        </p>
        <SelectField
          label="Article on the master item list"
          value={article}
          onChange={(e) => setArticle(e.target.value)}
          options={[
            { value: '', label: 'Choose an article…' },
            ...items.map((i) => ({ value: i.articleNo, label: `${i.articleNo} · ${i.product} ${i.shade || i.componentType} · ${i.packSize}` })),
          ]}
        />
        <Note>
          Posting adds it to the vessel’s stock as the {scan.kind} it was, dated at the original scan and
          recorded under your name.
        </Note>
        <p className="text-small">
          Not on the list? Add it to the{' '}
          <Link to="/admin/products" className="font-semibold text-brand hover:underline">
            master item list
          </Link>{' '}
          first.
        </p>
      </div>
    </Dialog>
  )
}

function CloseHeldDialog({ event, onClose }: { event: QuarantinedEvent; onClose: () => void }) {
  const { user } = useViewer()
  const [outcome, setOutcome] = useState<'resolved' | 'dismissed'>('resolved')
  const [note, setNote] = useState('')
  return (
    <Dialog
      title="Close held event"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!note.trim()}
            onClick={() => {
              closeHeldEvent(event.id, outcome, note.trim(), user)
              onClose()
            }}
          >
            Close event
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>
          {event.summary}. {event.errorDetail}
        </p>
        <SelectField
          label="Outcome"
          value={outcome}
          onChange={(e) => setOutcome(e.target.value as 'resolved' | 'dismissed')}
          options={[
            { value: 'resolved', label: 'Resolved — fixed another way (e.g. a stock adjustment)' },
            { value: 'dismissed', label: 'Dismissed — nothing to do' },
          ]}
        />
        <TextAreaField label="Note (required)" value={note} onChange={(e) => setNote(e.target.value)} />
        <p className="text-small">Closing posts nothing to stock and cannot be undone.</p>
      </div>
    </Dialog>
  )
}
