import { useEffect, useState, type ReactNode } from 'react'
import { useLocation } from 'react-router'
import { StatusScreen } from '../app/pages/StatusScreen'
import { authConfig, type AuthMode } from './authConfig'
import { signIn, userManager } from './session'

type GateState = 'checking' | 'signed-in' | 'redirecting' | 'failed'

/**
 * Shows the dashboard only to a signed-in user (D-11). Without a valid session it sends the
 * browser to Keycloak and brings it back to the same page afterwards.
 */
export function AuthGate({
  children,
  mode = authConfig.mode,
}: {
  children: ReactNode
  mode?: AuthMode
}) {
  if (mode === 'mock') return <>{children}</>
  if (mode === 'missing') {
    return (
      <StatusScreen title="Sign-in isn't configured">
        This build has no sign-in settings. Set VITE_OIDC_AUTHORITY and VITE_OIDC_CLIENT_ID.
      </StatusScreen>
    )
  }
  return <OidcGate>{children}</OidcGate>
}

function OidcGate({ children }: { children: ReactNode }) {
  const location = useLocation()
  const [state, setState] = useState<GateState>('checking')
  const returnTo = `${location.pathname}${location.search}`

  useEffect(() => {
    const um = userManager()
    if (!um) return
    let active = true
    const goSignIn = () => {
      setState('redirecting')
      signIn(returnTo).catch(() => active && setState('failed'))
    }
    um.getUser()
      .then((user) => {
        if (!active) return
        if (user && !user.expired) setState('signed-in')
        else goSignIn()
      })
      .catch(goSignIn)
    // Refresh failed and the token ran out: sign in again, back to this page.
    um.events.addAccessTokenExpired(goSignIn)
    return () => {
      active = false
      um.events.removeAccessTokenExpired(goSignIn)
    }
    // Only on first load; later navigation keeps the session.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (state === 'signed-in') return <>{children}</>
  if (state === 'failed') {
    return (
      <StatusScreen title="We couldn't reach sign-in">
        Please check your connection and reload the page.
      </StatusScreen>
    )
  }
  return <StatusScreen title="Signing you in…" />
}
