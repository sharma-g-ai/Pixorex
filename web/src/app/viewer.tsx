import { createContext, useContext, useState, type ReactNode } from 'react'
import type { User } from '../data/model'
import { users } from '../data/sample'

/**
 * Who is signed in. Static screens: a "Preview as" switcher picks a sample user, so each
 * role's view (FR-23, FR-24) can be shown without sign-in.
 */
interface Viewer {
  user: User
  setUserId: (id: string) => void
}

const ViewerContext = createContext<Viewer | null>(null)

/** One sample user per role, plus a second PPG User scoped by customer instead of region. */
export const previewUsers = ['u01', 'u02', 'u03', 'u06', 'u07', 'u12']

const KEY = 'seastock.preview-user'

function stored(): string {
  try {
    return sessionStorage.getItem(KEY) ?? 'u01'
  } catch {
    return 'u01'
  }
}

export function ViewerProvider({ children }: { children: ReactNode }) {
  const [userId, setUserId] = useState(stored)
  const user = users.find((u) => u.id === userId) ?? (users[0] as User)
  const choose = (id: string) => {
    setUserId(id)
    try {
      sessionStorage.setItem(KEY, id)
    } catch {
      // Storage blocked: the choice lasts until reload.
    }
  }
  return <ViewerContext value={{ user, setUserId: choose }}>{children}</ViewerContext>
}

export function useViewer(): Viewer {
  const viewer = useContext(ViewerContext)
  if (!viewer) throw new Error('useViewer needs a ViewerProvider')
  return viewer
}
