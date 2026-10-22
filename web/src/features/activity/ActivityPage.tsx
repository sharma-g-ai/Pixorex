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
import type { TransactionSource, TransactionType } from '../../data/model'
import {
  customerById,
  itemByArticle,
  liters,
  transactionsFor,
  userById,
  vesselById,
  visibleVessels,
} from '../../data/queries'
import { deliveryNotes } from '../../data/sample'
import { downloadCsv } from '../../lib/csv'
import { ActivityTable } from './ActivityTable'
import { DeliveryNoteDialog } from './DeliveryNoteDialog'
import { DeliveryNotesTable, differences, receivedCans } from './DeliveryNotesTable'

type TabKey = 'transactions' | 'notes'

/**
 * Everything recorded on board: the audit trail of transactions (FR-12, FR-13), and the
 * delivery notes received with their tally (FR-01 – FR-05). ?dn=<number> opens one note.
 */
export function ActivityPage() {
  const { user } = useViewer()
  const [params, setParams] = useSearchParams()
  const tab: TabKey = params.get('tab') === 'notes' ? 'notes' : 'transactions'
  const scope = useScopeFilter()
  const period = usePeriod()
  const [type, setType] = useState<TransactionType | ''>('')
  const [source, setSource] = useState<TransactionSource | ''>('')
  const [tally, setTally] = useState('')
  const [search, setSearch] = useState('')

  const ids = scope.vessels.map((v) => v.id)
  const inPeriod = (at: string) => at.slice(0, 10) >= period.from && at.slice(0, 10) <= period.to
  const rows = transactionsFor(ids)
    .filter((t) => inPeriod(t.recordedAt))
    .filter((t) => (!type || t.type === type) && (!source || t.source === source))
  const notes = deliveryNotes
    .filter((dn) => ids.includes(dn.vessel) && inPeriod(dn.capturedAt))
    .filter((dn) => !tally || (tally === 'matched' ? differences(dn) === 0 : differences(dn) > 0))
    .filter((dn) =>
      `${dn.dnNumber} ${dn.customerReference}`.toLowerCase().includes(search.trim().toLowerCase()),
    )
    .sort((a, b) => b.capturedAt.localeCompare(a.capturedAt))

  // Only notes for vessels the user may see open (FR-23).
  const open = deliveryNotes.find(
    (d) => d.dnNumber === params.get('dn') && visibleVessels(user).some((v) => v.id === d.vessel),
  )
  const closeNote = () => {
    params.delete('dn')
    setParams(params, { replace: true })
  }

  const exportCsv = () =>
    tab === 'transactions'
      ? downloadCsv(
          'activity.csv',
          [
            'Transaction ID',
            'Type',
            'Recorded (UTC)',
            'Synced (UTC)',
            'Region',
            'Customer',
            'Vessel',
            'Article no.',
            'Product',
            'Shade',
            'Cans',
            'Liters',
            'User',
            'Device',
            'Source',
            'DN',
            'Reason',
          ],
          rows.map((t) => {
            const item = itemByArticle(t.articleNo)
            const v = vesselById(t.vessel)
            const c = v && customerById(v.customer)
            return [
              t.id,
              t.type,
              t.recordedAt,
              t.syncedAt,
              c?.region ?? '',
              c?.name ?? '',
              v?.name ?? '',
              t.articleNo,
              item?.product ?? '',
              item?.shade ?? '',
              t.cans,
              liters(t.articleNo, t.cans),
              userById(t.user)?.name ?? '',
              t.device,
              t.source,
              t.dn ?? '',
              t.reason ?? '',
            ]
          }),
        )
      : downloadCsv(
          'delivery-notes.csv',
          [
            'DN number',
            'DN date',
            'Region',
            'Customer',
            'Vessel',
            'IMO',
            'Customer reference',
            'Lines',
            'Cans received',
            'Differences',
            'Received by',
            'Confirmed (UTC)',
            'Synced (UTC)',
          ],
          notes.map((dn) => {
            const v = vesselById(dn.vessel)
            const c = v && customerById(v.customer)
            return [
              dn.dnNumber,
              dn.dnDate,
              c?.region ?? '',
              c?.name ?? '',
              v?.name ?? '',
              v?.imo ?? '',
              dn.customerReference,
              dn.lines.length,
              receivedCans(dn),
              differences(dn),
              userById(dn.capturedBy)?.name ?? '',
              dn.capturedAt,
              dn.syncedAt,
            ]
          }),
        )

  return (
    <>
      <PageHeader
        title="Activity"
        subtitle="Everything recorded on board: receipts, consumption, adjustments and baseline counts"
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
          onChange={(key) => setParams(key === 'notes' ? { tab: 'notes' } : {})}
          tabs={[
            { key: 'transactions', label: 'Transactions' },
            { key: 'notes', label: 'Delivery notes' },
          ]}
        />
        <FilterBar>
          {period.controls}
          {scope.controls}
          {tab === 'transactions' ? (
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
                options={[
                  { value: '', label: 'All sources' },
                  { value: 'DN scan', label: 'DN scan' },
                  { value: 'Label scan', label: 'Label scan' },
                  { value: 'Manual adjustment', label: 'Manual adjustment' },
                ]}
              />
            </>
          ) : (
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
              <TextField
                label="Search"
                placeholder="DN number or customer ref."
                className="w-60"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </>
          )}
        </FilterBar>

        <Card flush>
          <div className="flex justify-end px-5 pt-3">
            <Muted>
              {tab === 'transactions'
                ? `${rows.length} transactions`
                : `${notes.length} delivery notes`}{' '}
              · times in UTC
            </Muted>
          </div>
          <div className="p-4">
            {tab === 'transactions' ? (
              <ActivityTable rows={rows} />
            ) : (
              <DeliveryNotesTable rows={notes} />
            )}
          </div>
        </Card>
        {tab === 'notes' && (
          <Note>
            The crew resolves differences on the tablet before confirming (FR-04, FR-05); the portal
            shows the result. Delivery note images are not kept (D-07).
          </Note>
        )}
      </PageBody>
      {open && <DeliveryNoteDialog dn={open} onClose={closeNote} />}
    </>
  )
}
