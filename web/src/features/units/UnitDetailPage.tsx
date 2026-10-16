import { Link, useParams } from 'react-router'
import { useBuAdmins } from '../../api/buAdmins'
import { useBusinessUnits, type BusinessUnit } from '../../api/businessUnits'
import { useEscalations } from '../../api/escalations'
import { Badge } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { Person } from '../../components/Person'
import { StatTile } from '../../components/StatTile'
import { RecentActivityCard } from '../auditLog/RecentActivityCard'
import { waitingStatus } from '../review/reviewRules'

/** One unit seen by the EA: its BU Admin, numbers, escalations and activity (canvas EA 25–28, 67). */
export function UnitDetailPage() {
  const { buId = '' } = useParams()
  const units = useBusinessUnits()
  const unit = units.data?.find((u) => u.bu_id === buId)

  if (units.isPending) return <Card className="m-8">Loading the unit…</Card>
  if (!unit) return <Card className="m-8">This unit doesn't exist or was removed.</Card>
  return <UnitDetail unit={unit} />
}

function UnitDetail({ unit }: { unit: BusinessUnit }) {
  const q = `?unit=${unit.bu_id}`
  const escalated = unit.escalated_count ?? 0

  return (
    <>
      <PageHeader
        title={unit.name}
        subtitle={`Overview › Unit · ${unit.facility_name}`}
        actions={
          <Link to="/overview" className={buttonClasses('link')}>
            ← Back to overview
          </Link>
        }
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8">
        <AdminCard unit={unit} />
        <div className="grid grid-cols-2 gap-3.5 lg:grid-cols-3">
          <StatTile value={unit.waiting_count ?? 0} label="waiting review" to={`/scans${q}`} />
          <StatTile
            value={escalated}
            label="over 24 h · escalated to you"
            to={escalated ? `/escalations${q}` : undefined}
            tone={escalated ? 'warning' : 'default'}
          />
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

function AdminCard({ unit }: { unit: BusinessUnit }) {
  const admins = useBuAdmins()
  const admin = admins.data?.find((a) => a.user_id === unit.bu_admin?.user_id)
  const others = admin?.units.filter((u) => u.bu_id !== unit.bu_id).map((u) => u.name) ?? []

  return (
    <Card
      title="BU Admin"
      action={
        <Link to="/bu-admins" className={buttonClasses('secondary')}>
          Manage
        </Link>
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
        <p className="text-body text-danger-strong">
          <b>No BU Admin.</b> This unit's scans that wait over 24 hours come to you.
        </p>
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
