import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router'
import { Button } from '../components/Button'
import { AuthCard } from '../components/layout/AuthCard'
import { authConfig } from './authConfig'
import { completeSignIn, signIn } from './session'

/** Keycloak sends the browser back here with the code; finish sign-in and go on (D-11). */
export function AuthCallbackPage() {
  const navigate = useNavigate()
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let active = true
    completeSignIn()
      .then((returnTo) => active && navigate(returnTo, { replace: true }))
      .catch(() => active && setFailed(true))
    return () => {
      active = false
    }
  }, [navigate])

  if (!failed) {
    return (
      <AuthCard>
        <p className="text-center text-body text-ink-muted">Signing you in…</p>
      </AuthCard>
    )
  }
  return (
    <AuthCard>
      <h1 className="text-page-title font-bold">Sign-in didn't finish</h1>
      <p className="text-body-sm text-ink-muted">
        The sign-in link may have expired or been used already.
      </p>
      <Button className="h-12" onClick={() => void signIn('/')}>
        Sign in again
      </Button>
    </AuthCard>
  )
}

/** After sign-out (contract 1.3 and Keycloak logout). */
export function SignedOutPage() {
  const navigate = useNavigate()
  return (
    <AuthCard>
      <h1 className="text-page-title font-bold">You're signed out</h1>
      <p className="text-body-sm text-ink-muted">
        Sign in with your work email; we'll send you a one-time code.
      </p>
      <Button
        className="h-12"
        onClick={() => (authConfig.mode === 'oidc' ? void signIn('/') : void navigate('/'))}
      >
        Sign in
      </Button>
    </AuthCard>
  )
}
