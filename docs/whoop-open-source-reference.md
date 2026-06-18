# WHOOP Open-Source Reference — Community Consensus

This document surveys **every major open-source WHOOP project found online** (as of June 2026) and records what the community agrees on, where projects disagree, and how to use haptics, alarms, and other strap commands. It is the research backing for `packages/whoop-sdk/`.

**Not affiliated with WHOOP, Inc.** This is independent reverse-engineering for interoperability with hardware you own.

---

## 1. How many repos were actually surveyed?

In the first SDK pass, work leaned heavily on code already embedded in this repo (itself derived from NOOP/goose) plus a shallow web search. **This document is the follow-up audit** — a deliberate pass across the ecosystem.

### Repositories read in depth (source, protocol docs, or issues)

| Repo / source | Stars (approx.) | Generation | What we extracted |
|---|---|---|---|
| [NoopApp/noop](https://github.com/NoopApp/noop) | 726 | 4.0 + 5.0 | `docs/PROTOCOL.md`, wiki Protocol/Features, issues #48 (haptics), PRs #78/#85 (5.0 buzz + alarm) |
| [johnmiddleton12/my-whoop](https://github.com/johnmiddleton12/my-whoop) | 278 | 4.0 | `FINDINGS.md` — IMU/optical decode, command probe table, prior-art trust ratings |
| [b-nnett/goose](https://github.com/b-nnett/goose) | 2.5k | 5.0 | Puffin protocol, Rust core, CLIENT_HELLO, sync UX patterns |
| [bWanShiTong/openwhoop](https://github.com/bWanShiTong/openwhoop) | 285 | 4.0 (+ 5.0 WIP) | `constants.rs` command enum (most complete public list), maverick framing, alarm CLI |
| [bWanShiTong/reverse-engineering-whoop-post](https://github.com/bWanShiTong/reverse-engineering-whoop-post) | 232 | 4.0 | Alarm capture hex dumps, early command numbering (pre-consensus), CRC work |
| [andyguzmaneth/whoop4-ble](https://github.com/andyguzmaneth/whoop4-ble) | — | 4.0 | **5-byte SET_CLOCK** discovery, trim offset fix, drain semantics |
| [Alec Jude Wilson — Cracking WHOOP 5.0](https://judes.club/writing/cracking-the-whoop-5-bluetooth-protocol/) | blog | 5.0 | Bonding requirements, puffin envelope, opcode reuse vs renumbering traps |
| [felixnext/whoopy](https://github.com/felixnext/whoopy) | 5 | Cloud API | REST v2 models, OAuth, endpoints |
| [gabrielmbmb/whoop-client](https://github.com/gabrielmbmb/whoop-client) | — | Cloud API | Endpoint coverage |
| [project-whoopsie/whoopsie](https://github.com/project-whoopsie/whoopsie) | — | 4.0 | Research PoC + protocol sibling repo |
| [Gadgetbridge #5731](https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/5731) | — | 5.0 | tazjin IMU notes (6 integers), command count ~70 |
| [developer.whoop.com](https://developer.whoop.com/) | official | Cloud | OAuth scopes, OpenAPI (no BLE) |

### Repositories identified but lower trust or not fully parsed

| Repo | Why included | Trust note |
|---|---|---|
| [jogolden/whoomp](https://github.com/jogolden/whoomp) | Foundational 4.0 framing + events | **High** — cited by everyone; repo intermittently unavailable |
| [cs-balazs/gowhoop](https://github.com/cs-balazs/gowhoop) | Go BLE client | **Medium** — 4-byte SET_CLOCK (superseded by andyguzmaneth) |
| [christianmeurer/whoop-reader](https://github.com/christianmeurer/whoop-reader) | Python BLE reader | **Low** — my-whoop explicitly flags wrong UUIDs / fabricated tables |
| [jacc/whoop-re](https://github.com/jacc/whoop-re) | Cloud REST RE | **Medium** — separate from BLE |
| [zachgodsell93/Get-My-Whoop](https://github.com/zachgodsell93/Get-My-Whoop) | Cloud data export | Official API only |
| [Sivasai2207/WHOOP-Reverse-Engineering-5.0](https://github.com/Sivasai2207/WHOOP-Reverse-Engineering-5.0) | 5.0 Kotlin | Unverified |
| [ayobo1/Reverse-Engineering-Whoop-4.0](https://github.com/ayobo1/Reverse-Engineering-Whoop-4.0) | 4.0 Python | Small, unverified |

**Total: 12 repos/sources read in depth, 7+ additional identified via GitHub search and cross-citations.**

---

## 2. Community consensus (high confidence)

These are agreed across NOOP, my-whoop, openwhoop, goose, and andyguzmaneth:

### 2.1 GATT topology — WHOOP 4.0

| Role | UUID |
|---|---|
| Custom service | `61080001-8d6d-82b8-614a-1c8cb0f8dcc6` |
| Command write | `61080002-…` |
| Command response notify | `61080003-…` |
| Event notify | `61080004-…` |
| Data notify (fragmented) | `61080005-…` |
| Memfault/diagnostics notify | `61080007-…` |
| Standard HR | service `180D`, char `2A37` (works **unbonded**) |
| Standard battery | service `180F`, char `2A19` |

⚠️ **Do not use** `whoop-reader`'s UUID map — my-whoop documents it as shifted/wrong.

### 2.2 GATT topology — WHOOP 5.0 / MG ("puffin" / "maverick")

| Role | UUID |
|---|---|
| Custom service | `fd4b0001-cce1-4033-93ce-002d5875f58a` |
| Command write | `fd4b0002-…` |
| Notify channels | `fd4b0003`, `fd4b0004`, `fd4b0005`, `fd4b0007` |

Bonding is **stricter** than 4.0: custom channels need an encrypted bond. WHOOP 5 uses a static 16-byte `CLIENT_HELLO` write-with-response to initiate just-works pairing.

### 2.3 Frame envelope — WHOOP 4.0

```
[0xAA][len u16 LE][CRC8(len)][type][seq][cmd][payload…][CRC32(inner) u32 LE]
```

- `len` = inner byte count + 4 (trailer position)
- CRC8: poly `0x07` over length bytes only
- CRC32: zlib/reflected poly `0xEDB88320` over inner `[type…payload]`
- Command frames use `type = 35` (0x23)

### 2.4 Frame envelope — WHOOP 5.0

```
[0xAA][0x01][declLen u16 LE][hdr 2B][CRC16-Modbus hdr][inner…pad4][CRC32 u32 LE]
```

- Inner record starts at byte 8: `[type][seq][cmd][payload…]`
- Inner must be **padded to 4-byte boundary** before CRC32 — critical for 12-byte haptic payloads
- CRC16-Modbus over first 6 header bytes
- Puffin packet types 38/56 alias to 36/49 for decoding

### 2.5 Bonding

| Generation | Method | Notes |
|---|---|---|
| 4.0 | One **write-with-response** to command char (typically `GET_BATTERY_LEVEL` / 26) | Triggers just-works bond; FAL limits one paired phone |
| 5.0 | Static `CLIENT_HELLO` frame, write-with-response | Notify chars subscribed **after** bond; pre-bond subscribe stalls |

Live HR via `0x2A37` works without bond. **Haptics and alarms require bond.**

### 2.6 Historical offload state machine

1. `SET_CLOCK` (10) — **must** set RTC or strap won't save/serve history
2. `SEND_HISTORICAL_DATA` (22)
3. Strap streams type-47 packets + type-49/56 metadata
4. On `HISTORY_END`: client sends `HISTORICAL_DATA_RESULT` (23) with trim cursor
5. Repeat until `HISTORY_COMPLETE`

**Trim cursor offset** (consensus after andyguzmaneth + whoomp): in `HISTORY_END` metadata payload, trim is **u32 at byte offset 10** of the metadata payload (not byte 8 — older code had this wrong).

### 2.7 SET_CLOCK payload — important disagreement resolved

| Source | Payload | Verdict |
|---|---|---|
| whoomp, gowhoop, early NOOP | 4 bytes: `[epoch u32 LE]` | ❌ Accepted on wire but **RTC not updated** (andyguzmaneth) |
| andyguzmaneth, NOOP (current) | 8 bytes: `[epoch u32 LE][subsec u32 LE]` or 5+ bytes with any 5th commit byte | ✅ RTC actually latches |
| Aceso SDK (current) | 8 bytes, subsec zeros | ✅ Matches NOOP |

---

## 3. Command reference (consensus opcodes)

The most complete public enumeration is [openwhoop `constants.rs`](https://github.com/bWanShiTong/openwhoop/blob/master/src/openwhoop-codec/src/constants.rs). Below is the **safe subset** documented across NOOP + my-whoop + openwhoop.

All commands are sent as `type=35` frames on the command characteristic. Use **write-with-response** — write-without-response is silently ignored on many firmware builds.

### 3.1 Core lifecycle

| Opcode | Name | Payload | Purpose |
|---:|---|---|---|
| 1 | `LINK_VALID` | — | Keep-alive |
| 3 | `TOGGLE_REALTIME_HR` | `[0x01]` on / `[0x00]` off | Live type-40 HR stream |
| 7 | `REPORT_VERSION_INFO` | `[0x00]` | Firmware strings (harvard/boylston) |
| 10 | `SET_CLOCK` | `[epoch u32 LE][subsec u32 LE]` (8B) | Set strap RTC — **required before history** |
| 11 | `GET_CLOCK` | `[0x00]` (needs active drain on some FW) | Read RTC for clock correlation |
| 22 | `SEND_HISTORICAL_DATA` | `[0x00]` | Start history offload |
| 23 | `HISTORICAL_DATA_RESULT` | `[0x01][trim u32 LE][0x00000000]` | ACK `HISTORY_END` chunk |
| 26 | `GET_BATTERY_LEVEL` | `[0x00]` | Battery %; also 4.0 bond-init write |
| 34 | `GET_DATA_RANGE` | `[0x00]` | Oldest/newest stored record window |
| 35 | `GET_HELLO_HARVARD` | `[0x00]` | Serial, charging flag, worn byte |
| 63 | `SEND_R10_R11_REALTIME` | `[0x00]` off / `[0x01]` on | **Real** control for type-43 raw flood (not 81/82) |
| 76 | `GET_ADVERTISING_NAME_HARVARD` | `[0x00]` | BLE advertised name |

### 3.2 Research / sensors (4.0 proven)

| Opcode | Name | Payload | Purpose |
|---:|---|---|---|
| 39–44 | LED/TIA/bias get/set | varies | Optical front-end config |
| 81 | `START_RAW_DATA` | `[0x01]` | Enable raw collection mode |
| 82 | `STOP_RAW_DATA` | `[0x01]` | Disable raw collection |
| 105 | `TOGGLE_IMU_MODE_HISTORICAL` | `[0x01]` | IMU in historical |
| 106 | `TOGGLE_IMU_MODE` | `[0x01]` | IMU in realtime |
| 107 | `ENABLE_OPTICAL_DATA` | — | Optical data path |
| 108 | `TOGGLE_OPTICAL_MODE` | — | Optical mode toggle |
| 131 | `SET_RESEARCH_PACKET` | string | Research mode toggles (`enable_r19_packets`, etc.) |

### 3.3 Destructive — never send

| Opcode | Name | Hazard |
|---:|---|---|
| 25 | `FORCE_TRIM` | Discards stored data |
| 29 | `REBOOT_STRAP` | Reboots strap |
| 32 | `POWER_CYCLE_STRAP` | Power cycle |
| 36–38, 142–144 | Firmware load | Bricks device if misused |
| 45 | `ENTER_BLE_DFU` | Bootloader |
| 99 | `RESET_FUEL_GAUGE` | Battery gauge reset |

---

## 4. Haptics — vibration patterns

The WHOOP strap has a **single haptic motor** (TI DRV2625-class driver). All feedback — notifications, alarms, coaching — is patterns on that motor.

### 4.1 WHOOP 4.0 — `RUN_HAPTICS_PATTERN` (opcode **79** / 0x4F)

**Payload (5 bytes):**

```
[patternId u8][loops u8][0x00][0x00][0x00]
```

| Field | Meaning |
|---|---|
| `patternId` | Index into strap's preset library |
| `loops` | Repeat count for the pattern |

**Documented pattern IDs (4.0):**

| ID | Name / use | Source |
|---:|---|---|
| 2 | Alarm buzz | NOOP wiki — "pattern 2 = alarm buzz" |
| (others) | Query via `GET_ALL_HAPTICS_PATTERN` (80) | Returns preset table from strap |

**Stop in-progress haptic:** `STOP_HAPTICS` (opcode **122**), payload `[0x00]`.

**Enumerate patterns:** `GET_ALL_HAPTICS_PATTERN` (opcode **80**), empty payload. Response is a `COMMAND_RESPONSE` frame — exact byte layout not fully published in any repo; call the command on a bonded strap and parse the response.

**NOOP application-level patterns** (built from preset IDs + loop counts, bonded strap required):

| Use case | Pattern style |
|---|---|
| Test buzz | Single pulse |
| HIIT work interval | Triple-buzz |
| HIIT rest interval | Single buzz |
| Countdown 3-2-1 | Tick per second |
| Workout complete | Long 5-loop buzz |
| HR zone coaching | Buzz on zone entry + recovery |

### 4.2 WHOOP 5.0 / MG — `RUN_HAPTIC_PATTERN_MAVERICK` (opcode **19** / 0x13)

⚠️ **Opcode 79 is explicitly rejected** on 5.0 firmware (`COMMAND_RESPONSE result = 0x03`). This was confirmed in [NOOP issue #48](https://github.com/NoopApp/noop/issues/48).

**Payload (12 bytes):**

```
[0x01][effect0..effect7 (8 bytes)][loopControl u16 LE][overallLoop u8]
```

| Field | Meaning |
|---|---|
| byte 0 | Always `0x01` |
| effects[0..7] | Up to 4 × u16 LE **DRV2625 library effect IDs** (unused slots zero) |
| loopControl | Inner loop control (u16 LE) |
| overallLoop | Outer repeat count |

**Known working example — "notify" buzz** (NOOP #48, decompiled from official app):

```
01 2F 00 98 00 00 00 00 00 00 00 00
```

Effect IDs: **47** (0x2F) and **152** (0x98) — DRV2625 ROM waveform library entries.

**Named presets decoded from working 5.0 app** (NOOP #48):

| Preset name | Description |
|---|---|
| `notify` | Short notification tap |
| `alarm` | Alarm-strength pattern |
| `strong` | Strong buzz |
| `gentle` | Gentle buzz |

**Full preset library** (NOOP #48, post-fix): single, double, triple, pulse, strong, gentle, escalate, SOS — mapped to DRV2625 effect ID sequences. Exact byte tables live in NOOP's closed test vectors; community has not published a complete ID→name CSV.

### 4.3 DRV2625 effect ID reference (hardware)

The motor driver chip ships with a ROM waveform library. Common IDs (from TI DRV2625 docs, referenced by NOOP):

| ID | Waveform |
|---:|---|
| 1 | Strong Click |
| 2 | Medium Click |
| 3 | Light Click |
| 4 | Tick |
| 5 | Bump |
| 6 | Strong Double Click |
| 7–9 | Medium/Light double/triple |
| 10 | Buzz |
| 11–12 | Ramp up/down |
| … | (123 ROM effects total) |

5.0 presets are **compositions** of these IDs in the 8-byte effects field.

### 4.4 Haptic events (strap → app)

Subscribe to event notify char. Relevant `EventNumber` values:

| Event | Value | Meaning |
|---|---:|---|
| `HAPTICS_FIRED` | 60 | Strap played a haptic |
| `HAPTICS_TERMINATED` | 100 | Haptic stopped early |
| `STRAP_DRIVEN_ALARM_EXECUTED` | 57 | Firmware alarm fired |
| `APP_DRIVEN_ALARM_EXECUTED` | 58 | App-triggered alarm fired |

### 4.5 Practical haptics checklist

1. **Bond first** — HR alone does not prove bond
2. **Write-with-response** on command char
3. **4.0:** opcode 79, 5-byte payload
4. **5.0:** opcode 19, 12-byte payload, **4-byte pad** in puffin frame
5. Check `COMMAND_RESPONSE`: `0x01` = accepted, `0x03` = rejected/wrong opcode
6. Use `STOP_HAPTICS` (122) to cancel

---

## 5. Alarms

WHOOP alarms are **firmware-scheduled wrist buzzes** — the strap's RTC fires them even if the phone app is killed. This is distinct from sending a one-shot haptic.

### 5.1 Alarm commands (WHOOP 4.0 — consensus)

| Opcode | Name | Payload | Purpose |
|---:|---|---|---|
| 66 | `SET_ALARM_TIME` | `[0x01][epoch u32 LE][0x00][0x00]` (7 bytes) | Arm alarm for Unix time |
| 67 | `GET_ALARM_TIME` | `[0x01]` | Read currently armed alarm |
| 68 | `RUN_ALARM` | `[0x01]` | Fire alarm immediately (test) |
| 69 | `DISABLE_ALARM` | `[0x01]` | Disarm alarm |

**Swift/Go helper (NOOP):**

```swift
// epochSec = Unix seconds for wake time
[0x01] + UInt32(epochSec).littleEndianBytes + [0x00, 0x00]
```

**openwhoop CLI** accepts: absolute datetime, time-of-day (`07:00:00`), or relative (`10min`, `30min`, `hour`) — it converts to Unix epoch before sending opcode 66.

### 5.2 Alarm behavior (community observations)

| Topic | Consensus |
|---|---|
| Single daily alarm | bWanShiTong: strap holds **one** alarm slot; official app replaces it when sleep goal changes |
| Smart / light-sleep wake | Handled in **phone app / cloud** — firmware alarm fires at exact armed time (NOOP: "no light-sleep early wake") |
| Alarm modes in official app | bWanShiTong captured writes labeled "Exact time", "Peak", "Perform", "In the Green" — all share same opcode `0x42` in early numbering (= 66 decimal in current consensus) with different timestamps |
| On fire | Strap buzzes + emits `STRAP_DRIVEN_ALARM_EXECUTED` (57) or `APP_DRIVEN_ALARM_EXECUTED` (58) |
| After dismiss | `STRAP_DRIVEN_ALARM_DISABLED` (59); tapping strap sends `SEND_HISTORICAL_DATA` (bWanShiTong) |
| RTC prerequisite | Alarm requires valid RTC — run `SET_CLOCK` first |

### 5.3 WHOOP 5.0 / MG alarms — partial / experimental

| Status | Detail |
|---|---|
| Opcode numbers | Same family (66–69) cited in NOOP docs |
| Payload | May differ from 4.0 — NOOP PR #78 landed 5.0 alarm with "correct 5/MG payloads" but details are flag-gated |
| Risk | Alec Jude Wilson: on 5.0, opcode `0x42` in **old** capture was `SET_ALARM_TIME` — sending clock-like payloads at wrong lifecycle causes **buzz on every connect** |
| Recommendation | Treat 5.0 alarms as **experimental** until validated on your firmware; use haptics (opcode 19) for reliable test buzz |

### 5.4 Example: arm alarm for 07:00 tomorrow (4.0)

```swift
import WhoopSDK

// After bonded connection:
let wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0,
                                 of: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)!
let payload = WhoopCommand.setAlarmPayload(epochSec: UInt32(wake.timeIntervalSince1970))
// Send as SET_ALARM_TIME (66) inside a type-35 frame, write-with-response
```

### 5.5 Example: test buzz now (4.0)

```swift
// RUN_HAPTICS_PATTERN (79), payload [0x02, 0x02, 0x00, 0x00, 0x00]
// patternId=2 (alarm), loops=2
```

### 5.6 Example: test buzz now (5.0)

```swift
// RUN_HAPTIC_PATTERN_MAVERICK (19)
// payload: [0x01, 0x2F, 0x00, 0x98, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
// + puffin 4-byte padding in frame builder
```

---

## 6. Cloud REST API (not BLE)

Separate from strap BLE. Official docs: [developer.whoop.com](https://developer.whoop.com/).

| Python client | Coverage |
|---|---|
| [felixnext/whoopy](https://github.com/felixnext/whoopy) | OAuth, cycles, sleep, recovery, workouts, profile |
| [gabrielmbmb/whoop-client](https://github.com/gabrielmbmb/whoop-client) | Same + MCP server |
| [zachgodsell93/Get-My-Whoop](https://github.com/zachgodsell93/Get-My-Whoop) | Historical export + SQLite |

**OAuth scopes:** `read:recovery`, `read:cycles`, `read:workout`, `read:sleep`, `read:profile`, `read:body_measurement`, `offline`.

Aceso `WhoopAPI` module ports whoopy's v2 surface. Cloud API gives **computed** recovery/strain/sleep scores; BLE gives **raw** sensor data.

---

## 7. Known disagreements and traps

| Topic | Trap | Correct approach |
|---|---|---|
| Service UUID | `whoop-reader` uses `61080000-…` | Use `61080001-…` |
| SET_CLOCK size | 4-byte payload | Use 8 bytes (or ≥5 with any commit byte) |
| HISTORY_END trim | trim at byte 8 | trim at byte **10** of metadata payload |
| 5.0 haptics | opcode 79 | opcode **19** with 12-byte DRV2625 payload |
| 5.0 framing | skip padding | pad inner to **4-byte boundary** |
| Raw data flood | STOP_RAW_DATA (82) | Use **SEND_R10_R11_REALTIME** (63) |
| Early bWanShiTong opcode `0x42` | "set alarm" in hex captures | Same as decimal **66** in modern tables — numbering style differs by author |
| SpO2 / skin temp values | expected on BLE | **Not on wire** — computed in WHOOP cloud from raw PPG |
| Bond vs HR | HR works ⇒ bonded | 0x2A37 works **unbonded**; haptics need bond |

---

## 8. What Aceso WhoopSDK implements today

| Area | Status |
|---|---|
| 4.0 + 5.0 framing/CRC | ✅ |
| Bond, reconnect, FAL errors | ✅ |
| Live HR, battery, history offload | ✅ |
| IMU + optical raw decode | ✅ (my-whoop offsets) |
| Strap events | ✅ (partial set) |
| Alarm commands | ⚠️ Opcodes defined, **not exposed** in BLE client API |
| 4.0 haptics (79) | ⚠️ Opcode defined, **not exposed** in BLE client API |
| 5.0 haptics (19) | ❌ Not implemented |
| GET_ALL_HAPTICS_PATTERN | ❌ Not implemented |
| Cloud REST v2 | ✅ WhoopAPI module |

---

## 9. Recommended reading order

1. [NOOP PROTOCOL.md](https://github.com/NoopApp/noop/blob/main/docs/PROTOCOL.md) — best single BLE reference
2. [my-whoop FINDINGS.md](https://github.com/johnmiddleton12/my-whoop/blob/main/FINDINGS.md) — IMU/optical + trust table
3. [openwhoop constants.rs](https://github.com/bWanShiTong/openwhoop/blob/master/src/openwhoop-codec/src/constants.rs) — fullest command enum
4. [NOOP issue #48](https://github.com/NoopApp/noop/issues/48) — 5.0 haptics decode
5. [andyguzmaneth PROTOCOL.md](https://github.com/andyguzmaneth/whoop4-ble/blob/main/docs/PROTOCOL.md) — SET_CLOCK + trim fix
6. [Alec Jude Wilson — WHOOP 5.0](https://judes.club/writing/cracking-the-whoop-5-bluetooth-protocol/) — bonding + puffin envelope

---

## 10. Attribution

Reverse-engineering credit (community convention):

- **johnmiddleton12/my-whoop** — WHOOP 4.0 protocol, IMU/optical
- **b-nnett/goose** — WHOOP 5.0 puffin protocol
- **jogolden/whoomp** — framing, commands, events
- **bWanShiTong** — early traffic analysis, alarm captures
- **NoopApp/noop** — unified 4.0+5.0 docs, 5.0 haptics/alarm fixes
- **andyguzmaneth/whoop4-ble** — SET_CLOCK 5-byte discovery, trim offset

This is an independent interoperability project. Not affiliated with WHOOP. Not a medical device.
