import { useState } from 'react'
import { Link } from 'react-router'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { SyncAge } from '../../components/StockBadges'
import { TextField } from '../../components/TextField'
import type { Vessel } from '../../data/model'
import { customerById } from '../../data/queries'
import { customers, regions, vessels as sampleVessels } from '../../data/sample'
import { formatDate } from '../../lib/format'

/** FR-21: vessels, their PPG vessel ID, IMO, customer and tablet (D-12: one per vessel). */
export function VesselsAdminPage() {
  const [rows, setRows] = useState(sampleVessels)
  const [region, setRegion] = useState('')
  const [customer, setCustomer] = useState('')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<Vessel | 'new' | null>(null)
  const shown = rows.filter((v) => {
    const c = customerById(v.customer)
    return (
      (!region || c?.region === region) &&
      (!customer || v.customer === customer) &&
      `${v.name} ${v.vesselId} ${v.imo}`.toLowerCase().includes(search.trim().toLowerCase())
    )
  })

  return (
    <>
      <SectionBar
        title="Vessels"
        subtitle="Each vessel belongs to one customer and has one tablet and one paint locker"
        actions={
          <Button onClick={() => setEditing('new')}>
            <Icon name="plus" /> Add vessel
          </Button>
        }
      />
      <>
        <FilterBar>
          <SelectField
            label="Region"
            className="w-40"
            value={region}
            onChange={(e) => setRegion(e.target.value)}
            options={[
              { value: '', label: 'All regions' },
              ...regions.map((r) => ({ value: r.code, label: r.code })),
            ]}
          />
          <SelectField
            label="Customer"
            className="w-60"
            value={customer}
            onChange={(e) => setCustomer(e.target.value)}
            options={[
              { value: '', label: 'All customers' },
              ...customers.map((c) => ({ value: c.id, label: c.name })),
            ]}
          />
          <TextField
            label="Search"
            placeholder="Name, vessel ID or IMO"
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
                      <Link
                        to={`/sea-stock?vessel=${v.id}`}
                        className="font-semibold text-brand hover:underline"
                      >
                        {v.name}
                      </Link>
                      <div>
                        <Muted>{v.imo}</Muted>
                      </div>
                    </div>
                  ),
                },
                { header: 'Vessel ID', width: 0.8, cell: (v) => <Mono>{v.vesselId}</Mono> },
                { header: 'Customer', width: 1.5, cell: (v) => customerById(v.customer)?.name },
                {
                  header: 'Tablet',
                  width: 1,
                  cell: (v) =>
                    v.device ? (
                      <div>
                        <Mono>{v.device.id}</Mono>
                        <div>
                          <Muted>
                            {v.device.platform} · app {v.device.appVersion}
                          </Muted>
                        </div>
                      </div>
                    ) : (
                      <Badge tone="warning">Not paired</Badge>
                    ),
                },
                {
                  header: 'Opening stock',
                  width: 0.9,
                  cell: (v) =>
                    v.baselineOn ? (
                      <Muted>{formatDate(v.baselineOn)}</Muted>
                    ) : (
                      <Badge tone="warning">Not captured</Badge>
                    ),
                },
                { header: 'Last sync', width: 1.1, cell: (v) => <SyncAge at={v.lastSync} /> },
                {
                  header: '',
                  width: 0.4,
                  align: 'right',
                  cell: (v) => (
                    <Button variant="link" onClick={() => setEditing(v)}>
                      Edit
                    </Button>
                  ),
                },
              ]}
            />
          </div>
        </Card>
        <Note>
          How a tablet is paired to its vessel is not set yet; device supply and management sit with
          PPG or the vessel operator (BRD §10).
        </Note>
      </>
      {editing && (
        <VesselDialog
          vessel={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSave={(v) => {
            setRows((all) =>
              all.some((x) => x.id === v.id)
                ? all.map((x) => (x.id === v.id ? v : x))
                : [...all, v],
            )
            setEditing(null)
          }}
        />
      )}
    </>
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
  const [name, setName] = useState(vessel?.name ?? '')
  const [vesselId, setVesselId] = useState(vessel?.vesselId ?? '')
  const [imo, setImo] = useState(vessel?.imo.replace('IMO ', '') ?? '')
  const [customer, setCustomer] = useState(vessel?.customer ?? '')
  const imoOk = /^\d{7}$/.test(imo)
  const ready = name.trim() && vesselId.trim() && imoOk && customer
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
                name: name.trim(),
                vesselId: vesselId.trim(),
                imo: `IMO ${imo}`,
                customer,
                device: vessel?.device ?? null,
                baselineOn: vessel?.baselineOn ?? null,
                lastSync: vessel?.lastSync ?? null,
                status: vessel?.status ?? 'active',
              })
            }
          >
            {vessel ? 'Save changes' : 'Add vessel'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <TextField label="Vessel name" value={name} onChange={(e) => setName(e.target.value)} />
        <div className="grid grid-cols-2 gap-3">
          <TextField
            label="Vessel ID (as in PPG systems)"
            value={vesselId}
            onChange={(e) => setVesselId(e.target.value)}
          />
          <TextField
            label="IMO number"
            inputMode="numeric"
            placeholder="7 digits"
            value={imo}
            onChange={(e) => setImo(e.target.value.replace(/\D/g, '').slice(0, 7))}
            error={imo && !imoOk ? 'An IMO number has 7 digits' : undefined}
          />
        </div>
        <SelectField
          label="Customer"
          value={customer}
          onChange={(e) => setCustomer(e.target.value)}
          options={[
            { value: '', label: 'Choose a customer…' },
            ...customers.map((c) => ({ value: c.id, label: `${c.name} · ${c.region}` })),
          ]}
        />
        <p className="text-small">
          The delivery note is matched to the vessel by IMO number first, then by name (FR-01).
        </p>
      </div>
    </Dialog>
  )
}
