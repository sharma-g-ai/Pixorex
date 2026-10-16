import { createContext, type ReactNode } from 'react'

/** Shown at the right end of every page header, e.g. the notifications bell. */
export const HeaderExtrasContext = createContext<ReactNode>(null)
