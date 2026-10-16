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
export async function signIn(returnTo: string, loginHint?: string): Promise<void> {
  const um = userManager()
  if (!um) return
  await um.signinRedirect({
    state: { returnTo } satisfies SignInState,
    ...(loginHint ? { login_hint: loginHint } : {}),
  })
}

let completing: { url: string; result: Promise<string> } | null = null

/**
 * Finishes the Keycloak redirect and says where the user was going. The code in the URL can be
 * used once, so a second call for the same URL (React runs effects twice in development, or a
 * double render) shares the first call's result instead of failing.
 */
export function completeSignIn(
  url: string = window.location.href,
  um: Pick<UserManager, 'signinRedirectCallback'> | null = userManager(),
): Promise<string> {
  if (!um) return Promise.resolve('/')
  if (completing?.url !== url) {
    const result = um.signinRedirectCallback(url).then((user) => {
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
