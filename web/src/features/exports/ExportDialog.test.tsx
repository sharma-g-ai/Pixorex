import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { exportFileName } from '../../lib/download'
import { ExportDialog } from './ExportDialog'

const createExport = vi.fn()
vi.mock('../../api/exports', () => ({
  useCreateExport: () => ({ mutateAsync: createExport, isPending: false }),
}))
const downloadText = vi.fn()
vi.mock('../../lib/download', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  downloadText: (...args: unknown[]) => downloadText(...args),
}))

const handlers = { onClose: vi.fn(), onQueued: vi.fn(), onDownloaded: vi.fn() }
const scopes = [
  { key: 'view', label: 'What you see', filters: { bu_id: 'p04', review_status: 'waiting' } },
  {
    key: 'approved',
    label: 'Approved scans only',
    filters: { bu_id: 'p04', review_status: 'approved' },
  },
]

beforeEach(() => {
  createExport.mockReset()
  downloadText.mockReset()
  for (const fn of Object.values(handlers)) fn.mockReset()
})

describe('Export dialog (contract 4.1)', () => {
  it('GIVEN up to 1,000 rows THEN the CSV downloads straight away', async () => {
    createExport.mockResolvedValueOnce({ kind: 'file', csv: 'a,b\n1,2' })
    render(
      <ExportDialog
        kind="scans"
        title="Export scans to CSV"
        scopes={scopes}
        note="n"
        {...handlers}
      />,
    )
    expect(
      screen.getByText(/Names, emails and phone numbers are masked in the file\./),
    ).toBeInTheDocument()
    fireEvent.click(screen.getByLabelText('Approved scans only'))
    fireEvent.click(screen.getByLabelText('Photo links (valid 1 hour)'))
    fireEvent.click(screen.getByRole('button', { name: 'Download CSV' }))

    await waitFor(() => expect(handlers.onDownloaded).toHaveBeenCalled())
    expect(downloadText).toHaveBeenCalledWith(expect.stringMatching(/^pixorex-scans-/), 'a,b\n1,2')
    const { body, idempotencyKey } = createExport.mock.calls[0]?.[0] ?? {}
    expect(idempotencyKey).toEqual(expect.any(String))
    expect(body).toMatchObject({
      export_kind: 'scans',
      filters: { bu_id: 'p04', review_status: 'approved' },
      options: { include_photo_links: true },
    })
  })

  it('GIVEN a big export THEN it is handed back as a background job', async () => {
    const job = { export_id: 'e1', export_kind: 'audit_log', status: 'queued' }
    createExport.mockResolvedValueOnce({ kind: 'job', job })
    render(
      <ExportDialog
        kind="audit_log"
        title="Export audit log"
        unitOptions={[{ value: 'p04', label: 'Plant 04' }]}
        categoryOptions={[{ value: 'review', label: 'Review decisions' }]}
        note="n"
        {...handlers}
      />,
    )
    fireEvent.change(screen.getByLabelText('Units'), { target: { value: 'p04' } })
    fireEvent.click(screen.getByRole('button', { name: 'Download CSV' }))

    await waitFor(() => expect(handlers.onQueued).toHaveBeenCalledWith(job))
    expect(createExport.mock.calls[0]?.[0].body).toEqual({
      export_kind: 'audit_log',
      filters: { bu_id: 'p04' },
    })
  })

  it('GIVEN From after To THEN download is blocked', () => {
    render(<ExportDialog kind="scans" title="t" scopes={scopes} note="n" {...handlers} />)
    fireEvent.change(screen.getByLabelText('From'), { target: { value: '2026-10-05' } })
    fireEvent.change(screen.getByLabelText('To'), { target: { value: '2026-10-01' } })
    expect(screen.getByRole('button', { name: 'Download CSV' })).toBeDisabled()
  })
})

describe('exportFileName', () => {
  it('names the file by kind and date', () => {
    expect(exportFileName('audit_log', new Date('2026-10-05T12:00:00Z'))).toBe(
      'pixorex-audit-log-2026-10-05.csv',
    )
  })
})
