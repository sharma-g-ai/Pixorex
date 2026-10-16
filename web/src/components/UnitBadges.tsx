import { Badge } from './Badge'

/** Unit names as grey pills. */
export function UnitBadges({ names }: { names: string[] }) {
  return (
    <div className="flex flex-wrap gap-1">
      {names.map((name) => (
        <Badge key={name} tone="neutral">
          {name}
        </Badge>
      ))}
    </div>
  )
}
