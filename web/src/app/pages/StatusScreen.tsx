import type { ReactNode } from 'react'
import icon from '../../assets/pixorex-icon.png'

interface StatusScreenProps {
  title: string
  children?: ReactNode
}

/** Full-page message outside the shell: loading, errors, no access. */
export function StatusScreen({ title, children }: StatusScreenProps) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-page p-6">
      <div className="w-full max-w-md rounded-xl border border-line bg-surface p-8 text-center">
        <img src={icon} alt="" className="mx-auto mb-4 size-10" />
        <h1 className="text-lg font-bold">{title}</h1>
        {children && <div className="mt-2 text-body text-ink-muted">{children}</div>}
      </div>
    </main>
  )
}
