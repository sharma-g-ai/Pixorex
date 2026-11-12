import { UserManager, WebStorageStateStore } from 'oidc-client-ts'
import { authConfig, type OidcSettings } from './authConfig'

/** Where to go back to after Keycloak, kept in the OIDC state. */
interface SignInState {
  returnTo: string
}

let manager: UserManager | null = null

/** The one OIDC client of the app (D-11). Null in mock mode. */
export function userManager(settings: OidcSettings | null = authConfig.oidc): UserManager | null {
  if (!settings) return null
  manager ??= new UserManager({
    authority: settings.authority,
    client_id: settings.clientId,
    redirect_uri: `${window.location.origin}/auth/callback`,
    post_logout_redirect_uri: `${window.location.origin}/signed-out`,
    response_type: 'code',
    scope: 'openid profile email',
    // Tokens live for this tab only; never in localStorage (D-11).
    userStore: new WebStorageStateStore({ store: window.sessionStorage }),
    // Renews with the refresh token before expiry; no hidden iframe.
    automaticSilentRenew: true,
    monitorSession: false,
  })
  return manager
}

/** The access token for API calls, or null when not signed in (or in mock mode). */
export async function getAccessToken(): Promise<string | null> {
  const user = await userManager()?.getUser()
  return user && !user.expired ? user.access_token : null
}

/** Sends the browser to Keycloak. `loginHint` pre-fills the email (activation, D-08). */
export async function signIn(
  returnTo: string,
  loginHint?: string,
  um: Pick<UserManager, 'signinRedirect'> | null = userManager(),
): Promise<void> {
  if (!um) return
  await um.signinRedirect({
    state: { returnTo } satisfies SignInState,
    ...(loginHint ? { login_hint: loginHint } : {}),
  })
}

// Sign-in as one particular person (right after accepting an invite). Keycloak reuses a session
// already in this browser (its cookie step runs first and ignores login_hint), so whoever was
// signed in before — e.g. the EA who sent the invite — would come back instead, and the invited
// person would never get their code. prompt=login cannot fix it: Keycloak then re-authenticates
// the existing user and refuses a different one. So the callback checks who came back and, if it
// is someone else, ends that session and signs in again as the invited email (keys per tab).
const EXPECTED_EMAIL_KEY = 'pixorex.auth.expected_email'
const SWITCHED_KEY = 'pixorex.auth.switched'

/** Signs in as `email`; another person's Keycloak session in this browser is ended first. */
export async function signInAs(
  returnTo: string,
  email: string,
  um: Pick<UserManager, 'signinRedirect'> | null = userManager(),
  storage: Storage = window.sessionStorage,
): Promise<void> {
  if (!um) return
  storage.setItem(EXPECTED_EMAIL_KEY, email.trim().toLowerCase())
  storage.removeItem(SWITCHED_KEY)
  await signIn(returnTo, email, um)
}

/** After signInAs ended someone else's session: the email to sign in as now, else null. */
export function pendingSignInEmail(storage: Storage = window.sessionStorage): string | null {
  return storage.getItem(SWITCHED_KEY) ? storage.getItem(EXPECTED_EMAIL_KEY) : null
}

let completing: { url: string; result: Promise<string | null> } | null = null

type CallbackManager = Pick<UserManager, 'signinRedirectCallback'> &
  Partial<Pick<UserManager, 'removeUser' | 'signoutRedirect'>>

/**
 * Finishes the Keycloak redirect and says where the user was going. The code in the URL can be
 * used once, so a second call for the same URL (React runs effects twice in development, or a
 * double render) shares the first call's result instead of failing.
 * Resolves null when the browser is on its way to Keycloak again (wrong person, see signInAs).
 */
export function completeSignIn(
  url: string = window.location.href,
  um: CallbackManager | null = userManager(),
  storage: Storage = window.sessionStorage,
): Promise<string | null> {
  if (!um) return Promise.resolve('/')
  if (completing?.url !== url) {
    const result = um.signinRedirectCallback(url).then(async (user) => {
      const expected = storage.getItem(EXPECTED_EMAIL_KEY)
      const email = String(user.profile?.email ?? '').toLowerCase()
      if (expected && email !== expected && !storage.getItem(SWITCHED_KEY)) {
        // Someone else's session came back: end it, then /signed-out signs in as `expected`.
        storage.setItem(SWITCHED_KEY, '1')
        await um.removeUser?.()
        await um.signoutRedirect?.({ id_token_hint: user.id_token })
        return null
      }
      // Done (right person, or already switched once: never loop).
      storage.removeItem(EXPECTED_EMAIL_KEY)
      storage.removeItem(SWITCHED_KEY)
      const state = user.state as Partial<SignInState> | undefined
      return safeReturnPath(state?.returnTo)
    })
    completing = { url, result }
  }
  return completing.result
}

/** Ends the Keycloak session (after the API session, contract 1.3). */
export async function endKeycloakSession(): Promise<void> {
  const um = userManager()
  if (!um) return
  const user = await um.getUser()
  await um.removeUser()
  await um.signoutRedirect(user?.id_token ? { id_token_hint: user.id_token } : undefined)
}

/** Only paths inside this app; never an absolute or protocol-relative URL (open-redirect guard). */
export function safeReturnPath(path: string | undefined): string {
  if (!path || !path.startsWith('/') || path.startsWith('//') || path.startsWith('/\\')) return '/'
  return path
}

const LAST_REDIRECT_KEY = 'pixorex.auth.last_redirect'
const LOOP_WINDOW_MS = 30_000

/**
 * The API said 401: the token is missing, expired or its session was revoked (contract 1.3,
 * removal). Sign in again once; a second 401 within 30 s means sign-in cannot fix it, so stop
 * instead of bouncing between the app and Keycloak. Returns false when it stopped.
 */
export async function handleUnauthorized(
  returnTo: string,
  now: number = Date.now(),
  storage: Storage = window.sessionStorage,
  um: Pick<UserManager, 'removeUser' | 'signinRedirect'> | null = userManager(),
): Promise<boolean> {
  if (!um) return false
  const last = Number(storage.getItem(LAST_REDIRECT_KEY) ?? 0)
  if (now - last < LOOP_WINDOW_MS) return false
  storage.setItem(LAST_REDIRECT_KEY, String(now))
  await um.removeUser()
  await um.signinRedirect({ state: { returnTo } satisfies SignInState })
  return true
}

/**
 * The API said 403 account-removed: this person was removed from every unit. Clear local tokens
 * and leave the app — do not sign in again (Keycloak login is disabled server-side).
 */
export async function handleAccountRemoved(
  um: Pick<UserManager, 'removeUser'> | null = userManager(),
  leave: (path: string) => void = (path) => {
    window.location.replace(path)
  },
): Promise<void> {
  if (um) await um.removeUser()
  leave('/signed-out?reason=removed')
}
