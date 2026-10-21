import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { readAuthConfig } from './authConfig'
import { AuthGate } from './AuthGate'
import { SignedOutPage } from './AuthPages'
import { completeSignIn, handleAccountRemoved, handleUnauthorized, safeReturnPath } from './session'

describe('auth config (D-11)', () => {
  it('uses OIDC when both settings are present, trimmed', () => {
    expect(
      readAuthConfig({
        DEV: false,
        VITE_OIDC_AUTHORITY: ' https://id.example.com/realms/pixorex ',
        VITE_OIDC_CLIENT_ID: 'pixorex-web',
      }),
    ).toEqual({
      mode: 'oidc',
      oidc: { authority: 'https://id.example.com/realms/pixorex', clientId: 'pixorex-web' },
    })
  })

  it('falls back to the mock only in development; a production build without settings refuses', () => {
    expect(readAuthConfig({ DEV: true }).mode).toBe('mock')
    expect(readAuthConfig({ DEV: false }).mode).toBe('missing')
    expect(readAuthConfig({ DEV: false, VITE_OIDC_AUTHORITY: 'https://x' }).mode).toBe('missing')
  })
})

describe('return path after sign-in (open-redirect guard)', () => {
  it.each([
    ['/scans?unit=p04', '/scans?unit=p04'],
    ['/', '/'],
    [undefined, '/'],
    ['https://evil.example', '/'],
    ['//evil.example', '/'],
    ['/\\evil.example', '/'],
    ['javascript:alert(1)', '/'],
  ])('%s → %s', (input, expected) => {
    expect(safeReturnPath(input)).toBe(expected)
  })
})

describe('finishing sign-in', () => {
  it('GIVEN the callback runs twice for one code THEN the code is exchanged once and both get the page', async () => {
    const callback = vi.fn().mockResolvedValue({ state: { returnTo: '/scans?unit=p04' } })
    const um = { signinRedirectCallback: callback }
    const url = 'http://localhost/auth/callback?code=one-time&state=s1'
    const [a, b] = await Promise.all([
      completeSignIn(url, um as never),
      completeSignIn(url, um as never),
    ])
    expect(callback).toHaveBeenCalledTimes(1)
    expect([a, b]).toEqual(['/scans?unit=p04', '/scans?unit=p04'])
  })

  it('GIVEN a hostile return path in the state THEN goes home instead', async () => {
    const um = {
      signinRedirectCallback: vi.fn().mockResolvedValue({ state: { returnTo: '//evil.example' } }),
    }
    expect(await completeSignIn('http://localhost/auth/callback?code=two', um as never)).toBe('/')
  })
})

describe('401 handling (loop guard)', () => {
  const store = () => {
    const data = new Map<string, string>()
    return {
      getItem: (k: string) => data.get(k) ?? null,
      setItem: (k: string, v: string) => void data.set(k, v),
    } as unknown as Storage
  }
  const um = () => ({ removeUser: vi.fn(), signinRedirect: vi.fn() })

  it('GIVEN a 401 THEN signs in again once, back to the same page', async () => {
    const fake = um()
    expect(await handleUnauthorized('/scans', 1_000_000, store(), fake as never)).toBe(true)
    expect(fake.removeUser).toHaveBeenCalled()
    expect(fake.signinRedirect).toHaveBeenCalledWith({ state: { returnTo: '/scans' } })
  })

  it('GIVEN a second 401 within 30 s THEN stops instead of looping', async () => {
    const s = store()
    const fake = um()
    await handleUnauthorized('/scans', 1_000_000, s, fake as never)
    expect(await handleUnauthorized('/scans', 1_020_000, s, fake as never)).toBe(false)
    expect(fake.signinRedirect).toHaveBeenCalledTimes(1)
    expect(await handleUnauthorized('/scans', 1_040_001, s, fake as never)).toBe(true)
  })

  it('GIVEN mock mode (no OIDC client) THEN does nothing', async () => {
    expect(await handleUnauthorized('/', 0, store(), null)).toBe(false)
  })
})

describe('403 account-removed', () => {
  it('GIVEN the account was removed THEN clears the user and leaves without signing in again', async () => {
    const um = { removeUser: vi.fn() }
    const leave = vi.fn()
    await handleAccountRemoved(um as never, leave)
    expect(um.removeUser).toHaveBeenCalled()
    expect(leave).toHaveBeenCalledWith('/signed-out?reason=removed')
  })
})

const signIn = vi.fn()
const getUser = vi.fn()
vi.mock('./session', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  signIn: (...a: unknown[]) => signIn(...a),
  userManager: () => ({
    getUser,
    events: { addAccessTokenExpired: vi.fn(), removeAccessTokenExpired: vi.fn() },
  }),
}))

describe('AuthGate', () => {
  beforeEach(() => {
    signIn.mockReset().mockResolvedValue(undefined)
    getUser.mockReset()
  })
  const gate = (mode: 'oidc' | 'mock' | 'missing', path = '/scans?unit=p04') =>
    render(
      <MemoryRouter initialEntries={[path]}>
        <AuthGate mode={mode}>
          <h1>Dashboard</h1>
        </AuthGate>
      </MemoryRouter>,
    )

  it('GIVEN a production build without settings THEN refuses to run', () => {
    gate('missing')
    expect(screen.getByRole('heading', { name: "Sign-in isn't configured" })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Dashboard' })).not.toBeInTheDocument()
  })

  it('GIVEN mock mode THEN shows the dashboard', () => {
    gate('mock')
    expect(screen.getByRole('heading', { name: 'Dashboard' })).toBeInTheDocument()
  })

  it('GIVEN a valid session THEN shows the dashboard', async () => {
    getUser.mockResolvedValue({ expired: false, access_token: 't' })
    gate('oidc')
    expect(await screen.findByRole('heading', { name: 'Dashboard' })).toBeInTheDocument()
    expect(signIn).not.toHaveBeenCalled()
  })

  it('GIVEN no or an expired session THEN goes to Keycloak and comes back to the same page', async () => {
    getUser.mockResolvedValue({ expired: true })
    gate('oidc')
    await waitFor(() => expect(signIn).toHaveBeenCalledWith('/scans?unit=p04'))
    expect(screen.queryByRole('heading', { name: 'Dashboard' })).not.toBeInTheDocument()
  })

  it('GIVEN Keycloak cannot be reached THEN says so instead of a blank page', async () => {
    getUser.mockResolvedValue(null)
    signIn.mockRejectedValue(new Error('network'))
    gate('oidc')
    expect(
      await screen.findByRole('heading', { name: "We couldn't reach sign-in" }),
    ).toBeInTheDocument()
  })
})

describe('after sign-out (canvas: straight to sign-in)', () => {
  beforeEach(() => signIn.mockReset().mockResolvedValue(undefined))
  const signedOut = (mode: 'oidc' | 'mock', path = '/signed-out') =>
    render(
      <MemoryRouter initialEntries={[path]}>
        <SignedOutPage mode={mode} />
      </MemoryRouter>,
    )

  it('GIVEN Keycloak THEN goes straight to sign-in, no signed-out page', async () => {
    signedOut('oidc')
    await waitFor(() => expect(signIn).toHaveBeenCalledWith('/'))
    expect(screen.queryByRole('heading', { name: "You're signed out" })).not.toBeInTheDocument()
  })

  it('GIVEN mock mode (no sign-in screen) THEN shows the signed-out card', () => {
    signedOut('mock')
    expect(screen.getByRole('heading', { name: "You're signed out" })).toBeInTheDocument()
    expect(signIn).not.toHaveBeenCalled()
  })

  it('GIVEN account removed THEN stays put and does not open Keycloak sign-in', () => {
    signedOut('oidc', '/signed-out?reason=removed')
    expect(screen.getByRole('heading', { name: 'Your access was removed' })).toBeInTheDocument()
    expect(signIn).not.toHaveBeenCalled()
  })
})
