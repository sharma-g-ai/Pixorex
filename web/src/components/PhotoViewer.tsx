import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'

export interface ViewerPhoto {
  no: number
  url: string
}

const MIN = 1
const MAX = 6

/**
 * Full-screen photo viewer over the page (native <dialog>: Esc closes, the page behind
 * is inert). Zoom with the wheel or the buttons, drag to move, rotate, and step through
 * the scan's photos. Replaces opening the signed photo link in a new tab, which also
 * expired after 15 minutes. Render it only while open.
 */
export function PhotoViewer({
  photos,
  start,
  onClose,
}: {
  photos: ViewerPhoto[]
  start: number
  onClose: () => void
}) {
  const ref = useRef<HTMLDialogElement>(null)
  const [index, setIndex] = useState(start)
  const [zoom, setZoom] = useState(1)
  const [turn, setTurn] = useState(0)
  const [offset, setOffset] = useState({ x: 0, y: 0 })
  const drag = useRef<{ x: number; y: number } | null>(null)
  const photo = photos[index]

  useEffect(() => {
    const dialog = ref.current
    if (!dialog || dialog.open) return
    if (typeof dialog.showModal === 'function') dialog.showModal()
    else dialog.setAttribute('open', '')
  }, [])

  const reset = () => {
    setZoom(1)
    setTurn(0)
    setOffset({ x: 0, y: 0 })
  }
  const go = (step: number) => {
    setIndex((i) => (i + step + photos.length) % photos.length)
    reset()
  }
  const zoomBy = (factor: number) =>
    setZoom((z) => {
      const next = Math.min(MAX, Math.max(MIN, z * factor))
      if (next === MIN) setOffset({ x: 0, y: 0 })
      return next
    })

  const onPointerDown = (e: ReactPointerEvent) => {
    if (zoom === MIN) return
    drag.current = { x: e.clientX - offset.x, y: e.clientY - offset.y }
    e.currentTarget.setPointerCapture(e.pointerId)
  }
  const onPointerMove = (e: ReactPointerEvent) => {
    if (drag.current) setOffset({ x: e.clientX - drag.current.x, y: e.clientY - drag.current.y })
  }

  if (!photo) return null
  const many = photos.length > 1
  const tool =
    'rounded-lg bg-white/15 px-3 py-1.5 text-small font-semibold text-white hover:bg-white/25 focus-visible:outline-2 focus-visible:outline-white'

  return (
    <dialog
      ref={ref}
      aria-label={`Photo ${photo.no} of ${photos.length}`}
      onCancel={(e) => {
        e.preventDefault()
        onClose()
      }}
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight' && many) go(1)
        if (e.key === 'ArrowLeft' && many) go(-1)
        if (e.key === '+' || e.key === '=') zoomBy(1.4)
        if (e.key === '-') zoomBy(1 / 1.4)
      }}
      className="m-0 h-dvh max-h-none w-dvw max-w-none bg-ink/95 p-0 text-white backdrop:bg-ink/80"
    >
      <div className="flex h-full flex-col">
        <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
          <span className="text-small font-semibold">
            Photo {photo.no} of {photos.length}
            <span className="ml-2 font-normal text-white/60">
              scroll or use + and − to zoom, drag to move
            </span>
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              className={tool}
              aria-label="Zoom out"
              onClick={() => zoomBy(1 / 1.4)}
            >
              −
            </button>
            <button type="button" className={tool} aria-label="Zoom in" onClick={() => zoomBy(1.4)}>
              +
            </button>
            <button type="button" className={tool} onClick={() => setTurn((t) => (t + 90) % 360)}>
              Rotate
            </button>
            <button type="button" className={tool} onClick={reset}>
              Reset
            </button>
            <button type="button" className={tool} onClick={onClose}>
              Close
            </button>
          </div>
        </div>
        <div
          className="relative flex min-h-0 grow items-center justify-center overflow-hidden"
          onWheel={(e) => zoomBy(e.deltaY < 0 ? 1.15 : 1 / 1.15)}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={() => (drag.current = null)}
          style={{ cursor: zoom > MIN ? 'grab' : 'default', touchAction: 'none' }}
        >
          <img
            src={photo.url}
            alt={`Photo ${photo.no} of ${photos.length}`}
            draggable={false}
            className="max-h-full max-w-full object-contain select-none"
            style={{
              transform: `translate(${offset.x}px, ${offset.y}px) scale(${zoom}) rotate(${turn}deg)`,
            }}
          />
          {many && (
            <>
              <button
                type="button"
                aria-label="Previous photo"
                onClick={() => go(-1)}
                className={`${tool} absolute top-1/2 left-4 -translate-y-1/2 text-lg`}
              >
                ‹
              </button>
              <button
                type="button"
                aria-label="Next photo"
                onClick={() => go(1)}
                className={`${tool} absolute top-1/2 right-4 -translate-y-1/2 text-lg`}
              >
                ›
              </button>
            </>
          )}
        </div>
      </div>
    </dialog>
  )
}
