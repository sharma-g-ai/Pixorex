import { Navigate, Outlet, useLocation, useNavigate } from 'react-router'
import { Sidebar } from '../components/layout/Sidebar'
import { allowedPath, homePath, navigationFor } from './navigation'
import { useViewer } from './viewer'

/** Sidebar on the left, the current page on the right. */
export function Layout() {
  const { user } = useViewer()
  const location = useLocation()
  const navigate = useNavigate()

  // A page the previewed role may not open goes back to their home page.
  if (!allowedPath(user.role, location.pathname))
    return <Navigate to={homePath(user.role)} replace />

  return (
    <div className="flex h-screen overflow-hidden bg-page">
      <Sidebar sections={navigationFor(user.role)} onSignOut={() => navigate('/sign-in')} />
      <main className="flex min-w-0 grow flex-col">
        {/* Remount on a role switch so filters start fresh. */}
        <Outlet key={user.id} />
      </main>
    </div>
  )
}
