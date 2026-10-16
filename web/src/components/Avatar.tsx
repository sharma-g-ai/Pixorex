import { initials } from '../lib/initials'

type AvatarTone = 'light' | 'on-dark'

const tones: Record<AvatarTone, string> = {
  light: 'bg-brand-navy-soft text-brand-navy',
  'on-dark': 'bg-white/20 text-white',
}

interface AvatarProps {
  name: string
  tone?: AvatarTone
  /** 'sm' 30 px (lists), 'md' 32 px (sidebar). */
  size?: 'sm' | 'md'
}

/** Initials in a circle. */
export function Avatar({ name, tone = 'light', size = 'sm' }: AvatarProps) {
  const box = size === 'sm' ? 'size-7.5 text-caption' : 'size-8 text-xs'
  return (
    <div
      aria-hidden="true"
      className={`flex shrink-0 items-center justify-center rounded-full font-bold ${box} ${tones[tone]}`}
    >
      {initials(name)}
    </div>
  )
}
