import { useBusinessUnits } from '../api/businessUnits'
import { useSwitchUnit, type Me, type UnitRole } from '../api/me'
import { AppShell } from '../components/layout/AppShell'
import { ContextCard } from '../components/layout/ContextCard'
import { Sidebar } from '../components/layout/Sidebar'
import { HeaderExtrasContext } from '../components/layout/headerExtras'
import { UnitSwitcher } from '../components/layout/UnitSwitcher'
import { NotificationsBell } from '../features/notifications/NotificationsBell'
import { useSignOut } from '../auth/useSignOut'
import { adminUnits, currentAdminUnit, type DashboardRole } from './access'
import { DashboardContext } from './DashboardContext'
import { navigation, roleLabel } from './navigation'

interface DashboardLayoutProps {
  me: Me
  role: DashboardRole
}

/** The shell for one role: its sidebar, menu and unit context around the pages. */
export function DashboardLayout({ me, role }: DashboardLayoutProps) {
  const unit = role === 'bu_admin' ? currentAdminUnit(me) : null
  const signOut = useSignOut()

  return (
    <DashboardContext.Provider value={{ me, role, unit }}>
      <HeaderExtrasContext.Provider value={<NotificationsBell role={role} />}>
        <AppShell
          sidebar={
            <Sidebar
              context={
                role === 'enterprise_admin' ? (
                  <CompanyCard me={me} />
                ) : (
                  unit && <UnitContext me={me} current={unit} />
                )
              }
              items={navigation[role]}
              userName={me.full_name}
              roleLabel={roleLabel[role]}
              onSignOut={() => void signOut()}
            />
          }
        />
      </HeaderExtrasContext.Provider>
    </DashboardContext.Provider>
  )
}

function CompanyCard({ me }: { me: Me }) {
  const { data: units } = useBusinessUnits()
  const detail = units ? `${units.length} ${units.length === 1 ? 'unit' : 'units'}` : undefined
  return <ContextCard label="Company" title={me.tenant_name} detail={detail} />
}

function UnitContext({ me, current }: { me: Me; current: UnitRole }) {
  const switchUnit = useSwitchUnit()
  return (
    <UnitSwitcher
      units={adminUnits(me)}
      current={current}
      onSelect={(buId) => switchUnit.mutate(buId)}
      busy={switchUnit.isPending}
    />
  )
}
