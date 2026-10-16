import { z } from 'zod'

/** A trimmed, valid email address; used by every invite form. */
export const emailField = (message = 'Enter a valid work email.') =>
  z.string().trim().pipe(z.email(message))

/** At least one unit ticked. */
export const unitIdsField = (message = 'Pick at least one unit.') =>
  z.array(z.string()).min(1, message)

/** A person's name as shown to colleagues: trimmed, 2 to 100 characters. */
export const fullNameField = (message = 'Enter your full name.') =>
  z.string().trim().min(2, message).max(100, 'Use 100 characters or fewer.')
