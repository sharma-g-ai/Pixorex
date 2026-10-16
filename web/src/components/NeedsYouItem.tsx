import { Link } from 'react-router'
import { Icon, type IconName } from './icons'

const tones = {
  warning: { box: 'bg-warning-soft text-warning', count: 'text-warning' },
  navy: { box: 'bg-brand-navy-soft text-brand-navy', count: 'text-brand-navy' },
}

export interface NeedsYouItemProps {
  icon: IconName
  tone: keyof typeof tones
  count: number
  title: string
  text: string
  link?: { to: string; label: string }
}

/** A count that needs attention, what it means, and where to act (canvas EA 03, BU 03). */
export function NeedsYouItem({ icon, tone, count, title, text, link }: NeedsYouItemProps) {
  return (
    <section
      aria-label={title}
      className="flex min-w-0 flex-col gap-3 rounded-xl border border-line bg-surface px-4.5 py-4"
    >
      <div className="flex items-center justify-between">
        <div className={`flex size-9.5 items-center justify-center rounded-lg ${tones[tone].box}`}>
          <Icon name={icon} size={18} />
        </div>
        <div className={`text-stat font-bold ${tones[tone].count}`}>{count}</div>
      </div>
      <div>
        <h3 className="text-sm font-bold">{title}</h3>
        <p className="mt-0.5 text-small leading-snug text-ink-muted">{text}</p>
      </div>
      {link && (
        <Link to={link.to} className="mt-auto text-body-sm font-bold text-brand-navy">
          {link.label}
        </Link>
      )}
    </section>
  )
}
