import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { Icon } from '../../components/icons'
import { PageHeader } from '../../components/layout/PageHeader'
import { Card, Muted, Note, PageBody } from '../../components/Page'
import { usePeriod } from '../../components/PeriodPicker'
import { FilterBar, useScopeFilter } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { Tabs } from '../../components/Tabs'
import { TextField } from '../../components/TextField'
import type { AuditEntry, DeliveryNote, TransactionSource, TransactionType } from '../../data/model'
import {
  customerById,
  inPeriod,
  itemByArticle,
  liters,
  recordedByLabel,
  transactionsFor,
  vesselById,
  visibleCustomers,
  visibleVessels,
} from '../../data/queries'
import { can } from '../../data/roles'
import { auditLog, deliveryNotes } from '../../data/sample'
import { useStore } from '../../data/store'
import { downloadCsv } from '../../lib/csv'
import { ActivityTable } from './ActivityTable'
import { AuditLogTable, auditCategories } from './AuditLogTable'
import { DeliveryNoteDialog } from './DeliveryNoteDialog'
import { DeliveryNotesTable, differences, receivedCans } from './DeliveryNotesTable'

type TabKey = 'transactions' | 'notes' | 'audit'

const sources: TransactionSource[] = ['DN scan', 'Label scan', 'Manual entry', 'Manual adjustment', 'Review match']

/**
 * Everything recorded: stock transactions (FR-12, FR-13), delivery notes with their tally
 * (FR-01 – FR-05), and the audit log of admin and tablet actions (Domain 6).
 * ?tab=notes|audit opens a tab; ?dn=<number> opens one delivery note.
 */
export function ActivityPage() {
  useStore()
  const { user } = useViewer()
  const [params, setParams] = useSearchParams()
  const showAudit = can(user, 'view-audit')
  const asked = params.get('tab')
  const tab: TabKey = asked === 'notes' ? 'notes' : asked === 'audit' && showAudit ? 'audit' : 'transactions'
  const scope = useScopeFilter()
  const period = usePeriod()
  const [type, setType] = useState<TransactionType | ''>('')
  const [source, setSource] = useState<TransactionSource | ''>('')
  const [tally, setTally] = useState('')
  const [imoCheck, setImoCheck] = useState<DeliveryNote['imoCheck'] | ''>('')
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState<AuditEntry['category'] | ''>('')

  const ids = scope.vessels.map((v) => v.id)
  const rows = transactionsFor(ids)
    .filter((t) => inPeriod(t.recordedAt, period.from, period.to))
    .filter((t) => (!type || t.type === type) && (!source || t.source === source))
  const notes = deliveryNotes
    .filter((dn) => ids.includes(dn.vessel) && inPeriod(dn.confirmedAt, period.from, period.to))
    .filter((dn) => !tally || (tally === 'matched' ? differences(dn) === 0 : differences(dn) > 0))
    .filter((dn) => !imoCheck || dn.imoCheck === imoCheck)
    .filter((dn) => `${dn.dnNumber} ${dn.customerReference}`.toLowerCase().includes(search.trim().toLowerCase()))
    .sort((a, b) => b.confirmedAt.localeCompare(a.confirmedAt))
  // A Customer Admin sees only entries about their own customer (to confirm).
  const ownCustomers = new Set(visibleCustomers(user).map((c) => c.id))
  const audit = auditLog
    .filter((a) => user.scope.kind === 'all' || (a.customer !== null && ownCustomers.has(a.customer)))
    .filter((a) => !scope.vessel || a.vessel === scope.vessel)
    .filter((a) => !scope.customer || a.customer === scope.customer)
    .filter((a) => inPeriod(a.at, period.from, period.to) && (!category || a.category === category))

  // Only notes for vessels the user may see open.
  const open = deliveryNotes.find((d) => d.dnNumber === params.get('dn') && visibleVessels(user).some((v) => v.id === d.vessel))
  const closeNote = () => {
    params.delete('dn')
    setParams(params, { replace: true })
  }

  const exportCsv = () => {
    if (tab === 'transactions')
      return downloadCsv(
        'transactions.csv',
        ['Transaction ID', 'Type', 'Recorded (UTC)', 'Received (UTC)', 'Customer', 'Vessel', 'IMO', 'Article no.', 'Product', 'Shade', 'Cans', 'Liters', 'Origin', 'Recorded by', 'Source', 'DN', 'Reason'],
        rows.map((t) => {
          const item = itemByArticle(t.articleNo)
          const v = vesselById(t.vessel)
          return [t.id, t.type, t.recordedAt, t.receivedAt, customerById(v?.customer ?? '')?.name ?? '', v?.name ?? '', v?.imo ?? '', t.articleNo, item?.product ?? '', item?.shade ?? '', t.cans, liters(t.articleNo, t.cans), t.origin, recordedByLabel(t), t.source, t.dn ?? '', t.reason ?? '']
        }),
      )
    if (tab === 'notes')
      return downloadCsv(
        'delivery-notes.csv',
        ['DN number', 'DN date', 'Customer', 'Vessel', 'IMO', 'IMO on note', 'IMO check', 'Customer reference', 'Lines', 'Cans received', 'Differences', 'Tablet', 'Confirmed (UTC)', 'Received (UTC)'],
        notes.map((dn) => {
          const v = vesselById(dn.vessel)
          return [dn.dnNumber, dn.dnDate, customerById(v?.customer ?? '')?.name ?? '', v?.name ?? '', v?.imo ?? '', dn.imoOnNote ?? '', dn.imoCheck, dn.customerReference, dn.lines.length, receivedCans(dn), differences(dn), dn.device, dn.confirmedAt, dn.receivedAt]
        }),
      )
    return downloadCsv(
      'audit-log.csv',
      ['When (UTC)', 'Actor type', 'Actor', 'Area', 'What happened'],
      audit.map((a) => [a.at, a.actorType, a.actor ?? '', auditCategories[a.category], a.summary]),
    )
  }

  const count =
    tab === 'transactions' ? `${rows.length} transactions` : tab === 'notes' ? `${notes.length} delivery notes` : `${audit.length} entries`

  return (
    <>
      <PageHeader
        title="Activity"
        subtitle="Everything recorded: stock movements, delivery notes and who did what"
        actions={
          <Button variant="secondary" onClick={exportCsv}>
            <Icon name="download" /> Export CSV
          </Button>
        }
      />
      <PageBody>
        <Tabs
          label="Activity"
          current={tab}
          onChange={(key) => setParams(key === 'transactions' ? {} : { tab: key })}
          tabs={[
            { key: 'transactions', label: 'Transactions' },
            { key: 'notes', label: 'Delivery notes' },
            ...(showAudit ? [{ key: 'audit' as const, label: 'Audit log' }] : []),
          ]}
        />
        <FilterBar>
          {period.controls}
          {scope.controls}
          {tab === 'transactions' && (
            <>
              <SelectField
                label="Type"
                className="w-40"
                value={type}
                onChange={(e) => setType(e.target.value as TransactionType | '')}
                options={[
                  { value: '', label: 'All types' },
                  { value: 'receipt', label: 'Receipt' },
                  { value: 'consumption', label: 'Consumption' },
                  { value: 'adjustment', label: 'Adjustment' },
                  { value: 'baseline', label: 'Baseline' },
                ]}
              />
              <SelectField
                label="Source"
                className="w-44"
                value={source}
                onChange={(e) => setSource(e.target.value as TransactionSource | '')}
                options={[{ value: '', label: 'All sources' }, ...sources.map((s) => ({ value: s, label: s }))]}
              />
            </>
          )}
          {tab === 'notes' && (
            <>
              <SelectField
                label="Tally"
                className="w-44"
                value={tally}
                onChange={(e) => setTally(e.target.value)}
                options={[
                  { value: '', label: 'All' },
                  { value: 'matched', label: 'All matched' },
                  { value: 'differences', label: 'With differences' },
                ]}
              />
              <SelectField
                label="IMO check"
                className="w-40"
                value={imoCheck}
                onChange={(e) => setImoCheck(e.target.value as DeliveryNote['imoCheck'] | '')}
                options={[
                  { value: '', label: 'All' },
                  { value: 'match', label: 'Matches' },
                  { value: 'mismatch', label: 'Mismatch' },
                  { value: 'not_read', label: 'Not read' },
                ]}
              />
              <TextField
                label="Search"
                placeholder="DN number or customer ref."
                className="w-60"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </>
          )}
          {tab === 'audit' && (
            <SelectField
              label="Area"
              className="w-48"
              value={category}
              onChange={(e) => setCategory(e.target.value as AuditEntry['category'] | '')}
              options={[{ value: '', label: 'All areas' }, ...Object.entries(auditCategories).map(([value, label]) => ({ value, label }))]}
            />
          )}
        </FilterBar>

        <Card flush>
          <div className="flex justify-end px-5 pt-3">
            <Muted>{count} · times in UTC</Muted>
          </div>
          <div className="p-4">
            {tab === 'transactions' && <ActivityTable rows={rows} />}
            {tab === 'notes' && <DeliveryNotesTable rows={notes} />}
            {tab === 'audit' && <AuditLogTable rows={audit} />}
          </div>
        </Card>
        {tab === 'notes' && (
          <Note>
            The crew sorts out differences on the tablet before confirming; the portal shows the result. The
            vessel is always the tablet’s vessel: the IMO read from the paper is only checked. Delivery note
            images are not kept.
          </Note>
        )}
      </PageBody>
      {open && <DeliveryNoteDialog dn={open} onClose={closeNote} />}
    </>
  )
}
