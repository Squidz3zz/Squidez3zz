# Main Menu v3: Loading Screen, Music, Button Sounds, "You" in Credits, Repeating Wave

**Date:** 2026-10-05
**Place:** "Untitled Experience" (placeId 95688118364991)

**Builds on:** `docs/superpowers/specs/2026-10-04-main-menu-v2-design.md` (merged to master) and v1. All v1 and v2 guarantees still hold:
- the player spawns only on Play, and respawns after death;
- the I-1 fallback stays: a menu that cannot open spawns the player;
- nothing new yields on the Play path, and every module call from init is pcall'd;
- scene hooks must not yield and must be idempotent;
- the full-screen overlay ScreenGuis stay as they are.

**Status:** design approved in chat; this spec awaits review.

## Goal

Add four things, all in the existing heavy-factory theme:
1. A factory-themed **loading screen** that genuinely preloads the menu's assets before the menu appears.
2. **Background music**, one looping track per scene, plus **button sound effects**. Both follow the Settings board's Music and Sound Effects sliders.
3. In Credits, move the **viewing player's avatar off the podium** into the foreground. It stands with its back to the camera, looking at the developer's podium, and its hover label reads **"YOU"**.
4. Make the main-menu avatar **wave repeatedly**.

## Sound assets (supplied by the user)

| Key | Asset | Used for |
|---|---|---|
| `Hover` | rbxassetid://113223325628963 | pointer or gamepad selection enters any menu button, including PLAY |
| `Confirm` | rbxassetid://111174530730534 | clicking any button except PLAY |
| `PlaySelect` | rbxassetid://81613840001484 | clicking PLAY |
| `MenuMusic` | rbxassetid://107320882976955 | Menu scene music (loops) |
| `SettingsMusic` | rbxassetid://108614839813561 | Settings scene music (loops) |
| `CreditsMusic` | rbxassetid://88263973909083 | Credits scene music (loops) |

## Success criteria

**Loading screen**
- The factory loading screen appears within the first second of joining. Roblox's default loading screen is removed.
- It shows:
  - the game title, in Oswald Bold with amber trim;
  - a spinning amber gear/hazard ring;
  - one tip, which changes every 4 s.
- It stays up for at least 2 s. It hands over once assets are loaded, or after 20 s at most.
- It fades to black, then the menu fades in.

**Music**
- The scene's track loops at the Music slider's volume.
- Changing scene crossfades tracks behind the black fade.
- Pressing PLAY fades the music out within the 0.4 s screen fade.
- Nothing plays after Play.

**Button sounds**
- The Hover, Confirm and PlaySelect sounds play as in the table, at the Sound Effects slider's volume.
- Hover is not repeated for a button that is already hovered.

**Credits**
- The viewer's avatar stands in the foreground, off to one side, with its back to the camera, facing the developer's podium.
- It does not hide the developer avatar, the developer's name label, or the BACK button.
- Hovering it, or tapping it, shows the amber outline and the label `YOU`.
- `ViewerCreditStand` stays in the room, empty.

**Main-menu avatar**
- It waves when it appears, then again every 6 s while the menu is shown.

**Failure handling**
- A sound that fails to load is skipped with a warning. Everything else still works.
- A failing or missing loading screen never stops the menu from opening, and never stops Play.

**Console**
- No errors during the full flow.

## Assumptions

- The user owns the six audio assets, or they are public, so Roblox lets them play in this experience. Each is verified at implementation time, and any that won't load are reported to the user.
- Music and Sound Effects default to 0.5. Settings are still not saved between sessions.
- Gameplay music is out of scope.

## Asset config: `ReplicatedFirst.MenuAssets` (ModuleScript)

This is the one place to edit sound IDs and tips. It lives in ReplicatedFirst so the loading screen can read it before anything else has replicated.

- `Sounds`: a table of the six keys and asset IDs above.
- `Tips`: an array of 6–8 short factory-flavoured placeholder tips. One example: "TIP: THE FURNACE NEVER SLEEPS. NEITHER DO WE." The user edits these.
- `LOADING_MIN_SECONDS = 2`, `LOADING_MAX_SECONDS = 20`, `TIP_SECONDS = 4`.

Disk path: `src/ReplicatedFirst/MenuAssets.luau`.

## Loading screen: `ReplicatedFirst.LoadingScreen` (LocalScript)

Disk path: `src/ReplicatedFirst/LoadingScreen.client.luau`.

### Startup
1. **Build the UI.** Build a ScreenGui `LoadingScreen` in code and parent it to PlayerGui immediately. Then call `ReplicatedFirst:RemoveDefaultLoadingScreen()`. The ScreenGui has:
   - IgnoreGuiInset true, ScreenInsets None, DisplayOrder 20, so it sits above every menu gui;
   - ResetOnSpawn false;
   - a full-screen backdrop RGB(16,14,12) with the same four-edge vignette gradient as the menu;
   - a `Title` TextLabel reading "GAME TITLE", Oswald Bold, amber UIStroke;
   - a `Spinner` (amber ring or gear, built from Frames and UICorner, or a UIStroke ring with a hazard gap) that rotates continuously;
   - a `Tip` TextLabel, which cycles through `MenuAssets.Tips` every `TIP_SECONDS`.
   - Layout is Scale only. Phones keep everything inside the safe area: the content sits in an inner Frame. The backdrop and vignette fill the whole screen.
2. **Signal state.** Set the PlayerGui attribute `LoadingDone = false`.

### Preload (in the background, never on the Play path)
Load these in parallel:
- `game:IsLoaded()` or `game.Loaded:Wait()`;
- `ContentProvider:PreloadAsync` over Sound instances made from `MenuAssets.Sounds`. The preload callback records which assets failed. Each failure is warned once, naming its key.
- `ReplicatedStorage.MainMenu`, `MainMenuVignette` and `MainMenuFader` appearing;
- `workspace.SettingsRoom` and `workspace.CreditsRoom` appearing;
- `ReplicatedStorage.MenuAvatars[userId]` appearing.

Each wait has its own cap, and the overall time is capped by `LOADING_MAX_SECONDS`.

### Handoff
When everything has loaded and at least `LOADING_MIN_SECONDS` have passed, or once `LOADING_MAX_SECONDS` have passed:
1. Fade the backdrop to black (0.4 s).
2. Set `LoadingDone = true`.
3. Wait for the PlayerGui attribute `MenuOpen == true`, for at most 3 s.
4. Fade the loading gui out (0.4 s) and destroy it.

**Failed asset keys** are written to the attribute `LoadingFailedSounds`, a comma-separated string, so tests and the audio module can see them.

**Studio-only:** if `RunService:IsStudio()`, a `TestHook` BindableFunction under the script supports `Invoke("state")`. It returns `{ done, elapsed, failed }`.

## MainMenuClient changes

- **Waiting for the loading screen.** Before `setupMenu()` parents the menu, wait for `PlayerGui:GetAttribute("LoadingDone") == true`, for at most `LOADING_MAX_SECONDS + 5`. This happens in setup, never on the Play path.
  - If `ReplicatedFirst.LoadingScreen` doesn't exist, don't wait.
  - If the wait times out, open the menu anyway and warn.
  - The I-1 fallback is unchanged.
- **New modules,** loaded with the existing `loadModule` pattern and pcall'd:
  - `MenuAudio` (music);
  - `ButtonSounds` (SFX).

## Music: `MenuAudio` (ModuleScript under MainMenuClient)

- **`start()`**
  - Create three looping Sounds in `SoundService`, named `MenuMusic`, `SettingsMusic` and `CreditsMusic`. They are client-local.
  - Each has `SoundGroup = SoundService.Music`, `Looped = true`, `Volume = 1` (the group's volume is the slider) and its SoundId from `MenuAssets`.
  - Play `MenuMusic`.
- **`setScene(name: "Menu" | "Settings" | "Credits")`**
  - Crossfade over 0.8 s: tween the old track's Volume to 0, then pause it, while the new track tweens 0 → 1 and plays. It must not yield.
  - Each track resumes from where it paused.
- **`stop()`**
  - Non-yielding and idempotent.
  - Tween every track's Volume to 0 over 0.4 s, then stop and destroy the tracks.
  - Called on the Play path, pcall'd, right after `SceneDirector.stop()`.
- **SceneDirector integration.** SceneDirector gets a new optional ctx callback, `onSceneChanged(name)`, called right after it switches the current scene, behind the fader, with no yield. init passes `MenuAudio.setScene` there.
- **Failed tracks.** A failed track (in `LoadingFailedSounds`, or `IsLoaded` still false when it would play) is skipped silently after a single warning.

## Button sounds: `ButtonSounds` (ModuleScript under MainMenuClient)

- **`init()`** creates the three SFX Sounds in `SoundService` with `SoundGroup = SoundService.SFX`.
- **`hover()`, `confirm()`, `playSelect()`** each start the sound from the beginning (`TimePosition = 0`, then `Play`), non-yielding.
- **Wiring.** `ButtonEffects` gets an optional `onHover` callback per attach, fired when a button goes from idle to hover (mouse enter, gamepad selection gained, touch begin), not on press. init wires these:
  - PLAY, SETTINGS, CREDITS and BACK: `ButtonEffects.attach(button, { onHover = ButtonSounds.hover })`.
  - Their `Activated` handlers call `ButtonSounds.confirm()` (SETTINGS, CREDITS, BACK) or `ButtonSounds.playSelect()` (PLAY) first, pcall'd and non-yielding.
  - Settings board switches: hover on the row's `MouseEnter`, and confirm on flip.
- **Play path.** `playSelect()` is non-yielding. It must not be cut off by the Play fade: SFX keeps playing while the music fades.

## Credits: "You" in the foreground

- **New marker.** `workspace.CreditsRoom.ViewerSpot` is an anchored, invisible marker Part, with CanCollide, CanQuery and CanTouch false. It is built by `studio/build_menu_rooms.luau` and added to the live room.
- **Placement.** The spot is on the floor between `CreditsCameraShot` and `PlayerCreditStand`:
  - about a third of the way from the camera;
  - offset to the side away from the developer, so the developer avatar, its label and BACK stay clear;
  - facing the developer podium horizontally, so the camera sees the avatar's back.
  - The camera framing is unchanged.
- **CreditsRoom.**
  - The Viewer slot places its clone so its feet stand on `ViewerSpot`, facing the developer podium.
  - `DisplayName` for the viewer is `"YOU"`.
  - The developer's placement and label are unchanged.
  - `ViewerCreditStand` stays, empty.
- **Hover.** Same as before: an amber Highlight plus a BillboardGui reading `YOU`. The Include-list raycast already covers it.
- **Build script.** `studio/build_menu_rooms.luau` adds `ViewerSpot` and keeps its guard. The live room gets the same marker, and live must equal the script's output.

## Main-menu repeating wave: `CharacterPreview`

- `show` plays the wave on appear, then repeats it every `WAVE_INTERVAL = 6` seconds (a constant at the top).
- The loop stops when the clone is destroyed (on Play, or when the viewport goes).
- It runs in its own `task.spawn`, checks `clone.Parent` before each wave, and never yields the caller.

## Components

| Component | Type | Location | Change |
|---|---|---|---|
| `MenuAssets` | ModuleScript | ReplicatedFirst | New: sound IDs, tips, timing constants |
| `LoadingScreen` | LocalScript | ReplicatedFirst | New: loading UI, preload, handoff |
| `MenuAudio` | ModuleScript | under MainMenuClient | New: scene music, crossfade, fade-out on Play |
| `ButtonSounds` | ModuleScript | under MainMenuClient | New: hover/confirm/playSelect |
| `SceneDirector` | ModuleScript | under MainMenuClient | Optional `onSceneChanged` ctx callback |
| `ButtonEffects` | ModuleScript | under MainMenuClient | Optional `onHover` callback |
| `SettingsBoard` | ModuleScript | under MainMenuClient | Switch rows play hover and confirm |
| `CreditsRoom` | ModuleScript | under MainMenuClient | Viewer on `ViewerSpot`, label YOU |
| `CharacterPreview` | ModuleScript | under MainMenuClient | Repeating wave |
| `MainMenuClient` (init) | LocalScript | StarterPlayerScripts | Waits for LoadingDone; wires audio and SFX; stops music on Play |
| `build_menu_rooms.luau` | build script | studio/ | Adds ViewerSpot |
| `default.project.json` | Rojo | repo root | Maps `src/ReplicatedFirst` |
| `docs/RECOVERY.md` | doc | docs/ | Adds the ReplicatedFirst scripts and ViewerSpot |

## Error handling

- **Loading screen errors.** The menu opens after its own timeout, and the loading gui is removed: init destroys `PlayerGui.LoadingScreen` if it is still there after the menu opens.
- **Sound load failures.** A warning only.
- **Audio module errors.** All calls are pcall'd, so the menu and Play are unaffected.
- **Missing `ViewerSpot`.** The viewer isn't placed, with a warning, and the developer is still shown.

## Testing

Tests are Studio `.luau` snippets run via execute_luau, as before.

### New tests
- **`loading.client.luau`** (fresh playtest; must run first):
  - the `LoadingScreen` gui exists early, with Title, Spinner and Tip;
  - the tip text changes within 5 s;
  - `LoadingDone` becomes true within `LOADING_MAX_SECONDS`, and not before `LOADING_MIN_SECONDS`;
  - the menu opens, and the loading gui is gone within 2 s after that;
  - `LoadingFailedSounds` is listed. The test **reports** any failed sound keys so the user learns which sounds Roblox refused.
- **`audio.client.luau`:**
  - `MenuMusic` is playing in the `Music` group, and the other tracks are not playing, or are at volume 0;
  - after `goTo("Settings")`, `SettingsMusic` is playing and `MenuMusic` is paused within 1.5 s; the same for Credits;
  - after Play, there are no music Sounds left within 1 s;
  - the SFX sounds are in the `SFX` group;
  - real hovers and clicks make the right SFX play: hovering PLAY, clicking SETTINGS, then clicking BACK. Check `IsPlaying` or `TimePosition > 0` shortly after.
- **`credits_room` additions:**
  - the Viewer stands on `ViewerSpot` (feet within 0.3 studs), with its LookVector facing the developer podium (dot product > 0.8), and the camera sees its back (dot of the viewer's LookVector with the camera-to-viewer direction > 0.5);
  - hover shows `YOU`;
  - `ViewerCreditStand` exists and has no avatar on it;
  - the Viewer's screen rectangle does not overlap the developer's head or name label, or the BACK button.
- **`character_preview` addition:** a wave track starts at least twice within 14 s of the avatar appearing.
- **`rooms.edit` addition:** `ViewerSpot` exists, with the marker properties.

### Updates
Update any existing tests that the new SFX or music wiring touches, and the startup timing, since the menu now waits for the loading screen.

### Screenshots
The loading screen, the credits shot with YOU hovered, and the main menu.

## Out of scope

- Gameplay music.
- Saving settings.
- Per-button custom sounds beyond the table.
- A progress bar on the loading screen (the user chose not to have one).
- Real-touch and controller verification (the user does these with the Device Emulator and a controller).
