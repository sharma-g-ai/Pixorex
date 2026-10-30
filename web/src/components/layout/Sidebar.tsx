import { NavLink } from 'react-router'
import type { NavSection } from '../../app/navigation'
import { useViewer } from '../../app/viewer'
import { scopeLabel } from '../../data/queries'
import { roleInfo } from '../../data/roles'
import { Avatar } from '../Avatar'
import { Icon } from '../icons'
import { Wordmark } from './Wordmark'

interface SidebarProps {
  sections: NavSection[]
  onSignOut: () => void
}

export function Sidebar({ sections, onSignOut }: SidebarProps) {
  const { user } = useViewer()
  const role = roleInfo(user.role)

  return (
    <aside className="flex w-62 shrink-0 flex-col bg-brand-dark pt-5 pb-4">
      <div className="px-5.5 pb-4">
        <Wordmark />
      </div>

      <div className="mx-3.5 mb-3 rounded-lg bg-white/8 px-3.5 py-2.5">
        <div className="text-label font-bold tracking-wider text-white/50 uppercase">
          {user.role === 'ppg-admin' ? 'PPG' : 'Customer'} scope
        </div>
        <div className="mt-0.5 truncate text-body-sm font-semibold text-white">
          {scopeLabel(user)}
        </div>
      </div>

      <nav
        aria-label="Main"
        className="flex min-h-0 grow flex-col gap-3 overflow-y-auto px-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {sections.map((section, i) => (
          <div key={i} className="flex flex-col gap-0.5">
            {section.title && (
              <div className="px-3 pb-1 text-label font-bold tracking-wider text-white/45 uppercase">
                {section.title}
              </div>
            )}
            {section.items.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                className={({ isActive }) =>
                  `flex items-center gap-2.5 rounded-lg px-3 py-1.75 text-body ${
                    isActive
                      ? 'bg-brand font-semibold text-white'
                      : 'text-white/70 hover:bg-white/10 hover:text-white'
                  }`
                }
              >
                <Icon name={item.icon} />
                {item.label}
              </NavLink>
            ))}
          </div>
        ))}
      </nav>

      <div className="mt-3 flex items-center gap-2.5 border-t border-white/10 px-4.5 pt-3.5">
        <Avatar name={user.name} tone="on-dark" size="md" />
        <div className="min-w-0 grow">
          <div className="truncate text-body-sm font-semibold text-white">{user.name}</div>
          <div className="truncate text-caption text-white/60">{role.label}</div>
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
