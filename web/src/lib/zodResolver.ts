import type { FieldErrors, FieldValues, Resolver } from 'react-hook-form'
import type { ZodType } from 'zod'

/**
 * Connects a Zod schema to React Hook Form (instead of adding @hookform/resolvers).
 * The first message per field is shown.
 */
export function zodResolver<T extends FieldValues>(schema: ZodType<T>): Resolver<T> {
  return async (values) => {
    const result = schema.safeParse(values)
    if (result.success) return { values: result.data, errors: {} }

    const errors: Record<string, { type: string; message: string }> = {}
    for (const issue of result.error.issues) {
      const path = issue.path.join('.')
      errors[path] ??= { type: issue.code, message: issue.message }
    }
    return { values: {}, errors: errors as FieldErrors<T> }
  }
}
