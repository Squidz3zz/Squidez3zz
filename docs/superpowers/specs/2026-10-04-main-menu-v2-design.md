# Main Menu v2: Heavy-Factory Menu with Settings and Credits Rooms

**Date:** 2026-10-04
**Place:** "Untitled Experience" (placeId 95688118364991, owner UserId 71629421)
**Builds on:** `docs/superpowers/specs/2026-10-04-main-menu-design.md` (v1, merged to master). Every v1 behaviour not changed here still holds: spawn only on Play, respawn, the avatar pipeline, fault isolation, and the I-1 fallback.
**Status:** Design approved in chat; this spec awaits review.

## Goal

Restyle the main menu with a **heavy-factory** look: rusty steel, grates, girders, amber warning lights and haze.

- **Main menu:** a tighter button layout, a bigger waist-up avatar, a dark vignette, and a camera that sways slightly with the mouse.
- **Settings and Credits:** these become full **3D scenes**. Pressing either button fades to black and cuts to a camera in a dressed factory room.
- **Settings room:** the settings UI lives on a board.
- **Credits room:** shows the developer and the viewing player. Hovering highlights each one and shows their name.

## Success criteria

- **Main menu layout:**
  - The three buttons sit middle-left, vertically centred, with gaps of about 9% of screen height (roughly an inch at 1080p).
  - The title sits above them, sharing their left edge.
  - The layout passes the phone check at 844×390.
- **Avatar:** the preview shows the avatar from the waist up, larger than v1. The wave arm stays in frame.
- **Vignette:** dark edges are visible on all four sides of the screen. They are gone after Play.
- **Mouse sway:** the camera rotates toward the mouse by at most 2° yaw and 2° pitch, smoothed, in every menu scene. There is no sway when the Camera Sway switch is off, or on touch or gamepad input with no mouse.
- **Settings:** fades to black (0.4s out, 0.4s in) and cuts to the Settings room. The board shows working Music and SFX sliders and Camera Sway and Screen Effects switches. BACK returns to the main menu the same way.
- **Credits:** fades and cuts to the Credits room. The developer's avatar stands on the stand and the viewing player's avatar stands on a second stand. Hovering (or tapping) either one shows an amber outline and a name label. BACK returns.
- **Room placement:** the rooms are underneath the map, out of reach of normal gameplay. They are always present on the client, even with StreamingEnabled.
- **Play:** works from the main menu as before. Every v1 guarantee still holds.
- **Console:** no errors during the full flow.

## Assumptions

- Settings are not saved between sessions. Every join starts with Music 0.5, SFX 0.5, Camera Sway on and Screen Effects on.
- **The developer** is the experience owner: `game.CreatorId` when `game.CreatorType == User`. If the experience is owned by a group, a `DEVELOPER_USER_ID` constant in MenuServer is used instead, set to 71629421 today.
- The user places `MenuCameraShot` over their map later. Until then the default angle is used.
- The user may restyle fonts, colours and room props in Studio afterwards.

## Main menu restyle

- **Root layout (Scale only).** The first draft's numbers were tuned while building (the phone check, the Vignette layering and the "upper half, bigger" avatar), so the values below are the shipped ones. Each one that changed says **tuned**, with the draft value.
  - `Root`: ZIndex 55 (**tuned**: the draft left it at the default, under the Vignette, which dimmed the title and buttons). It sits below `Back` (60). The Vignette and the Fader are ScreenGuis of their own (see **Vignette**), so their order against `Root` comes from DisplayOrder, not ZIndex.
  - `Title`: AnchorPoint (0, 1), Position {0.06, 0}, {0.27, 0} (**tuned** from 0.30), Size {0.40, 0}, {0.10, 0}. Its bottom edge sits just above the buttons, which start at 0.31, and its top edge is at 0.17, below the topbar band on a phone (66 px at 390 px, the band ends at 58).
  - `Buttons`: AnchorPoint (0, 0.5), Position {0.06, 0}, {0.56, 0}, Size {0.24, 0}, {0.50, 0} (**tuned** from 0.42).
  - `UIListLayout`: Padding {0.1775, 0} (**tuned** from 0.215). UIListLayout padding scales with the Buttons frame, not the screen, so 0.1775 × 0.50 ≈ 0.089 of screen height. Each button is Size {1, 0}, {0.215, 0} of the frame (**tuned** from 0.19), which is ≈ 0.1075 of the screen, 42 px at 390 px. The draft values gave 31 px buttons on the phone, under the 40 px tap target.
  - The rule that survives any further tuning: the on-screen gap between buttons stays between 0.08 and 0.10 of screen height, and every button is at least 40 px tall at 390 px.
  - `Back`: AnchorPoint (0, 1), Position {0.03, 0}, {0.95, 0}, Size {0.12, 0}, {0.11, 0} (**tuned** from 0.09, which is only 35 px at 390 px), ZIndex 60.
- **CharacterView** (**tuned**: the draft put it at Position {0.56, 0}, {0.10, 0}, Size {0.40, 0}, {0.85, 0}): AnchorPoint (0, 1), Position {0.48, 0}, {1, 0}, Size {0.48, 0}, {0.85, 0}, with a `UIAspectRatioConstraint` of 1.3. It sits on the bottom edge of the screen, because the avatar is cut off there, and runs from 0.48 to 0.96 of the width, clear of the Buttons (end at 0.30) and the Title frame (ends at 0.46). The aspect ratio shrinks it on a screen too wide for 0.85 of its height.
  - `CharacterPreview` frames the **upper body** as a window, not a margin around the whole figure: the bottom edge sits just under the waist (the bottom of `Torso`, or of `LowerTorso` for R15) and the top edge is above the head, high enough for the raised wave hand. The legs are cut off at the bottom of the view.
  - The framing is asymmetric and tuned (fractions of the upper-body height, torso bottom to head top): `WAIST_MARGIN` 0.05 below the waist, `HAND_ROOM` 0.45 above the head, `WINDOW_SLACK` 1.06 on the window height, and `AIM_SHIFT` toward the waving arm's side (R6 0.12, R15 0). The camera aims at the centre of the window with FOV 30. Measured over a looping wave, the head stays fully in the frame and the waving hand stays in the frame to within 3%. Facing and idle/wave behaviour are unchanged.
- **Vignette:** a `Vignette` Frame (full screen, ZIndex 50) holds four edge Frames named `Top`, `Bottom`, `Left` and `Right`.
  - Colour is RGB (12, 9, 6).
  - Each edge is about 0.18 of the screen deep and has a `UIGradient` running from Transparency 0.15 at the outer edge to 1 at the inner edge.
  - It lives in `MainMenuVignette`, a full-screen overlay ScreenGui (ScreenInsets `None`, IgnoreGuiInset true, DisplayOrder 9, behind the menu), so it reaches the notch strips and rounded edges of a phone. The menu itself (`MainMenu`: `Root` and `Back`, DisplayOrder 10) keeps ScreenInsets `DeviceSafeInsets`, so the buttons and BACK never sit under a notch. (When the Vignette was a child of `MainMenu` it stopped at the safe area and left blank strips on a phone.)
  - It is destroyed with the other two menu ScreenGuis after Play.
- **Factory skin:**
  - Buttons: background RGB (38, 36, 34), a 0.03-wide left accent bar RGB (255, 150, 30), white Oswald text and uppercase labels.
  - ButtonEffects stroke colour becomes amber RGB (255, 150, 30). Its scale values are unchanged.
  - Title: Oswald Bold with an amber UIStroke.
- **Colour grade:** while the menu is open, the client adds `Lighting.MenuColorCorrection` (ColorCorrectionEffect: Contrast 0.1, Saturation -0.15, TintColor RGB (255, 235, 210)). It is removed on Play.
- **Removed:** `SettingsPanel` and `CreditsPanel` (the old popups).

## Scenes and transitions

`SceneDirector`, a new client ModuleScript, owns three scenes: `Menu`, `Settings` and `Credits`.

### Scene definition

| Scene | Camera marker | Shown on enter | Hidden on enter |
|---|---|---|---|
| Menu | `workspace.MenuCameraShot`, or the default CFrame | Root (title, buttons, character), vignette | — |
| Settings | `workspace.SettingsRoom.SettingsCameraShot` | Settings board UI, BACK | Root |
| Credits | `workspace.CreditsRoom.CreditsCameraShot` | Credit avatars + hover, BACK | Root |

- **Camera markers** are anchored, invisible (Transparency 1), CanCollide/CanQuery/CanTouch false Parts. The camera's CFrame equals the marker's CFrame.
- **Default Menu CFrame:** if `MenuCameraShot` is missing, use `CFrame.lookAt(Vector3.new(0, 40, 80), Vector3.new(0, 0, 0))`.

### Transitions

`SceneDirector.goTo(name)`:
1. Fade the existing `Fader` to opaque over 0.4s. The `Fader` lives in `MainMenuFader`, a full-screen overlay ScreenGui (ScreenInsets `None`, DisplayOrder 11, over everything), so the fade also covers the notch strips of a phone while the menu stays in the safe area.
2. Run the old scene's `exit` and the new scene's `enter`. Set the camera base CFrame.
3. Fade back in over 0.4s.

Further details:
- It is debounced: calls are ignored while a transition is running.
- Play during a transition is allowed. Play wins.
- Play is only reachable from Menu.

### BACK and fallbacks

- **BACK:** a screen-space TextButton named `Back`, bottom-left, with the factory skin. It is shown only in Settings and Credits and calls `goTo("Menu")`.
- **Missing room or marker:** if a room or its marker is missing, `goTo` warns (and returns false without yielding) and stays on the current scene. The Persistent rooms stream in with the first load, so a click that beats them is tried once more when the room arrives, unless the player chose another scene or pressed Play in the meantime.
- **Controller:** after each cut, a controller player's selection moves to `Back` in a room, or to the Settings or Credits button on return to the menu. While a room is up, ButtonB is bound (action `MenuBack`) to `goTo("Menu")`: only the press is sunk. It is unbound on Menu and by `stop()`. Board sliders and switches are not controller-navigable.
- **Fault isolation:** scene `enter` and `exit` hooks run in pcall. A failing hook still completes the fade back in. None of this is on the Play path.

## Camera sway (replaces the orbit)

`MenuCamera` is rewritten. The orbit and `MenuCameraFocus` are removed.

- `MenuCamera.start()` sets CameraType Scriptable, adds `MenuBlur` (Size 6, reduced from 16 so the map reads behind the menu) when Screen Effects is on, and connects a RenderStepped updater.
- `MenuCamera.setBase(cf: CFrame, opts: { blur: boolean }?)`: SceneDirector calls this on each scene change. The blur is for the Menu scene only (`blur` defaults to true, SceneDirector passes false for Settings and Credits), because in the rooms the 3D board and avatars are the interface and must stay sharp. The colour grade stays in every scene, and with Screen Effects off there is neither.
- **Sway** is computed every frame:
  - Mouse offset from screen centre, normalised to -1..1 on each axis.
  - Target rotation is `CFrame.Angles(-ny * rad(2), -nx * rad(2), 0)`.
  - It is smoothed with an exponential lerp, alpha `1 - exp(-6 * dt)`.
  - Camera CFrame = base × smoothed rotation.
- **Sway is zero when:**
  - the Camera Sway setting is off; or
  - `UserInputService.MouseEnabled` is false; or
  - the last input type was Touch or Gamepad.
- `MenuCamera.stop()` keeps its v1 contract: non-yielding, idempotent, fades the blur, restores CameraType Custom. It also removes `MenuColorCorrection`.
- **Streaming:** the server calls `RequestStreamAroundAsync` around the `MenuCameraShot` position. This replaces the `MenuCameraFocus` attribute and uses a `MenuCameraShot` Workspace attribute set at server start. The rooms don't need it (see Rooms).

## Rooms

### Placement
- The user's four parts (`BackgroundForSettings`, `Settingsboard`, `BackgroundForCredits`, `PlayerCreditStand`) move as a group by (0, -200, 0), keeping their relative layout.
- They are reparented into two Models: `workspace.SettingsRoom` and `workspace.CreditsRoom`.
- Both Models have `ModelStreamingMode = Persistent`, so they are always on the client.

### Dressing
Each room is an enclosed factory corner around the user's parts:
- floor, side walls and ceiling with no gaps, so the sky and sun don't leak;
- CorrodedMetal and DiamondPlate materials in rust and steel tones;
- girders and pipes;
- a grate floor section;
- 2–3 amber caged lamps (`PointLight` or `SpotLight`, colour (255, 160, 60));
- a subtle haze ParticleEmitter (very low rate, large and transparent).

The user's backdrop becomes the back wall's centrepiece, with CorrodedMetal applied. Every built part is anchored. Decorative parts have CanQuery false so they never block hover raycasts.

### Room contents
- **Settings room:** `SettingsCameraShot`, placed facing the board's front face and framing it fully.
- **Credits room:**
  - `CreditsCameraShot`, framing both stands with the avatars' upper bodies;
  - `PlayerCreditStand` (the user's, for the developer);
  - `ViewerCreditStand`, a new matching stand beside it.

### Build script
`studio/build_menu_rooms.luau` builds or rebuilds both rooms reproducibly.
- It refuses to run if `SettingsRoom` or `CreditsRoom` already exists.
- If the user's four parts exist, it adopts them, moving them into the Models. If not, it creates simple stand-ins with the same names and sizes.

## Settings room

- **Board UI:** a `SurfaceGui` named `SettingsBoardGui`, built at runtime by the client in PlayerGui.
  - `Adornee` is `Settingsboard`, on the Face pointing at `SettingsCameraShot`.
  - `SizingMode` is PixelsPerStud (50), and `ClipsDescendants` is true.
- **Board layout:** the factory skin, with a header "SETTINGS" and four rows:
  - **Music:** a slider controlling `SoundService.Music.Volume` (0–1).
  - **Sound Effects:** a slider controlling `SoundService.SFX`, a new SoundGroup with Volume 0.5. The menu build creates it if missing.
  - **Camera Sway:** an ON/OFF switch, default ON.
  - **Screen Effects:** an ON/OFF switch, default ON. Off hides the vignette, removes `MenuBlur` and removes `MenuColorCorrection`. On restores them.
- **Touch targets:** the board is only about 270 px tall on a phone in landscape, so the whole row is the target (about 45 px, over the 40 px minimum): a press anywhere on a slider row starts that slider's drag, and a tap anywhere on a switch row (its `RowHit` button) flips the switch.
- **Shared state:** a client `MenuSettings` ModuleScript owns the two booleans, with `get(name)`, `set(name, value)` and a `Changed` BindableEvent. MenuCamera and SceneDirector read from it.
- **Slider reuse:** sliders reuse `VolumeSlider`. Its drag mapping is verified on the board with a real mouse drag. If SurfaceGui input positions don't line up with the slider's `AbsolutePosition` space, `VolumeSlider` is adjusted to map correctly in both ScreenGui and SurfaceGui.

## Credits room

### Avatars
- **Developer:** the server builds `ReplicatedStorage.CreditAvatars.Developer`.
  - It uses the same description pipeline as the v1 menu avatar: pcall'd, with a default fallback.
  - The model gets the attribute `DisplayName`, from `Players:GetNameFromUserIdAsync`, falling back to "Developer".
  - It is built once at server start.
- **Viewer:** the client clones its own `MenuAvatars[UserId]`, using the existing wait-for-parts logic, and sets `DisplayName` = `LocalPlayer.DisplayName`.

### Placement
- On entering Credits, the client places local clones in `workspace.CreditsRoom.CreditAvatars`, a client-only Folder.
- Each clone stands on top of its stand, facing the camera, with Animate removed, anchored, and playing the idle on loop.
- Clones are created once and reused on later visits.
- On Play, the folder is destroyed.

### Hover
While the Credits scene is active:
- A raycast from the mouse (`Camera:ViewportPointToRay`, on `GetMouseLocation()`) runs against the avatars only, using a RaycastParams include list.
- The hovered avatar gets a `Highlight` (OutlineColor (255, 150, 30), FillTransparency 1).
- It also gets a `BillboardGui` above the head with the `DisplayName` text in the factory font.
- Un-hovering removes both.
- **Touch:** a tap on an avatar shows it until another tap elsewhere. `TouchTap` positions are in screen space (below the top bar's inset), so taps use `Camera:ScreenPointToRay`; mixing the spaces misses by the inset (about 58 px).
- **Name label:** a 56 px BillboardGui, `StudsOffset` (0, 1.5, 0), low enough to stay inside the view at 844x390.

## Server changes (MenuServer)

- Build `CreditAvatars.Developer` at startup (above).
- Set the `MenuCameraShot` Workspace attribute (Vector3 position) at startup if the marker exists, and stream around it for each player.
  - If `workspace.MenuCameraShot` is a BasePart it is also made safe at startup: Anchored, Transparency 1, CanCollide, CanQuery and CanTouch false. The camera looks out of the part's Front face; `docs/RECOVERY.md` has the command-bar line that places it from the editor camera.
- Keep all v1 behaviour.

## Components

| Component | Type | Location | Change |
|---|---|---|---|
| `build_main_menu_ui.luau` | build script | `studio/` | New layout, vignette, skin, Back button, SFX group; panels removed; builds three ScreenGuis (`MainMenuVignette`, `MainMenu`, `MainMenuFader`) |
| `build_menu_rooms.luau` | build script | `studio/` | New: rooms, markers, ViewerCreditStand |
| `MenuServer` | Script | ServerScriptService | Developer credit avatar, MenuCameraShot streaming |
| `MainMenuClient` (init) | LocalScript | StarterPlayerScripts | Wires SceneDirector; Settings/Credits buttons call `goTo`; Play unchanged |
| `SceneDirector` | ModuleScript | under MainMenuClient | New: scenes, fades, BACK |
| `MenuSettings` | ModuleScript | under MainMenuClient | New: sway/effects booleans + Changed |
| `MenuCamera` | ModuleScript | under MainMenuClient | Rewritten: base CFrame + sway, effects toggle |
| `SettingsBoard` | ModuleScript | under MainMenuClient | New: builds SurfaceGui, sliders, switches |
| `CreditsRoom` | ModuleScript | under MainMenuClient | New: places avatars, hover highlight + name |
| `CharacterPreview` | ModuleScript | under MainMenuClient | Upper-body framing |
| `ButtonEffects` | ModuleScript | under MainMenuClient | Amber stroke colour |
| `VolumeSlider` | ModuleScript | under MainMenuClient | Works inside a SurfaceGui |

The I-1 header list of required UI names in `init.client.luau` is updated:
- `SettingsPanel` and `CreditsPanel` are removed.
- `Vignette` and `Back` are added.
- The names are grouped per ScreenGui: `MainMenu` (`Root`, ..., `Back`), `MainMenuVignette` (`Vignette`) and `MainMenuFader` (`Fader`). The client clones all three, and treats a missing one like a missing `MainMenu` (setup throws and the I-1 fallback destroys every clone that exists).

## Error handling

- Any missing room, marker, board or stand means that scene's `goTo` warns and does nothing. The menu and Play keep working.
- Developer avatar failure leaves the stand empty, with a warning.
- Viewer avatar not ready means the viewer stand is empty until it arrives, using the same timeouts as v1.
- All new module calls from init are pcall'd, following the v1 pattern. Nothing new runs on the Play path except `SceneDirector`'s cleanup. That cleanup is non-yielding and pcall'd.

## Testing

Tests are Studio `.luau` snippets run via execute_luau, as in v1.

- **Update:** `ui_layout`, `phone_layout`, `menu_client`, `camera_slider`, `character_preview`.
  - Their panel and orbit assumptions are replaced.
  - `camera_slider` becomes a sway check.
  - `phone_layout` checks the new layout and the Back button.
- **New:**
  - `scenes.client.luau`: each `goTo` puts the camera at the marker (within tolerance) and toggles Root and Back. Debounce works. Back returns to Menu.
  - `sway.client.luau`: the sway angle stays at or under 2°, and is zero when the setting is off.
  - `settings_board.client.luau`: the sliders set volumes, the switches flip settings and effects.
  - `credits_room.client.luau`: both avatars are on stands, facing the camera, and a simulated hover applies and removes the Highlight and name label.
  - `rooms.edit.luau`: the rooms exist, sit under the map, are Persistent and enclosed, and the markers are present.
- **Screenshots:** of the main menu, the Settings room and the Credits room (with a hover), for the user.

## Out of scope

- Saving settings between sessions.
- The real game map and the `MenuCameraShot` placement (the user's job).
- More credit entries beyond the developer and the viewer.
- Music and SFX audio content.
- Gamepad sway.
- Fully redoing the art if the user wants a different look later. Rooms and skin are built so they can be restyled in Studio.
