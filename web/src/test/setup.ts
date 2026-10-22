import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'
import { resetSampleData } from '../data/store'

afterEach(() => {
  cleanup()
  resetSampleData()
})
