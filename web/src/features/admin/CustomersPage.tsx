import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { StatusBadge } from '../../components/StatusBadge'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { ImportDialog } from './ImportDialog'
import { SectionBar } from './SectionBar'
import { Card, Mono, Muted } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import type { Customer } from '../../data/model'
import { customers, NOW, users, vessels } from '../../data/sample'
import { importCustomers, saveCustomer, useStore } from '../../data/store'
import { formatDate } from '../../lib/format'

/** FR-21: customers, with their customer ID in PPG systems. PPG Admin only. */
export function CustomersPage() {
  useStore()
  const { user } = useViewer()
  const [status, setStatus] = useState('')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<Customer | 'new' | null>(null)
  const [importing, setImporting] = useState(false)
  const shown = customers.filter(
    (c) =>
      (!status || c.status === status) &&
      `${c.name} ${c.customerCode}`.toLowerCase().includes(search.trim().toLowerCase()),
  )

  return (
    <>
      <SectionBar
        title="Customers"
        subtitle="Customer accounts, with the customer ID used in PPG systems"
        actions={
          <>
            <Button variant="secondary" onClick={() => setImporting(true)}>
              <Icon name="upload" /> Import from Excel
            </Button>
            <Button onClick={() => setEditing('new')}>
              <Icon name="plus" /> Add customer
            </Button>
          </>
        }
      />
      <FilterBar>
        <SelectField
          label="Status"
          className="w-36"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          options={[
            { value: '', label: 'All' },
            { value: 'active', label: 'Active' },
            { value: 'inactive', label: 'Inactive' },
          ]}
        />
        <TextField
          label="Search"
          placeholder="Name or customer ID"
          className="w-64"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </FilterBar>
      <Card flush>
        <div className="p-4">
          <DataTable
            label="Customers"
            rows={shown}
            rowKey={(c) => c.id}
            empty="No customers match these filters"
            columns={[
              { header: 'Customer', width: 2, cell: (c) => <b>{c.name}</b> },
              { header: 'Customer ID', cell: (c) => <Mono>{c.customerCode}</Mono> },
              {
                header: 'Vessels',
                width: 0.6,
                align: 'right',
                cell: (c) => vessels.filter((v) => v.customer === c.id).length,
              },
              {
                header: 'Customer Admins',
                width: 0.9,
                align: 'right',
                cell: (c) =>
                  users.filter((u) => u.scope.kind === 'customer' && u.scope.customer === c.id).length,
              },
              { header: 'Status', width: 0.8, cell: (c) => <StatusBadge status={c.status} /> },
              { header: 'Added', width: 0.9, cell: (c) => <Muted>{formatDate(c.addedOn)}</Muted> },
              {
                header: '',
                width: 0.5,
                align: 'right',
                cell: (c) => (
                  <Button variant="link" onClick={() => setEditing(c)}>
                    Edit
                  </Button>
                ),
              },
            ]}
          />
        </div>
      </Card>
      {editing && (
        <CustomerDialog
          customer={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSave={(c) => {
            saveCustomer(c, user)
            setEditing(null)
          }}
        />
      )}
      {importing && <ImportCustomersDialog onClose={() => setImporting(false)} />}
    </>
  )
}

function CustomerDialog({
  customer,
  onClose,
  onSave,
}: {
  customer: Customer | null
  onClose: () => void
  onSave: (c: Customer) => void
}) {
  const [name, setName] = useState(customer?.name ?? '')
  const [code, setCode] = useState(customer?.customerCode ?? '')
  const [status, setStatus] = useState(customer?.status ?? 'active')
  const taken = customers.some((c) => c.customerCode === code.trim() && c.id !== customer?.id)
  const ready = name.trim() && code.trim() && !taken
  return (
    <Dialog
      title={customer ? `Edit ${customer.name}` : 'Add customer'}
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
                id: customer?.id ?? `c-${Date.now()}`,
                name: name.trim(),
                customerCode: code.trim(),
                status,
                addedOn: customer?.addedOn ?? NOW.slice(0, 10),
              })
            }
          >
            {customer ? 'Save changes' : 'Add customer'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <TextField label="Customer name" value={name} onChange={(e) => setName(e.target.value)} />
        <TextField
          label="Customer ID (as in PPG systems)"
          value={code}
          onChange={(e) => setCode(e.target.value)}
          error={taken ? 'Another customer has this ID' : undefined}
        />
        {customer && (
          <SelectField
            label="Status"
            value={status}
            onChange={(e) => setStatus(e.target.value as Customer['status'])}
            options={[
              { value: 'active', label: 'Active' },
              { value: 'inactive', label: 'Inactive' },
            ]}
          />
        )}
      </div>
    </Dialog>
  )
}

/** New rows in the sample PPG customer file used by the import preview. */
const importSample: Customer[] = [
  { id: 'c-imp1', customerCode: 'C-410877', name: 'Baltic Bulk Carriers', status: 'active', addedOn: NOW.slice(0, 10) },
  { id: 'c-imp2', customerCode: 'C-411203', name: 'Coral Sea Tankers', status: 'active', addedOn: NOW.slice(0, 10) },
]

/** D-03: the customer list from PPG's Excel file, matched on customer ID. */
function ImportCustomersDialog({ onClose }: { onClose: () => void }) {
  const { user } = useViewer()
  const fresh = importSample.filter((r) => !customers.some((c) => c.customerCode === r.customerCode))
  const known = customers.slice(0, 3)
  return (
    <ImportDialog
      title="Import customers"
      intro="Upload PPG’s customer list as Excel (.xlsx) or CSV with the columns: customer ID, customer name. A row whose customer ID is already here updates that customer’s name."
      counts={[
        { label: 'New customers', count: fresh.length, tone: 'success' },
        { label: 'Already here — name updated', count: known.length, tone: 'neutral' },
      ]}
      problems={['Row 7: the customer ID is empty.']}
      toLoad={fresh.length + known.length}
      noun="customers"
      onLoad={() => importCustomers([...known, ...fresh], user)}
      onClose={onClose}
    />
  )
}
