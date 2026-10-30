import { useState } from 'react'
import { useViewer } from '../../app/viewer'
import { Button } from '../../components/Button'
import { CheckboxList } from '../../components/CheckboxList'
import { Dialog } from '../../components/Dialog'
import { Mono, Note } from '../../components/Page'
import { TextField } from '../../components/TextField'
import type { Vessel } from '../../data/model'
import { activeDevice, openEnrolmentCode, userById } from '../../data/queries'
import { cancelEnrolmentCode, issueEnrolmentCode, recordPasswordReset, useStore } from '../../data/store'
import { formatDateTime } from '../../lib/format'

/**
 * Pair a tablet to a vessel with a one-time enrolment code, valid 72 hours (data model Domain 2).
 * The vessel signs in on the new tablet and enters the code; issuing a new code cancels the open one.
 */
export function PairTabletDialog({ vessel, onClose }: { vessel: Vessel; onClose: () => void }) {
  useStore()
  const { user } = useViewer()
  const current = activeDevice(vessel.id)
  const open = openEnrolmentCode(vessel.id)
  const [replace, setReplace] = useState<'replace'[]>([])
  const [issued, setIssued] = useState<string | null>(null)
  const ready = !current || replace.length > 0
  return (
    <Dialog
      title={`Pair a tablet · ${vessel.name}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {issued ? 'Done' : 'Cancel'}
          </Button>
          {!issued && (
            <Button disabled={!ready} onClick={() => setIssued(issueEnrolmentCode(vessel.id, replace.length > 0, user))}>
              {open ? 'Issue a new code' : 'Issue code'}
            </Button>
          )}
        </>
      }
    >
      <div className="flex flex-col gap-4">
        {issued ? (
          <>
            <p>Enter this code on the new tablet after signing in as the vessel:</p>
            <p className="text-center text-2xl font-bold tracking-widest">
              <Mono>{issued}</Mono>
            </p>
            <p className="text-small">
              It works once and expires in 72 hours. Share it with the vessel only.
            </p>
          </>
        ) : (
          <>
            <p>
              {current ? (
                <>
                  Paired now: <Mono>{current.id}</Mono> ({current.model}).
                </>
              ) : (
                'No tablet is paired to this vessel.'
              )}
            </p>
            {open && (
              <Note tone="warning">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span>
                    Code <Mono>{open.code}</Mono> is open, issued by {userById(open.issuedBy)?.name ?? 'an admin'};
                    expires {formatDateTime(open.expiresAt)}. A new code cancels it.
                  </span>
                  <Button variant="danger-link" onClick={() => cancelEnrolmentCode(open.id, user)}>
                    Cancel this code
                  </Button>
                </div>
              </Note>
            )}
            {current && (
              <CheckboxList
                label="Replacing the tablet"
                value={replace}
                onChange={setReplace}
                options={[
                  {
                    value: 'replace',
                    label: `The new tablet replaces ${current.id}; it is unpaired once the new one enrols`,
                  },
                ]}
              />
            )}
            <p className="text-small">One tablet per vessel (D-12). The code is valid for 72 hours and works once.</p>
          </>
        )}
      </div>
    </Dialog>
  )
}

/**
 * Reset the vessel's sign-in password, e.g. at crew change. The tablet asks for the new password
 * at its next sign-in. The password rule and who hands it to the crew are to confirm with PPG.
 */
export function PasswordResetDialog({ vessel, onClose }: { vessel: Vessel; onClose: () => void }) {
  const { user } = useViewer()
  const [password, setPassword] = useState('')
  const [again, setAgain] = useState('')
  const long = password.length >= 12
  const same = password === again
  return (
    <Dialog
      title={`Reset password · ${vessel.name}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            disabled={!long || !same}
            onClick={() => {
              recordPasswordReset(vessel.id, user)
              onClose()
            }}
          >
            Reset password
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p>
          The vessel signs in on its tablet with this password. Last changed{' '}
          {vessel.passwordChangedAt ? formatDateTime(vessel.passwordChangedAt) : 'never'}.
        </p>
        <TextField
          label="New password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          error={password && !long ? 'At least 12 characters' : undefined}
        />
        <TextField
          label="Type it again"
          type="password"
          value={again}
          onChange={(e) => setAgain(e.target.value)}
          error={again && !same ? 'The two do not match' : undefined}
        />
      </div>
    </Dialog>
  )
}
