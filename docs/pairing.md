# Building Aceso and pairing with WHOOP

## Prerequisites

- **Xcode 17+** with the iOS 26 SDK installed
- **Physical iPhone** running iOS 26+ (Bluetooth doesn't work in the simulator)
- A **WHOOP 4.0 or 5.0** strap charged and not actively connected to the official WHOOP app

---

## 1. Open the project

```bash
open apps/ios/Aceso.xcodeproj
```

---

## 2. Add the Bluetooth capability in Xcode

1. In the Project Navigator, select the **Aceso** project (top of the tree).
2. Select the **Aceso** target (not AcesoTests or AcesoUITests).
3. Click the **Signing & Capabilities** tab.
4. Click **+ Capability**.
5. Double-click **Background Modes**.
6. Check **Uses Bluetooth LE accessories**.

Xcode will create an entitlements file and wire `CODE_SIGN_ENTITLEMENTS` automatically.

---

## 3. Select your iPhone and build

1. Plug your iPhone into the Mac via USB (or use wireless debugging if already paired).
2. In Xcode, select your iPhone from the device picker in the toolbar.
3. The first time: on the iPhone, tap **Trust** when the "Trust This Computer?" prompt appears.
4. Press **⌘R** (or the ▶ Run button).
5. Xcode will build, sign with your team (`9TNKSPKJLH`), and install the app.

If you get a "Developer Mode" prompt on the iPhone: go to **Settings → Privacy & Security → Developer Mode**, enable it, and restart. Then build again.

---

## 5. Pairing with WHOOP 4.0

WHOOP 4.0 pairing is automatic — no prep needed on the strap side.

1. **Close the official WHOOP app** on any phone it's connected to, or turn that phone's Bluetooth off. The strap holds a single encrypted bond; if another device holds it, Aceso's bond write will be refused.
2. Launch **Aceso** on your iPhone. It starts scanning immediately on launch.
3. The app will discover the strap, connect, and trigger just-works Bluetooth bonding automatically by writing a `GET_BATTERY_LEVEL` command.
4. iOS will show a **"Aceso" Would Like to Use Bluetooth** permission prompt — tap **OK**.
5. Within a few seconds `connectionState` goes `.connected`, live HR appears, and the strap begins offloading its 14-day history in the background.

**If the strap shows "Encryption is insufficient" in logs** (meaning the bond was refused):
- The strap is still bonded to another device. Close the WHOOP app on that device (or turn off its Bluetooth) and try again.
- On the iPhone: go to **Settings → Bluetooth**, find your WHOOP, tap the ⓘ, and tap **Forget This Device**. Then relaunch Aceso.

---

## 6. Pairing with WHOOP 5.0

WHOOP 5.0 holds an encrypted bond that you must explicitly break before Aceso can claim it.

### First-time pairing

1. **Close the official WHOOP app** completely (or toggle Bluetooth off on that phone).
2. **Put the strap into pairing mode:**
   - Tap the band firmly and repeatedly (on the sensor side) until the **LEDs flash blue**.
   - This clears the old bond and makes the strap discoverable.
3. On the iPhone, go to **Settings → Bluetooth** and check that the strap is **not** already listed as a paired device. If it is, tap ⓘ → **Forget This Device**.
4. Launch **Aceso**. It will scan for the `fd4b0001-…` service.
5. Aceso writes the static **CLIENT_HELLO** frame to start the puffin session. iOS triggers just-works bonding during this write.
6. The iOS Bluetooth permission prompt appears — tap **OK**.
7. Once bonded, the puffin notify characteristics are subscribed and live HR starts streaming (it may take 5–10 seconds).

### Reconnecting (after first pair)

No LED flashing needed. Just close the WHOOP app on your phone, launch Aceso, and it reconnects automatically within a few seconds.

### If bonding fails ("bond refused" / "Authentication is insufficient")

The strap is still bonded to another device. Repeat the LED-flash pairing-mode step above and ensure the WHOOP app is fully closed everywhere before retrying.

> **Only one device at a time.** Because the strap holds a single Bluetooth bond, whichever app bonded last "owns" the encrypted features (history, events, haptics). Live heart rate via the standard BLE profile (2A37) streams without a bond, so you'll see HR even without ownership — but syncing history requires the bond.

---

## 7. What to expect after connecting

| Feature | When it appears |
|---|---|
| Live heart rate | Within 1–2 seconds of connecting |
| Battery level | Within a few seconds (4.0: from GET_BATTERY_LEVEL response; 5.0: from standard 0x2A19) |
| History offload | Starts ~1.5s after bond; the strap streams its last 14 days automatically |
| `onSamples` callback | Fires every 30 seconds while connected with a batch of HR + R-R + battery samples |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| App stuck on "Scanning…" | Strap is off-wrist or out of range. Put it on and get within ~3m. |
| "Encryption is insufficient" | Another device holds the bond. Close WHOOP app elsewhere and retry. |
| HR shows but no history sync | App doesn't hold the bond. Disconnect, put strap in pairing mode (5.0) or forget-and-repair (4.0), and reconnect. |
| Build fails with entitlements error | In Signing & Capabilities, verify Background Modes → "Uses Bluetooth LE accessories" is checked. |
| "Trust This Computer?" never appeared | Unplug, re-plug USB, unlock the phone, plug in again. |
| Developer Mode prompt | Settings → Privacy & Security → Developer Mode → enable → restart phone. |
