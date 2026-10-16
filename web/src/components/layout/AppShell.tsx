import type { ReactNode } from 'react'
import { Outlet } from 'react-router'

interface AppShellProps {
  sidebar: ReactNode
}

/** Sidebar on the left, the current page on the right (canvas: 240 px sidebar). */
export function AppShell({ sidebar }: AppShellProps) {
  return (
    <div className="flex h-screen overflow-hidden bg-page">
      {sidebar}
      <main className="flex min-w-0 grow flex-col">
        <Outlet />
      </main>
    </div>
  )
}
