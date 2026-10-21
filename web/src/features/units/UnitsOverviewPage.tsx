import { Link } from 'react-router'
import { useBuAdmins } from '../../api/buAdmins'
import { useBusinessUnits } from '../../api/businessUnits'
import { useInvites } from '../../api/invites'
import { buttonClasses } from '../../components/buttonClasses'
import { Card } from '../../components/Card'
import { PageHeader } from '../../components/layout/PageHeader'
import { useDashboard } from '../../app/DashboardContext'
import { NeedsYouPanel } from './NeedsYouPanel'
import { UnitCard } from './UnitCard'
import { needsYou, otherUnitsOfAdmin } from './unitSummary'
import { latestAdminInvite } from './vacantUnits'

/** EA-01 Overview: every unit of the company and what needs the EA (canvas: EA 03). */
export function UnitsOverviewPage() {
  const { me } = useDashboard()
  const units = useBusinessUnits()
  const admins = useBuAdmins()
  const invites = useInvites()
  const count = units.data?.length

  return (
    <>
      <PageHeader
        title="Overview"
        subtitle={
          count === undefined
            ? me.tenant_name
            : `${me.tenant_name} · ${count} business ${count === 1 ? 'unit' : 'units'}`
        }
        actions={
          <Link to="/overview/new-unit" className={buttonClasses('primary')}>
            + Create unit
          </Link>
        }
      />
      <div className="flex grow flex-col gap-5 overflow-y-auto px-8 pt-6 pb-8 *:shrink-0">
        {units.isPending && <Card>Loading units…</Card>}
        {units.isError && <Card>We couldn't load the units. Please refresh the page.</Card>}

        {units.data && units.data.length === 0 && (
          <Card title="No business units yet">
            <p className="text-body text-ink-muted">
              Create the first unit to start setting up Pixorex.
            </p>
          </Card>
        )}

        {units.data && units.data.length > 0 && (
          <>
            <div className="grid grid-cols-[repeat(auto-fill,minmax(15rem,1fr))] gap-4">
              {units.data.map((unit) => (
                <UnitCard
                  key={unit.bu_id}
                  unit={unit}
                  alsoRuns={otherUnitsOfAdmin(units.data, unit)}
                  adminLastActive={
                    admins.data?.find((a) => a.user_id === unit.bu_admin?.user_id)?.last_active_at
                  }
                  invite={latestAdminInvite(invites.data ?? [], unit.bu_id)}
                />
              ))}
            </div>
            <NeedsYouPanel {...needsYou(units.data)} />
          </>
        )}
      </div>
    </>
  )
}
