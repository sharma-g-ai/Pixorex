const STORAGE_KEY = 'pixorex.device_id'

/**
 * Stable ID of this browser, sent as X-Device-Id on every API call
 * (ARCHITECTURE §10). The API keeps one user_session per user and device.
 */
export function getDeviceId(storage: Storage = window.localStorage): string {
  try {
    const existing = storage.getItem(STORAGE_KEY)
    if (existing) return existing
    const created = crypto.randomUUID()
    storage.setItem(STORAGE_KEY, created)
    return created
  } catch {
    // Storage blocked (private mode): fall back to an ID for this page load.
    return (fallbackId ??= crypto.randomUUID())
  }
}

let fallbackId: string | undefined
