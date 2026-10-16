import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useNavigate } from 'react-router'
import { z } from 'zod'
import { useAcceptInvite, useInvitePreview, type InvitePreview } from '../../api/activation'
import { errorMessage } from '../../api/client'
import { authConfig } from '../../auth/authConfig'
import { signIn } from '../../auth/session'
import { Alert } from '../../components/Alert'
import { Badge } from '../../components/Badge'
import { Button } from '../../components/Button'
import { TextField } from '../../components/TextField'
import { AuthCard } from '../../components/layout/AuthCard'
import { fullNameField } from '../../lib/validation'
import { timeLeft } from '../../lib/time'
import { zodResolver } from '../../lib/zodResolver'
import { inviteProblem, isDeadInvite, takeInviteToken } from './inviteLink'

const schema = z.object({ full_name: fullNameField() })
type Values = z.infer<typeof schema>

/**
 * A BU Admin opens the invite link and activates (canvas BU 01; contracts 1.6, 1.7).
 * Keycloak then emails the code that verifies the address (BU 33, decision D-08).
 */
export function ActivatePage() {
  // Read once, then take the token out of the address bar and history (D-11).
  const [token] = useState(() => takeInviteToken())

  const preview = useInvitePreview(token)

  if (!token) {
    return (
      <Problem
        title="This invite link is incomplete"
        text="Open the whole link from your invite email. If it still fails, ask your Enterprise Admin to send a new invite."
      />
    )
  }
  if (preview.isPending) return <AuthCard>Checking your invite…</AuthCard>
  if (preview.isError) return <Problem {...inviteProblem(preview.error)} />
  if (preview.data.role === 'field_technician') {
    return (
      <Problem
        title="Activate in the mobile app"
        text="This invite is for a field technician. Open the link on your phone with the Pixorex app installed."
      />
    )
  }
  return <ActivateForm token={token} invite={preview.data} />
}

function ActivateForm({ token, invite }: { token: string; invite: InvitePreview }) {
  const accept = useAcceptInvite()
  const navigate = useNavigate()
  const [deadLink, setDeadLink] = useState<unknown>(null)
  const [error, setError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<Values>({ resolver: zodResolver(schema), defaultValues: { full_name: '' } })
  const left = timeLeft(invite.expires_at)

  const onSubmit = async ({ full_name }: Values) => {
    setError(null)
    try {
      await accept.mutateAsync({ token, full_name })
    } catch (err) {
      // A dead link replaces the form; anything else (bad name, network) keeps it.
      if (isDeadInvite(err)) setDeadLink(err)
      else setError(errorMessage(err))
      return
    }
    // Keycloak emails the code that verifies the address (D-08); in mock mode go straight in.
    if (authConfig.mode === 'oidc') await signIn('/', invite.email)
    else await navigate('/', { replace: true })
  }

  if (deadLink) return <Problem {...inviteProblem(deadLink)} />

  return (
    <AuthCard>
      <h1 className="text-page-title font-bold">Activate your account</h1>
      <p className="-mt-1.5 text-body-sm text-ink-muted">
        You've been added to Pixorex as a BU Admin. Check your details, then activate.
      </p>
      {error && <Alert tone="danger">{error}</Alert>}
      <form noValidate onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-3.5">
        <TextField
          label="Full name"
          autoComplete="name"
          autoFocus
          error={errors.full_name?.message}
          {...register('full_name')}
        />
        <div>
          <TextField label="Work email" value={invite.email} readOnly disabled />
          <p className="mt-1.5 text-xs text-ink-subtle">From your invite — can't be changed</p>
        </div>
        <section aria-label="Your business units">
          <h2 className="mb-1.5 text-small font-semibold text-ink-muted">
            {invite.units.length === 1 ? 'Your business unit' : 'Your business units'}
          </h2>
          <ul className="flex flex-col gap-2">
            {invite.units.map((u) => (
              <li
                key={u.bu_id}
                className="flex items-center justify-between gap-3 rounded-lg border border-line bg-page px-3.5 py-2.75"
              >
                <div className="min-w-0">
                  <div className="truncate text-body font-semibold">{u.name}</div>
                  <div className="text-meta text-ink-subtle">
                    Assigned by {invite.invited_by_name} (Enterprise Admin)
                  </div>
                </div>
                <Badge tone="neutral">BU Admin</Badge>
              </li>
            ))}
          </ul>
        </section>
        <Button type="submit" disabled={isSubmitting} className="h-12 text-card-title">
          {isSubmitting ? 'Activating…' : 'Activate account'}
        </Button>
      </form>
      <p className="text-center text-meta text-ink-subtle">
        No password needed — you sign in with a code sent to your email.{' '}
        {left ? `This invite link expires in ${left.replace(' left', '')}.` : ''}
      </p>
    </AuthCard>
  )
}

function Problem({
  title,
  text,
  canSignIn = false,
}: {
  title: string
  text: string
  canSignIn?: boolean
}) {
  const navigate = useNavigate()
  return (
    <AuthCard>
      <h1 className="text-page-title font-bold">{title}</h1>
      <p className="text-body-sm text-ink-muted">{text}</p>
      {canSignIn && (
        <Button
          className="h-12"
          onClick={() => (authConfig.mode === 'oidc' ? void signIn('/') : void navigate('/'))}
        >
          Sign in
        </Button>
      )}
    </AuthCard>
  )
}
