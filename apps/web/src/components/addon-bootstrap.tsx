import { useEffect } from 'react'
import { activateAll } from '#/addon-loader'

export default function AddonBootstrap() {
  useEffect(() => {
    activateAll()
  }, [])
  return null
}
