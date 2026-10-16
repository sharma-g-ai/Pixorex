import { z } from 'zod'
import { emailField, unitIdsField } from '../../lib/validation'

/** Invite a BU Admin (canvas EA 14; contract 1.8). */
export const inviteBuAdminSchema = z.object({
  email: emailField(),
  bu_ids: unitIdsField('Pick at least one unit without a BU Admin.'),
})
export type InviteBuAdminValues = z.infer<typeof inviteBuAdminSchema>

/** Edit the units a BU Admin runs (canvas EA 15; contract 1.16). */
export const editUnitsSchema = z.object({
  bu_ids: unitIdsField('Keep at least one unit. To take every unit away, use Remove.'),
})
export type EditUnitsValues = z.infer<typeof editUnitsSchema>

/** Remove a BU Admin from units (canvas EA 16–18; contract 1.17). */
export const removeBuAdminSchema = z
  .object({
    bu_ids: unitIdsField('Tick at least one unit.'),
    next: z.enum(['invite', 'later']),
    replacement_email: z.string().trim(),
  })
  .superRefine((v, ctx) => {
    if (v.next === 'invite' && !emailField().safeParse(v.replacement_email).success) {
      ctx.addIssue({
        code: 'custom',
        path: ['replacement_email'],
        message: 'Enter a valid work email.',
      })
    }
  })
export type RemoveBuAdminValues = z.infer<typeof removeBuAdminSchema>
