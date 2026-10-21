import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router'
import { Button } from '../components/Button'
import { AuthCard } from '../components/layout/AuthCard'
import { authConfig, type AuthMode } from './authConfig'
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

/**
 * Keycloak's post-logout return (contract 1.3). Canvas: sign-out goes straight to sign-in, so
 * with Keycloak this page only passes through. The card is for mock mode, which has no sign-in.
 * `?reason=removed` is for accounts disabled after full unit removal — stay here; do not re-login.
 */
export function SignedOutPage({ mode = authConfig.mode }: { mode?: AuthMode }) {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const removed = params.get('reason') === 'removed'

  useEffect(() => {
    if (mode === 'oidc' && !removed) void signIn('/')
  }, [mode, removed])

  if (removed) {
    return (
      <AuthCard>
        <h1 className="text-page-title font-bold">Your access was removed</h1>
        <p className="text-body-sm text-ink-muted">
          This account no longer has access. Contact your administrator if you need it restored.
        </p>
      </AuthCard>
    )
  }

  if (mode === 'oidc') {
    return (
      <AuthCard>
        <p className="text-center text-body text-ink-muted">Taking you to sign-in…</p>
      </AuthCard>
    )
  }
  return (
    <AuthCard>
      <h1 className="text-page-title font-bold">You're signed out</h1>
      <p className="text-body-sm text-ink-muted">
        Sign in with your work email; we'll send you a one-time code.
      </p>
      <Button className="h-12" onClick={() => void navigate('/')}>
        Sign in
      </Button>
    </AuthCard>
  )
}
