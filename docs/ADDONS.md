# Writing an Addon

Copy `addons/_template/` into `addons/<your-addon>/`. Each sub-folder is optional — only create the platforms you need.

## Server addon (`server/addon.go`)

1. Declare a `package` name.
2. Implement `server.Addon` (one method: `Register() error`).
3. Call `server.RegisterAddon(&yourAddon{})` inside `func init()`.
4. The `init()` will run when `addon-loader.go` blank-imports your package.

## Web addon (`web/index.ts`)

Export a default `WebAddon` object. `addon-loader.ts` picks it up automatically via `import.meta.glob`. If you need UI surface area, export components and import them from your route or a shared layout.

## iOS addon (`ios/*.swift`)

1. Implement `IOSAddon` (two members: `id: String`, `activate()`).
2. Register in a module initialiser:

```swift
private let _register: Void = {
    AddonLoader.shared.register(MyAddon())
}()
```

`activate()` is called during `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
