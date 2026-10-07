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
- `ReplicatedStorage.TabletMenu`: the tablet's menu, a `ScreenGui` that is switched off (the game copies it into each
  player's screen). It is in the factory look and made of fractions of the screen, so it fits a phone. You can restyle it
  in Studio, as long as the names inside it stay (`Header` with `Title`, `Status` and `Close`; `Injections` with `List`
  and its `EntryTemplate`; `Target` with `Head`, `Torso`, `LeftArm`, `RightArm`, `LeftLeg` and `RightLeg`; `Confirm`).
  The colours of a picked, a lost and a greyed-out button are set by `TabletMenu.luau`, not by the template.
- `ServerStorage.LabBackup`: untouched copies of Bob, the tablet and the hard drive as you built them, made the first time
  the script ran.

The script is safe to run again: it only builds what is missing and leaves everything else as it is (if you moved
`BobHome` or the `Chair`, they stay where you put them). The one thing a re-run moves is the `Gantry` and Bob: they
line up under `BobHome` (and the two lines on Bob's screen are laid out again so they read upright). To move Bob's resting spot, drag `BobHome` (keep its
front face toward the way Bob's needle should point), then run the script again. To rebuild:

- **A piece of the lab** (for example the `Chair`, the `Gantry` or the `TabletMenu`): delete it, then run `studio/build_lab.luau`.
- **Bob, the tablet or the hard drive**: delete the broken one (`Workspace.Room1.BobTheInjector`, `ServerStorage.Tablet`
  or `ReplicatedStorage.LabAssets.HardDrives.Explosive`), copy (do not move) its original from `ServerStorage.LabBackup`
  into `Workspace`, then run the script. It rebuilds the piece from the original and uses that copy up.
- If `ServerStorage.LabBackup` is gone too, Bob, the tablet and the hard drive cannot be rebuilt: open an older saved or
  published version of the place.

### d) Put the scripts back

There are twenty-four scripts. The file names are in `src/`.

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
| `HardDriveEffects` | ModuleScript | `ServerScriptService` | `src/ServerScriptService/HardDriveEffects.luau` |
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
| `TabletMenu` | ModuleScript | `LabClient` | `.../LabClient/TabletMenu.luau` |
| `GooglyEyes` | ModuleScript | `LabClient` | `.../LabClient/GooglyEyes.luau` |
| `BobAnimator` | ModuleScript | `LabClient` | `.../LabClient/BobAnimator.luau` |
| `DeathScreen` | LocalScript | `StarterPlayer` -> `StarterPlayerScripts` | `src/StarterPlayer/StarterPlayerScripts/DeathScreen.client.luau` |

`DeathScreen` is the death screen for every death in the game, not only Room 1's: the moment your character dies the screen
cuts to black, every sound goes silent and a ringing in the ears plays (`LabConfig.Sounds.DeathRing`, fading to nothing over
`LabConfig.RESPAWN_TIME`). When you respawn the black fades out over 1.5 seconds and the sounds come back at the volumes they
had. It makes `PlayerGui.DeathScreen` (with a full-screen `Black` Frame) and `SoundService.DeathRing` by itself, and writes each
SoundGroup's volume to its `DeathSavedVolume` attribute while it is silenced, so do not delete those. Without `LabConfig` it still
cuts to black, with no ringing, and fades over 5 seconds. If the script breaks, Roblox's normal death shows instead.

`LabServer` is Room 1's server side and needs the pieces that `studio/build_lab.luau` builds (see c). It handles
claiming and the injections. Claiming: a player who triggers the claim prompt becomes the owner (`Workspace.Room1`'s `Owner` attribute holds their UserId,
0 when free, and the sign reads "ROOM 1 / FREE" or "ROOM 1 / <their name>"), a copy of their avatar sits in the chair as
`Room1.Subject`, and a `Tablet` goes into their Backpack. If the copy dies the owner dies, and the other way round. The
owner triggering the prompt again, or leaving the game, frees the room; when the owner respawns, a fresh copy and tablet are
made. It reads where to seat the copy from `Chair.Seat.SubjectSpot`, so a moved chair works without a code change. It also
sets `Players.RespawnTime` from `LabConfig.RESPAWN_TIME` at startup. `LabClient` sets the claim prompt's text on each player's
own screen ("Claim Room 1" when free, "Release Room 1" for the owner, switched off for everyone else).

Injections: when the game starts, `LabServer` makes `ReplicatedStorage.LabRemotes` with the `RequestInjection` remote in it (do
not build these by hand). The owner's tablet asks it for a Harddrive and a limb; `LabServer` checks the request and either
refuses it (with a reason the tablet shows, such as "BOB IS BUSY" or "LIMB ALREADY LOST") or runs Bob's injection: the doorway
`Shutter` slides shut, Bob moves, injects and goes home, and the shutter opens again. It never moves Bob itself: it writes
what he is doing on `Room1.BobTheInjector` as attributes (`State`, `Target`, `HardDrive`, `PhaseStart`) and each player's
game animates him from those, so do not delete those attributes. As the needle comes out, `HardDriveEffects` (which goes
straight into `ServerScriptService`, next to `LabServer`, not inside it) does what the Harddrive does, to the copy and the
owner at once. Explosive: the limb glows red and beeps faster and faster for `LabConfig.FUSE_SECONDS`, then blows: an arm or
a leg falls off both bodies (and lies on the floor for `LabConfig.LOST_LIMB_SECONDS`) and both lose `LabConfig.LIMB_DAMAGE`
health; the head or the torso kills both. Losing the right arm also takes the tablet away until the owner respawns. If the
room is freed or the owner dies before the blast, Bob goes home and the fuse goes out with nothing blown off. Without
`HardDriveEffects` the room can still be claimed, but every injection is refused (the Output window says why).

`TabletMenu` is the tablet's menu (it sits **inside** `LabClient`, like the ModuleScripts under `MainMenuClient`) and needs the
`ReplicatedStorage.TabletMenu` template that `studio/build_lab.luau` builds (see c). `LabClient` opens it when the owner
clicks, taps or presses the trigger with the Tablet in hand, and closes it when the tablet is put away or taken (a lost right
arm, a release), when the owner's character dies, and on the X or a controller's B. The owner picks a Harddrive (the list is
`LabConfig.HardDrives`) and a limb (drawn as a body seen from the front, so the owner's right limbs are on the screen's
left), and CONFIRM then asks the server (`RequestInjection`). A limb already blown off reads LOST and cannot be picked. While
Bob is busy the menu opens read-only and shows what he is doing, and a refusal from the server (such as "BOB IS BUSY") shows
in the top bar for three seconds. It plays the main menu's hover and click sounds (`SoundService.MenuSfxHover` and
`MenuSfxConfirm`) and is silent without them. If `TabletMenu` or its template is broken, the Output window says so once and
claiming still works, but there is no tablet menu.

`BobAnimator` (also **inside** `LabClient`) moves Bob on each player's screen from the attributes above: the carriage and
sleeve slide along the gantry (the crossbeam with them), the column lowers through the sleeve, Bob turns to face the limb and
the needle slides out into it and back, then he goes home to `BobHome`. Each phase is timed from `PhaseStart`, so a player who
joins mid-injection sees Bob in the right place. His screen reads the phase ("TARGET: LEFT ARM" over "EXPLOSIVE",
"INJECTING", "RETURNING", a slowly pulsing "STANDBY"). It adds two sounds of its own on each player's side, in the SFX group:
`BobMotor` in the carriage (louder the faster Bob moves) and `NeedleHiss` in the needle (while the needle is in). On Standby,
when a player walks into the room (the invisible `Zone`), Bob slides over until his eyes are `LabConfig.FOLLOW_DISTANCE` studs
from the nearest one (slowly, at most 4 studs a second), turns to face them and lowers his needle to their head's height; when
nobody is in the room he drifts back to `BobHome`. His body swings a little when he starts and stops. His googly eyes roll
inside their whites (they use `GooglyEyes`, another ModuleScript inside `LabClient`), look toward the player he is watching, and
spin when something blows up in the room. While he moves
in and injects, the copy's head turns to watch the needle and the injected limb twitches; that happens on each player's screen
only, and the copy faces forward again when Bob is back on Standby. It reads Bob as built when the game starts, so it needs the
names `studio/build_lab.luau` gives (`Column.Core.ColumnPivot`, `Needle.NeedleTip` and `NeedleBase`, `Body.Screen.Display`,
`Body.EyeWhiteL` and `EyeWhiteR` with their `EyeCenter`, `Pupils.PupilL` and `PupilR`, the `Gantry` parts and `Room1.Zone`)
and Bob resting at `BobHome`. How far the carriage may travel is a list at the top of the script (x 35.5 to 56, z 19.2 to
52.2), next to the follow speed, swing and flinch settings. If it breaks, the Output window says so once and Bob stays still,
but injections still happen.

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
6. Reset your character. The screen cuts to black at once with a ringing in your ears and no other sound, and after about 5
   seconds you respawn, the black fades out and the music and sound effects come back. The menu does not come back.
7. Walk to the panel outside Room 1's window and press its prompt ("Claim Room 1"). The sign changes to your name, a copy of
   your avatar sits in the chair facing the window, and a Tablet is in your toolbar. Press the prompt again ("Release
   Room 1"): the copy and the Tablet go and the sign says FREE. Claim again and reset your character: after it respawns
   there is a fresh copy and one Tablet.
8. While you own Room 1, hold the Tablet (press its number key, or tap it in the toolbar) and click, tap or press the trigger.
   The tablet menu opens in dark steel and amber: "BOB-LINK / ROOM 1" at the top with "STANDBY" and a dot, a list with
   EXPLOSIVE and its picture, and a body drawn from the front with HEAD, TORSO, R ARM, L ARM, R LEG and L LEG (R ARM is on the
   left of the screen). CONFIRM stays grey ("PICK A HARDDRIVE AND A LIMB") until you pick EXPLOSIVE and a limb, then reads
   e.g. "CONFIRM: EXPLOSIVE INTO LEFT ARM". Press it: the menu closes and Bob goes to work. Open the tablet again while he
   moves: it is read-only and the top bar shows MOVING, INJECTING or RETURNING. After the blast the limb reads LOST and
   cannot be picked. The X, putting the tablet away, and (on a controller) B all close the menu, and so does dying. On a
   phone every button is easy to tap and the menu stays clear of the notch and the top bar.
9. The Output window has no red text. A warning about a sound that did not load (`LoadingScreen: sound '...'`, `ButtonSounds: ...` or `MenuAudio: ...`) means
   Roblox refused that sound's asset id: fix the id in `MenuAssets`, or its permissions.

## What these steps cannot bring back

The build scripts make the **baseline look**. If you restyled the menu or the rooms in Studio after your last publish,
for example moved a button, changed a colour, or added a lamp, those changes were not in the scripts. Redo them, and
publish again straight away. The menu's colours and fonts are the exception: they live in `MenuAssets` (the theme), not in
Studio, so they come back with the scripts. The menu Title's words are built as "A Regular Experiment"; if you changed them in
Studio since, redo that.

Room 1's walls, Bob, the tablet and the hard drive are not in any script at all (see c). If the place file itself is lost,
so are they, and so is their backup in `ServerStorage.LabBackup`, which lives in the same place file.
