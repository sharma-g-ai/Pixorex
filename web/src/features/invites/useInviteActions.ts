import { errorMessage } from '../../api/client'
import { useCancelInvite, useResendInvite, type Invite } from '../../api/invites'

export interface Notice {
  text: string
  error?: boolean
}

/** Resend and cancel for invite rows, reporting the result as a notice. */
export function useInviteActions(onNotice: (notice: Notice) => void) {
  const resend = useResendInvite()
  const cancel = useCancelInvite()

  const run = (action: Promise<unknown>, success: string) =>
    action
      .then(() => onNotice({ text: success }))
      .catch((err: unknown) => onNotice({ text: errorMessage(err), error: true }))

  return {
    busy: resend.isPending || cancel.isPending,
    resend: (invite: Invite) =>
      void run(resend.mutateAsync(invite.invite_id), `Invite sent again to ${invite.email}.`),
    cancel: (invite: Invite) =>
      void run(cancel.mutateAsync(invite.invite_id), `Invite to ${invite.email} removed.`),
  }
}
