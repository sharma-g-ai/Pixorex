export type ButtonVariant =
  'primary' | 'secondary' | 'danger' | 'link' | 'danger-link' | 'inverse' | 'inverse-outline'

const boxed = 'rounded-lg border-[1.5px] px-4 py-2'

const variants: Record<ButtonVariant, string> = {
  primary: `${boxed} border-brand-navy bg-brand-navy text-white hover:bg-brand-navy-dark`,
  secondary: `${boxed} border-line-strong bg-surface text-ink hover:bg-page`,
  danger: `${boxed} border-danger bg-danger text-white hover:bg-danger-strong`,
  // On a navy bar (e.g. the selection bar in the review queue).
  inverse: `${boxed} border-surface bg-surface text-brand-navy hover:bg-brand-navy-tint`,
  'inverse-outline': `${boxed} border-white/50 text-white hover:bg-white/10`,
  // Text-only actions inside table rows ("Resend", "Remove").
  link: 'text-brand-navy hover:underline',
  'danger-link': 'text-danger hover:underline',
}

/**
 * Button styling, also for links that look like buttons:
 * <Link className={buttonClasses('primary')} to="...">.
 */
export function buttonClasses(variant: ButtonVariant = 'primary'): string {
  // justify-center: full-width buttons (activation, sign-in cards) keep their label centred.
  return `inline-flex items-center justify-center gap-2 whitespace-nowrap text-body font-semibold disabled:cursor-not-allowed disabled:opacity-60 ${variants[variant]}`
}
