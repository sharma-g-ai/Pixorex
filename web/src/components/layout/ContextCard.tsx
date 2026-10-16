interface ContextCardProps {
  label: string
  title: string
  detail?: string
}

/** The translucent card at the top of the sidebar ("Company" / "Business unit"). */
export function ContextCard(props: ContextCardProps) {
  return (
    <div className="rounded-lg bg-white/10 px-3 py-2.5">
      <ContextCardText {...props} />
    </div>
  )
}

/** The card's text, also used inside the unit switcher button. */
export function ContextCardText({ label, title, detail }: ContextCardProps) {
  return (
    <div className="min-w-0">
      <div className="text-label font-bold tracking-wider text-white/55 uppercase">{label}</div>
      <div className="mt-0.5 truncate text-body font-semibold text-white">{title}</div>
      {detail && <div className="text-meta text-white/60">{detail}</div>}
    </div>
  )
}
