import { useParams } from 'react-router'
import { ScanReviewView } from './ScanReviewView'

interface ScanReviewPageProps {
  /** Where the scan was opened from, for "← Back". */
  back: { to: string; label: string }
}

/** Route wrapper: the scan id comes from the URL (/review-queue/:scanId, /escalations/:scanId, …). */
export function ScanReviewPage({ back }: ScanReviewPageProps) {
  const { scanId } = useParams()
  if (!scanId) return null
  return <ScanReviewView key={scanId} scanId={scanId} back={back} />
}
