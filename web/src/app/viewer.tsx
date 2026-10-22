import { createContext, useContext, useState, type ReactNode } from 'react'
import type { User } from '../data/model'
import { users } from '../data/sample'

/**
 * Who is signed in. Static screens: accounts are the sample users, all with one sample
 * password, and the session lasts until the tab closes. The real sign-in method is open (D-11).
 */
export const SAMPLE_PASSWORD = 'SeaStock@2026'

export type SignInResult = { ok: true; user: User } | { ok: false; error: string }

interface Session {
  user: User | null
  signIn: (email: string, password: string) => SignInResult
  signOut: () => void
}

const SessionContext = createContext<Session | null>(null)

const KEY = 'seastock.session'

function stored(): string | null {
  try {
    return sessionStorage.getItem(KEY)
  } catch {
    return null
  }
}

function remember(id: string | null) {
  try {
    if (id) sessionStorage.setItem(KEY, id)
    else sessionStorage.removeItem(KEY)
  } catch {
    // Storage blocked: the session lasts until reload.
  }
}

/** Checks the e-mail and password; the role and scope then decide what the user sees. */
export function checkSignIn(email: string, password: string): SignInResult {
  const user = users.find((u) => u.email.toLowerCase() === email.trim().toLowerCase())
  if (!user || password !== SAMPLE_PASSWORD)
    return { ok: false, error: 'E-mail or password is incorrect.' }
  if (user.status === 'disabled')
    return {
      ok: false,
      error: 'This account is disabled. Ask your administrator to turn it back on.',
    }
  if (user.status === 'invited')
    return {
      ok: false,
      error: 'This account is not set up yet. Open the invite e-mail to set your password.',
    }
  return { ok: true, user }
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [userId, setUserId] = useState(stored)
  const user = users.find((u) => u.id === userId && u.status === 'active') ?? null
  const session: Session = {
    user,
    signIn: (email, password) => {
      const result = checkSignIn(email, password)
      if (result.ok) {
        setUserId(result.user.id)
        remember(result.user.id)
      }
      return result
    },
    signOut: () => {
      setUserId(null)
      remember(null)
    },
  }
  return <SessionContext value={session}>{children}</SessionContext>
}

export function useSession(): Session {
  const session = useContext(SessionContext)
  if (!session) throw new Error('useSession needs a SessionProvider')
  return session
}

/** The signed-in user, for pages behind sign-in (the Layout sends everyone else to sign-in). */
export function useViewer(): { user: User } {
  const { user } = useSession()
  if (!user) throw new Error('useViewer is only for signed-in pages')
  return { user }
}
