import { Navigate, Outlet, useLocation, useNavigate } from 'react-router'
import { Sidebar } from '../components/layout/Sidebar'
import { allowedPath, HOME_PATH, navigationFor } from './navigation'
import { useSession } from './viewer'

/** Sidebar on the left, the current page on the right. */
export function Layout() {
  const { user, signOut } = useSession()
  const location = useLocation()
  const navigate = useNavigate()

  // Every page needs sign-in; come back here afterwards.
  if (!user)
    return <Navigate to="/sign-in" replace state={{ from: location.pathname + location.search }} />

  // A page the user's role may not open goes back to their home page.
  if (!allowedPath(user, location.pathname)) return <Navigate to={HOME_PATH} replace />

  return (
    <div className="flex h-screen overflow-hidden bg-page">
      <Sidebar
        sections={navigationFor(user)}
        onSignOut={() => {
          signOut()
          navigate('/sign-in', { replace: true })
        }}
      />
      <main className="flex min-w-0 grow flex-col">
        {/* Remount for each user so filters start fresh. */}
        <Outlet key={user.id} />
      </main>
    </div>
  )
}
