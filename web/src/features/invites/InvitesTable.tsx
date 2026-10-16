import type { Invite } from '../../api/invites'
import { Badge, type BadgeStatus } from '../../components/Badge'
import { buttonClasses } from '../../components/buttonClasses'
import { DataTable, type Column } from '../../components/DataTable'
import { Person } from '../../components/Person'
import { UnitBadges } from '../../components/UnitBadges'
import { timeAgo } from '../../lib/time'
import { inviteExpired, inviteStatus } from './inviteStatus'

/** Someone removed from the unit, listed with the invites so they can be invited again. */
export interface RemovedAccount {
  id: string
  email: string
  detail: string
  status: BadgeStatus
}

type Row =
  | { kind: 'invite'; invite: Invite; status: BadgeStatus }
  | { kind: 'removed'; account: RemovedAccount; status: BadgeStatus }

interface InvitesTableProps {
  label: string
  invites: Invite[]
  removed?: RemovedAccount[]
  /** Show the units each invite is for (EA view across units). */
  showUnits?: boolean
  busy: boolean
  onResend: (invite: Invite) => void
  onCancel: (invite: Invite) => void
  onReinvite?: (email: string) => void
}

/** Open invites (pending, expired) and removed accounts, with their actions. */
export function InvitesTable({ removed = [], showUnits = false, ...props }: InvitesTableProps) {
  const rows: Row[] = [
    ...props.invites.flatMap((invite): Row[] => {
      const status = inviteStatus(invite)
      return status ? [{ kind: 'invite', invite, status }] : []
    }),
    ...removed.map((account): Row => ({ kind: 'removed', account, status: account.status })),
  ]

  const columns: Column<Row>[] = [
    {
      header: 'Person',
      width: 2,
      cell: (row) =>
        row.kind === 'invite' ? (
          <Person
            name={row.invite.email}
            detail={`Invited by ${row.invite.invited_by_name} · ${timeAgo(row.invite.created_at)}`}
          />
        ) : (
          <Person name={row.account.email} detail={row.account.detail} />
        ),
    },
    ...(showUnits
      ? [
          {
            header: 'Units',
            width: 1.4,
            cell: (row: Row) =>
              row.kind === 'invite' ? (
                <UnitBadges names={row.invite.units.map((u) => u.name)} />
              ) : null,
          },
        ]
      : []),
    {
      header: 'Status',
      width: 1.4,
      cell: (row) => <Badge tone={row.status.tone}>{row.status.label}</Badge>,
    },
    {
      header: 'Actions',
      width: 2,
      align: 'right',
      cell: (row) => <RowActions row={row} {...props} />,
    },
  ]

  return (
    <DataTable
      label={props.label}
      columns={columns}
      rows={rows}
      rowKey={(row) => (row.kind === 'invite' ? row.invite.invite_id : row.account.id)}
      empty="No open invites."
    />
  )
}

function RowActions({
  row,
  busy,
  onResend,
  onCancel,
  onReinvite,
}: { row: Row } & Omit<InvitesTableProps, 'label' | 'invites'>) {
  if (row.kind === 'removed') {
    return onReinvite ? (
      <button
        type="button"
        className={buttonClasses('link')}
        onClick={() => onReinvite(row.account.email)}
      >
        Send new invite
      </button>
    ) : null
  }
  const expired = inviteExpired(row.invite)
  return (
    <div className="flex justify-end gap-3.5">
      <button
        type="button"
        disabled={busy}
        className={buttonClasses('link')}
        aria-label={`Resend invite to ${row.invite.email}`}
        onClick={() => onResend(row.invite)}
      >
        Resend
      </button>
      <button
        type="button"
        disabled={busy}
        className={buttonClasses('danger-link')}
        aria-label={`${expired ? 'Remove' : 'Cancel'} invite to ${row.invite.email}`}
        onClick={() => onCancel(row.invite)}
      >
        {expired ? 'Remove' : 'Cancel invite'}
      </button>
    </div>
  )
}
