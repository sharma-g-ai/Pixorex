import { useState } from 'react'
import { useBuAdmins, type BuAdmin } from '../../api/buAdmins'
import { useBusinessUnits } from '../../api/businessUnits'
import { useInvites } from '../../api/invites'
import { Alert } from '../../components/Alert'
import { Button } from '../../components/Button'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { InvitesTable } from '../invites/InvitesTable'
import { useInviteActions, type Notice } from '../invites/useInviteActions'
import { BuAdminsTable } from './BuAdminsTable'
import { EditUnitsDialog } from './EditUnitsDialog'
import { InviteBuAdminDialog } from './InviteBuAdminDialog'
import { RemoveBuAdminDialog } from './RemoveBuAdminDialog'
import { editOptions, inviteOptions, removeOptions } from './unitOptions'

type Open =
  | { dialog: 'invite' }
  | { dialog: 'edit'; admin: BuAdmin }
  | { dialog: 'remove'; admin: BuAdmin }
  | null

/** EA-01 BU Admins: who runs each unit, and pending BU Admin invites (canvas EA 13–18). */
export function BuAdminsPage() {
  const admins = useBuAdmins()
  const units = useBusinessUnits()
  const invites = useInvites()
  const [open, setOpen] = useState<Open>(null)
  const [notice, setNotice] = useState<Notice | null>(null)
  const inviteActions = useInviteActions(setNotice)

  const unitList = units.data ?? []
  const buAdminInvites = (invites.data ?? []).filter((i) => i.role === 'bu_admin')
  const done = (text: string) => {
    setOpen(null)
    setNotice({ text })
  }

  return (
    <>
      <PageHeader
        title="BU Admins"
        subtitle="Who runs each business unit"
        actions={<Button onClick={() => setOpen({ dialog: 'invite' })}>+ Invite BU Admin</Button>}
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8">
        {notice && (
          <Alert tone={notice.error ? 'danger' : 'info'} role={notice.error ? 'alert' : 'status'}>
            {notice.text}
          </Alert>
        )}

        <Card
          title="BU Admins"
          action={
            <span className="text-small text-ink-muted">
              Each unit has exactly one BU Admin · one BU Admin can run several units
            </span>
          }
        >
          {admins.isPending ? (
            <p className="text-body text-ink-muted">Loading BU Admins…</p>
          ) : admins.isError ? (
            <p className="text-body text-ink-muted">
              We couldn't load the BU Admins. Please refresh.
            </p>
          ) : (
            <BuAdminsTable
              admins={admins.data}
              onEdit={(admin) => setOpen({ dialog: 'edit', admin })}
              onRemove={(admin) => setOpen({ dialog: 'remove', admin })}
            />
          )}
        </Card>

        <Card
          title="Pending invites"
          action={<span className="text-small text-ink-muted">Magic links are valid 24 hours</span>}
        >
          <InvitesTable
            label="Pending BU Admin invites"
            invites={buAdminInvites}
            showUnits
            busy={inviteActions.busy}
            onResend={inviteActions.resend}
            onCancel={inviteActions.cancel}
          />
        </Card>

        <Alert tone="info">
          Technicians are invited and managed by each unit's BU Admin, from their own Technicians
          page.
        </Alert>
      </div>

      {open?.dialog === 'invite' && (
        <InviteBuAdminDialog
          options={inviteOptions(unitList, buAdminInvites)}
          onClose={() => setOpen(null)}
          onSent={(email) => done(`Invite sent to ${email}. The link is valid for 24 hours.`)}
        />
      )}
      {open?.dialog === 'edit' && (
        <EditUnitsDialog
          admin={open.admin}
          options={editOptions(open.admin, unitList, buAdminInvites)}
          onClose={() => setOpen(null)}
          onSaved={(name) => done(`Units of ${name} were updated.`)}
          onRemove={() => setOpen({ dialog: 'remove', admin: open.admin })}
        />
      )}
      {open?.dialog === 'remove' && (
        <RemoveBuAdminDialog
          admin={open.admin}
          options={removeOptions(open.admin, unitList)}
          onClose={() => setOpen(null)}
          onRemoved={done}
        />
      )}
    </>
  )
}
