import type { ReactNode } from 'react'
import wordmark from '../../assets/pixorex-wordmark.png'

/** White card on the navy background, used before the dashboard opens (canvas BU 01, 33). */
export function AuthCard({ children }: { children: ReactNode }) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-linear-to-br from-brand-navy to-brand-navy-dark p-6">
      <div className="flex w-full max-w-110 flex-col gap-3.5 rounded-2xl bg-surface px-10 pt-10 pb-8 shadow-2xl">
        <img src={wordmark} alt="Pixorex" className="mx-auto mb-1.5 block h-10 w-auto" />
        {children}
      </div>
    </main>
  )
}
