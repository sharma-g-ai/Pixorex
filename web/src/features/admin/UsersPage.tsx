import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Avatar } from '../../components/Avatar'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Muted } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import type { RegionCode, RoleKey, Scope, User } from '../../data/model'
import { scopeLabel, visibleCustomers, visibleVessels } from '../../data/queries'
import { roleInfo, roles } from '../../data/roles'
import { customers, regions, users as sampleUsers, vessels } from '../../data/sample'
import { formatDateTime } from '../../lib/format'

const statusLook: Record<
  User['status'],
  { label: string; tone: 'success' | 'warning' | 'neutral' }
> = {
  active: { label: 'Active', tone: 'success' },
  invited: { label: 'Invited', tone: 'warning' },
  disabled: { label: 'Disabled', tone: 'neutral' },
}

/** Users in the admin's own scope: everyone for PPG, own customer for a Customer Administrator. */
function managedBy(admin: User, user: User): boolean {
  if (admin.role === 'ppg-admin') return true
  const custs = new Set(visibleCustomers(admin).map((c) => c.id))
  if (user.scope.kind === 'customer') return custs.has(user.scope.customer)
  if (user.scope.kind === 'vessel') {
    const id = user.scope.vessel
    return custs.has(vessels.find((v) => v.id === id)?.customer ?? '')
  }
  return false
}

/** FR-22: users, each tied to a vessel, a customer or PPG, with a role (FR-23) and scope (FR-24). */
export function UsersPage() {
  const { user: admin } = useViewer()
  const [rows, setRows] = useState(sampleUsers)
  const [role, setRole] = useState<RoleKey | ''>('')
  const [status, setStatus] = useState('')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<User | 'new' | null>(null)
  const assignable = admin.role === 'ppg-admin' ? roles : roles.filter((r) => r.level !== 'PPG')
  const shown = rows
    .filter((u) => managedBy(admin, u))
    .filter((u) => (!role || u.role === role) && (!status || u.status === status))
    .filter((u) => `${u.name} ${u.email}`.toLowerCase().includes(search.trim().toLowerCase()))

  return (
    <>
      <SectionBar
        title="Users"
        subtitle={
          admin.role === 'ppg-admin'
            ? 'Everyone with access to Sea Stock'
            : `Users at ${scopeLabel(admin)}`
        }
        actions={
          <Button onClick={() => setEditing('new')}>
            <Icon name="plus" /> Add user
          </Button>
        }
      />
      <>
        <FilterBar>
          <SelectField
            label="Role"
            className="w-52"
            value={role}
            onChange={(e) => setRole(e.target.value as RoleKey | '')}
            options={[
              { value: '', label: 'All roles' },
              ...assignable.map((r) => ({ value: r.key, label: r.label })),
            ]}
          />
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
                  width: 1.3,
                  cell: (u) => (
                    <div>
                      <div>{roleInfo(u.role).label}</div>
                      <Muted>{u.title}</Muted>
                    </div>
                  ),
                },
                { header: 'Level', width: 0.7, cell: (u) => roleInfo(u.role).level },
                {
                  header: 'Scope',
                  width: 1.6,
                  cell: (u) => <span className="text-body-sm">{scopeLabel(u)}</span>,
                },
                {
                  header: 'Status',
                  width: 0.7,
                  cell: (u) => (
                    <Badge tone={statusLook[u.status].tone}>{statusLook[u.status].label}</Badge>
                  ),
                },
                {
                  header: 'Last sign-in',
                  width: 1,
                  cell: (u) => (
                    <Muted>{u.lastSignIn ? formatDateTime(u.lastSignIn) : 'Never'}</Muted>
                  ),
                },
                {
                  header: '',
                  width: 0.4,
                  align: 'right',
                  cell: (u) => (
                    <Button variant="link" onClick={() => setEditing(u)}>
                      Edit
                    </Button>
                  ),
                },
              ]}
            />
          </div>
        </Card>
      </>
      {editing && (
        <UserDialog
          user={editing === 'new' ? null : editing}
          admin={admin}
          onClose={() => setEditing(null)}
          onSave={(u) => {
            setRows((all) =>
              all.some((x) => x.id === u.id)
                ? all.map((x) => (x.id === u.id ? u : x))
                : [...all, u],
            )
            setEditing(null)
          }}
        />
      )}
    </>
  )
}

function Checks<T extends string>({
  label,
  options,
  value,
  onChange,
}: {
  label: string
  options: { value: T; label: string }[]
  value: T[]
  onChange: (v: T[]) => void
}) {
  return (
    <fieldset>
      <legend className="mb-1.5 text-small font-semibold text-ink-muted">{label}</legend>
      <div className="flex flex-col gap-1.5 rounded-lg border border-line p-3">
        {options.map((o) => (
          <label key={o.value} className="flex items-center gap-2 text-body text-ink">
            <input
              type="checkbox"
              className="size-4 accent-brand"
              checked={value.includes(o.value)}
              onChange={(e) =>
                onChange(
                  e.target.checked ? [...value, o.value] : value.filter((x) => x !== o.value),
                )
              }
            />
            {o.label}
          </label>
        ))}
      </div>
    </fieldset>
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
  const isPpgAdmin = admin.role === 'ppg-admin'
  const assignable = isPpgAdmin ? roles : roles.filter((r) => r.level !== 'PPG')
  const ownCustomers = isPpgAdmin ? customers : visibleCustomers(admin)
  const ownVessels = isPpgAdmin ? vessels : visibleVessels(admin)

  const [name, setName] = useState(user?.name ?? '')
  const [email, setEmail] = useState(user?.email ?? '')
  const [title, setTitle] = useState(user?.title ?? '')
  const [role, setRole] = useState<RoleKey | ''>(user?.role ?? '')
  const [status, setStatus] = useState(user?.status ?? 'invited')
  const [ppgScope, setPpgScope] = useState<'regions' | 'customers'>(
    user?.scope.kind === 'customers' ? 'customers' : 'regions',
  )
  const [scopeRegions, setScopeRegions] = useState<RegionCode[]>(
    user?.scope.kind === 'regions' ? user.scope.regions : [],
  )
  const [scopeCustomers, setScopeCustomers] = useState<string[]>(
    user?.scope.kind === 'customers' ? user.scope.customers : [],
  )
  const [customer, setCustomer] = useState(
    user?.scope.kind === 'customer'
      ? user.scope.customer
      : ownCustomers.length === 1
        ? (ownCustomers[0]?.id ?? '')
        : '',
  )
  const [vessel, setVessel] = useState(user?.scope.kind === 'vessel' ? user.scope.vessel : '')

  const level = role ? roleInfo(role).level : null
  let scope: Scope | null = null
  if (role === 'ppg-admin') scope = { kind: 'all' }
  else if (role === 'ppg-user')
    scope =
      ppgScope === 'regions'
        ? scopeRegions.length
          ? { kind: 'regions', regions: scopeRegions }
          : null
        : scopeCustomers.length
          ? { kind: 'customers', customers: scopeCustomers }
          : null
  else if (level === 'Customer' && customer) scope = { kind: 'customer', customer }
  else if (level === 'Vessel' && vessel) scope = { kind: 'vessel', vessel }
  const ready = name.trim() && /\S+@\S+\.\S+/.test(email) && role && scope

  return (
    <Dialog
      title={user ? `Edit ${user.name}` : 'Add user'}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!ready}
            onClick={() =>
              role &&
              scope &&
              onSave({
                id: user?.id ?? `u-${Date.now()}`,
                name: name.trim(),
                email: email.trim(),
                title: title.trim(),
                role,
                scope,
                status,
                lastSignIn: user?.lastSignIn ?? null,
              })
            }
          >
            {user ? 'Save changes' : 'Add and send invite'}
          </Button>
        </>
      }
    >
      <div className="flex max-h-[60vh] flex-col gap-4 overflow-y-auto pr-1">
        <div className="grid grid-cols-2 gap-3">
          <TextField label="Full name" value={name} onChange={(e) => setName(e.target.value)} />
          <TextField
            label="Job title"
            placeholder="e.g. Chief Officer"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>
        <TextField
          label="Work e-mail"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <SelectField
          label="Role"
          value={role}
          onChange={(e) => setRole(e.target.value as RoleKey | '')}
          options={[
            { value: '', label: 'Choose a role…' },
            ...assignable.map((r) => ({ value: r.key, label: `${r.label} — ${r.heldBy}` })),
          ]}
        />

        {role === 'ppg-admin' && (
          <Muted>PPG Administrators see all regions, customers and vessels.</Muted>
        )}
        {role === 'ppg-user' && (
          <>
            <SelectField
              label="Scope"
              value={ppgScope}
              onChange={(e) => setPpgScope(e.target.value as 'regions' | 'customers')}
              options={[
                { value: 'regions', label: 'Whole regions' },
                { value: 'customers', label: 'Specific customers' },
              ]}
            />
            {ppgScope === 'regions' ? (
              <Checks
                label="Regions"
                options={regions.map((r) => ({ value: r.code, label: `${r.code} · ${r.name}` }))}
                value={scopeRegions}
                onChange={setScopeRegions}
              />
            ) : (
              <Checks
                label="Customers"
                options={customers.map((c) => ({ value: c.id, label: `${c.name} · ${c.region}` }))}
                value={scopeCustomers}
                onChange={setScopeCustomers}
              />
            )}
          </>
        )}
        {level === 'Customer' && (
          <SelectField
            label="Customer"
            value={customer}
            onChange={(e) => setCustomer(e.target.value)}
            disabled={ownCustomers.length === 1}
            options={[
              { value: '', label: 'Choose a customer…' },
              ...ownCustomers.map((c) => ({ value: c.id, label: c.name })),
            ]}
          />
        )}
        {level === 'Vessel' && (
          <SelectField
            label="Vessel"
            value={vessel}
            onChange={(e) => setVessel(e.target.value)}
            options={[
              { value: '', label: 'Choose a vessel…' },
              ...ownVessels.map((v) => ({ value: v.id, label: `${v.name} · ${v.imo}` })),
            ]}
          />
        )}
        {user && (
          <SelectField
            label="Status"
            value={status}
            onChange={(e) => setStatus(e.target.value as User['status'])}
            options={[
              { value: 'active', label: 'Active' },
              { value: 'invited', label: 'Invited' },
              { value: 'disabled', label: 'Disabled — cannot sign in' },
            ]}
          />
        )}
      </div>
    </Dialog>
  )
}
