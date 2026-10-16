import { Avatar } from './Avatar'

interface PersonProps {
  name: string
  /** Grey second line, e.g. an email or "Also runs Plant 05". */
  detail?: string
}

/** Avatar with a name and an optional grey line, as in lists and cards. */
export function Person({ name, detail }: PersonProps) {
  return (
    <div className="flex items-center gap-2.5">
      <Avatar name={name} />
      <div className="min-w-0">
        <div className="truncate font-semibold">{name}</div>
        {detail && <div className="truncate text-xs text-ink-subtle">{detail}</div>}
      </div>
    </div>
  )
}
