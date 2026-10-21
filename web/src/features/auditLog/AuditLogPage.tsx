import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { useAuditLog, type AuditCategory } from '../../api/auditLog'
import { useBusinessUnits } from '../../api/businessUnits'
import type { ExportJob } from '../../api/exports'
import { useDashboard } from '../../app/DashboardContext'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { DataTable } from '../../components/DataTable'
import { LoadMore } from '../../components/LoadMore'
import { PageHeader } from '../../components/layout/PageHeader'
import { SelectField } from '../../components/SelectField'
import { datePresetLabels, dateRange, type DatePreset } from '../../lib/dateRange'
import { ExportDialog } from '../exports/ExportDialog'
import { ExportJobNotice } from '../exports/ExportJobNotice'
import { DOWNLOADED_NOTICE } from '../exports/exportText'
import { auditColumns } from './auditColumns'
import { auditCategoryLabels } from './auditLabels'

const categoryOptions = Object.entries(auditCategoryLabels).map(([value, label]) => ({
  value,
  label,
}))
const auditPresets = ['today', '7d', '30d'] as const satisfies DatePreset[]

/**
 * Insert-only audit log (canvas EA 22, 51–66, 69; contract 3.22). EA sees every unit;
 * a BU Admin sees their current unit (decision D-06).
 */
export function AuditLogPage() {
  const { role, unit: buUnit } = useDashboard()
  const ea = role === 'enterprise_admin'
  const units = useBusinessUnits()
  const [params] = useSearchParams()
  const [unit, setUnit] = useState(params.get('unit') ?? '')
  const [category, setCategory] = useState<AuditCategory | ''>('')
  const [period, setPeriod] = useState<DatePreset>('7d')
  const [exporting, setExporting] = useState(false)
  const [exportJob, setExportJob] = useState<ExportJob | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const buId = ea ? unit : (buUnit?.bu_id ?? '')
  const log = useAuditLog({
    ...(buId ? { bu_id: buId } : {}),
    ...(category ? { category } : {}),
    ...dateRange(period),
  })
  const unitOptions = ea
    ? (units.data ?? []).map((u) => ({ value: u.bu_id, label: u.name }))
    : undefined
  const filtered = unit !== '' || category !== '' || period !== '7d'

  return (
    <>
      <PageHeader
        title="Audit log"
        subtitle={
          ea
            ? 'Every admin and review action, all units'
            : `Every admin and review action in ${buUnit?.name ?? 'your unit'}`
        }
        actions={
          <Button variant="secondary" onClick={() => setExporting(true)}>
            Export CSV
          </Button>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        {exportJob && <ExportJobNotice key={exportJob.export_id} job={exportJob} />}
        <div className="flex flex-wrap items-center gap-3">
          {unitOptions && (
            <SelectField
              label="Unit"
              hideLabel
              className="w-48"
              value={unit}
              onChange={(e) => setUnit(e.target.value)}
              options={[{ value: '', label: 'All units' }, ...unitOptions]}
            />
          )}
          <SelectField
            label="Type of action"
            hideLabel
            className="w-48"
            value={category}
            onChange={(e) => setCategory(e.target.value as AuditCategory | '')}
            options={[{ value: '', label: 'All actions' }, ...categoryOptions]}
          />
          <SelectField
            label="Date range"
            hideLabel
            className="w-40"
            value={period}
            onChange={(e) => setPeriod(e.target.value as DatePreset)}
            options={auditPresets.map((p) => ({ value: p, label: datePresetLabels[p] }))}
          />
          {filtered && (
            <Button
              variant="link"
              onClick={() => {
                setUnit('')
                setCategory('')
                setPeriod('7d')
              }}
            >
              Clear filters
            </Button>
          )}
        </div>
        {log.isPending ? (
          <Card>Loading the audit log…</Card>
        ) : log.isError ? (
          <Card>We couldn't load the audit log. Please refresh.</Card>
        ) : (
          <DataTable
            label="Audit log"
            columns={auditColumns}
            rows={log.items}
            rowKey={(e) => String(log.items.indexOf(e))}
            empty="Nothing recorded for these filters."
          />
        )}
        <LoadMore {...log} />
        <p className="text-small text-ink-subtle">
          The audit log can't be edited or deleted by anyone. It's kept 1 year online and 3 years
          archived.
        </p>
      </div>
      {exporting && (
        <ExportDialog
          kind="audit_log"
          title="Export audit log"
          unitOptions={unitOptions}
          categoryOptions={categoryOptions}
          note="The export itself is added to the audit log."
          onClose={() => setExporting(false)}
          onDownloaded={() => {
            setExporting(false)
            setNotice(DOWNLOADED_NOTICE)
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
