# Main Menu — Design Spec

**Date:** 2026-10-04
**Place:** Place1 (Roblox Studio)
**Status:** Approved in chat, awaiting spec review

## Goal

A main menu shown when a player joins. It has a title at the top left, Play / Settings / Credits buttons stacked under it, and the player's own avatar animated on the right, over a blurred, slowly orbiting view of the map. The player does not spawn until they press Play.

## Success criteria

- On join, the menu appears with the player's avatar idling, facing the camera, and waving once.
- Hovering a button makes it pop out (it grows and gets an outline). Mobile touch and gamepad selection trigger the same pop.
- Settings and Credits panels open and close.
- Play fades the menu out, spawns the player, and returns normal camera control.
- After dying, the player respawns and the menu does not reappear.
- The layout scales correctly on phone and desktop screen sizes.
- No errors in the output console during the flow.

## Assumptions

- The menu shows once per session, on join, not on each respawn.
- The music volume slider controls a `SoundService.Music` SoundGroup. No music exists yet, so the slider is wiring for later.
- Credits content is placeholder text the user will edit.
- The user will restyle the title font and text themselves.

## Layout

The existing `StarterGui.ScreenGui` is reused and moved to `ReplicatedStorage.MainMenu`.

**Why it moves:** `Players.CharacterAutoLoads` is off, and Roblox only copies StarterGui into PlayerGui when a character spawns, so a menu left in StarterGui would never appear.

- `ResetOnSpawn = false`, `IgnoreGuiInset = true`.
- `Title`: the existing TextLabel, top left.
- `Buttons`: a Frame under the title with a UIListLayout holding the `Play`, `Settings` and `Credits` TextButtons.
- `CharacterView`: a ViewportFrame that replaces the existing ImageLabel on the right. It contains a `WorldModel`, which is required for animations to play.
- `SettingsPanel`: a centered Frame with a music volume slider and a Close button. Hidden by default.
- `CreditsPanel`: a centered Frame with placeholder text and a Close button. Hidden by default.
- All sizes and positions use Scale, with UIAspectRatioConstraint where shapes must hold.

## Components

| Component | Type | Location | Responsibility |
|---|---|---|---|
| `MenuServer` | Script | ServerScriptService | Sets `CharacterAutoLoads = false`. On PlayerAdded, builds the avatar model into `ReplicatedStorage.MenuAvatars[UserId]`. On `PlayPressed`, spawns the player once and removes the avatar model. Respawns players after death (`Players.RespawnTime`). Cleans up on PlayerRemoving. |
| `PlayPressed` | RemoteEvent | ReplicatedStorage | Client to server: "Play was pressed." |
| `MenuAvatars` | Folder | ReplicatedStorage | Temporary per-player avatar models (created by the server) |
| `MainMenuClient` | LocalScript | StarterPlayerScripts | Clones `MainMenu` into PlayerGui, starts the camera, preview and button effects, wires the panels and Play. |
| `ButtonEffects` | ModuleScript | child of MainMenuClient | `ButtonEffects.attach(button)`: hover/press/selection pop via a UIScale and UIStroke with TweenService. |
| `CharacterPreview` | ModuleScript | child of MainMenuClient | `CharacterPreview.show(viewportFrame, model)`: clones the model into the WorldModel, frames a camera on it facing front, plays idle on loop and a wave once. |
| `MenuCamera` | ModuleScript | child of MainMenuClient | `MenuCamera.start()` / `MenuCamera.stop()`: scriptable orbit around the map center plus a client BlurEffect. Stop fades the blur and restores `CameraType = Custom`. |

## Data flow

1. **Player joins.** The server builds a HumanoidDescription model and places it in `MenuAvatars[UserId]`.
2. **Menu starts.** The client clones the menu UI and starts MenuCamera. It waits for `MenuAvatars[UserId]` and passes it to CharacterPreview.
3. **Player clicks Play.** The client debounces the press, fades the UI, stops MenuCamera and fires `PlayPressed`.
4. **Server spawns the player.** The server ignores the event if the player has already spawned. Otherwise it calls `LoadCharacter()` and destroys the menu avatar.
5. **Player dies later.** The server waits `RespawnTime`, then calls `LoadCharacter()`. The menu stays gone, because it has `ResetOnSpawn = false` and was destroyed after Play.

## Animation details

- **Idle animation:** read from the model's `Animate` script (`idle.Animation1`) so the player's animation pack is respected. If that's missing, fall back to the default R15 idle `rbxassetid://507766666` or the default R6 idle `rbxassetid://180435571`.
- **Wave:** plays once on open. R15 uses `rbxassetid://507770239`, R6 uses `rbxassetid://128777973`.
- **Animator:** animations are played through the Humanoid's Animator inside the WorldModel.

## Error handling

- `GetHumanoidDescriptionFromUserId` is wrapped in pcall and retried once. On failure it falls back to `HumanoidDescription.new()`, which also covers Studio test players with negative UserIds.
- The client waits for the avatar with a timeout. If none arrives, the viewport stays empty and the menu still works.
- Play is debounced on both the client and the server.
- Animation load failures are caught, and the character shows in its bind pose instead of crashing.

## Testing

Playtest in Studio and verify each success criterion:

- Check the console output for errors.
- Take screen captures of the menu, the hover state and the panels.
- Verify the spawn after Play.
- Reset the character and verify the respawn without the menu.
- Check the layout at a phone-sized viewport.

## Out of scope

- Shop
- Actual music tracks
- Saving settings between sessions
- A custom animation from the Animation Editor (the user can swap the idle ID later)
