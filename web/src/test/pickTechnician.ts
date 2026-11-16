import { fireEvent, within } from '@testing-library/react'

/** In the delegate dialog: type part of a name into the technician search and pick the match. */
export function pickTechnician(dialog: ReturnType<typeof within>, part: string) {
  fireEvent.change(dialog.getByRole('combobox', { name: 'Technician' }), {
    target: { value: part },
  })
  fireEvent.click(dialog.getByRole('option', { name: new RegExp(part) }))
}
