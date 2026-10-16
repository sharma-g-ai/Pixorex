import { describe, expect, it } from 'vitest'
import { initials } from './initials'

describe('initials', () => {
  it.each([
    ['R. Kowalski', 'RK'],
    ['Asha Mehta', 'AM'],
    ['Asha Rani Mehta', 'AM'],
    ['Cher', 'C'],
    ['', '?'],
  ])('%s → %s', (name, expected) => {
    expect(initials(name)).toBe(expected)
  })
})
