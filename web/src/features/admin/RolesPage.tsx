import { DataTable } from '../../components/DataTable'
import { Icon } from '../../components/icons'
import { SectionBar } from './SectionBar'
import { Card, Note } from '../../components/Page'
import { accessLabels, can, permissionLabels, roles } from '../../data/roles'
import { users } from '../../data/sample'

/** FR-23: what each role may see and do. Read-only; roles are fixed for the MVP. */
export function RolesPage() {
  return (
    <>
      <SectionBar
        title="Roles & permissions"
        subtitle="One role per level: PPG, customer and vessel"
      />
      <>
        <div className="grid gap-3.5 md:grid-cols-3">
          {roles.map((r) => (
            <div key={r.key} className="rounded-xl border border-line bg-surface p-4">
              <div className="text-label font-bold tracking-wider text-ink-subtle uppercase">
                {r.level} level
              </div>
              <div className="mt-1 text-card-title font-bold">{r.label}</div>
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
                ...accessLabels.map((a) => ({
                  header: `${a.label} · ${a.detail}`,
                  align: 'center' as const,
                  cell: (p: (typeof permissionLabels)[number]) =>
                    can(a.key, p.key) ? (
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
          Proposed split, to confirm with PPG: the BRD sets the levels (FR-23, D-04, D-13) but not
          every permission, e.g. whether a Customer Admin manages their own users, or who reviews
          negative stock.
        </Note>
      </>
    </>
  )
}
