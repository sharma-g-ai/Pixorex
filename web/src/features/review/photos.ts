export interface Photo {
  no: number
  url: string
}

/**
 * Photos from a scan review. The contract leaves the item shape open; the API doc
 * describes {photo_no, url} with 15-minute signed URLs, so only items with a url are used.
 */
export function photoList(photos: readonly object[]): Photo[] {
  return photos.flatMap((p, i) => {
    const item = p as { photo_no?: unknown; url?: unknown }
    if (typeof item.url !== 'string') return []
    return [{ no: typeof item.photo_no === 'number' ? item.photo_no : i + 1, url: item.url }]
  })
}
