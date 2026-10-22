import { useState } from 'react'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Mono, Muted } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { TextField } from '../../components/TextField'
import type { Customer, RegionCode } from '../../data/model'
import { customers as sampleCustomers, NOW, regions, users, vessels } from '../../data/sample'
import { formatDate } from '../../lib/format'

/** FR-21: customers, with their PPG customer ID and region. Changes last until reload. */
export function CustomersPage() {
  const [rows, setRows] = useState(sampleCustomers)
  const [region, setRegion] = useState('')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<Customer | 'new' | null>(null)
  const shown = rows.filter(
    (c) =>
      (!region || c.region === region) &&
      `${c.name} ${c.customerId}`.toLowerCase().includes(search.trim().toLowerCase()),
  )

  return (
    <>
      <SectionBar
        title="Customers"
        subtitle="Customer accounts, as held in PPG systems"
        actions={
          <Button onClick={() => setEditing('new')}>
            <Icon name="plus" /> Add customer
          </Button>
        }
      />
      <>
        <FilterBar>
          <SelectField
            label="Region"
            className="w-44"
            value={region}
            onChange={(e) => setRegion(e.target.value)}
            options={[
              { value: '', label: 'All regions' },
              ...regions.map((r) => ({ value: r.code, label: r.code })),
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
                { header: 'Customer ID', cell: (c) => <Mono>{c.customerId}</Mono> },
                { header: 'Region', width: 0.7, cell: (c) => c.region },
                {
                  header: 'Vessels',
                  width: 0.6,
                  align: 'right',
                  cell: (c) => vessels.filter((v) => v.customer === c.id).length,
                },
                {
                  header: 'Users',
                  width: 0.6,
                  align: 'right',
                  cell: (c) =>
                    users.filter(
                      (u) =>
                        (u.scope.kind === 'customer' && u.scope.customer === c.id) ||
                        (u.scope.kind === 'vessel' &&
                          vessels.find((v) => v.id === (u.scope as { vessel: string }).vessel)
                            ?.customer === c.id),
                    ).length,
                },
                {
                  header: 'Status',
                  width: 0.8,
                  cell: (c) => (
                    <Badge tone={c.status === 'active' ? 'success' : 'neutral'}>
                      {c.status === 'active' ? 'Active' : 'Inactive'}
                    </Badge>
                  ),
                },
                {
                  header: 'Added',
                  width: 0.9,
                  cell: (c) => <Muted>{formatDate(c.addedOn)}</Muted>,
                },
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
      </>
      {editing && (
        <CustomerDialog
          customer={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSave={(c) => {
            setRows((all) =>
              all.some((x) => x.id === c.id)
                ? all.map((x) => (x.id === c.id ? c : x))
                : [...all, c],
            )
            setEditing(null)
          }}
        />
      )}
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
  const [customerId, setCustomerId] = useState(customer?.customerId ?? '')
  const [region, setRegion] = useState<RegionCode | ''>(customer?.region ?? '')
  const [status, setStatus] = useState(customer?.status ?? 'active')
  const ready = name.trim() && customerId.trim() && region
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
              region &&
              onSave({
                id: customer?.id ?? `c-${Date.now()}`,
                name: name.trim(),
                customerId: customerId.trim(),
                region,
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
          value={customerId}
          onChange={(e) => setCustomerId(e.target.value)}
        />
        <SelectField
          label="Region"
          value={region}
          onChange={(e) => setRegion(e.target.value as RegionCode | '')}
          options={[
            { value: '', label: 'Choose a region…' },
            ...regions.map((r) => ({ value: r.code, label: `${r.code} · ${r.name}` })),
          ]}
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
