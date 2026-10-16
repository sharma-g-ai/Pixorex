/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Keycloak realm URL for sign-in (D-11). Unset in development = mock sign-in. */
  readonly VITE_OIDC_AUTHORITY?: string
  /** Keycloak public client of the dashboard (D-11). */
  readonly VITE_OIDC_CLIENT_ID?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
