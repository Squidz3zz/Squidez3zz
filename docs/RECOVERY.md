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

### c) Rebuild Room 1's injection lab

Room 1 itself (its walls, floor, window and doorway), Bob the Injector, the tablet and the Explosive hard drive were built
by hand in Studio. They exist **only in the place file**: no script can make them again, so save and publish after you
change them.

`studio/build_lab.luau` builds the lab's pieces around them and rewires Bob and the tablet:

- `Workspace.Room1`: `Zone` (the invisible box that tells whether a player is in the room), `Chair` (its `Seat` holds
  `SubjectSpot`, where the test subject sits), `ClaimButton` (the panel outside the window with the claim prompt and the
  "ROOM 1 / FREE" sign), `Shutter` (the doorway's shutter, built open), `Gantry` (the ceiling rails, crossbeam and
  carriage Bob travels on), `BobHome` (an invisible marker where Bob rests) and `BobTheInjector` (Bob, moved under the
  carriage and regrouped into `Column`, `Body`, `Needle` and `Pupils`).
- `ServerStorage.Tablet`: the tablet, made into a Tool.
- `ReplicatedStorage.LabAssets.HardDrives.Explosive`: the hard drive, the picture in the tablet's list.
- `ServerStorage.LabBackup`: untouched copies of Bob, the tablet and the hard drive as you built them, made the first time
  the script ran.

The script is safe to run again: it only builds what is missing and leaves everything else as it is (if you moved
`BobHome` or the `Chair`, they stay where you put them). The one thing a re-run moves is the `Gantry` and Bob: they
line up under `BobHome`. To move Bob's resting spot, drag `BobHome` (keep its
front face toward the way Bob's needle should point), then run the script again. To rebuild:

- **A piece of the lab** (for example the `Chair` or the `Gantry`): delete it, then run `studio/build_lab.luau`.
- **Bob, the tablet or the hard drive**: delete the broken one (`Workspace.Room1.BobTheInjector`, `ServerStorage.Tablet`
  or `ReplicatedStorage.LabAssets.HardDrives.Explosive`), copy (do not move) its original from `ServerStorage.LabBackup`
  into `Workspace`, then run the script. It rebuilds the piece from the original and uses that copy up.
- If `ServerStorage.LabBackup` is gone too, Bob, the tablet and the hard drive cannot be rebuilt: open an older saved or
  published version of the place.

### d) Put the scripts back

There are nineteen scripts. The file names are in `src/`.

**Easy way, with Rojo** (a free tool, https://rojo.space; version 7.3 or newer):

1. Install Rojo and its Studio plugin.
2. In a terminal opened in this folder, run `rojo serve`.
3. In Studio, open the Rojo plugin and press **Connect**.

The file `default.project.json` already says where everything goes. It only touches `ReplicatedFirst`,
`ReplicatedStorage`, `ServerScriptService` and `StarterPlayerScripts`, and it leaves your other scripts (and the menu's
ScreenGuis in `ReplicatedStorage`) alone.

**By hand:** create each script with the right kind and parent, then paste the file's text into it.

| Name | Kind | Parent | File to copy |
|---|---|---|---|
| `MenuAssets` | ModuleScript | `ReplicatedFirst` | `src/ReplicatedFirst/MenuAssets.luau` |
| `LoadingScreen` | LocalScript | `ReplicatedFirst` | `src/ReplicatedFirst/LoadingScreen.client.luau` |
| `LabConfig` | ModuleScript | `ReplicatedStorage` | `src/ReplicatedStorage/LabConfig.luau` |
| `MenuServer` | Script | `ServerScriptService` | `src/ServerScriptService/MenuServer.server.luau` |
| `LabServer` | Script | `ServerScriptService` | `src/ServerScriptService/LabServer.server.luau` |
| `MainMenuClient` | LocalScript | `StarterPlayer` -> `StarterPlayerScripts` | `src/StarterPlayer/StarterPlayerScripts/MainMenuClient/init.client.luau` |
| `ButtonEffects` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/ButtonEffects.luau` |
| `ButtonSounds` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/ButtonSounds.luau` |
| `CharacterPreview` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/CharacterPreview.luau` |
| `CreditsRoom` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/CreditsRoom.luau` |
| `MenuAudio` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuAudio.luau` |
| `MenuCamera` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuCamera.luau` |
| `MenuSettings` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuSettings.luau` |
| `MenuTheme` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/MenuTheme.luau` |
| `RoomLighting` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/RoomLighting.luau` |
| `SceneDirector` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/SceneDirector.luau` |
| `SettingsBoard` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/SettingsBoard.luau` |
| `VolumeSlider` | ModuleScript | `MainMenuClient` | `.../MainMenuClient/VolumeSlider.luau` |
| `LabClient` | LocalScript | `StarterPlayer` -> `StarterPlayerScripts` | `src/StarterPlayer/StarterPlayerScripts/LabClient/init.client.luau` |

`LabServer` is Room 1's server side and needs the pieces that `studio/build_lab.luau` builds (see c). So far it handles
claiming: a player who triggers the claim prompt becomes the owner (`Workspace.Room1`'s `Owner` attribute holds their UserId,
0 when free, and the sign reads "ROOM 1 / FREE" or "ROOM 1 / <their name>"), a copy of their avatar sits in the chair as
`Room1.Subject`, and a `Tablet` goes into their Backpack. If the copy dies the owner dies, and the other way round. The
owner triggering the prompt again, or leaving the game, frees the room; when the owner respawns, a fresh copy and tablet are
made. It reads where to seat the copy from `Chair.Seat.SubjectSpot`, so a moved chair works without a code change. It also
sets `Players.RespawnTime` from `LabConfig.RESPAWN_TIME` at startup. `LabClient` sets the claim prompt's text on each player's
own screen ("Claim Room 1" when free, "Release Room 1" for the owner, switched off for everyone else).

The twelve ModuleScripts under `MainMenuClient` sit **inside** it (drag them onto it in the Explorer). `MenuAssets` and
`LoadingScreen` go straight into `ReplicatedFirst`, not into `MainMenuClient`, and `LabConfig` (the settings of Room 1's injection lab) goes straight into `ReplicatedStorage`. `MenuAudio` plays the menu's music (one looping track per scene, on the Music slider). `RoomLighting` turns the outdoor light off while Settings or Credits shows, so the room is meant to look dark and amber from its first frame instead of after a few seconds (checked by eye in Studio and approved on 2026-10-06), and puts it back on the way out and on Play. The settled rooms come out somewhat darker with it on. `MenuAssets` is the one place to change the
menu's look (`THEME`, see below), its sound ids (a plain number works too), the loading screen's title (`GAME_TITLE`) and tips, and its timings. The main
menu's own title is a different thing: it is the `Title` label inside `ReplicatedStorage.MainMenu`, which you edit in Studio. The names must match exactly.
`MenuTheme` paints the theme on the menu when it opens (see "Themes").

### Themes: changing how the menu looks

The look of the whole menu is one setting at the top of `ReplicatedFirst.MenuAssets`: `THEME = "SterileBright"`. Two presets
ship in `Themes`: `Factory` (the rusty factory look: dark steel, amber, Oswald) and `SterileBright` (a bright bio-lab: white
panels, teal, storm-blue text, Michroma and Titillium Web, a thin yellow and black hazard stripe at the top of the screen).
To switch, change the name in quotes. To make your own, copy a whole preset inside `Themes`, give it a new name and edit its
colours (`Color3.fromRGB(red, green, blue)`) and fonts, then set `THEME` to that name. A preset can leave keys out (they use
Factory's value), and a wrong name or a value of the wrong kind falls back to Factory with a warning in the Output window, so a
mistyped name or colour never breaks the menu. Never rename or delete `Factory` (every preset falls back to it), and to change the
factory look copy it under a new name instead of editing it. A mistake in the file's own writing (a missing comma, quote or
bracket) is different: the whole of `MenuAssets` then fails to load, so the sound ids, the loading screen's title and tips and its
timings are lost along with the theme. The menu still opens and Play still works, in the Factory look, with no sounds, "LOADING..."
as the only tip and the default timings, and the Output window names the error.

What a theme paints: the main menu's title colours and font, PLAY / SETTINGS / CREDITS / BACK (and whether they darken when
hovered), the screen edges and the hazard stripe, the loading screen, the Settings room's board, the name label and outline in
Credits, and the tint of the colour grade over the menu screens (warm in Factory, cool and nearly neutral in SterileBright; it only
affects the menu, Settings and Credits). What it does **not** touch: the 3D rooms and their lamps, the black fade, and the room
lighting.

Important: the colours and fonts of those pieces come from the theme **at runtime**. When the menu opens it is painted over, so
editing the colours or fonts of `ReplicatedStorage.MainMenu` (the buttons, the Title's colour or font, the Vignette) in Studio
has no effect while a theme is active; change the theme instead. Positions, sizes and the **words** (such as the Title's text,
"A Regular Experiment") are still edited in Studio. `studio/build_main_menu_ui.luau` always builds the Factory baseline; the
theme is what turns it into another look.

### e) Turn off automatic spawning

In the Explorer, click **Players**. In Properties, untick **CharacterAutoLoads**. The menu holds each player until they
press Play, so nobody should spawn on their own. (How long a dead player waits before respawning is `Players.RespawnTime`,
which `LabServer` sets from `LabConfig.RESPAWN_TIME` when the game starts.)

### f) Optional: the menu's map camera

The menu looks at your map from a spot you choose. Fly the editor camera to the view you want, then run this in the
Command Bar. It makes a part called `MenuCameraShot` there. The camera looks out of the part's **Front** face, which
is the way the editor camera was looking.

```lua
local p = workspace:FindFirstChild("MenuCameraShot") or Instance.new("Part"); p.Name = "MenuCameraShot"; p.Size = Vector3.new(1,1,1); p.Anchored = true; p.CFrame = workspace.CurrentCamera.CFrame; p.Parent = workspace
```

When the game starts it anchors the part, hides it and turns off its collisions, so you do not have to. Without this
part, the menu uses a default angle.

### g) Playtest checklist

Press **Play** in Studio (the Test tab) and check each of these:

1. A loading screen shows first, in the theme's colours (dark with an amber ring in Factory, light with a teal ring and the
   hazard stripe in SterileBright), with the title, a spinning ring and a tip. It stays for at least 2 seconds,
   fades to black, and the menu fades in.
2. The menu opens with the title, three buttons, and your avatar on the right after a few seconds. In the Device
   Emulator (a phone, landscape) the border (dark in Factory, pale in SterileBright) and the fades reach every screen edge, notch included. Music plays and
   changes track with each scene (Menu, Settings, Credits), and fades out when you press Play.
3. **Settings** fades to a room with a board. The sliders move and the switches flip. **BACK** returns. The buttons and
   the switches make a hover sound and a click sound (PLAY has its own click sound).
4. **Credits** fades to a room with the developer's avatar on a stand, and the player's own avatar in the foreground,
   seen from behind, looking at it. Hovering one shows a name (the player's says `YOU`). **BACK** returns.
5. **Play** spawns your character and the menu goes away.
6. Reset your character. It respawns and the menu does not come back.
7. Walk to the panel outside Room 1's window and press its prompt ("Claim Room 1"). The sign changes to your name, a copy of
   your avatar sits in the chair facing the window, and a Tablet is in your toolbar. Press the prompt again ("Release
   Room 1"): the copy and the Tablet go and the sign says FREE. Claim again and reset your character: after it respawns
   there is a fresh copy and one Tablet.
8. The Output window has no red text. A warning about a sound that did not load (`LoadingScreen: sound '...'`, `ButtonSounds: ...` or `MenuAudio: ...`) means
   Roblox refused that sound's asset id: fix the id in `MenuAssets`, or its permissions.

## What these steps cannot bring back

The build scripts make the **baseline look**. If you restyled the menu or the rooms in Studio after your last publish,
for example moved a button, changed a colour, or added a lamp, those changes were not in the scripts. Redo them, and
publish again straight away. The menu's colours and fonts are the exception: they live in `MenuAssets` (the theme), not in
Studio, so they come back with the scripts. The menu Title's words are built as "A Regular Experiment"; if you changed them in
Studio since, redo that.

Room 1's walls, Bob, the tablet and the hard drive are not in any script at all (see c). If the place file itself is lost,
so are they, and so is their backup in `ServerStorage.LabBackup`, which lives in the same place file.
