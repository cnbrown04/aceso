export interface WebAddon {
  id: string;
  activate?: () => void;
}

// Picked up at build time — add a web/index.ts to any addon to include it.
const modules = import.meta.glob("../../../addons/*/web/index.ts", {
  eager: true,
}) as Record<string, { default: WebAddon }>;

export const addons: WebAddon[] = Object.values(modules).map((m) => m.default);

export function activateAll(): void {
  for (const addon of addons) {
    addon.activate?.();
  }
}
