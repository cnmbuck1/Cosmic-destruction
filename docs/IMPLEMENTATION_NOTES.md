# Implementation notes: prototype v0.1.0

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
| Orb mass / radius | 9 kg / 0.38 m |
| Launch speed | 21 m/s |
| Gravity | -13 (levels 1 and 2), -10 (level 3) |
| Block mass | 1 kg per 0.9 m cube (heavy ×3.5, scaled by volume) |
| Block friction / restitution | 0.7 / 0.08 |
| Physics timestep | 1/120 s |
| Camera | horizontal FOV 66°, fixed behind and above the cannon |

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
