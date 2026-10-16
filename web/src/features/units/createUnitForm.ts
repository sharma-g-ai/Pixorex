import { z } from 'zod'
import { emailField } from '../../lib/validation'
import type { CreateBusinessUnit } from '../../api/businessUnits'

/** Create business unit form (canvas: EA 11 "Create business unit"). */
export const createUnitSchema = z
  .object({
    name: z.string().trim().min(1, 'Enter the unit name.'),
    facility_name: z.string().trim().min(1, 'Enter the facility name.'),
    admin_mode: z.enum(['invite', 'existing']),
    invite_email: z.string().trim(),
    user_id: z.string(),
  })
  .superRefine((v, ctx) => {
    if (v.admin_mode === 'invite' && !emailField().safeParse(v.invite_email).success) {
      ctx.addIssue({
        code: 'custom',
        path: ['invite_email'],
        message: 'Enter a valid email address.',
      })
    }
    if (v.admin_mode === 'existing' && !v.user_id) {
      ctx.addIssue({ code: 'custom', path: ['user_id'], message: 'Pick a BU Admin.' })
    }
  })

export type CreateUnitValues = z.infer<typeof createUnitSchema>

export const emptyCreateUnit: CreateUnitValues = {
  name: '',
  facility_name: '',
  admin_mode: 'invite',
  invite_email: '',
  user_id: '',
}

/** The request body for contract 1.13. */
export function toCreateUnitBody(v: CreateUnitValues): CreateBusinessUnit {
  return {
    name: v.name,
    facility_name: v.facility_name,
    bu_admin: v.admin_mode === 'invite' ? { invite_email: v.invite_email } : { user_id: v.user_id },
  }
}

/** Which form field a server error belongs to, by problem code or validation field name. */
export const serverFieldFor: Record<string, keyof CreateUnitValues> = {
  'duplicate-name': 'name',
  'not-a-bu-admin': 'user_id',
  name: 'name',
  facility_name: 'facility_name',
  'bu_admin.invite_email': 'invite_email',
  'bu_admin.user_id': 'user_id',
}

export const serverMessages: Record<string, string> = {
  'duplicate-name': 'A unit with this name already exists.',
  'not-a-bu-admin': 'This person is no longer a BU Admin. Pick someone else.',
}
