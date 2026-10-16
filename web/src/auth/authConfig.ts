/**
 * How the dashboard signs in (decision D-11).
 * - `oidc`: Keycloak, Authorization Code + PKCE. Needs VITE_OIDC_AUTHORITY and VITE_OIDC_CLIENT_ID.
 * - `mock`: local development against the mock API only; the dev proxy adds a placeholder token.
 * - `missing`: a production build without the OIDC settings. The app refuses to run.
 */
export type AuthMode = 'oidc' | 'mock' | 'missing'

export interface OidcSettings {
  /** Keycloak realm URL, e.g. https://id.example.com/realms/pixorex */
  authority: string
  /** Public client of the dashboard, e.g. pixorex-web */
  clientId: string
}

interface Env {
  DEV: boolean
  VITE_OIDC_AUTHORITY?: string
  VITE_OIDC_CLIENT_ID?: string
}

export function readAuthConfig(env: Env = import.meta.env): {
  mode: AuthMode
  oidc: OidcSettings | null
} {
  const authority = env.VITE_OIDC_AUTHORITY?.trim()
  const clientId = env.VITE_OIDC_CLIENT_ID?.trim()
  if (authority && clientId) return { mode: 'oidc', oidc: { authority, clientId } }
  return { mode: env.DEV ? 'mock' : 'missing', oidc: null }
}

export const authConfig = readAuthConfig()
