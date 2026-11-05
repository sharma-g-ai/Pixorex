import { describe, expect, it } from 'vitest'
import { formatScanId } from './scanId'

describe('formatScanId', () => {
  it('groups a 10-digit scan ID as 3 3 3 1', () => {
    expect(formatScanId('1000000040')).toBe('100 000 004 0')
  })
  it('leaves anything else alone', () => {
    expect(formatScanId('REC-12')).toBe('REC-12')
  })
})
