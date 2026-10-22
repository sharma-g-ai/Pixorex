/** "R. Kowalski" → "RK", "Asha Mehta" → "AM", "" → "?". */
export function initials(fullName: string): string {
  const letters = fullName
    .split(/[\s.]+/)
    .filter(Boolean)
    .map((part) => part[0]?.toUpperCase() ?? '')
  if (letters.length === 0) return '?'
  return letters.length === 1 ? (letters[0] ?? '?') : `${letters[0]}${letters[letters.length - 1]}`
}
