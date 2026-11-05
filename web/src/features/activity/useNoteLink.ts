import { useSearchParams } from 'react-router'

/** A link that opens one delivery note and keeps the page's tab and filters. */
export function useNoteLink(): (dnNumber: string) => string {
  const [params] = useSearchParams()
  return (dnNumber) => {
    const next = new URLSearchParams(params)
    next.set('dn', dnNumber)
    return `?${next}`
  }
}
