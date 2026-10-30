import { DataTable } from '../../components/DataTable'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Note } from '../../components/Page'
import { can, permissionLabels, roles } from '../../data/roles'
import { users } from '../../data/sample'

/** FR-23: what each role may see and do. Read-only; roles are fixed for the MVP. */
export function RolesPage() {
  return (
    <>
      <SectionBar title="Roles & permissions" subtitle="Two portal roles; each vessel signs in on its own tablet" />
      <div className="grid gap-3.5 md:grid-cols-2">
        {roles.map((r) => (
          <div key={r.key} className="rounded-xl border border-line bg-surface p-4">
            <div className="text-card-title font-bold">{r.label}</div>
            <div className="mt-1 text-small text-ink-muted">Held by: {r.heldBy}</div>
            <div className="mt-2 text-small">Sees: {r.sees}</div>
            <div className="mt-3 text-small font-semibold text-brand">
              {users.filter((u) => u.role === r.key && u.status !== 'disabled').length} users
            </div>
          </div>
        ))}
      </div>

      <Card title="Permissions" flush>
        <div className="p-4">
          <DataTable
            label="Permissions"
            rows={permissionLabels}
            rowKey={(p) => p.key}
            empty="No permissions"
            columns={[
              {
                header: 'Permission',
                width: 2.4,
                cell: (p) => (
                  <div>
                    <div>{p.label}</div>
                    {p.note && <div className="text-caption text-ink-muted">{p.note}</div>}
                  </div>
                ),
              },
              ...roles.map((r) => ({
                header: r.label,
                align: 'center' as const,
                cell: (p: (typeof permissionLabels)[number]) =>
                  can(r.key, p.key) ? (
                    <Icon name="check" className="mx-auto text-success" aria-label="Yes" />
                  ) : (
                    <span className="text-ink-subtle">—</span>
                  ),
              })),
            ]}
          />
        </div>
      </Card>
      <Note>
        The BRD names a third role, Vessel Admin (FR-22, FR-23). In the data model the vessel itself is the
        tablet’s user, so there is no vessel account in the portal. Permissions marked “to confirm” are a
        proposal to agree with PPG.
      </Note>
    </>
  )
}
