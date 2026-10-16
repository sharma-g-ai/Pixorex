import { useState } from 'react'
import { Link } from 'react-router'
import { useBusinessUnits } from '../../api/businessUnits'
import { useInvites } from '../../api/invites'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { InviteBuAdminDialog } from '../buAdmins/InviteBuAdminDialog'
import { inviteOptions } from '../buAdmins/unitOptions'
import { inviteStatus } from '../invites/inviteStatus'
import { useInviteActions, type Notice } from '../invites/useInviteActions'
import { vacantUnits, type VacantUnit } from './vacantUnits'

/** "Units without a BU Admin" from the Overview's "Needs you" (canvas EA, contracts 1.9–1.12). */
export function VacantUnitsPage() {
  const units = useBusinessUnits()
  const invites = useInvites()
  const [notice, setNotice] = useState<Notice | null>(null)
  const [inviting, setInviting] = useState<string | null>(null)
  const actions = useInviteActions(setNotice)

  const rows = vacantUnits(units.data ?? [], invites.data ?? [])
  const pending = (invites.data ?? []).filter((i) => i.status === 'pending')

  return (
    <>
      <PageHeader
        title="Units without a BU Admin"
        subtitle="Overview › Needs you"
        actions={
          <Link to="/overview" className={buttonClasses('link')}>
            ← Back to overview
          </Link>
        }
      />
      <div className="flex grow flex-col gap-4 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone={notice.error ? 'danger' : 'info'} role="status">
            {notice.text}
          </Alert>
        )}
        <Alert tone="info">
          Each unit needs one BU Admin. Until someone accepts, the unit's scans that wait over 24
          hours come to you.
        </Alert>
        {units.isPending || invites.isPending ? (
          <Card>Loading units…</Card>
        ) : units.isError || invites.isError ? (
          <Card>We couldn't load the units. Please refresh.</Card>
        ) : rows.length === 0 ? (
          <Card>Every unit has a BU Admin.</Card>
        ) : (
          rows.map((row) => (
            <VacantUnitCard
              key={row.unit.bu_id}
              row={row}
              busy={actions.busy}
              onResend={() => row.invite && actions.resend(row.invite)}
              onInvite={() => setInviting(row.unit.bu_id)}
            />
          ))
        )}
      </div>
      {inviting && (
        <InviteBuAdminDialog
          options={inviteOptions(units.data ?? [], pending)}
          initialUnitIds={[inviting]}
          onClose={() => setInviting(null)}
          onSent={(email) => {
            setInviting(null)
            setNotice({ text: `Invite sent to ${email}. The link works for 24 hours.` })
          }}
        />
      )}
    </>
  )
}

interface VacantUnitCardProps {
  row: VacantUnit
  busy: boolean
  onResend: () => void
  onInvite: () => void
}

function VacantUnitCard({ row, busy, onResend, onInvite }: VacantUnitCardProps) {
  const { unit, invite } = row
  const status = invite ? inviteStatus(invite) : null
  return (
    <section
      aria-label={unit.name}
      className="flex flex-col gap-3.5 rounded-xl border border-line bg-surface px-5 py-4.5"
    >
      <div>
        <h2 className="text-unit-title font-bold">{unit.name}</h2>
        <p className="text-small text-ink-subtle">{unit.facility_name} · no BU Admin</p>
      </div>
      <dl className="grid grid-cols-2 gap-2.5 lg:grid-cols-4">
        <Fact label="Invite" value={invite?.email ?? '—'} />
        <Fact
          label="Invite status"
          value={status ? <Badge tone={status.tone}>{status.label}</Badge> : '—'}
        />
        <Fact label="Scans waiting review" value={String(unit.waiting_count ?? 0)} />
        <Fact label="Escalated to you" value={String(unit.escalated_count ?? 0)} />
      </dl>
      <div className="flex flex-wrap items-center gap-2">
        <p className="grow text-small text-ink-muted">
          If the invite expires, you'll see it here and under BU Admins → Pending invites.
        </p>
        <Button variant="secondary" onClick={onInvite}>
          Invite someone else
        </Button>
        {invite && (
          <Button disabled={busy} onClick={onResend}>
            Resend invite
          </Button>
        )}
      </div>
    </section>
  )
}

function Fact({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-lg bg-page px-3 py-2.5">
      <dt className="text-meta text-ink-subtle">{label}</dt>
      <dd className="text-body font-semibold">{value}</dd>
    </div>
  )
}
