import { useExportJob, type ExportJob } from '../../api/exports'
import { Alert } from '../../components/Alert'
import { buttonClasses } from '../../components/buttonClasses'
import { timeLeft } from '../../lib/time'

/** Progress of a large export prepared in the background (contract 4.2). */
export function ExportJobNotice({ job }: { job: ExportJob }) {
  const live = useExportJob(job.export_id)
  const current = live.data ?? job

  if (current.status === 'failed') {
    return (
      <Alert tone="danger">The export failed. Please try again with a shorter date range.</Alert>
    )
  }
  if (current.status === 'ready' && current.download_url) {
    const left = current.link_expires_at ? timeLeft(current.link_expires_at) : null
    return (
      <Alert tone="info" role="status">
        Your export is ready{current.row_count ? ` (${current.row_count} rows)` : ''}.{' '}
        {left ? (
          <a href={current.download_url} className={buttonClasses('link')}>
            Download CSV · link {left}
          </a>
        ) : (
          'The link has expired; export again to get a new one.'
        )}
      </Alert>
    )
  }
  return (
    <Alert tone="info" role="status">
      Preparing your export in the background. You'll also get a dashboard notice and an email with
      a link valid for 1 hour.
    </Alert>
  )
}
