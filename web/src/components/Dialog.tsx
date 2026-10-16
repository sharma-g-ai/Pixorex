import { useEffect, useId, useRef, type ReactNode } from 'react'

interface DialogProps {
  title: string
  onClose: () => void
  /** Buttons at the bottom right. */
  footer: ReactNode
  children: ReactNode
}

/**
 * Modal dialog on the native <dialog> element: the browser keeps focus inside,
 * Esc closes it and the page behind is inert. Render it only while open.
 */
export function Dialog({ title, onClose, footer, children }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const titleId = useId()

  useEffect(() => {
    const dialog = ref.current
    if (!dialog || dialog.open) return
    // jsdom (tests) has no showModal; a plain open attribute is enough there.
    if (typeof dialog.showModal === 'function') dialog.showModal()
    else dialog.setAttribute('open', '')
  }, [])

  return (
    <dialog
      ref={ref}
      aria-labelledby={titleId}
      onCancel={(e) => {
        e.preventDefault()
        onClose()
      }}
      className="m-auto w-full max-w-130 rounded-2xl bg-surface p-0 text-ink shadow-2xl backdrop:bg-ink/45"
    >
      <div className="flex flex-col gap-4 px-7 pt-6.5 pb-5.5">
        <h2 id={titleId} className="text-lg font-bold">
          {title}
        </h2>
        <div className="text-body leading-normal text-ink-muted">{children}</div>
        <div className="flex justify-end gap-2.5">{footer}</div>
      </div>
    </dialog>
  )
}
