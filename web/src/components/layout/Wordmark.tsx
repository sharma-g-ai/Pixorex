/** "PPG | SeaStock". tone 'dark' for white backgrounds (sign-in). */
export function Wordmark({ tone = 'light' }: { tone?: 'light' | 'dark' }) {
  return (
    <div className="flex items-baseline gap-2" aria-label="PPG SeaStock">
      <span
        className={`text-[22px] font-extrabold tracking-tight ${tone === 'light' ? 'text-white' : 'text-brand-dark'}`}
      >
        PPG
      </span>
      <span
        className={`text-lg font-light ${tone === 'light' ? 'text-white/40' : 'text-ink-subtle'}`}
      >
        |
      </span>
      <span className="text-lg font-bold tracking-tight text-brand-accent">SeaStock</span>
    </div>
  )
}
