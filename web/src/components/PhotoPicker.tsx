import { useId, useRef, useState, type DragEvent } from 'react'
import { Button } from './Button'

interface PhotoPickerProps {
  label: string
  file: File | null
  onChange: (file: File | null) => void
  /** Greys the picker out, e.g. while the photo is being read. */
  disabled?: boolean
  /** File types taken, as in the input's accept. */
  accept?: string
  /** Keep the label for screen readers only, with no heading shown above the box. */
  hideLabel?: boolean
}

const sizeOf = (bytes: number) =>
  bytes >= 1_000_000
    ? `${(bytes / 1_000_000).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1000))} KB`

/**
 * A photo chooser: a clear box with a "Choose image" button (or drop an image on it), and the
 * chosen file's name and size with Change / Remove, in place of the browser's plain
 * "Choose file / No file chosen" input. The real input stays in the page, hidden, so screen
 * readers and tests still reach it by the label.
 */
export function PhotoPicker({
  label,
  file,
  onChange,
  disabled = false,
  accept = 'image/jpeg,image/png',
  hideLabel = false,
}: PhotoPickerProps) {
  const id = useId()
  const input = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const [wrongType, setWrongType] = useState(false)
  const allowed = accept.split(',').map((t) => t.trim())

  const take = (picked: File | null) => {
    if (picked && !allowed.includes(picked.type)) {
      setWrongType(true)
      return
    }
    setWrongType(false)
    onChange(picked)
  }
  const drop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    setOver(false)
    if (!disabled) take(e.dataTransfer.files[0] ?? null)
  }
  const choose = () => input.current?.click()

  return (
    <div>
      <label
        htmlFor={id}
        className={hideLabel ? 'sr-only' : 'mb-1.5 block text-small font-semibold text-ink-muted'}
      >
        {label}
      </label>
      <input
        ref={input}
        id={id}
        type="file"
        accept={accept}
        disabled={disabled}
        className="sr-only"
        onChange={(e) => {
          take(e.target.files?.[0] ?? null)
          e.target.value = '' // choosing the same file again still counts
        }}
      />
      <div
        onDragOver={(e) => {
          e.preventDefault()
          if (!disabled) setOver(true)
        }}
        onDragLeave={() => setOver(false)}
        onDrop={drop}
        className={`flex items-center gap-3 rounded-lg border-[1.5px] border-dashed px-3.5 py-3 ${
          over ? 'border-brand-navy bg-brand-navy-tint' : 'border-line-strong bg-page'
        } ${disabled ? 'opacity-60' : ''}`}
      >
        {file ? (
          <>
            <span className="min-w-0 grow">
              <span className="block truncate text-body font-semibold" title={file.name}>
                {file.name}
              </span>
              <span className="text-small text-ink-subtle">{sizeOf(file.size)}</span>
            </span>
            <Button variant="secondary" disabled={disabled} onClick={choose}>
              Change
            </Button>
            <Button variant="secondary" disabled={disabled} onClick={() => onChange(null)}>
              Remove
            </Button>
          </>
        ) : (
          <>
            <span className="min-w-0 grow text-small text-ink-muted">
              Drop an image here, or choose one. JPEG or PNG.
            </span>
            <Button variant="secondary" disabled={disabled} onClick={choose}>
              Choose image
            </Button>
          </>
        )}
      </div>
      {wrongType && (
        <p role="alert" className="mt-1.5 text-small text-danger">
          That file isn't a JPEG or PNG image.
        </p>
      )}
    </div>
  )
}
