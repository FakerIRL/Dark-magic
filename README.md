# Dark Magic – FiveM

A standalone FiveM resource: black energy pours out of the player's hand, twists into a
purple-black beam, scorches whatever it touches and is visible to every player nearby.

## Features

- **Beam**: a camera-facing glow-and-core ribbon with dark twisted tendrils, travelling energy
  orbs, a pulsing impact sphere, an expanding shock ring and a spinning rune on the ground.
- **Light**: purple point lights at the hand and the impact point plus a spotlight that stops at
  the impact, so the magic lights up the scene at night.
- **Particles**: tinted smoke-and-crackle aura on the hand, four looped emitters that drift along
  the beam, throttled sparks and dark puffs spaced by distance, dark-cloud and electric bursts at
  the impact, "appear / vanish" puffs when the cast starts and ends.
- **Charge-up**: everything ramps up over the first second of channelling (beam size, light,
  particles, camera shake, controller rumble, screen tint, damage).
- **Feel**: the arm follows the camera (pointing move network), hand-held camera shake with a
  release punch, purple screen tint that fades out, pulsed gamepad rumble, sounds on arm, cast
  and hit, a charge bar that only shows while channelling.
- **Gameplay**: fire zones along the beam path, vehicle damage (relayed through the server when
  another player owns the vehicle), NPC damage + ragdoll + push, player damage validated by the
  server, objects pushed away.
- **Sync**: other players see your beam, aura, emitters, lights, particles and rings (state bags,
  10 Hz with keep-alive, distance-based level of detail up to 150 m).
- **Safe**: ACE permission, server-side range, routing-bucket and rate checks, NaN-proof damage,
  server watchdog against forged beams, asset loading with timeouts, full cleanup on stop.

## Requirements

- FiveM server with **OneSync** enabled (`onesync on` or `infinity`). Without it player damage
  and beam sync are silently unavailable; the server prints a warning at start.

## Installation

1. Put the files in `resources/dark_magic`. The folder name is the resource name: if you cloned
   the repository, rename `Dark-magic` to `dark_magic` or adapt the `ensure` line.
2. In `server.cfg`:

```cfg
ensure dark_magic
add_ace group.admin darkmagic.use allow
```

Give the `darkmagic.use` permission to whichever group or identifier should be able to cast.

## Usage

| Action | How |
| --- | --- |
| Toggle magic | `/darkmagic`, or bind *Dark Magic - Toggle* in Settings > Key Bindings > FiveM |
| Force off | `/darkmagicoff` |
| Channel | hold **E** (rebindable: *Dark Magic - Channel* in Settings > Key Bindings > FiveM) |

Aim with the camera; the beam leaves your right hand and hits whatever the reticle points at
within 35 m. Fire zones appear after 450 ms of channelling and burn for two seconds.

Magic switches itself off when you die or when you draw a weapon (`Config.WeaponPolicy`). You
cannot channel from inside a vehicle unless `Config.AllowInVehicle = true`. FiveM remembers each
player's first-seen key binding, so changing `CastKey` later only affects new players; existing
players rebind in Settings > Key Bindings > FiveM.

## Configuration

Everything lives in `config.lua`:

| Key | What it does |
| --- | --- |
| `Range`, `ChargeMs`, `RecastMs` | reach of the beam, charge-up time, minimum gap between casts |
| `AcePermission` | ACE string checked by the server (default `darkmagic.use`) |
| `CastKey`, `ToggleKey` | default key bindings |
| `WeaponPolicy` | `holster` (default, magic replaces the weapon), `require` (needs a weapon in hand) or `ignore` |
| `AutoOffOnDeath`, `AllowInVehicle`, `Notify` | auto-disable on death, casting from a vehicle, notifications |
| `LoadTimeoutMs` | max wait for a particle or animation asset; on timeout `[dark_magic] failed to load ...` is printed and that effect is skipped |
| `Beam`, `Impact`, `Lights` | colours, ribbon widths, tendrils, orbs, ring sizes, light ranges |
| `Ptfx` | every particle effect used (asset, name, scale, tint), beam emitters and burst spacing |
| `Screen` | timecycle tint and fade, optional post-FX, camera shakes, rumble, hit flash |
| `Audio` | sound names per event; set `enabled = false` to mute |
| `Anim` | `point` (arm follows the camera) or `clip` (dict/clip upper-body loop) |
| `Fire`, `Damage` | fire zone budget and damage numbers per entity type |
| `Sync` | replication rate, keep-alive, stale timeout, render distance and LOD bands |
| `Hud`, `Text` | charge bar position and fade, every user-facing string |

All particle, timecycle, screen-FX and animation names are verified against GTA V data dumps.
Sound names exist in the game but are a matter of taste: swap them freely. Some DLC sound sets
need their audio bank loaded on your server; if one stays silent, pick another.

## API

```lua
exports.dark_magic:setState(source, true)   -- arm or disarm a player from another resource
exports.dark_magic:isEnabled(source)        -- boolean
```

## Upgrading from 1.x

- The client events `darkmagic:toggle` and `darkmagic:forceoff` no longer exist; use the
  exports above or the `/darkmagic` and `/darkmagicoff` commands.
- The default weapon rule changed from "needs a weapon in hand" to "magic replaces the weapon";
  set `Config.WeaponPolicy = 'require'` to keep the old behaviour.

## Credits

Development: Fake
