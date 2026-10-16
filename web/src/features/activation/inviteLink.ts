import { ApiError, problemCode } from '../../api/client'

/**
 * The invite token from the link `/activate#token=…` (D-11). The fragment never reaches a
 * server. `?token=` is accepted too, for links from an older email template.
 */
export function readInviteToken(hash: string, search: string): string {
  const fromHash = new URLSearchParams(hash.replace(/^#/, '')).get('token')
  const fromQuery = new URLSearchParams(search).get('token')
  return (fromHash ?? fromQuery ?? '').trim()
}

/** Survives React Strict Mode remount after the hash is stripped (D-11). */
let inviteTokenCache = ''

/**
 * Read the token from the URL, cache it, and strip it from the address bar.
 * On remount (Strict Mode) the cache still has the token.
 */
export function takeInviteToken(
  hash: string = window.location.hash,
  search: string = window.location.search,
): string {
  const fromUrl = readInviteToken(hash, search)
  if (fromUrl) {
    inviteTokenCache = fromUrl
    if (typeof window !== 'undefined' && (window.location.hash || window.location.search)) {
      window.history.replaceState(null, '', window.location.pathname)
    }
    return fromUrl
  }
  return inviteTokenCache
}

/** Test helper: clear the in-memory invite token between cases. */
export function clearInviteTokenCache(): void {
  inviteTokenCache = ''
}

const deadLinkCodes = ['invite-expired', 'invite-used', 'invite-cancelled']

/** The link itself no longer works (expired, used, cancelled), as opposed to a fixable error. */
export function isDeadInvite(err: unknown): boolean {
  return err instanceof ApiError && deadLinkCodes.includes(problemCode(err.problem))
}

/** What to tell someone whose link no longer works (contract 1.6, 1.7: 409 problems). */
export function inviteProblem(err: unknown): { title: string; text: string; canSignIn: boolean } {
  const code = err instanceof ApiError ? problemCode(err.problem) : ''
  switch (code) {
    case 'invite-expired':
      return {
        title: 'This invite has expired',
        text: 'Invite links work for 24 hours. Ask your Enterprise Admin to send a new one.',
        canSignIn: false,
      }
    case 'invite-used':
      return {
        title: 'This invite was already used',
        text: 'Your account is set up. Sign in with your work email.',
        canSignIn: true,
      }
    case 'invite-cancelled':
      return {
        title: 'This invite was cancelled',
        text: 'Ask your Enterprise Admin if you should still have access.',
        canSignIn: false,
      }
    default:
      return {
        title: "We couldn't open this invite",
        text: 'Check that you opened the whole link from the email, then try again.',
        canSignIn: false,
      }
  }
}
