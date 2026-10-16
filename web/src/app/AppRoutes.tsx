import type { ReactNode } from 'react'
import { Navigate, Route, Routes } from 'react-router'
import { ApiError } from '../api/client'
import { useMe } from '../api/me'
import { AuditLogPage } from '../features/auditLog/AuditLogPage'
import { BuAdminsPage } from '../features/buAdmins/BuAdminsPage'
import { EscalationsPage } from '../features/escalations/EscalationsPage'
import { EquipmentTypesPage } from '../features/equipmentTypes/EquipmentTypesPage'
import { LocationsPage } from '../features/locations/LocationsPage'
import { DelegationsPage } from '../features/review/DelegationsPage'
import { ReviewQueuePage } from '../features/review/ReviewQueuePage'
import { ScanReviewPage } from '../features/review/ScanReviewPage'
import { ScansPage } from '../features/scans/ScansPage'
import { TechniciansPage } from '../features/staff/TechniciansPage'
import { BuHomePage } from '../features/home/BuHomePage'
import { CreateUnitPage } from '../features/units/CreateUnitPage'
import { UnitDetailPage } from '../features/units/UnitDetailPage'
import { VacantUnitsPage } from '../features/units/VacantUnitsPage'
import { UnitsOverviewPage } from '../features/units/UnitsOverviewPage'
import { dashboardRole, type DashboardRole } from './access'
import { DashboardLayout } from './DashboardLayout'
import { homePath, navigation } from './navigation'
import { PlaceholderPage } from './pages/PlaceholderPage'
import { StatusScreen } from './pages/StatusScreen'

/** Built screens by menu path; menu items not listed here show a placeholder. */
const screens: Partial<Record<string, ReactNode>> = {
  '/overview': <UnitsOverviewPage />,
  '/home': <BuHomePage />,
  '/bu-admins': <BuAdminsPage />,
  '/locations': <LocationsPage />,
  '/technicians': <TechniciansPage />,
  '/equipment-types': <EquipmentTypesPage />,
  '/review-queue': <ReviewQueuePage />,
  '/delegations': <DelegationsPage />,
  '/escalations': <EscalationsPage />,
  '/scans': <ScansPage />,
  '/audit-log': <AuditLogPage />,
}

/** Pages reached from inside a screen, not from the menu. */
const subPages: Record<DashboardRole, { path: string; element: ReactNode }[]> = {
  enterprise_admin: [
    { path: '/overview/new-unit', element: <CreateUnitPage /> },
    { path: '/overview/units/:buId', element: <UnitDetailPage /> },
    { path: '/overview/units-without-bu-admin', element: <VacantUnitsPage /> },
    {
      path: '/escalations/:scanId',
      element: <ScanReviewPage back={{ to: '/escalations', label: 'Escalated scans' }} />,
    },
    {
      path: '/scans/:scanId',
      element: <ScanReviewPage back={{ to: '/scans', label: 'Scans' }} />,
    },
  ],
  bu_admin: [
    {
      path: '/review-queue/:scanId',
      element: <ScanReviewPage back={{ to: '/review-queue', label: 'Review queue' }} />,
    },
  ],
}

/** Loads the signed-in user, then shows only the routes their role may use. */
export function AppRoutes() {
  const me = useMe()

  if (me.isPending) return <StatusScreen title="Loading…" />
  if (me.isError) {
    const detail = me.error instanceof ApiError ? me.error.problem.title : 'Please try again.'
    return <StatusScreen title="We couldn't load your account">{detail}</StatusScreen>
  }

  const role = dashboardRole(me.data)
  if (!role) {
    return (
      <StatusScreen title="No dashboard access">
        The dashboard is for Enterprise Admins and BU Admins. Technicians use the Pixorex mobile
        app.
      </StatusScreen>
    )
  }

  // Routes of the other role do not exist for this user, so they fall back home.
  return (
    <Routes>
      <Route element={<DashboardLayout me={me.data} role={role} />}>
        {navigation[role].map((item) => (
          <Route
            key={item.path}
            path={item.path}
            element={screens[item.path] ?? <PlaceholderPage title={item.label} task={item.task} />}
          />
        ))}
        {subPages[role].map((page) => (
          <Route key={page.path} path={page.path} element={page.element} />
        ))}
        <Route path="*" element={<Navigate to={homePath(role)} replace />} />
      </Route>
    </Routes>
  )
}
