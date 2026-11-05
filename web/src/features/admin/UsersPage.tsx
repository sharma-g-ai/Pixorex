import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Avatar } from '../../components/Avatar'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { StatusBadge } from '../../components/StatusBadge'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Muted } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import type { RoleKey, Scope, User } from '../../data/model'
import { hoursFrom, scopeLabel, visibleCustomers } from '../../data/queries'
import { roleInfo, roles } from '../../data/roles'
import { NOW, users } from '../../data/sample'
import { cancelInvite, resendInvite, saveUser, useStore } from '../../data/store'
import { formatDate, formatDateTime } from '../../lib/format'

/** A PPG Admin manages everyone; a Customer Admin only the Customer Admins of their own customer. */
function managedBy(admin: User, user: User): boolean {
  if (admin.scope.kind === 'all') return true
  return user.scope.kind === 'customer' && user.scope.customer === admin.scope.customer
}

function InviteState({ user }: { user: User }) {
  const invite = user.invite
  if (user.status !== 'invited' || !invite) return null
  if (invite.status === 'cancelled') return <Muted>Invite cancelled</Muted>
  if (invite.status === 'expired' || invite.expiresAt <= NOW) return <Badge tone="danger">Invite expired</Badge>
  return <Muted>Invite expires {formatDate(invite.expiresAt)}</Muted>
}

/**
 * FR-22: portal users. Each is a PPG Admin (all customers) or a Customer Admin (one customer);
 * vessels sign in on their tablet, so there are no crew or vessel accounts here. New users get an e-mailed invite.
 */
export function UsersPage() {
  const { user: admin } = useViewer()
  useStore()
  const isPpg = admin.scope.kind === 'all'
  const [role, setRole] = useState<RoleKey | ''>('')
  const [status, setStatus] = useState('')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<User | 'new' | null>(null)
  const shown = users
    .filter((u) => managedBy(admin, u))
    .filter((u) => (!role || u.role === role) && (!status || u.status === status))
    .filter((u) => `${u.name} ${u.email}`.toLowerCase().includes(search.trim().toLowerCase()))

  return (
    <>
      <SectionBar
        title="Users"
        subtitle={isPpg ? 'Everyone with access to the portal' : `Customer Admins at ${scopeLabel(admin)}`}
        actions={
          <Button onClick={() => setEditing('new')}>
            <Icon name="plus" /> Invite user
          </Button>
        }
      />
      <FilterBar>
        {isPpg && (
          <SelectField
            label="Role"
            className="w-48"
            value={role}
            onChange={(e) => setRole(e.target.value as RoleKey | '')}
            options={[{ value: '', label: 'All roles' }, ...roles.map((r) => ({ value: r.key, label: r.label }))]}
          />
        )}
        <SelectField
          label="Status"
          className="w-36"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          options={[
            { value: '', label: 'All' },
            { value: 'active', label: 'Active' },
            { value: 'invited', label: 'Invited' },
            { value: 'disabled', label: 'Disabled' },
          ]}
        />
        <TextField
          label="Search"
          placeholder="Name or e-mail"
          className="w-60"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </FilterBar>
      <Card flush>
        <div className="p-4">
          <DataTable
            label="Users"
            rows={shown}
            rowKey={(u) => u.id}
            empty="No users match these filters"
            columns={[
              {
                header: 'User',
                width: 2,
                cell: (u) => (
                  <div className="flex min-w-0 items-center gap-2.5">
                    <Avatar name={u.name} />
                    <div className="min-w-0">
                      <div className="truncate font-semibold">{u.name}</div>
                      <div className="truncate text-small text-ink-muted">{u.email}</div>
                    </div>
                  </div>
                ),
              },
              {
                header: 'Role',
                width: 1.2,
                cell: (u) => (
                  <div>
                    <div>{roleInfo(u.role).label}</div>
                    <Muted>{u.title}</Muted>
                  </div>
                ),
              },
              { header: 'Scope', width: 1.4, cell: (u) => <span className="text-body-sm">{scopeLabel(u)}</span> },
              {
                header: 'Status',
                width: 1.1,
                cell: (u) => (
                  <div>
                    <StatusBadge status={u.status} />
                    <div>
                      <InviteState user={u} />
                    </div>
                  </div>
                ),
              },
              {
                header: 'Last sign-in',
                width: 1,
                cell: (u) => <Muted>{u.lastSignIn ? formatDateTime(u.lastSignIn) : 'Never'}</Muted>,
              },
              {
                header: '',
                width: 1.3,
                align: 'right',
                cell: (u) => (
                  <div className="flex flex-wrap justify-end gap-x-3">
                    {u.status === 'invited' && (
                      <Button variant="link" onClick={() => resendInvite(u.id, admin)}>
                        Resend
                      </Button>
                    )}
                    {u.status === 'invited' && u.invite?.status === 'pending' && (
                      <Button variant="danger-link" onClick={() => cancelInvite(u.id, admin)}>
                        Cancel invite
                      </Button>
                    )}
                    <Button variant="link" onClick={() => setEditing(u)}>
                      Edit
                    </Button>
                  </div>
                ),
              },
            ]}
          />
        </div>
      </Card>
      {editing && (
        <UserDialog
          user={editing === 'new' ? null : editing}
          admin={admin}
          onClose={() => setEditing(null)}
          onSave={(u) => {
            saveUser(u, admin)
            setEditing(null)
          }}
        />
      )}
    </>
  )
}

function UserDialog({
  user,
  admin,
  onClose,
  onSave,
}: {
  user: User | null
  admin: User
  onClose: () => void
  onSave: (u: User) => void
}) {
  const isPpg = admin.scope.kind === 'all'
  const ownCustomers = visibleCustomers(admin)
  const self = user?.id === admin.id

  const [name, setName] = useState(user?.name ?? '')
  const [email, setEmail] = useState(user?.email ?? '')
  const [title, setTitle] = useState(user?.title ?? '')
  const [role, setRole] = useState<RoleKey>(user?.role ?? (isPpg ? 'ppg-admin' : 'customer-admin'))
  const [status, setStatus] = useState(user?.status ?? 'invited')
  const [customer, setCustomer] = useState(
    user?.scope.kind === 'customer' ? user.scope.customer : ownCustomers.length === 1 ? (ownCustomers[0]?.id ?? '') : '',
  )
  const taken = users.some((u) => u.email.toLowerCase() === email.trim().toLowerCase() && u.id !== user?.id)

  const scope: Scope | null = role === 'ppg-admin' ? { kind: 'all' } : customer ? { kind: 'customer', customer } : null
  const ready = name.trim() && /\S+@\S+\.\S+/.test(email) && !taken && scope

  return (
    <Dialog
      title={user ? `Edit ${user.name}` : 'Invite user'}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!ready}
            onClick={() =>
              scope &&
              onSave({
                id: user?.id ?? `u-${Date.now()}`,
                name: name.trim(),
                email: email.trim().toLowerCase(),
                title: title.trim(),
                role,
                scope,
                status,
                lastSignIn: user?.lastSignIn ?? null,
                invite: user ? user.invite : { status: 'pending', sentAt: NOW, expiresAt: hoursFrom(NOW, 7 * 24) },
              })
            }
          >
            {user ? 'Save changes' : 'Send invite'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-3">
          <TextField label="Full name" value={name} onChange={(e) => setName(e.target.value)} />
          <TextField
            label="Job title (optional)"
            placeholder="e.g. Fleet Manager"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>
        <TextField
          label="Work e-mail"
          type="email"
          value={email}
          disabled={user !== null}
          onChange={(e) => setEmail(e.target.value)}
          error={taken ? 'Someone already uses this e-mail' : undefined}
        />
        {isPpg && (
          <SelectField
            label="Role"
            value={role}
            disabled={self}
            onChange={(e) => setRole(e.target.value as RoleKey)}
            options={roles.map((r) => ({ value: r.key, label: `${r.label} — ${r.heldBy}` }))}
          />
        )}
        {role === 'customer-admin' ? (
          <SelectField
            label="Customer"
            value={customer}
            onChange={(e) => setCustomer(e.target.value)}
            disabled={ownCustomers.length === 1}
            options={[
              { value: '', label: 'Choose a customer…' },
              ...ownCustomers.map((c) => ({ value: c.id, label: `${c.name} · ${c.customerCode}` })),
            ]}
          />
        ) : (
          <Muted>A PPG Admin sees and manages every customer and vessel.</Muted>
        )}
        {user && !self && user.status !== 'invited' && (
          <SelectField
            label="Status"
            value={status}
            onChange={(e) => setStatus(e.target.value as User['status'])}
            options={[
              { value: 'active', label: 'Active' },
              { value: 'disabled', label: 'Disabled — cannot sign in' },
            ]}
          />
        )}
        {!user && <p className="text-small">They get an e-mail to set a password. The invite lasts 7 days (to confirm).</p>}
      </div>
    </Dialog>
  )
}
