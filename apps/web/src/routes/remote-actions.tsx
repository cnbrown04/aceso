import { createFileRoute, Link } from '@tanstack/react-router'
import RemoteActionsPanel from '../../../../addons/remote-actions/web/remote-actions-panel'

export const Route = createFileRoute('/remote-actions')({
  component: RemoteActionsPanel,
})
