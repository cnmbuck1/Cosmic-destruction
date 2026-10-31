# Cosmic Destruction

**Cnmbuck Studios**: a physics-based 3D destruction puzzle game for iPhone.
Prototype v0.1.0 (Swift, SceneKit, SwiftUI; iOS 17+, portrait).

You fire the Cnmbuck signature orb from an electromagnetic railgun at
structures standing on a neon lunar platform floating in space. Knock 80% of
the target blocks off the platform before you run out of shots.

## Run it

1. Open `CosmicDestruction.xcodeproj` in **Xcode 16 or newer**. The project uses
   folder-synchronized groups, so every file under `CosmicDestruction/` is
   included automatically.
2. Pick the **CosmicDestruction** scheme and any iPhone simulator (iOS 17+).
3. Press **Run** (⌘R).

To run on a physical iPhone, select your team under *Signing & Capabilities*
(the bundle ID is `com.cnmbuckstudios.cosmicdestruction`; change it if it's taken).

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
button**. A `DBG` button then appears in the HUD. It shows FPS, rigid-body
count, gravity, launch speed, yaw/elevation, targets left, and completion, and
has live sliders for orb mass, launch speed, gravity, block friction,
restitution, mass, settle threshold, and camera FOV. *Slow-motion moments* can
also be switched off there.

## Project layout

```
CosmicDestruction/
  App/        App entry point and screen navigation
  Core/       Engine-agnostic rules (no SceneKit imports)
              GameConfig, GameManager, LevelDefinition, Levels, LevelManager, ProgressStore
  Engine/     GameSession (game loop + coordinator), GameSCNView (touch input), physics helpers
  Scene/      SceneManager, PlatformBuilder, MaterialLibrary, ProceduralTextures
  Gameplay/   CannonController, OrbController, OrbVisual, StructureManager, TrajectoryIndicator
  Effects/    EffectsManager (flashes, particles, shockwaves, shake, slow motion)
  Audio/      AudioManager (sound + haptics), SoundSynth (procedurally generated audio)
  UI/         SwiftUI menus, HUD, overlays, debug overlay
docs/IMPLEMENTATION_NOTES.md   Design decisions, tuning notes, next steps
```

There are no external dependencies or bundled assets. Every texture and sound
is generated at runtime.
