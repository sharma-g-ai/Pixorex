import { useState } from 'react'
import { Link } from 'react-router'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { SelectField } from '../../components/SelectField'
import { SyncAge, TransactionBadge } from '../../components/StockBadges'
import type { UnrecognisedScan } from '../../data/model'
import {
  customerById,
  daysSince,
  negativeStock,
  unrecognisedFor,
  userById,
  vesselById,
  visibleVessels,
} from '../../data/queries'
import { can } from '../../data/roles'
import { items } from '../../data/sample'
import { formatDateTime } from '../../lib/format'

/** Vessels whose tablet has not synced within the 1–3 days A-07 expects. */
export function lateVessels(vesselIds: string[]) {
  return visibleVesselsById(vesselIds).filter((v) => {
    const days = daysSince(v.lastSync)
    return days === null || days > 3
  })
}

function visibleVesselsById(ids: string[]) {
  return ids.map((id) => vesselById(id)).filter((v) => v !== undefined)
}

/**
 * What needs someone's attention: late syncs (A-07), and the BRD §13 mitigations — negative
 * stock surfaced for review, unrecognised articles flagged rather than rejected.
 */
export function NeedsAttention() {
  const { user } = useViewer()
  const ids = visibleVessels(user).map((v) => v.id)
  const late = lateVessels(ids)
  const negative = can(user, 'view-review') ? negativeStock(ids) : []
  const unrecognised = can(user, 'view-review') ? unrecognisedFor(ids) : []
  const [matching, setMatching] = useState<UnrecognisedScan | null>(null)
  const canResolve = can(user, 'resolve-unrecognised')

  return (
    <section id="attention" className="flex flex-col gap-5">
      <Card
        title="Late or no sync"
        subtitle="No sync for more than 3 days (A-07 expects every 1–3 days)"
        flush
      >
        <div className="p-4">
          <DataTable
            label="Late sync"
            rows={late}
            rowKey={(v) => v.id}
            empty="Every vessel synced in the last 3 days"
            columns={[
              {
                header: 'Vessel',
                width: 1.6,
                cell: (v) => (
                  <div>
                    <Link
                      to={`/sea-stock?vessel=${v.id}`}
                      className="font-semibold text-brand hover:underline"
                    >
                      {v.name}
                    </Link>
                    <div>
                      <Muted>{customerById(v.customer)?.name}</Muted>
                    </div>
                  </div>
                ),
              },
              { header: 'Tablet', width: 0.9, cell: (v) => <Mono>{v.device?.id ?? '—'}</Mono> },
              {
                header: 'Opening stock',
                width: 1,
                cell: (v) =>
                  v.baselineOn ? 'Captured' : <span className="text-warning">Not captured</span>,
              },
              { header: 'Last sync', width: 1.2, cell: (v) => <SyncAge at={v.lastSync} /> },
            ]}
          />
        </div>
      </Card>
      {can(user, 'view-review') && (
        <>
          <Card
            title="Negative stock"
            subtitle="More cans scanned out than the vessel has on record"
            flush
          >
            <div className="p-4">
              <DataTable
                label="Negative stock"
                rows={negative}
                rowKey={(l) => `${l.vessel}-${l.item.articleNo}`}
                empty="No negative stock"
                columns={[
                  {
                    header: 'Vessel',
                    width: 1.4,
                    cell: (l) => (
                      <div>
                        <Link
                          to={`/sea-stock?vessel=${l.vessel}`}
                          className="font-semibold text-brand hover:underline"
                        >
                          {vesselById(l.vessel)?.name}
                        </Link>
                        <div>
                          <Muted>{customerById(vesselById(l.vessel)?.customer ?? '')?.name}</Muted>
                        </div>
                      </div>
                    ),
                  },
                  {
                    header: 'Item',
                    width: 1.8,
                    cell: (l) => (
                      <div>
                        <div className="font-semibold">{l.item.product}</div>
                        <Muted>
                          <Mono>{l.item.articleNo}</Mono> · {l.item.componentType} ·{' '}
                          {l.item.packSize}
                        </Muted>
                      </div>
                    ),
                  },
                  {
                    header: 'On record',
                    width: 0.8,
                    align: 'right',
                    cell: (l) => <b className="text-danger">{l.cans} cans</b>,
                  },
                  { header: 'Last change', width: 1.1, cell: (l) => formatDateTime(l.lastChange) },
                  {
                    header: 'Likely cause',
                    width: 2,
                    cell: () => (
                      <span className="text-small text-ink-muted">
                        A receipt not scanned, a missed opening count, or a can scanned out twice
                        (BRD §13). Correct with a stock adjustment on the tablet.
                      </span>
                    ),
                  },
                ]}
              />
            </div>
          </Card>

          <Card
            title="Unrecognised scans"
            subtitle="Held aside: not in Sea Stock until matched to an article"
            flush
          >
            <div className="p-4">
              <DataTable
                label="Unrecognised scans"
                rows={unrecognised}
                rowKey={(s) => s.id}
                empty="No unrecognised scans"
                columns={[
                  {
                    header: 'Vessel',
                    width: 1.3,
                    cell: (s) => (
                      <div>
                        <div className="font-semibold">{vesselById(s.vessel)?.name}</div>
                        <Muted>{userById(s.user)?.name}</Muted>
                      </div>
                    ),
                  },
                  { header: 'Type', width: 0.9, cell: (s) => <TransactionBadge type={s.type} /> },
                  {
                    header: 'Read from the label',
                    width: 2,
                    cell: (s) => (
                      <div>
                        <div>
                          Article no.{' '}
                          {s.readArticleNo ? (
                            <Mono>{s.readArticleNo}</Mono>
                          ) : (
                            <span className="text-danger">not readable</span>
                          )}
                        </div>
                        <Muted>
                          {s.readProduct} · {s.readShade}
                        </Muted>
                      </div>
                    ),
                  },
                  { header: 'Cans', width: 0.5, align: 'right', cell: (s) => s.cans },
                  { header: 'Recorded', width: 1.1, cell: (s) => formatDateTime(s.recordedAt) },
                  {
                    header: '',
                    width: 0.9,
                    align: 'right',
                    cell: (s) =>
                      canResolve ? (
                        <Button variant="link" onClick={() => setMatching(s)}>
                          Match to article
                        </Button>
                      ) : (
                        <Muted>PPG admin to match</Muted>
                      ),
                  },
                ]}
              />
            </div>
          </Card>
          <Note>
            Who reviews negative stock and how it is corrected in the portal is not set in the BRD
            yet. Corrections are made as stock adjustments on the tablet (FR-13).
          </Note>
        </>
      )}

      {matching && <MatchDialog scan={matching} onClose={() => setMatching(null)} />}
    </section>
  )
}

function MatchDialog({ scan, onClose }: { scan: UnrecognisedScan; onClose: () => void }) {
  // Suggest the article whose product and shade match what was read (A-02 fallback).
  const suggestion = items.find(
    (i) => i.status === 'active' && i.product === scan.readProduct && i.shade === scan.readShade,
  )
  const [article, setArticle] = useState(suggestion?.articleNo ?? '')
  return (
    <Dialog
      title="Match to article"
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={onClose} disabled={!article}>
            Match and post
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>
          Read from the label: article no. {scan.readArticleNo ?? 'not readable'},{' '}
          {scan.readProduct}, {scan.readShade} — {scan.cans} {scan.cans === 1 ? 'can' : 'cans'}.
        </p>
        {suggestion && (
          <Note>
            Product and shade match article <b>{suggestion.articleNo}</b>. The article number was
            probably misread.
          </Note>
        )}
        <SelectField
          label="Article on the master item list"
          value={article}
          onChange={(e) => setArticle(e.target.value)}
          options={[
            { value: '', label: 'Choose an article…' },
            ...items
              .filter((i) => i.status === 'active')
              .map((i) => ({
                value: i.articleNo,
                label: `${i.articleNo} · ${i.product} ${i.shade || i.componentType} · ${i.packSize}`,
              })),
          ]}
        />
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
