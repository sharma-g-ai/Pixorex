import { describe, expect, it } from 'vitest'
import { appInviteLink, isMobileDevice } from './inviteLink'

const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/126.0 Mobile Safari/537.36'
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1'
const LAPTOP = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0 Safari/537.36'

describe('appInviteLink', () => {
  it('GIVEN Android THEN an intent link that opens the Pixorex app', () => {
    expect(appInviteLink('t 1/x', ANDROID)).toBe(
      'intent://activate?token=t%201%2Fx#Intent;scheme=pixorex;package=com.pixorex.mobile;end',
    )
  })

  it('GIVEN another phone THEN the pixorex:// link the app reads', () => {
    expect(appInviteLink('abc', IPHONE)).toBe('pixorex://activate?token=abc')
  })
})

describe('isMobileDevice', () => {
  it('GIVEN phones THEN true; a laptop THEN false', () => {
    expect(isMobileDevice(ANDROID)).toBe(true)
    expect(isMobileDevice(IPHONE)).toBe(true)
    expect(isMobileDevice(LAPTOP)).toBe(false)
  })
})
