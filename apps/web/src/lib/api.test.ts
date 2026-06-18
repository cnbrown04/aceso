// @vitest-environment jsdom
import { describe, expect, it, beforeEach } from 'vitest'
import { getAuthToken, setAuthToken } from '#/lib/api'

describe('api auth helpers', () => {
  beforeEach(() => {
    window.localStorage.clear()
  })

  it('stores and reads auth token', () => {
    setAuthToken('session-abc')
    expect(getAuthToken()).toBe('session-abc')
  })
})
