import { z } from 'zod'
import { emailField, unitIdsField } from '../../lib/validation'

/** Invite a technician (canvas BU 26; contract 1.8). */
export const inviteSchema = z.object({
  email: emailField(),
  bu_ids: unitIdsField(),
})

export type InviteValues = z.infer<typeof inviteSchema>

/** Server problem codes that belong to a field, with the message to show. */
export const inviteServerErrors: Record<string, { field: keyof InviteValues; message: string }> = {
  forbidden: { field: 'bu_ids', message: 'You can only invite into units you run.' },
}
