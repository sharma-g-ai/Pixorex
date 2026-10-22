import { useNavigate } from 'react-router'
import { Button } from '../../components/Button'
import { Wordmark } from '../../components/layout/Wordmark'
import { TextField } from '../../components/TextField'

/** Sign-in. The sign-in method (SSO, e-mail and password) is not set by the BRD yet (D-11). */
export function SignInPage() {
  const navigate = useNavigate()
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
        <form
          className="w-full max-w-90"
          onSubmit={(e) => {
            e.preventDefault()
            navigate('/')
          }}
        >
          <div className="mb-8 lg:hidden">
            <Wordmark tone="dark" />
          </div>
          <h2 className="text-page-title font-bold">Sign in</h2>
          <p className="mt-1 text-small text-ink-muted">
            Use the work e-mail your administrator registered.
          </p>
          <div className="mt-6 flex flex-col gap-4">
            <TextField label="Work e-mail" type="email" defaultValue="dana.whitfield@ppg.example" />
            <TextField label="Password" type="password" defaultValue="prototype" />
            <Button type="submit" className="mt-2 w-full">
              Sign in
            </Button>
            <button type="button" className="text-small font-semibold text-brand hover:underline">
              Forgot password?
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
