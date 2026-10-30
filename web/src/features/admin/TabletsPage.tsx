import { useState } from 'react'
import { Link } from 'react-router'
import { useViewer } from '../../app/viewer'
import { Badge, type BadgeTone } from '../../components/Badge'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { SectionBar } from './SectionBar'
import { Card, Mono, Muted, Note } from '../../components/Page'
import { FilterBar } from '../../components/ScopeFilters'
import { SelectField } from '../../components/SelectField'
import { TextAreaField } from '../../components/TextAreaField'
import type { Device } from '../../data/model'
import { lastVesselOfDevice, vesselOfDevice, visibleDevices } from '../../data/queries'
import { retireDevice, revokeDevice, useStore } from '../../data/store'
import { formatDateTime } from '../../lib/format'

type Shown = 'active' | 'retiring' | 'retired' | 'revoked'

function shownStatus(d: Device): Shown {
  return d.status === 'active' && d.retireRequestedAt ? 'retiring' : d.status
}

const looks: Record<Shown, { label: string; tone: BadgeTone }> = {
  active: { label: 'Active', tone: 'success' },
  retiring: { label: 'Retires at next sync', tone: 'warning' },
  retired: { label: 'Retired', tone: 'neutral' },
  revoked: { label: 'Revoked', tone: 'danger' },
}

/**
 * The tablets enrolled to vessels (data model Domain 2). Retire one that is being replaced, after
 * its last sync; revoke one that is lost or stolen, which stops it syncing at once.
 */
export function TabletsPage() {
  useStore()
  const { user } = useViewer()
  const [status, setStatus] = useState<Shown | ''>('')
  const [revoking, setRevoking] = useState<Device | null>(null)
  const rows = visibleDevices(user).filter((d) => !status || shownStatus(d) === status)

  return (
    <>
      <SectionBar title="Tablets" subtitle="One tablet per vessel; pair a new one from the Vessels tab" />
      <FilterBar>
        <SelectField
          label="Status"
          className="w-48"
          value={status}
          onChange={(e) => setStatus(e.target.value as Shown | '')}
          options={[{ value: '', label: 'All' }, ...Object.entries(looks).map(([value, l]) => ({ value, label: l.label }))]}
        />
      </FilterBar>
      <Card flush>
        <div className="p-4">
          <DataTable
            label="Tablets"
            rows={rows}
            rowKey={(d) => d.id}
            empty="No tablets match this filter"
            columns={[
              {
                header: 'Tablet',
                width: 1.5,
                cell: (d) => (
                  <div>
                    <Mono>{d.id}</Mono>
                    <div>
                      <Muted>{d.model}</Muted>
                    </div>
                    {!d.modelSupported && <Badge tone="warning">Model not on the supported list</Badge>}
                  </div>
                ),
              },
              {
                header: 'Vessel',
                width: 1.3,
                cell: (d) => {
                  const now = vesselOfDevice(d.id)
                  const last = now ?? lastVesselOfDevice(d.id)
                  return last ? (
                    <div>
                      <Link to={`/sea-stock?vessel=${last.id}`} className="font-semibold text-brand hover:underline">
                        {last.name}
                      </Link>
                      {!now && (
                        <div>
                          <Muted>No longer paired</Muted>
                        </div>
                      )}
                    </div>
                  ) : (
                    <Muted>—</Muted>
                  )
                },
              },
              {
                header: 'Software',
                width: 1,
                cell: (d) => (
                  <Muted>
                    {d.platform} {d.osVersion} · app {d.appVersion}
                  </Muted>
                ),
              },
              { header: 'Enrolled', width: 1, cell: (d) => formatDateTime(d.enrolledAt) },
              {
                header: 'Status',
                width: 1.1,
                cell: (d) => {
                  const s = shownStatus(d)
                  return (
                    <div>
                      <Badge tone={looks[s].tone}>{looks[s].label}</Badge>
                      {d.revokeReason && (
                        <div>
                          <Muted>{d.revokeReason}</Muted>
                        </div>
                      )}
                    </div>
                  )
                },
              },
              {
                header: '',
                width: 1,
                align: 'right',
                cell: (d) =>
                  d.status === 'active' && (
                    <div className="flex justify-end gap-x-3">
                      {!d.retireRequestedAt && (
                        <Button variant="link" onClick={() => retireDevice(d.id, user)}>
                          Retire
                        </Button>
                      )}
                      <Button variant="danger-link" onClick={() => setRevoking(d)}>
                        Revoke
                      </Button>
                    </div>
                  ),
              },
            ]}
          />
        </div>
      </Card>
      <Note>
        Retire: the tablet uploads what it holds at its next sync, then stops. Revoke: it can no longer sync,
        so anything not yet uploaded stays on it.
      </Note>
      {revoking && <RevokeDialog device={revoking} onClose={() => setRevoking(null)} />}
    </>
  )
}

function RevokeDialog({ device, onClose }: { device: Device; onClose: () => void }) {
  const { user } = useViewer()
  const [reason, setReason] = useState('')
  return (
    <Dialog
      title={`Revoke ${device.id}?`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant="danger"
            disabled={!reason.trim()}
            onClick={() => {
              revokeDevice(device.id, reason.trim(), user)
              onClose()
            }}
          >
            Revoke tablet
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>
          The tablet is unpaired from {vesselOfDevice(device.id)?.name ?? 'its vessel'} and can no longer sync.
          Anything recorded on it and not yet uploaded will not reach Sea Stock.
        </p>
        <TextAreaField
          label="Reason (required)"
          placeholder="e.g. Tablet lost overboard"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
      </div>
    </Dialog>
  )
}
