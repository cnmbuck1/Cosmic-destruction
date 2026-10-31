# Cosmic Destruction

**Cnmbuck Studios**: a physics-based 3D destruction puzzle game for iPhone.
Prototype v0.2.0 (Swift, SceneKit, SwiftUI; iOS 17+, portrait).

You fire the Cnmbuck signature orb from an electromagnetic railgun at
futuristic structures standing on a broken fragment of moon suspended over an
endless void. Knock 80% of the target pieces into the abyss before you run out
of shots. Levels: Lunar Gateway, Twin Spires, Orbital Citadel.

## Run it

1. Open `CosmicDestruction.xcodeproj` in **Xcode 16 or newer**. The project uses
   folder-synchronized groups, so every file under `CosmicDestruction/` is
   included automatically.
2. Pick the **CosmicDestruction** scheme and any iPhone simulator (iOS 17+).
3. Press **Run** (⌘R).

To run on a physical iPhone, select your team under *Signing & Capabilities*
(the bundle ID is `com.cnmbuckstudios.cosmic-destruction`, registered to Cnmbuck Studios).

Command-line build (the same command CI runs):

```sh
xcodebuild -project CosmicDestruction.xcodeproj -scheme CosmicDestruction \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## How to play

- **Drag anywhere** to aim. Horizontal drag turns the cannon, vertical drag
  raises or lowers it. A dotted cyan line previews the orb's path.
- **Release** to fire.
- Remove 80% of the target blocks (shown in the HUD bar) within 3 shots.
  Stars: 1 shot = ★★★, 2 shots = ★★, 3 shots = ★.

## Debug tools

In a **Debug** build, go to *Settings › Developer* and turn on **Debug overlay
button**. A `DBG` button then appears in the HUD. It shows FPS, bodies,
phase, orb speed and hits, radial impulses this shot, moved/fallen blocks,
debris trails, settle state, fragment size, abyss thresholds, and camera
values. It has live sliders grouped as projectile, blocks, destruction,
environment, and camera (all of `DestructionPhysicsConfig`). *Slow-motion
moments* can also be switched off there.

## Project layout

```
CosmicDestruction/
  App/        App entry point and screen navigation
  Core/       Engine-agnostic rules (no SceneKit imports)
              GameConfig, GameManager, LevelDefinition, Levels, LevelManager, ProgressStore
  Engine/     GameSession (game loop + coordinator), GameSCNView (touch input), physics helpers
  Scene/      SceneManager, PlatformBuilder, MaterialLibrary, ProceduralTextures
  Gameplay/   CannonController, OrbController, OrbVisual, StructureManager, AbyssCleanupManager, TrajectoryIndicator
  Effects/    EffectsManager (flashes, particles, shockwaves, shake, slow motion)
  Audio/      AudioManager (sound + haptics), SoundSynth (procedurally generated audio)
  UI/         SwiftUI menus, HUD, overlays, debug overlay
docs/IMPLEMENTATION_NOTES.md   Design decisions, tuning notes, next steps
```

There are no external dependencies or bundled assets. Every texture and sound
is generated at runtime.

## TestFlight

`.github/workflows/testflight.yml` archives a Release build, signs it with
Xcode's automatic signing using an App Store Connect API key, and uploads it
to TestFlight. You can run it from the Actions tab (*TestFlight › Run
workflow*) or by pushing a `v*` tag. It needs four repo secrets:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the .p8 file contents), and
`APPLE_TEAM_ID`. The build number is the workflow run number.

## Web preview

`web-preview/index.html` is a standalone browser port (Three.js + cannon.js)
of the same three levels, used for quick sharing. It is separate from the
iOS code, so changes to one are not reflected in the other.
