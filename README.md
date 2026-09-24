# Dark Magic – FiveM

A standalone FiveM resource: black energy pours out of the player's hand, twists into a
purple-black beam, scorches whatever it touches and is visible to every player nearby. Four
spells, an energy pool with overheat, a charged shot, curses that slow and darken their victims.

## Spells

Cycle with **Caps Lock** (rebindable) or `/darkspell beam|orb|curse|lift`.

| Spell | Key | What it does |
| --- | --- | --- |
| **Beam** | hold **E** | Twisted dark beam from the hand. Damages vehicles, NPCs and players, drops fire zones, reacts to the surface it hits. Release after a full charge to fire a **charged shot**: a dark explosion at the impact point. |
| **Dark Orb** | press **E** | A ball of black energy flies from the hand and detonates on impact. |
| **Curse** | press **E** | A rune circle appears where you aim for eight seconds: everyone inside is hurt, slowed and their vision darkens. NPCs inside take damage too. |
| **Grasp** | hold **E** on a vehicle | Lifts an unoccupied vehicle in front of you and holds it; release to hurl it where the camera points. |

**Energy**: every spell drains the pool shown on the HUD bar. It regenerates after a second of
rest; emptying it completely overheats the magic for a few seconds (bar turns red).

**Victims** hit by the beam, a blast or a curse are slowed, cannot sprint, take damage over time
and see their screen darken for a moment.

## Features

- **Beam**: camera-facing glow-and-core ribbon, dark twisted tendrils, travelling energy orbs,
  pulsing impact sphere, expanding shock ring and a spinning rune on the ground.
- **Material-aware impacts**: sparks on metal and vehicles, dust on concrete and dirt, dark smoke
  on wood (which burns longer), splashes and steam on water (no fire), scorch decals left behind.
- **Light**: purple point lights at the hand and the impact plus a spotlight that stops at the
  impact; blasts and curses light their surroundings.
- **Particles**: tinted smoke-and-crackle aura on the hand, looped emitters that drift along the
  beam, throttled sparks and puffs, dark-cloud and electric bursts, "appear / vanish" puffs.
- **Charge-up**: everything ramps over the first second of channelling (size, light, particles,
  camera shake, rumble, tint, damage).
- **Feel**: the arm follows the camera (pointing move network), hand-held camera shake, release
  punch, dark high-contrast tint that fades out, pulsed gamepad rumble, sounds on every event, a
  HUD with energy bar, charge bar and current spell.
- **Sync**: other players see your beam, orb, grasped vehicle, aura, emitters, lights, particles,
  rings, blasts and curses (state bags at 10 Hz with keep-alive, server broadcasts for one-shot
  events, distance-based level of detail up to 150 m).
- **Safe**: ACE permission, server-side range, routing-bucket, cooldown and rate checks,
  NaN-proof numbers, server watchdog against forged beams, asset loading with timeouts, full
  cleanup on stop.

## Requirements

- FiveM server with **OneSync** enabled (`onesync on` or `infinity`). Without it player damage,
  curses and sync are silently unavailable; the server prints a warning at start.

## Installation

1. Put the files in `resources/dark_magic`. The folder name is the resource name: if you cloned
   the repository, rename `Dark-magic` to `dark_magic` or adapt the `ensure` line. Releases on
   GitHub ship a ready-to-drop `dark_magic.zip`.
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
| Cast | **E** (rebindable: *Dark Magic - Channel*) |
| Next spell | **Caps Lock** (rebindable: *Dark Magic - Next spell*) or `/darkspell <name>` |

Aim with the camera; the beam leaves your right hand and hits whatever the reticle points at
within 35 m. Fire zones appear after 450 ms of channelling and burn for two seconds.

Magic switches itself off when you die or when you draw a weapon (`Config.WeaponPolicy`). You
cannot cast from inside a vehicle unless `Config.AllowInVehicle = true`. FiveM remembers each
player's first-seen key binding, so changing `CastKey` or `SpellKey` later only affects new
players; existing players rebind in Settings > Key Bindings > FiveM.

## Configuration

Everything lives in `config.lua`:

| Key | What it does |
| --- | --- |
| `Range`, `ChargeMs`, `RecastMs` | reach, charge-up time, minimum gap between beam casts |
| `AcePermission` | ACE string checked by the server (default `darkmagic.use`) |
| `CastKey`, `SpellKey`, `ToggleKey` | default key bindings |
| `WeaponPolicy` | `holster` (default, magic replaces the weapon), `require` (needs a weapon in hand) or `ignore` |
| `AutoOffOnDeath`, `AllowInVehicle`, `Notify` | auto-disable on death, casting from a vehicle, notifications |
| `LoadTimeoutMs` | max wait for a particle or animation asset; on timeout `[dark_magic] failed to load ...` is printed and that effect is skipped |
| `Spells` | spell order and names, orb speed and cost, curse radius / duration / damage / cooldown, grasp hold distance and throw speed |
| `Mana` | pool size, beam drain, regeneration, overheat duration, minimum to cast |
| `Blast` | charged shot and orb explosions: radius, explosion type, damage scale, particles, light |
| `Debuff` | victim slow factor, damage over time, darkness tint and durations per source |
| `Materials`, `Decal` | collision material hashes per category, scorch decal type and lifetime |
| `Beam`, `Impact`, `Lights` | colours, ribbon widths, tendrils, orbs, ring sizes, light ranges |
| `Ptfx` | every particle effect used, per material category |
| `Screen` | timecycle tint and fade, optional post-FX, camera shakes, rumble, hit flash |
| `Audio` | sound names per event; set `enabled = false` to mute |
| `Anim` | `point` (arm follows the camera) or `clip` (dict/clip upper-body loop) |
| `Fire`, `Damage` | fire zone budget and damage numbers per entity type |
| `Sync` | replication rate, keep-alive, stale timeout, render distance and LOD bands |
| `Hud`, `Text` | HUD position and fade, every user-facing string |

All particle, timecycle, screen-FX, decal and animation names are verified against GTA V data
dumps. Sound names exist in the game but are a matter of taste: swap them freely. Some DLC sound
sets need their audio bank loaded on your server; if one stays silent, pick another.

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
