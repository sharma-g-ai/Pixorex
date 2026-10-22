import { useState } from 'react'
import { Button } from '../../components/Button'
import { DataTable } from '../../components/DataTable'
import { Dialog } from '../../components/Dialog'
import { SectionBar } from './SectionBar'
import { Card, Note } from '../../components/Page'
import { TextField } from '../../components/TextField'
import type { Region } from '../../data/model'
import { customerById } from '../../data/queries'
import { customers, regions, users, vessels } from '../../data/sample'
import { saveRegion, useStore } from '../../data/store'

/** FR-24: the geographic levels that scope access and reporting (D-05: PPG sales regions). */
export function RegionsPage() {
  useStore()
  const rows = regions
  const [editing, setEditing] = useState<Region | null>(null)
  return (
    <>
      <SectionBar
        title="Regions"
        subtitle="PPG sales regions. Each customer belongs to one region."
      />
      <>
        <Card flush>
          <div className="p-4">
            <DataTable
              label="Regions"
              rows={rows}
              rowKey={(r) => r.code}
              empty="No regions"
              columns={[
                { header: 'Code', width: 0.6, cell: (r) => <b>{r.code}</b> },
                { header: 'Name', width: 2, cell: (r) => r.name },
                {
                  header: 'Customers',
                  align: 'right',
                  cell: (r) => customers.filter((c) => c.region === r.code).length,
                },
                {
                  header: 'Vessels',
                  align: 'right',
                  cell: (r) =>
                    vessels.filter((v) => customerById(v.customer)?.region === r.code).length,
                },
                {
                  header: 'PPG users scoped',
                  align: 'right',
                  cell: (r) =>
                    users.filter(
                      (u) => u.scope.kind === 'regions' && u.scope.regions.includes(r.code),
                    ).length,
                },
                {
                  header: '',
                  width: 0.5,
                  align: 'right',
                  cell: (r) => (
                    <Button variant="link" onClick={() => setEditing(r)}>
                      Edit
                    </Button>
                  ),
                },
              ]}
            />
          </div>
        </Card>
        <Note>
          The BRD names APAC, EMEA and USCA (D-05) and marks geography as not necessary for the MVP,
          while FR-24 and FR-25 include it. Whether a global customer can span regions is to be
          confirmed.
        </Note>
      </>
      {editing && (
        <RegionDialog
          region={editing}
          onClose={() => setEditing(null)}
          onSave={(r) => {
            saveRegion(r)
            setEditing(null)
          }}
        />
      )}
    </>
  )
}

function RegionDialog({
  region,
  onClose,
  onSave,
}: {
  region: Region
  onClose: () => void
  onSave: (r: Region) => void
}) {
  const [name, setName] = useState(region.name)
  return (
    <Dialog
      title={`Edit ${region.code}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={!name.trim()} onClick={() => onSave({ ...region, name: name.trim() })}>
            Save changes
          </Button>
        </>
      }
    >
      <TextField label="Region name" value={name} onChange={(e) => setName(e.target.value)} />
    </Dialog>
  )
}
