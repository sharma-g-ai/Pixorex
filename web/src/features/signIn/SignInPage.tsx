import { useState } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router'
import { useSession } from '../../app/viewer'
import { Button } from '../../components/Button'
import { Wordmark } from '../../components/layout/Wordmark'
import { TextField } from '../../components/TextField'
import { resetSampleData } from '../../data/store'

/**
 * Sign in with work e-mail and password. The role decides where the user lands: PPG Admin and
 * Customer Admin on the overview, Ship Admin on their vessel's stock.
 */
export function SignInPage() {
  const { user, signIn } = useSession()
  const navigate = useNavigate()
  const from = (useLocation().state as { from?: string } | null)?.from ?? '/'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [mode, setMode] = useState<'sign-in' | 'forgot' | 'sent'>('sign-in')
  const [wasReset, setWasReset] = useState(false)

  if (user) return <Navigate to="/" replace />

  return (
    <div className="flex min-h-screen bg-page">
      <div className="hidden w-[44%] flex-col justify-between bg-brand-dark p-12 text-white lg:flex">
        <Wordmark />
        <div>
          <h1 className="text-[30px] leading-tight font-bold">
            Sea Stock on every vessel, in one place.
          </h1>
          <p className="mt-3 max-w-md text-body leading-relaxed text-white/70">
            Paint and thinners on board, by product, shade and component type, updated from the
            crew’s tablet each time it syncs.
          </p>
        </div>
        <p className="text-caption text-white/40">PPG Protective &amp; Marine Coatings</p>
      </div>

      <div className="flex grow items-center justify-center p-8">
        <div className="w-full max-w-90">
          <div className="mb-8 lg:hidden">
            <Wordmark tone="dark" />
          </div>

          {mode === 'sign-in' && (
            <form
              noValidate
              onSubmit={(e) => {
                e.preventDefault()
                if (!email.trim() || !password) {
                  setError('Enter your e-mail and password.')
                  return
                }
                const result = signIn(email, password)
                if (result.ok) navigate(from, { replace: true })
                else setError(result.error)
              }}
            >
              <h2 className="text-page-title font-bold">Sign in</h2>
              <p className="mt-1 text-small text-ink-muted">
                Use the work e-mail your administrator registered.
              </p>
              <div className="mt-6 flex flex-col gap-4">
                <TextField
                  label="Work e-mail"
                  type="email"
                  autoComplete="username"
                  autoFocus
                  value={email}
                  onChange={(e) => {
                    setEmail(e.target.value)
                    setError('')
                  }}
                />
                <TextField
                  label="Password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => {
                    setPassword(e.target.value)
                    setError('')
                  }}
                />
                {error && (
                  <p
                    role="alert"
                    className="rounded-lg bg-danger-soft px-3 py-2.5 text-small text-danger"
                  >
                    {error}
                  </p>
                )}
                <Button type="submit" className="mt-2 w-full">
                  Sign in
                </Button>
                <button
                  type="button"
                  onClick={() => {
                    setMode('forgot')
                    setError('')
                  }}
                  className="text-small font-semibold text-brand hover:underline"
                >
                  Forgot password?
                </button>
              </div>
            </form>
          )}

          {mode === 'sign-in' && (
            <div className="mt-10 border-t border-line pt-4 text-center text-caption text-ink-subtle">
              Prototype with sample data.{' '}
              <button
                type="button"
                className="font-semibold text-brand hover:underline"
                onClick={() => {
                  resetSampleData()
                  setWasReset(true)
                }}
              >
                Reset sample data
              </button>
              {wasReset && (
                <span className="block text-success">Sample data is back to the start.</span>
              )}
            </div>
          )}

          {mode === 'forgot' && (
            <form
              noValidate
              onSubmit={(e) => {
                e.preventDefault()
                if (!/\S+@\S+\.\S+/.test(email)) setError('Enter your work e-mail.')
                else setMode('sent')
              }}
            >
              <h2 className="text-page-title font-bold">Reset your password</h2>
              <p className="mt-1 text-small text-ink-muted">
                We will e-mail you a link to choose a new password.
              </p>
              <div className="mt-6 flex flex-col gap-4">
                <TextField
                  label="Work e-mail"
                  type="email"
                  value={email}
                  onChange={(e) => {
                    setEmail(e.target.value)
                    setError('')
                  }}
                  error={error || undefined}
                />
                <Button type="submit" className="w-full">
                  Send reset link
                </Button>
                <button
                  type="button"
                  onClick={() => {
                    setMode('sign-in')
                    setError('')
                  }}
                  className="text-small font-semibold text-brand hover:underline"
                >
                  Back to sign in
                </button>
              </div>
            </form>
          )}

          {mode === 'sent' && (
            <div>
              <h2 className="text-page-title font-bold">Check your e-mail</h2>
              <p className="mt-2 text-body text-ink-muted">
                If an account exists for <b className="text-ink">{email}</b>, a reset link is on its
                way. The link works for one hour.
              </p>
              <Button
                variant="secondary"
                className="mt-6 w-full"
                onClick={() => setMode('sign-in')}
              >
                Back to sign in
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
