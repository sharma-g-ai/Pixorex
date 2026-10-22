/// <reference types="vite/client" />

interface ImportMetaEnv {
  /**
   * Set only for a role demo build (e.g. u01): the app starts signed in as that sample user
   * and keeps navigation inside the page, so it runs where the address bar cannot change.
   */
  readonly VITE_DEMO_USER?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
