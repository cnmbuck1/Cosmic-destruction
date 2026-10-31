# Implementation notes

## Build sheet 2.0 (v0.2.0)

Goal: destroying futuristic structures on a moon suspended over an endless
void, not shooting blocks on a circular board.

- **Destruction physics.** `DestructionPhysicsConfig` (Core/GameConfig.swift)
  holds every tunable value. On a significant orb hit, `GameSession` triggers a
  supplemental radial impulse (`StructureManager.applyRadialImpulse`) with
  quadratic distance falloff, a forward bias along the shot, an upward
  component, impulses scaled by block mass, and a hard clamp. It fires at most
  twice per orb, with a 0.3 s cooldown. The struck block also gets an extra
  push (`orbImpulseMultiplier`). Block speed is clamped every frame.
- **No invisible walls.** `AbyssCleanupManager` lets debris fall freely. It
  fades it between 4 m and 22 m below the platform (or very far sideways) and
  removes it only once it is fully faded.
- **Components.** standard, beam, column, heavy, wedge (triangular prism with
  a convex-hull body), and energy. Only energy cores glow. Columns are 2.5x
  denser so stacks never sit heavy-on-light, which makes solvers jitter.
- **Levels.** Lunar Gateway (21 pieces), Twin Spires (31), Orbital Citadel
  (37). All were checked for stability with a headless cannon.js simulation
  over 8 s at both stabilizer damping and zero damping (max drift under 6 cm).
  Each level has a `defaultElevation`, so an un-aimed first shot hits the
  structure instead of flying through the gate or under the deck.
- **Lunar fragment.** `PlatformBuilder` builds an 18 x 16 m fragment from
  custom meshes: an irregular outline (harmonic noise plus bites), a top
  surface that is exactly flat over the play area and cratered in the outer
  band, stacked strata rows, and a tapering rocky root under the island.
  Neon is limited to broken cyan edge accents, sparse fractures and veins,
  crystals, and the energy circle under the structure. Physics is a flat
  convex slab with its top at y = 0.
- **Camera.** It sits behind and above the cannon, tilted about 32 degrees
  down. The structure is in the upper third and the fragment's front edge,
  with the void beneath it, is at the bottom. Wide levels pull back via
  `cameraPullBack`. After the first impact the look target leans up to 18%
  toward it and eases back.
- **Completion.** A shot resolves when the orb is done, every block on the
  platform is below the settle speed, and nothing significant has collided
  for 0.5 s, or after 5 s. Victory waits 1.1 s so the collapse can play out.
- **HUD.** "DESTRUCTION: 65%" has a rolling number and a pulse on each
  increase.
- **Effects.** An expanding flat cyan shockwave plays at each supplemental
  impulse. Up to 6 debris pieces moving faster than 7 m/s carry glowing
  trails. Camera shake is scaled by `cameraShakeIntensity`.

# Prototype v0.1.0

## Architecture

| Spec component | Implementation |
|---|---|
| GameManager | `Core/GameManager.swift`: phases (aiming → resolving → won / failing → failed), shot counting, resolution timing, star scoring. Pure Swift, so it's unit-testable. |
| LevelManager | `Core/LevelManager.swift` + `Core/Levels.swift` (hand-authored block lists) + `Core/LevelDefinition.swift`. |
| SceneManager | `Scene/SceneManager.swift`: background, lighting, camera rig, containers, cleanup. Platform in `Scene/PlatformBuilder.swift`. |
| CannonController | `Gameplay/CannonController.swift`: geometry, yaw/elevation limits, charge glow, recoil. |
| OrbController | `Gameplay/OrbController.swift` (physics, lifecycle, cap of 3 active orbs) + `Gameplay/OrbVisual.swift` (swappable visual). |
| StructureManager | `Gameplay/StructureManager.swift`: builds blocks, tracks targets, displacement, abyss fade and cleanup. |
| EffectsManager | `Effects/EffectsManager.swift`. |
| AudioManager | `Audio/AudioManager.swift` (sound + haptics) + `Audio/SoundSynth.swift`. |
| GameUI | `UI/*`: HUD, overlays, menus; aiming indicator in `Gameplay/TrajectoryIndicator.swift`. |

`Engine/GameSession.swift` is the coordinator. It owns the SceneKit systems and
the engine-agnostic `GameManager`, and runs the game loop. Moving to RealityKit
means replacing `Scene/`, `Gameplay/`, `Effects/` and `GameSession`, while
`Core/` and `UI/` stay as they are.

## Key decisions

- **Main-thread game loop.** A `CADisplayLink` drives all game logic on the
  main thread. SceneKit physics contacts arrive on its render thread, so
  `ContactCollector` buffers them behind a lock and the loop drains them each
  frame. This keeps every gameplay class single-threaded and `@MainActor`.
- **Simulation clock.** Resolution timers use a clock that advances with
  physics speed and stops while paused. Pause and slow motion therefore never
  cut a shot short.
- **Stable stacks at load.** Blocks start a few millimeters apart vertically.
  Until the first shot they get heavy damping (`stabilizerDamping`), which
  stops the start-of-level jitter and creep that rigid-body stacks often show.
  Damping goes back to normal the moment the player fires.
- **Removal rule.** A target counts as removed once its center drops below
  `y = -1.6` (just under the platform's 1.5 m thickness) or leaves the ±12.5 m
  play area. Small moves and rotations never count.
- **Abyss.** Falling blocks keep simulating. Between y = -5 and y = -18 they
  fade and shrink (the scaling is on a child visual node, so physics isn't
  disturbed), and below -18 they are removed.
- **Shot resolution.** The next shot unlocks after at least 1 s, once the orb
  has resolved and the on-platform blocks have settled, or after at most 4.5 s.
  If the objective is already met, it ends early.
- **Failure grace.** After the last shot, there is a 1 s settle window before
  the Level Failed overlay. A block that falls during that window can still
  win the level.
- **Slow motion.** This triggers once per shot, when at least 35% of target
  blocks have moved more than 0.6 m during that shot. It runs at 0.3× physics
  speed for 0.4 s, then eases back over 0.25 s. It can be turned off in the
  developer settings.
- **Visuals.** HDR camera with bloom, PBR materials, and a procedural
  equirectangular starfield/nebula that also serves as the reflection
  environment. One shadow-casting directional light. Materials and block
  geometry are shared and cached.
- **Platform.** An irregular superellipse outline is extruded with `SCNShape`.
  Its collision shape is a convex hull: stable and cheap, but up to about
  0.3 m generous at the notches in the edge. Glowing rims are slightly larger
  thin copies of the outline that show along the edge.
- **Audio.** All sounds are synthesized at launch with `AVAudioEngine` (sine
  sweeps, filtered noise, arpeggios, and a seamless ambient drone loop). There
  are no audio files and no licensing questions. If the engine fails to start,
  the game continues silently.
- **Orb branding.** `SignatureOrbVisual` is a placeholder that uses no logo or
  wordmark. To use the final design, implement `OrbVisual` and assign it to
  `OrbController.visual`.
- **Swift 5 language mode** with minimal concurrency checking, chosen for
  prototype speed. Moving to Swift 6 strict concurrency is a later cleanup.

## Tuning starting points (`Core/GameConfig.swift`)

| Value | Default |
|---|---|
| Orb mass / radius | 12 kg / 0.4 m |
| Launch speed | 24 m/s |
| Gravity | -12 (levels 1 and 2), -10 (level 3) |
| Block mass | 0.55 kg per 0.8 m cube (heavy 1.8 kg, scaled by volume and kind density) |
| Block friction / restitution | 0.55 / 0.12 |
| Radial impulse | strength 7.5, radius 2.4 m, vertical 0.35, forward bias 0.45, max 9 |
| Max block speed | 22 m/s |
| Physics timestep | 1/120 s |
| Camera | horizontal FOV 60°, elevation 7.6 m, 4.2 m behind the cannon |

(Values updated for v0.2.0.)

These values have **not been playtested on a device yet**. Use the debug
overlay sliders to tune feel, then copy the values you like back into
`PhysicsTuning`.

## Known gaps

- No unit test target yet. `GameManager`, `LevelDefinition.stars`, and
  `ProgressStore` are written to be testable.
- The app icon slot is empty (the asset catalog only has a placeholder entry).
- Level difficulty and the 80% threshold need tuning in real playtests.
- There is no collapse-specific camera dolly. Only shake and slow motion are
  used, to keep the camera from disorienting the player.

## Suggested next iteration

1. Playtest on device and tune `PhysicsTuning` and the level layouts.
2. Add an XCTest target covering GameManager, scoring, and progression.
3. Energy block mechanic (for example, chain-reaction pulse on impact).
4. App icon and the final branded orb visual.
5. More levels, data-driven (JSON) once the format settles.
6. Profile with Instruments (draw calls, physics cost at 40+ bodies).
