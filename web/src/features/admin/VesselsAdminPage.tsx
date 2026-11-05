import { useState } from 'react'
import { Link } from 'react-router'
import { useViewer } from '../../app/viewer'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { ImportDialog } from './ImportDialog'
import { SectionBar } from './SectionBar'
import { PairTabletDialog, PasswordResetDialog } from './VesselAccessDialogs'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { StatusBadge } from '../../components/StatusBadge'
import { SyncAge } from '../../components/StockBadges'
import { TextField } from '../../components/TextField'
import type { User, Vessel } from '../../data/model'
import { activeDevice, customerById, isValidImo, openEnrolmentCode, visibleCustomers, visibleVessels } from '../../data/queries'
import { can } from '../../data/roles'
import { imoWithCheckDigit, vessels } from '../../data/sample'
import { importVessels, saveVessel, useStore } from '../../data/store'
import { formatDate } from '../../lib/format'

type Action = { kind: 'edit'; vessel: Vessel | null } | { kind: 'pair' | 'password'; vessel: Vessel } | { kind: 'import' }

/**
 * FR-21: vessels, identified by IMO, each with one customer and one tablet (D-12). A PPG Admin
 * adds and edits vessels; a Customer Admin imports, pairs tablets and resets passwords for their own.
 */
export function VesselsAdminPage() {
  useStore()
  const { user } = useViewer()
  const all = user.scope.kind === 'all'
  const [customer, setCustomer] = useState('')
  const [search, setSearch] = useState('')
  const [action, setAction] = useState<Action | null>(null)
  const shown = visibleVessels(user).filter(
    (v) =>
      (!customer || v.customer === customer) &&
      `${v.name} ${v.imo}`.toLowerCase().includes(search.trim().toLowerCase()),
  )

  return (
    <>
      <SectionBar
        title="Vessels"
        subtitle="Each vessel belongs to one customer and has one tablet; the vessel signs in on that tablet"
        actions={
          <>
            {can(user, 'import-vessels') && (
              <Button variant="secondary" onClick={() => setAction({ kind: 'import' })}>
                <Icon name="upload" /> Import from Excel
              </Button>
            )}
            {can(user, 'manage-vessels') && (
              <Button onClick={() => setAction({ kind: 'edit', vessel: null })}>
                <Icon name="plus" /> Add vessel
              </Button>
            )}
          </>
        }
      />
      <FilterBar>
        {all && (
          <SelectField
            label="Customer"
            className="w-60"
            value={customer}
            onChange={(e) => setCustomer(e.target.value)}
            options={[
              { value: '', label: 'All customers' },
              ...visibleCustomers(user).map((c) => ({ value: c.id, label: c.name })),
            ]}
          />
        )}
        <TextField
          label="Search"
          placeholder="Name or IMO"
          className="w-60"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </FilterBar>
      <Card flush>
        <div className="p-4">
          <DataTable
            label="Vessels"
            rows={shown}
            rowKey={(v) => v.id}
            empty="No vessels match these filters"
            columns={[
              {
                header: 'Vessel',
                width: 1.5,
                cell: (v) => (
                  <div>
                    <Link to={`/sea-stock?vessel=${v.id}`} className="font-semibold text-brand hover:underline">
                      {v.name}
                    </Link>
                    <div>
                      <Muted>
                        IMO <Mono>{v.imo}</Mono>
                      </Muted>
                    </div>
                  </div>
                ),
              },
              ...(all ? [{ header: 'Customer', width: 1.3, cell: (v: Vessel) => customerById(v.customer)?.name }] : []),
              {
                header: 'Tablet',
                width: 1,
                cell: (v) => {
                  const d = activeDevice(v.id)
                  const code = openEnrolmentCode(v.id)
                  return d ? (
                    <div>
                      <Mono>{d.id}</Mono>
                      <div>
                        <Muted>
                          {d.platform} · app {d.appVersion}
                        </Muted>
                      </div>
                    </div>
                  ) : (
                    <Badge tone="warning">{code ? 'Code issued' : 'Not paired'}</Badge>
                  )
                },
              },
              {
                header: 'Receiving',
                width: 0.7,
                cell: (v) => (v.receivingMode === 'scan' ? 'Scan' : 'By hand'),
              },
              {
                header: 'Opening stock',
                width: 0.9,
                cell: (v) =>
                  v.baselineOn ? <Muted>{formatDate(v.baselineOn)}</Muted> : <Badge tone="warning">Not captured</Badge>,
              },
              { header: 'Last sync', width: 1, cell: (v) => <SyncAge at={v.lastSync} /> },
              { header: 'Status', width: 0.7, cell: (v) => <StatusBadge status={v.status} /> },
              {
                header: '',
                width: 1.5,
                align: 'right',
                cell: (v) => <RowActions vessel={v} user={user} onAction={setAction} />,
              },
            ]}
          />
        </div>
      </Card>
      <Note>
        The IMO number is the vessel’s ID. The tablet signs in as the vessel, so crew need no accounts; reset
        the vessel password at crew change.
      </Note>
      {action?.kind === 'edit' && (
        <VesselDialog
          vessel={action.vessel}
          onClose={() => setAction(null)}
          onSave={(v) => {
            saveVessel(v, user)
            setAction(null)
          }}
        />
      )}
      {action?.kind === 'pair' && <PairTabletDialog vessel={action.vessel} onClose={() => setAction(null)} />}
      {action?.kind === 'password' && <PasswordResetDialog vessel={action.vessel} onClose={() => setAction(null)} />}
      {action?.kind === 'import' && <ImportVesselsDialog onClose={() => setAction(null)} />}
    </>
  )
}

function RowActions({ vessel, user, onAction }: { vessel: Vessel; user: User; onAction: (a: Action) => void }) {
  const active = vessel.status === 'active'
  return (
    <div className="flex flex-wrap justify-end gap-x-3">
      {can(user, 'manage-tablets') && active && (
        <Button variant="link" onClick={() => onAction({ kind: 'pair', vessel })}>
          Pair tablet
        </Button>
      )}
      {can(user, 'reset-vessel-password') && active && (
        <Button variant="link" onClick={() => onAction({ kind: 'password', vessel })}>
          Reset password
        </Button>
      )}
      {can(user, 'manage-vessels') && (
        <Button variant="link" onClick={() => onAction({ kind: 'edit', vessel })}>
          Edit
        </Button>
      )}
    </div>
  )
}

function VesselDialog({
  vessel,
  onClose,
  onSave,
}: {
  vessel: Vessel | null
  onClose: () => void
  onSave: (v: Vessel) => void
}) {
  const { user } = useViewer()
  const [name, setName] = useState(vessel?.name ?? '')
  const [imo, setImo] = useState(vessel?.imo ?? '')
  const [customer, setCustomer] = useState(vessel?.customer ?? '')
  const [receivingMode, setReceivingMode] = useState<Vessel['receivingMode']>(vessel?.receivingMode ?? 'scan')
  const [status, setStatus] = useState<Vessel['status']>(vessel?.status ?? 'active')
  const imoOk = isValidImo(imo)
  const taken = vessels.some((v) => v.imo === imo && v.id !== vessel?.id)
  const imoError =
    imo.length < 7 ? undefined : !imoOk ? 'The last digit does not match the IMO check digit' : taken ? 'Another vessel has this IMO' : undefined
  const ready = name.trim() && imoOk && !taken && customer
  return (
    <Dialog
      title={vessel ? `Edit ${vessel.name}` : 'Add vessel'}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!ready}
            onClick={() =>
              onSave({
                id: vessel?.id ?? `v-${Date.now()}`,
                imo,
                name: name.trim(),
                customer,
                receivingMode,
                baselineOn: vessel?.baselineOn ?? null,
                lastSync: vessel?.lastSync ?? null,
                status,
                passwordChangedAt: vessel?.passwordChangedAt ?? null,
                lastSignInAt: vessel?.lastSignInAt ?? null,
              })
            }
          >
            {vessel ? 'Save changes' : 'Add vessel'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-3">
          <TextField label="Vessel name" value={name} onChange={(e) => setName(e.target.value)} />
          <TextField
            label="IMO number (the vessel ID)"
            inputMode="numeric"
            placeholder="7 digits"
            value={imo}
            disabled={vessel !== null}
            onChange={(e) => setImo(e.target.value.replace(/\D/g, '').slice(0, 7))}
            error={imoError}
          />
        </div>
        <SelectField
          label="Customer"
          value={customer}
          disabled={vessel !== null}
          onChange={(e) => setCustomer(e.target.value)}
          options={[
            { value: '', label: 'Choose a customer…' },
            ...visibleCustomers(user).map((c) => ({ value: c.id, label: `${c.name} · ${c.customerCode}` })),
          ]}
        />
        <div className="grid grid-cols-2 gap-3">
          <SelectField
            label="Receiving on the tablet"
            value={receivingMode}
            onChange={(e) => setReceivingMode(e.target.value as Vessel['receivingMode'])}
            options={[
              { value: 'scan', label: 'Scan labels' },
              { value: 'manual', label: 'Enter by hand' },
            ]}
          />
          {vessel && (
            <SelectField
              label="Status"
              value={status}
              onChange={(e) => setStatus(e.target.value as Vessel['status'])}
              options={[
                { value: 'active', label: 'Active' },
                { value: 'inactive', label: 'Inactive' },
              ]}
            />
          )}
        </div>
        <p className="text-small">
          {vessel
            ? 'The IMO and the customer cannot be changed: the IMO ties the vessel to its stock and history, and a vessel cannot move to another customer in the MVP.'
            : 'The IMO read from a delivery note is checked against this number.'}{' '}
          The receiving setting reaches the tablet at its next sync.
        </p>
      </div>
    </Dialog>
  )
}

/** D-03: vessels from PPG's Excel file, matched on IMO. A Customer Admin loads only their own customer's. */
function ImportVesselsDialog({ onClose }: { onClose: () => void }) {
  const { user } = useViewer()
  const own = visibleCustomers(user)
  const target = own[0]
  const fresh: Vessel[] = target
    ? (
        [
          ['982001', 'Sea Harmony'],
          ['982002', 'Sea Liberty'],
        ] as const
      ).map(([six, name], i) => ({
        id: `v-imp${i + 1}`,
        imo: imoWithCheckDigit(six),
        name: `${target.name.split(' ')[0]} ${name}`,
        customer: target.id,
        receivingMode: 'scan',
        baselineOn: null,
        lastSync: null,
        status: 'active',
        passwordChangedAt: null,
        lastSignInAt: null,
      }))
    : []
  const toAdd = fresh.filter((r) => !vessels.some((v) => v.imo === r.imo))
  const known = visibleVessels(user).slice(0, 2)
  const problems = ['Row 5: IMO 9812345 fails the check digit.']
  const other = vessels.find((v) => v.customer !== target?.id)
  if (other) problems.push(`Row 6: IMO ${other.imo} belongs to another customer.`)
  if (user.scope.kind === 'customer') problems.push('Row 7: customer ID C-104530 is not your customer.')
  return (
    <ImportDialog
      title="Import vessels"
      intro="Upload the vessel list as Excel (.xlsx) or CSV with the columns: IMO number, vessel name, customer ID. A row whose IMO is already here updates that vessel’s name. All-or-nothing: a bad check digit, or an IMO that belongs to another customer, refuses the whole file and names the row."
      counts={[
        { label: 'New vessels', count: toAdd.length, tone: 'success' },
        { label: 'Already here — name updated', count: known.length, tone: 'neutral' },
      ]}
      problems={problems}
      allOrNothing
      toLoad={toAdd.length + known.length}
      noun="vessels"
      onLoad={() => importVessels([...known, ...toAdd], user)}
      onClose={onClose}
    />
  )
}
