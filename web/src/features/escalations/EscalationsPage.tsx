import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { useBusinessUnits, type BusinessUnit } from '../../api/businessUnits'
import { ApiError, errorMessage, problemCode } from '../../api/client'
import { useEscalations, useRemindBuAdmin } from '../../api/escalations'
import type { ExportJob } from '../../api/exports'
import { useInvites } from '../../api/invites'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { LoadMore } from '../../components/LoadMore'
import { PageHeader } from '../../components/layout/PageHeader'
import { Tabs } from '../../components/Tabs'
import { waitedFor } from '../../lib/time'
import { InviteBuAdminDialog } from '../buAdmins/InviteBuAdminDialog'
import { inviteOptions } from '../buAdmins/unitOptions'
import { ExportDialog } from '../exports/ExportDialog'
import { ExportJobNotice } from '../exports/ExportJobNotice'
import { DelegateBatchDialog } from '../review/DelegateBatchDialog'
import { MAX_BATCH } from '../review/SelectionBar'
import { groupByUnit, whyText, type UnitEscalations } from './escalationRules'
import { UnitEscalationsView } from './UnitEscalationsView'

/** Scans not approved within 24 hours, all units (canvas EA 04, 29–37; contracts 3.16, 3.17). */
export function EscalationsPage() {
  const escalations = useEscalations()
  const units = useBusinessUnits()
  const invites = useInvites()
  const [params] = useSearchParams()
  const [current, setCurrent] = useState(params.get('unit') ?? 'all')
  const [notice, setNotice] = useState<string | null>(null)
  const [delegating, setDelegating] = useState<{
    group: UnitEscalations
    scanIds: string[]
  } | null>(null)
  // Bumped after each batch so the unit view starts with nothing selected.
  const [batchesMade, setBatchesMade] = useState(0)
  const [exporting, setExporting] = useState(false)
  const [exportJob, setExportJob] = useState<ExportJob | null>(null)
  // The unit whose "Assign BU Admin" opened the invite dialog.
  const [assigning, setAssigning] = useState<string | null>(null)

  const groups = groupByUnit(escalations.items)
  const unitOf = (buId: string) => units.data?.find((u) => u.bu_id === buId)
  // The unit count covers pages not loaded yet; never show fewer than are listed.
  const countOf = (g: UnitEscalations) =>
    Math.max(unitOf(g.buId)?.escalated_count ?? 0, g.items.length)
  const total = groups.reduce((sum, g) => sum + countOf(g), 0)
  const open = groups.find((g) => g.buId === current)

  const remind = useRemind(setNotice)
  const delegate = (group: UnitEscalations, scanIds: string[]) => {
    if (scanIds.length === 0) {
      setNotice(`Every escalated scan in ${group.buName} is already in a batch.`)
      return
    }
    setDelegating({ group, scanIds: scanIds.slice(0, MAX_BATCH) })
  }

  return (
    <>
      <PageHeader
        title={open ? `Escalated scans · ${open.buName}` : 'Escalated scans'}
        subtitle={
          open
            ? `${countOf(open)} not approved within 24 hours`
            : 'Not approved within 24 hours · all units'
        }
        actions={
          <Button variant="secondary" onClick={() => setExporting(true)}>
            Export CSV
          </Button>
        }
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        {exportJob && <ExportJobNotice key={exportJob.export_id} job={exportJob} />}
        <Tabs
          label="Unit"
          look="pills"
          tabs={[
            { key: 'all', label: 'All units', count: total },
            ...groups.map((g) => ({ key: g.buId, label: g.buName, count: countOf(g) })),
          ]}
          current={open ? current : 'all'}
          onChange={setCurrent}
        />

        {escalations.isPending ? (
          <Card>Loading escalated scans…</Card>
        ) : escalations.isError ? (
          <Card>We couldn't load escalated scans. Please refresh.</Card>
        ) : open ? (
          <UnitEscalationsView
            key={`${open.buId}-${batchesMade}`}
            group={open}
            unit={unitOf(open.buId)}
            onRemind={() => remind(open.buId, unitOf(open.buId))}
            onDelegate={(scanIds) => delegate(open, scanIds)}
          />
        ) : groups.length === 0 ? (
          <Card>Nothing escalated. Every scan was decided within 24 hours.</Card>
        ) : (
          <>
            <Alert tone="info">
              A scan that isn't approved within 24 hours comes here as well as staying with its BU
              Admin. Open a unit to review its scans, or use the buttons on its card. Whoever
              decides first wins.
            </Alert>
            <div className="grid gap-3.5 lg:grid-cols-3">
              {groups.map((g) => (
                <EscalationCard
                  key={g.buId}
                  group={g}
                  count={countOf(g)}
                  unit={unitOf(g.buId)}
                  onReview={() => setCurrent(g.buId)}
                  onRemind={() => remind(g.buId, unitOf(g.buId))}
                  onAssign={() => setAssigning(g.buId)}
                  onDelegate={() =>
                    delegate(
                      g,
                      g.items.filter((e) => !e.batch_no).map((e) => e.scan_id),
                    )
                  }
                />
              ))}
            </div>
          </>
        )}
        <LoadMore {...escalations} />
      </div>

      {delegating && (
        <DelegateBatchDialog
          buId={delegating.group.buId}
          scanIds={delegating.scanIds}
          introPrefix={`${delegating.group.buName} · `}
          onClose={() => setDelegating(null)}
          onDone={(message) => {
            setDelegating(null)
            setBatchesMade((n) => n + 1)
            setNotice(message)
          }}
        />
      )}
      {assigning && (
        <InviteBuAdminDialog
          options={inviteOptions(
            units.data ?? [],
            (invites.data ?? []).filter((i) => i.status === 'pending'),
          )}
          initialUnitIds={[assigning]}
          onClose={() => setAssigning(null)}
          onSent={(email) => {
            setAssigning(null)
            setNotice(`Invite sent to ${email}. The link works for 24 hours.`)
          }}
        />
      )}
      {exporting && (
        <ExportDialog
          kind="scans"
          title="Export scans to CSV"
          scopes={[
            { key: 'all', label: 'All units', filters: {} },
            ...(open
              ? [{ key: 'unit', label: `${open.buName} only`, filters: { bu_id: open.buId } }]
              : []),
            {
              key: 'approved',
              label: 'Approved scans only',
              filters: { review_status: 'approved' },
            },
          ]}
          note="Exports of up to 1,000 rows download straight away. Bigger exports arrive as a dashboard notice and an email with a link valid for 1 hour. Every export is recorded in the audit log."
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

/** Remind the unit's BU Admin and say how it went. */
function useRemind(setNotice: (text: string) => void) {
  const remindBuAdmin = useRemindBuAdmin()
  return (buId: string, unit?: BusinessUnit) => {
    const name = unit?.bu_admin?.full_name ?? 'the BU Admin'
    remindBuAdmin.mutate(buId, {
      onSuccess: () => setNotice(`Reminder sent to ${name} by email and on the dashboard.`),
      onError: (err) =>
        setNotice(
          err instanceof ApiError && problemCode(err.problem) === 'no-bu-admin'
            ? 'This unit has no BU Admin to remind. Assign one from BU Admins.'
            : errorMessage(err),
        ),
    })
  }
}

interface EscalationCardProps {
  group: UnitEscalations
  count: number
  unit?: BusinessUnit
  onReview: () => void
  onRemind: () => void
  onAssign: () => void
  onDelegate: () => void
}

function EscalationCard({
  group,
  count,
  unit,
  onReview,
  onRemind,
  onAssign,
  onDelegate,
}: EscalationCardProps) {
  const admin = unit?.bu_admin?.full_name
  const noAdmin = group.noBuAdmin || (unit !== undefined && !admin)
  return (
    <section
      aria-label={group.buName}
      className="flex flex-col gap-3 rounded-xl border border-line bg-surface px-4.5 py-4"
    >
      <div className="flex items-start justify-between gap-2.5">
        <div className="min-w-0">
          <h2 className="text-card-title font-bold">{group.buName}</h2>
          <p className="text-small text-ink-subtle">
            {noAdmin ? 'No BU Admin' : `BU Admin ${admin ?? ''}`}
          </p>
        </div>
        <Badge tone="warning">
          {count} {count === 1 ? 'scan' : 'scans'}
        </Badge>
      </div>
      <dl className="grid grid-cols-2 gap-2.5">
        <div className="rounded-lg bg-page px-3 py-2.5">
          <dt className="text-meta text-ink-subtle">Oldest</dt>
          <dd className="text-body font-semibold text-warning">{waitedFor(group.oldest)}</dd>
        </div>
        <div className="rounded-lg bg-page px-3 py-2.5">
          <dt className="text-meta text-ink-subtle">Why</dt>
          <dd className="text-body font-semibold">
            {whyText(noAdmin ? 'no_bu_admin' : 'not_approved_24h', admin)}
          </dd>
        </div>
      </dl>
      <p className="text-small text-ink-muted">
        {noAdmin
          ? 'No BU Admin. Assign one with a magic link, or review or delegate these yourself.'
          : `${admin ?? 'The BU Admin'} also sees these. Remind them, or delegate. Whoever decides first wins.`}
      </p>
      <div className="mt-auto flex flex-wrap gap-2">
        <Button onClick={onReview}>Review</Button>
        {noAdmin ? (
          <Button variant="secondary" onClick={onAssign}>
            Assign BU Admin
          </Button>
        ) : (
          <Button variant="secondary" onClick={onRemind}>
            Remind {admin ?? 'BU Admin'}
          </Button>
        )}
        <Button variant="secondary" onClick={onDelegate}>
          Delegate to technicians
        </Button>
      </div>
    </section>
  )
}
