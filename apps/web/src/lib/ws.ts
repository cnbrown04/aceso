const WS_BASE = import.meta.env.VITE_WS_URL ?? 'ws://localhost:8080'

// Caller is responsible for calling ws.close() on unmount.
export function connect(path: string, onMessage: (data: unknown) => void): WebSocket {
  const ws = new WebSocket(`${WS_BASE}${path}`)
  ws.onmessage = (e) => onMessage(JSON.parse(e.data as string))
  return ws
}
