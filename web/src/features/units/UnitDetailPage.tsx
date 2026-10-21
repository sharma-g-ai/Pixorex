import { useState } from 'react'
import { Link, useParams } from 'react-router'
import { useBuAdmins } from '../../api/buAdmins'
import { useBusinessUnits, type BusinessUnit } from '../../api/businessUnits'
import { useEscalations } from '../../api/escalations'
import { useInvites } from '../../api/invites'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { Person } from '../../components/Person'
import { StatTile } from '../../components/StatTile'
import { RecentActivityCard } from '../auditLog/RecentActivityCard'
import { EditUnitsDialog } from '../buAdmins/EditUnitsDialog'
import { InviteBuAdminDialog } from '../buAdmins/InviteBuAdminDialog'
import { RemoveBuAdminDialog } from '../buAdmins/RemoveBuAdminDialog'
import { editOptions, inviteOptions, removeOptions } from '../buAdmins/unitOptions'
import { waitingStatus } from '../review/reviewRules'
import { shortDate, waitedFor } from '../../lib/time'
import { technicianCount } from './unitSummary'
import { latestAdminInvite } from './vacantUnits'

/** One unit seen by the EA: its BU Admin, numbers, escalations and activity (canvas EA 25–28, 67). */
export function UnitDetailPage() {
  const { buId = '' } = useParams()
  const units = useBusinessUnits()
  const unit = units.data?.find((u) => u.bu_id === buId)

  if (units.isPending) return <Card className="m-8">Loading the unit…</Card>
  if (!unit) return <Card className="m-8">This unit doesn't exist or was removed.</Card>
  return <UnitDetail unit={unit} units={units.data ?? []} />
}

function UnitDetail({ unit, units }: { unit: BusinessUnit; units: BusinessUnit[] }) {
  const q = `?unit=${unit.bu_id}`
  const escalated = unit.escalated_count ?? 0
  const [notice, setNotice] = useState<string | null>(null)

  return (
    <>
      <PageHeader
        title={unit.name}
        subtitle={`Overview › Unit · ${technicianCount(unit)}`}
        actions={
          <Link to="/overview" className={buttonClasses('link')}>
            ← Back to overview
          </Link>
        }
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {notice && (
          <Alert tone="info" role="status">
            {notice}
          </Alert>
        )}
        <AdminCard unit={unit} units={units} onDone={setNotice} />
        <div className="grid grid-cols-2 gap-3.5 lg:grid-cols-5">
          <StatTile
            value={unit.technician_count ?? 0}
            label={unit.technician_count === 1 ? 'technician' : 'technicians'}
          />
          <StatTile value={unit.waiting_count ?? 0} label="waiting review" to={`/scans${q}`} />
          <StatTile
            value={escalated}
            label="over 24 h · escalated to you"
            to={escalated ? `/escalations${q}` : undefined}
            tone={escalated ? 'warning' : 'default'}
          />
          <StatTile value={unit.scans_this_month ?? 0} label="scans this month" to={`/scans${q}`} />
          <StatTile value={unit.delegated_count ?? 0} label="in delegated batches" />
        </div>
        <div className="grid gap-5 lg:grid-cols-2">
          <EscalatedCard unit={unit} count={escalated} />
          <Card title="Manage this unit">
            <ul className="flex flex-col divide-y divide-line-soft">
              {[
                { to: `/scans${q}`, title: 'Scans', text: 'All scans from this unit' },
                { to: `/locations${q}`, title: 'Locations', text: 'Buildings, shops and bins' },
                { to: '/bu-admins', title: 'BU Admin', text: 'Invite, change or remove' },
                { to: `/audit-log${q}`, title: 'Audit log', text: 'Everything done in this unit' },
              ].map((link) => (
                <li key={link.title}>
                  <Link
                    to={link.to}
                    className="flex items-center justify-between py-3 hover:text-brand-navy"
                  >
                    <span>
                      <span className="block text-body font-semibold">{link.title}</span>
                      <span className="text-small text-ink-muted">{link.text}</span>
                    </span>
                    <span aria-hidden="true">→</span>
                  </Link>
                </li>
              ))}
            </ul>
          </Card>
        </div>
        <RecentActivityCard
          buId={unit.bu_id}
          title="Recent activity"
          hide={['Unit']}
          action={
            <Link to={`/audit-log?unit=${unit.bu_id}`} className={buttonClasses('link')}>
              Open audit log →
            </Link>
          }
        />
      </div>
    </>
  )
}

interface AdminCardProps {
  unit: BusinessUnit
  units: BusinessUnit[]
  onDone: (text: string) => void
}

/**
 * The unit's BU Admin, with "Edit units" and "Remove" as on the canvas (EA 25; 1.16, 1.17).
 * No BU Admin: "Assign BU Admin" invites one right here (contract 1.8).
 */
function AdminCard({ unit, units, onDone }: AdminCardProps) {
  const admins = useBuAdmins()
  const invites = useInvites()
  const [open, setOpen] = useState<'invite' | 'edit' | 'remove' | null>(null)
  const admin = admins.data?.find((a) => a.user_id === unit.bu_admin?.user_id)
  const others = admin?.units.filter((u) => u.bu_id !== unit.bu_id).map((u) => u.name) ?? []
  const buAdminInvites = (invites.data ?? []).filter((i) => i.role === 'bu_admin')
  const invite = latestAdminInvite(buAdminInvites, unit.bu_id)
  const pending = !unit.bu_admin?.user_id && invite?.status === 'pending' ? invite : null
  const done = (text: string) => {
    setOpen(null)
    onDone(text)
  }

  return (
    <Card
      title="BU Admin"
      action={
        admin ? (
          <div className="flex gap-3.5">
            <button type="button" className={buttonClasses('link')} onClick={() => setOpen('edit')}>
              Edit units
            </button>
            <button
              type="button"
              className={buttonClasses('danger-link')}
              onClick={() => setOpen('remove')}
            >
              Remove
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-3">
            {pending && (
              <Badge tone="warning">{`Invite pending · ${waitedFor(pending.created_at)}`}</Badge>
            )}
            <Button variant="secondary" onClick={() => setOpen('invite')}>
              Assign BU Admin
            </Button>
          </div>
        )
      }
    >
      {unit.bu_admin?.full_name ? (
        <div className="flex items-center gap-3">
          <Person
            name={unit.bu_admin.full_name}
            detail={[admin?.email, others.length ? `also runs ${others.join(', ')}` : null]
              .filter(Boolean)
              .join(' · ')}
          />
          {admin && (
            <Badge tone={admin.status === 'active' ? 'success' : 'neutral'}>
              {admin.status === 'active' ? 'Active' : 'Not activated yet'}
            </Badge>
          )}
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <div>
            <p className="text-body font-bold text-danger-strong">No BU Admin</p>
            {unit.vacant_since && (
              <p className="text-small text-ink-subtle">
                {`Since ${shortDate(unit.vacant_since)}`}
                {unit.previous_bu_admin?.full_name &&
                  ` · ${unit.previous_bu_admin.full_name} removed`}
              </p>
            )}
          </div>
          <Alert tone="info">
            {pending
              ? `Invite sent to ${pending.email}. Until someone accepts, ${unit.name}'s scans that wait over 24 hours come to you.`
              : "This unit's scans that wait over 24 hours come to you."}
          </Alert>
        </div>
      )}
      {open === 'invite' && (
        <InviteBuAdminDialog
          options={inviteOptions(units, buAdminInvites)}
          initialUnitIds={[unit.bu_id]}
          onClose={() => setOpen(null)}
          onSent={(email) => done(`Invite sent to ${email}. The link works for 24 hours.`)}
        />
      )}
      {admin && open === 'edit' && (
        <EditUnitsDialog
          admin={admin}
          options={editOptions(admin, units, buAdminInvites)}
          onClose={() => setOpen(null)}
          onSaved={(name) => done(`Units of ${name} were updated.`)}
          onRemove={() => setOpen('remove')}
        />
      )}
      {admin && open === 'remove' && (
        <RemoveBuAdminDialog
          admin={admin}
          options={removeOptions(admin, units)}
          onClose={() => setOpen(null)}
          onRemoved={done}
        />
      )}
    </Card>
  )
}

function EscalatedCard({ unit, count: unitCount }: { unit: BusinessUnit; count: number }) {
  const escalations = useEscalations(unit.bu_id)
  const first = escalations.items.slice(0, 3)
  const count = Math.max(unitCount, escalations.items.length)
  return (
    <Card
      title="Escalated to you"
      action={
        <Badge
          tone={count ? 'warning' : 'neutral'}
        >{`${count} ${count === 1 ? 'scan' : 'scans'}`}</Badge>
      }
    >
      {first.length === 0 ? (
        <p className="text-body text-ink-muted">
          Nothing escalated — every scan here was decided within 24 hours.
        </p>
      ) : (
        <>
          <ul className="flex flex-col divide-y divide-line-soft">
            {first.map((e) => {
              const status = waitingStatus(e.escalated_at)
              return (
                <li key={e.escalation_id} className="flex items-center gap-3 py-2.5">
                  <Link to={`/escalations/${e.scan_id}`} className="min-w-0 grow hover:underline">
                    <span className="block truncate font-semibold">{e.equipment_type_name}</span>
                    <span className="font-mono text-meta text-ink-subtle">{e.record_no}</span>
                  </Link>
                  <span className="text-small text-ink-muted">{e.captured_by_name}</span>
                  <Badge tone={status.tone}>{status.label}</Badge>
                </li>
              )
            })}
          </ul>
          <Link
            to={`/escalations?unit=${unit.bu_id}`}
            className={`${buttonClasses('secondary')} mt-3`}
          >
            Open all {count} escalated scans
          </Link>
        </>
      )}
    </Card>
  )
}
