const WS_BASE = import.meta.env.VITE_WS_URL ?? 'ws://localhost:8080'

import { getAuthToken } from '#/lib/api'

// Caller is responsible for calling ws.close() on unmount.
export function connect(path: string, onMessage: (data: unknown) => void): WebSocket {
  const token = getAuthToken()
  const url = new URL(`${WS_BASE}${path}`)
  if (token) url.searchParams.set('token', token)
  const ws = new WebSocket(url.toString())
  ws.onmessage = (e) => onMessage(JSON.parse(e.data as string))
  return ws
}

export function connectLive(onMessage: (data: unknown) => void): WebSocket {
  return connect('/ws/live', onMessage)
}
