import { useState } from 'react'
import { useInvites } from '../../api/invites'
import { useTechnicians, type Technician } from '../../api/technicians'
import { adminUnits } from '../../app/access'
import { useDashboard } from '../../app/DashboardContext'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { InvitesTable } from '../invites/InvitesTable'
import { useInviteActions, type Notice } from '../invites/useInviteActions'
import { InviteTechnicianDialog } from './InviteTechnicianDialog'
import { RemoveTechnicianDialog } from './RemoveTechnicianDialog'
import { splitTechnicians, technicianStatus } from './staffStatus'
import { TechniciansTable } from './TechniciansTable'

type Open =
  { dialog: 'invite'; email?: string } | { dialog: 'remove'; technician: Technician } | null

/** BU-01 Technicians: staff and invites of the current unit (canvas BU 25–27). */
export function TechniciansPage() {
  const { me, unit } = useDashboard()
  if (!unit?.bu_id) return null
  return <TechniciansOfUnit buId={unit.bu_id} unitName={unit.name ?? ''} units={adminUnits(me)} />
}

function TechniciansOfUnit({
  buId,
  unitName,
  units,
}: {
  buId: string
  unitName: string
  units: ReturnType<typeof adminUnits>
}) {
  const technicians = useTechnicians(buId)
  const invites = useInvites(buId)
  const [open, setOpen] = useState<Open>(null)
  const [notice, setNotice] = useState<Notice | null>(null)
  const inviteActions = useInviteActions(setNotice)

  const { current, removed } = splitTechnicians(technicians.data ?? [])

  return (
    <>
      <PageHeader
        title="Technicians"
        subtitle={unitName}
        actions={<Button onClick={() => setOpen({ dialog: 'invite' })}>+ Invite technician</Button>}
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone={notice.error ? 'danger' : 'info'} role={notice.error ? 'alert' : 'status'}>
            {notice.text}
          </Alert>
        )}

        <Card
          title="Technicians"
          action={
            <span className="text-small text-ink-muted">
              Field technicians use the mobile app only
            </span>
          }
        >
          {technicians.isPending ? (
            <p className="text-body text-ink-muted">Loading technicians…</p>
          ) : technicians.isError ? (
            <p className="text-body text-ink-muted">
              We couldn't load the technicians. Please refresh.
            </p>
          ) : (
            <TechniciansTable
              technicians={current}
              onRemove={(t) => setOpen({ dialog: 'remove', technician: t })}
            />
          )}
        </Card>

        <Card
          title="Invites and removed accounts"
          action={
            <span className="text-small text-ink-muted">
              Invite links are valid 24 hours · removed technicians need a new invite
            </span>
          }
        >
          <InvitesTable
            label="Invites and removed accounts"
            invites={invites.data ?? []}
            removed={removed.map((t) => ({
              id: t.user_id,
              email: t.email,
              detail: `Removed from ${unitName}`,
              status: technicianStatus(t),
            }))}
            busy={inviteActions.busy}
            onResend={inviteActions.resend}
            onCancel={inviteActions.cancel}
            onReinvite={(email) => setOpen({ dialog: 'invite', email })}
          />
        </Card>
      </div>

      {open?.dialog === 'invite' && (
        <InviteTechnicianDialog
          units={units}
          currentBuId={buId}
          email={open.email}
          onClose={() => setOpen(null)}
          onSent={(email) => {
            setOpen(null)
            setNotice({ text: `Invite sent to ${email}. The link is valid for 24 hours.` })
          }}
        />
      )}
      {open?.dialog === 'remove' && (
        <RemoveTechnicianDialog
          technician={open.technician}
          buId={buId}
          unitName={unitName}
          onClose={() => setOpen(null)}
          onRemoved={(name) => {
            setOpen(null)
            setNotice({ text: `${name} was removed from ${unitName}.` })
          }}
        />
      )}
    </>
  )
}
