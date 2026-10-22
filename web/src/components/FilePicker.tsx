import { Icon } from './icons'

interface FilePickerProps {
  /** File types the browser offers, e.g. ".xlsx,.csv". */
  accept: string
  /** Shown under the button, e.g. ".xlsx or .csv". */
  hint: string
  fileName: string | null
  onPick: (file: File) => void
}

/** A dashed drop-box style button for choosing one file. */
export function FilePicker({ accept, hint, fileName, onPick }: FilePickerProps) {
  return (
    <label className="flex cursor-pointer flex-col items-center gap-1.5 rounded-xl border-[1.5px] border-dashed border-line-strong px-4 py-6 text-center hover:bg-page">
      <Icon name="upload" size={20} className="text-brand" />
      <span className="font-semibold text-ink">{fileName ?? 'Choose a file'}</span>
      <span className="text-caption">{hint}</span>
      <input
        type="file"
        accept={accept}
        className="sr-only"
        onChange={(e) => {
          const file = e.target.files?.[0]
          if (file) onPick(file)
        }}
      />
    </label>
  )
}
