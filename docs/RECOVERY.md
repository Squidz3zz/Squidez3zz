# Recovery guide: getting the main menu back

This is for when Roblox Studio has lost your work (a crash, a PC restart, or a place that reopened as an older version).
You do not need anyone's help to follow it. Everything the menu needs is in this folder.

## First: always save your work

At the end of every Studio session, do one of these:

- **File -> Publish to Roblox** (best: the place is stored online), or
- **File -> Save to File** (saves a `.rbxl` copy on your PC).

If your PC restarts or Studio crashes, Studio can reopen the last published version. Anything you built after that
publish, such as the rooms, the menu, or the scripts, is gone. Publishing often is the whole trick.

## If Studio lost your work

Do these steps in order. Run a `.luau` file by opening it in a text editor, copying everything, pasting it into Studio's
**Command Bar** (View -> Command Bar), and pressing Enter. Then look at the **Output** window (View -> Output). Red
text means something went wrong. No red text means it worked.

### a) Rebuild the two rooms

1. In the Explorer, delete `Workspace.SettingsRoom` and `Workspace.CreditsRoom` if they exist (the script refuses to run
   while they do).
2. Run `studio/build_menu_rooms.luau`.

It builds both rooms. If your own four parts (`BackgroundForSettings`, `Settingsboard`, `BackgroundForCredits`,
`PlayerCreditStand`) are loose in Workspace, it uses them. If they are not there, it builds stand-ins with the same
names, so everything still works.

The Credits room also gets `ViewerSpot`: an invisible marker on the floor, in the foreground, where the player's own
avatar stands (seen from behind, looking at the developer's podium, with the hover label `YOU`). Without it the player's avatar is
left out of Credits, with a warning, and the developer's avatar still shows. The second podium, `ViewerCreditStand`,
stays empty. To move the player's avatar, move or turn `ViewerSpot`: it should rest on the floor, and the way its front
face points is the way the avatar looks.

### b) Rebuild the menu

1. In the Explorer, the menu is three ScreenGuis in `ReplicatedStorage`: `MainMenu`, `MainMenuVignette` and
   `MainMenuFader`. Move all three that exist out of the way (drag them into `ServerStorage`) or delete them. The script
   refuses to run while any one of them exists.
2. Run `studio/build_main_menu_ui.luau`.

It builds the three ScreenGuis again and adds `SoundService.Music` and `SoundService.SFX` if they are missing:

- `MainMenu` holds the title, buttons, avatar slot and BACK. It stays inside the phone's safe area, so nothing sits under
  a notch.
- `MainMenuVignette` holds the dark border, and `MainMenuFader` holds the black fade. Both are full-screen overlays
  (ScreenInsets `None`), so they reach the notch strips and rounded edges of a phone.

### c) Put the scripts back

There are fifteen scripts. The file names are in `src/`.

**Easy way, with Rojo** (a free tool, https://rojo.space; version 7.3 or newer):

1. Install Rojo and its Studio plugin.
2. In a terminal opened in this folder, run `rojo serve`.
3. In Studio, open the Rojo plugin and press **Connect**.

The file `default.project.json` already says where everything goes. It only touches `ReplicatedFirst`,
`ServerScriptService` and `StarterPlayerScripts`, and it leaves your other scripts alone.

**By hand:** create each script with the right kind and parent, then paste the file's text into it.

| Name | Kind | Parent | File to copy |
|---|---|---|---|
| `MenuAssets` | ModuleScript | `ReplicatedFirst` | `src/ReplicatedFirst/MenuAssets.luau` |
| `LoadingScreen` | LocalScript | `ReplicatedFirst` | `src/ReplicatedFirst/LoadingScreen.client.luau` |
| `MenuServer` | Script | `ServerScriptService` | `src/ServerScriptService/MenuServer.server.luau` |
| `MainMenuClient` | LocalScript | `StarterPlayer` -> `StarterPlayerScripts` | `src/StarterPlayer/StarterPlayerScripts/MainMenuClient/init.client.luau` |
| `ButtonEffects` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/ButtonEffects.luau` |
| `ButtonSounds` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/ButtonSounds.luau` |
| `CharacterPreview` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/CharacterPreview.luau` |
| `CreditsRoom` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/CreditsRoom.luau` |
| `MenuAudio` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuAudio.luau` |
| `MenuCamera` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuCamera.luau` |
| `MenuSettings` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuSettings.luau` |
| `RoomLighting` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/RoomLighting.luau` |
| `SceneDirector` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/SceneDirector.luau` |
| `SettingsBoard` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/SettingsBoard.luau` |
| `VolumeSlider` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/VolumeSlider.luau` |

The eleven ModuleScripts under `MainMenuClient` sit **inside** it (drag them onto it in the Explorer). `MenuAssets` and
`LoadingScreen` go straight into `ReplicatedFirst`, not into `MainMenuClient`. `MenuAudio` plays the menu's music (one looping track per scene, on the Music slider). `RoomLighting` turns the outdoor light off while Settings or Credits shows, so the room is meant to look dark and amber from its first frame instead of after a few seconds (checked by eye in Studio and approved on 2026-10-06), and puts it back on the way out and on Play. The settled rooms come out somewhat darker with it on. `MenuAssets` is the one place to change the
menu's sound ids (a plain number works too), the loading screen's title (`GAME_TITLE`) and tips, and its timings. The main
menu's own title is a different thing: it is the `Title` label inside `ReplicatedStorage.MainMenu`, which you edit in Studio. The names must match exactly.

### d) Turn off automatic spawning

In the Explorer, click **Players**. In Properties, untick **CharacterAutoLoads**. The menu holds each player until they
press Play, so nobody should spawn on their own.

### e) Optional: the menu's map camera

The menu looks at your map from a spot you choose. Fly the editor camera to the view you want, then run this in the
Command Bar. It makes a part called `MenuCameraShot` there. The camera looks out of the part's **Front** face, which
is the way the editor camera was looking.

```lua
local p = workspace:FindFirstChild("MenuCameraShot") or Instance.new("Part"); p.Name = "MenuCameraShot"; p.Size = Vector3.new(1,1,1); p.Anchored = true; p.CFrame = workspace.CurrentCamera.CFrame; p.Parent = workspace
```

When the game starts it anchors the part, hides it and turns off its collisions, so you do not have to. Without this
part, the menu uses a default angle.

### f) Playtest checklist

Press **Play** in Studio (the Test tab) and check each of these:

1. A dark loading screen shows first, with the title, a spinning amber ring and a tip. It stays for at least 2 seconds,
   fades to black, and the menu fades in.
2. The menu opens with the title, three buttons, and your avatar on the right after a few seconds. In the Device
   Emulator (a phone, landscape) the dark border and the fades reach every screen edge, notch included. Music plays and
   changes track with each scene (Menu, Settings, Credits), and fades out when you press Play.
3. **Settings** fades to a room with a board. The sliders move and the switches flip. **BACK** returns. The buttons and
   the switches make a hover sound and a click sound (PLAY has its own click sound).
4. **Credits** fades to a room with the developer's avatar on a stand, and the player's own avatar in the foreground,
   seen from behind, looking at it. Hovering one shows a name (the player's says `YOU`). **BACK** returns.
5. **Play** spawns your character and the menu goes away.
6. Reset your character. It respawns and the menu does not come back.
7. The Output window has no red text. A warning about a sound that did not load (`LoadingScreen: sound '...'`, `ButtonSounds: ...` or `MenuAudio: ...`) means
   Roblox refused that sound's asset id: fix the id in `MenuAssets`, or its permissions.

## What these steps cannot bring back

The build scripts make the **baseline look**. If you restyled the menu or the rooms in Studio after your last publish,
for example moved a button, changed a colour, or added a lamp, those changes were not in the scripts. Redo them, and
publish again straight away.
