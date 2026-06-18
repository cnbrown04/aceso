import { useEffect, useState } from 'react'
import { get, login, post } from '~web/lib/api'
import { connectLive } from '~web/lib/ws'

type Device = {
  id: string
  name: string
  platform: string
  online: boolean
}

type Command = {
  id: string
  device_id: string
  type: string
  status: string
  result?: { message?: string; code?: string }
}

export default function RemoteActionsPanel() {
  const [apiKey, setApiKey] = useState('dev-api-key')
  const [loggedIn, setLoggedIn] = useState(false)
  const [devices, setDevices] = useState<Device[]>([])
  const [selectedDevice, setSelectedDevice] = useState('')
  const [commands, setCommands] = useState<Command[]>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!loggedIn) return
    const ws = connectLive((msg) => {
      const event = msg as { type?: string; command?: Command; device?: Device }
      if (event.type === 'command' && event.command) {
        setCommands((prev) => {
          const rest = prev.filter((c) => c.id !== event.command!.id)
          return [event.command!, ...rest].slice(0, 20)
        })
      }
      if (event.type === 'presence' && event.device) {
        setDevices((prev) =>
          prev.map((d) => (d.id === event.device!.id ? { ...d, online: event.device!.online } : d)),
        )
      }
    })
    return () => ws.close()
  }, [loggedIn])

  async function handleLogin() {
    setError(null)
    try {
      await login(apiKey)
      setLoggedIn(true)
      await refreshDevices()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Login failed')
    }
  }

  async function refreshDevices() {
    const data = await get<{ devices: Device[] }>('/api/devices')
    setDevices(data.devices)
    if (!selectedDevice && data.devices[0]) setSelectedDevice(data.devices[0].id)
  }

  async function sendCommand(type: string, params: Record<string, unknown>) {
    if (!selectedDevice) return
    setBusy(true)
    setError(null)
    try {
      const cmd = await post<Command>('/api/commands', {
        device_id: selectedDevice,
        type,
        params,
      })
      setCommands((prev) => [cmd, ...prev].slice(0, 20))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Command failed')
    } finally {
      setBusy(false)
    }
  }

  const selected = devices.find((d) => d.id === selectedDevice)
  const offline = selected && !selected.online

  return (
    <section className="mx-auto max-w-2xl space-y-6 p-6">
      <header>
        <h1 className="text-2xl font-semibold">Remote Actions</h1>
        <p className="text-sm text-neutral-500">
          Send authenticated commands to your iPhone, which relays them to your bonded WHOOP strap.
        </p>
      </header>

      {!loggedIn ? (
        <div className="space-y-3 rounded-lg border p-4">
          <label className="block text-sm font-medium">API key</label>
          <input
            className="w-full rounded border px-3 py-2"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
          />
          <button className="rounded bg-teal-600 px-4 py-2 text-white" onClick={handleLogin}>
            Sign in
          </button>
        </div>
      ) : (
        <>
          <div className="space-y-2 rounded-lg border p-4">
            <label className="block text-sm font-medium">Device</label>
            <select
              className="w-full rounded border px-3 py-2"
              value={selectedDevice}
              onChange={(e) => setSelectedDevice(e.target.value)}
            >
              {devices.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name} ({d.online ? 'online' : 'offline'})
                </option>
              ))}
            </select>
            <button className="text-sm text-teal-700 underline" onClick={refreshDevices}>
              Refresh devices
            </button>
          </div>

          <div className="flex flex-wrap gap-2">
            <button
              disabled={busy || offline}
              className="rounded border px-3 py-2 disabled:opacity-50"
              onClick={() => sendCommand('haptic.preset5', { preset: 'notify' })}
            >
              Notify haptic
            </button>
            <button
              disabled={busy || offline}
              className="rounded border px-3 py-2 disabled:opacity-50"
              onClick={() => sendCommand('haptic.pattern4', { pattern: 'alarm', loops: 2 })}
            >
              Alarm haptic (4.0)
            </button>
            <button
              disabled={busy || offline}
              className="rounded border px-3 py-2 disabled:opacity-50"
              onClick={() => sendCommand('haptic.stop', {})}
            >
              Stop haptics
            </button>
          </div>

          {offline && (
            <p className="text-sm text-amber-700">
              Selected iPhone is offline — open the Aceso app with remote actions enabled.
            </p>
          )}
        </>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}

      {commands.length > 0 && (
        <div className="rounded-lg border p-4">
          <h2 className="mb-2 font-medium">Recent commands</h2>
          <ul className="space-y-2 text-sm">
            {commands.map((c) => (
              <li key={c.id} className="flex justify-between gap-4">
                <span>{c.type}</span>
                <span className="text-neutral-500">{c.status}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  )
}
