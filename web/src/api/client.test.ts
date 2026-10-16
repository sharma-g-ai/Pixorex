import { describe, expect, it } from 'vitest'
import { problemCode } from './client'

describe('problemCode', () => {
  it('GIVEN a problem type URI WHEN read THEN returns the stable code', () => {
    expect(problemCode({ type: '/problems/locked-after-publish' })).toBe('locked-after-publish')
  })

  it('GIVEN a bare code WHEN read THEN returns it unchanged', () => {
    expect(problemCode({ type: 'invalid-state' })).toBe('invalid-state')
  })
})
