import { useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { useBusinessUnits } from '../../api/businessUnits'
import type { ExportJob } from '../../api/exports'
import { useAllScans, type ScanRow } from '../../api/scans'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { DataTable, type Column } from '../../components/DataTable'
import { LoadMore } from '../../components/LoadMore'
import { PageHeader } from '../../components/layout/PageHeader'
import { SelectField } from '../../components/SelectField'
import { Tabs } from '../../components/Tabs'
import { TextField } from '../../components/TextField'
import { dateRange, datePresetLabels, type DatePreset } from '../../lib/dateRange'
import { timeAgo } from '../../lib/time'
import { ExportDialog } from '../exports/ExportDialog'
import { ExportJobNotice } from '../exports/ExportJobNotice'
import {
  reviewedByText,
  scanStatus,
  statusFilterLabels,
  statusQuery,
  type StatusFilter,
} from './scanStatus'

const columns: Column<ScanRow>[] = [
  {
    header: 'Scan',
    width: 2,
    cell: (s) => (
      <Link to={`/scans/${s.scan_id}`} className="block min-w-0 hover:underline">
        <span className="block truncate font-semibold">{s.equipment_type_name}</span>
        <span className="font-mono text-meta text-ink-subtle">{s.record_no}</span>
      </Link>
    ),
  },
  {
    header: 'Unit · location',
    width: 2,
    cell: (s) => <span className="truncate">{`${s.bu_name} · ${s.location_path}`}</span>,
  },
  { header: 'Captured by', width: 1, cell: (s) => s.captured_by_name },
  {
    header: 'Status',
    width: 1,
    cell: (s) => {
      const status = scanStatus(s)
      return <Badge tone={status.tone}>{status.label}</Badge>
    },
  },
  {
    header: 'Reviewed by',
    width: 1.3,
    cell: (s) => <span className="truncate">{reviewedByText(s)}</span>,
  },
  { header: 'Age', width: 0.8, cell: (s) => timeAgo(s.captured_at) },
]

/** Every scan in every unit, filtered by unit, status and date (canvas EA 20, 38–50; contract 3.18). */
export function ScansPage() {
  const units = useBusinessUnits()
  const [params] = useSearchParams()
  const [unit, setUnit] = useState(params.get('unit') ?? 'all')
  const [status, setStatus] = useState<StatusFilter>('any')
  const [period, setPeriod] = useState<DatePreset>('30d')
  // What is typed vs. what was searched: the list reloads on Enter, not on every key.
  const [typed, setTyped] = useState('')
  const [search, setSearch] = useState('')
  const [exporting, setExporting] = useState(false)
  const [exportJob, setExportJob] = useState<ExportJob | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const { delegated, ...exportFilters } = {
    ...(unit === 'all' ? {} : { bu_id: unit }),
    ...statusQuery(status),
    ...dateRange(period),
  }
  // Exports can't filter by "delegated" (contract 4.1 ExportFilters), the list can (3.18).
  const scans = useAllScans({
    ...exportFilters,
    ...(delegated ? { delegated } : {}),
    ...(search ? { q: search } : {}),
  })
  const unitName = units.data?.find((u) => u.bu_id === unit)?.name

  return (
    <>
      <PageHeader
        title="Scans"
        subtitle={`${unitName ?? 'All units'} · ${datePresetLabels[period].toLowerCase()}`}
        actions={
          <Button variant="secondary" onClick={() => setExporting(true)}>
            Export CSV
          </Button>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        {exportJob && <ExportJobNotice key={exportJob.export_id} job={exportJob} />}
        <div className="flex flex-wrap items-end gap-3">
          <div className="grow">
            <Tabs
              label="Unit"
              look="pills"
              tabs={[
                { key: 'all', label: 'All units' },
                ...(units.data ?? []).map((u) => ({ key: u.bu_id, label: u.name })),
              ]}
              current={unit}
              onChange={setUnit}
            />
          </div>
          <SelectField
            label="Status"
            hideLabel
            className="w-44"
            value={status}
            onChange={(e) => setStatus(e.target.value as StatusFilter)}
            options={Object.entries(statusFilterLabels).map(([value, label]) => ({ value, label }))}
          />
          <SelectField
            label="Date range"
            hideLabel
            className="w-40"
            value={period}
            onChange={(e) => setPeriod(e.target.value as DatePreset)}
            options={Object.entries(datePresetLabels).map(([value, label]) => ({ value, label }))}
          />
          <form
            role="search"
            className="w-64"
            onSubmit={(e) => {
              e.preventDefault()
              setSearch(typed.trim())
            }}
          >
            <TextField
              label="Search scans"
              hideLabel
              type="search"
              placeholder="Search type, serial, technician"
              value={typed}
              onChange={(e) => {
                setTyped(e.target.value)
                if (e.target.value === '') setSearch('')
              }}
            />
          </form>
        </div>
        {scans.isPending ? (
          <Card>Loading scans…</Card>
        ) : scans.isError ? (
          <Card>We couldn't load scans. Please refresh.</Card>
        ) : (
          <DataTable
            label="Scans"
            columns={columns}
            rows={scans.items}
            rowKey={(s) => s.scan_id}
            empty="No scans match these filters."
          />
        )}
        <LoadMore {...scans} />
        <p className="text-small text-ink-subtle">
          Exports of up to 1,000 rows download straight away. Bigger exports are prepared in the
          background and you get a dashboard notice and an email with a link valid for 1 hour.
        </p>
      </div>
      {exporting && (
        <ExportDialog
          kind="scans"
          title="Export scans to CSV"
          scopes={[
            {
              key: 'view',
              label: "What you're looking at",
              filters: exportFilters,
            },
            { key: 'all', label: 'All units', filters: {} },
            {
              key: 'approved',
              label: 'Approved scans only',
              filters: { review_status: 'approved' },
            },
          ]}
          note="Every export is recorded in the audit log."
          onClose={() => setExporting(false)}
          onDownloaded={() => {
            setExporting(false)
            setNotice('CSV downloaded. The export is recorded in the audit log.')
          }}
          onQueued={(job) => {
            setExporting(false)
            setExportJob(job)
          }}
        />
      )}
    </>
  )
}
