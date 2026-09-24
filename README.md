# Dark Magic – FiveM

A standalone FiveM resource: black energy pours out of the player's hand, twists into a
purple-black beam, scorches whatever it touches and is visible to every player nearby.

## Features

- **Beam**: twisted dark tendrils around a bright violet core, travelling energy orbs,
  pulsing impact sphere and rotating rune rings on the ground.
- **Light**: purple point lights at the hand and the impact point plus a spotlight along the
  beam, so the magic actually lights up the scene at night.
- **Particles**: smoky purple aura on the hand, tinted sparks and dark puffs along the beam,
  dark-cloud and electric bursts at the impact, "appear / vanish" puffs when the cast starts
  and ends. Emission is throttled, not spammed every frame.
- **Charge-up**: everything ramps up over the first second of channelling (beam size, light,
  particles, camera shake, controller rumble, screen tint, damage).
- **Feel**: channelling pose, subtle hand-held camera shake, purple screen tint, gamepad
  rumble, sounds on arm / cast / hit, a small charge bar on the HUD.
- **Gameplay**: fire zones along the beam path, vehicle damage, NPC damage + ragdoll + push,
  player damage validated by the server, objects pushed away.
- **Sync**: other players see your beam, aura, lights and particles (state bags, 10 Hz).
- **Safe**: ACE permission, server-side range and rate checks, asset loading with timeouts,
  full cleanup on resource stop.

## Installation

1. Copy the folder to `resources/dark_magic`.
2. In `server.cfg`:

```cfg
ensure dark_magic
add_ace group.admin darkmagic.use allow
```

Give the `darkmagic.use` permission to whichever group or identifier should be able to cast.

## Usage

| Action | How |
| --- | --- |
| Toggle magic | `/darkmagic` (or bind the *Dark Magic - Toggle* key in Settings > Key Bindings > FiveM) |
| Force off | `/darkmagicoff` |
| Channel | hold **E** (rebindable: *Dark Magic - Channel* in Settings > Key Bindings > FiveM) |

Aim with the camera; the beam leaves your right hand and hits whatever the reticle points at
within 35 m. Fire zones appear once the charge passes 35 % and burn for two seconds.

Magic switches itself off when you die or when you draw a weapon (`Config.WeaponPolicy`).

## Configuration

Everything lives in `config.lua`:

| Key | What it does |
| --- | --- |
| `Range`, `ChargeMs` | reach of the beam and charge-up time |
| `CastKey`, `ToggleKey` | default key bindings |
| `WeaponPolicy` | `holster` (default), `require` (original behaviour) or `ignore` |
| `Beam`, `Impact`, `Lights` | colours, thickness, strands, orbs, ring size, light ranges |
| `Ptfx` | every particle effect used (asset, name, scale, tint) |
| `Screen` | timecycle tint, optional post-FX, camera shake, rumble, hit flash |
| `Audio` | sound names per event; set `enabled = false` to mute |
| `Anim` | channelling pose |
| `Fire`, `Damage` | fire zones and damage numbers per entity type |
| `Sync` | replication rate and max render distance for other players |
| `Hud`, `Text` | charge bar position and every user-facing string |

All particle, timecycle, screen-FX and animation names are verified against GTA V data
dumps. Sound names exist in the game, but are a matter of taste: swap them freely.

## Credits

Development: Fake
