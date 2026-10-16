import type { ReactNode } from 'react'
import { NavLink } from 'react-router'
import wordmark from '../../assets/pixorex-wordmark-white.png'
import type { NavItem } from '../../app/navigation'
import { Avatar } from '../Avatar'
import { Icon } from '../icons'

interface SidebarProps {
  /** Company card (EA) or unit switcher (BU Admin), above the menu. */
  context: ReactNode
  items: NavItem[]
  userName: string
  roleLabel: string
  onSignOut: () => void
}

export function Sidebar({ context, items, userName, roleLabel, onSignOut }: SidebarProps) {
  return (
    <aside className="flex w-60 shrink-0 flex-col bg-linear-to-b from-brand-navy to-brand-navy-dark pt-5.5 pb-4.5">
      <div className="px-5.5 pb-5.5">
        <img src={wordmark} alt="Pixorex" className="block h-6.5 w-auto" />
      </div>

      <div className="mx-3.5 mb-4.5">{context}</div>

      <nav aria-label="Main" className="flex flex-col gap-0.5 px-3">
        {items.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            className={({ isActive }) =>
              `flex items-center gap-2.5 rounded-lg px-3 py-2.5 text-body ${
                isActive ? 'bg-white/15 font-bold text-white' : 'text-white/70 hover:bg-white/10'
              }`
            }
          >
            <Icon name={item.icon} />
            {item.label}
          </NavLink>
        ))}
      </nav>

      <div className="mt-auto flex items-center gap-2.5 border-t border-white/10 px-4.5 pt-3.5">
        <Avatar name={userName} tone="on-dark" size="md" />
        <div className="min-w-0 grow">
          <div className="truncate text-body-sm font-semibold text-white">{userName}</div>
          <div className="text-caption text-white/60">{roleLabel}</div>
        </div>
        <button
          type="button"
          onClick={onSignOut}
          aria-label="Sign out"
          title="Sign out"
          className="rounded-md p-1.5 text-white/70 hover:bg-white/10 hover:text-white"
        >
          <Icon name="sign-out" />
        </button>
      </div>
    </aside>
  )
}
