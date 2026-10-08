# Room 1 injection lab: design

Date: 2026-10-06. Status: approved in conversation, awaiting review of this written spec.

## Goal

The first slice of the game's main premise (inspired by Ro-Bio): a player claims Room 1, a linked copy of their avatar sits
in the room as the test subject, and the player uses a tablet to make Bob the Injector inject Harddrives into the copy's
limbs. Whatever happens to the copy happens to the player's real character. The first Harddrive is Explosive.

Success: a player can claim Room 1, open the tablet, pick Explosive and a limb, watch Bob travel, aim, inject and return,
and see the limb blow off both the copy and themselves (or both die on a head or torso hit, with the new death screen).
Bob follows and watches players who walk into the room, with bouncy googly eyes. Everything in the factory theme.

## Decisions (from the brainstorm)

| Topic | Decision |
|---|---|
| Test subject | A copy of the player's avatar, seated in Room 1, linked to the player. |
| The link | Exactly the same: every effect on the copy (limb loss, damage, death) is applied to the player too. If either dies, the other does too, and a fresh copy is seated when the player respawns. |
| Explosive | A 3 s fuse, then a blast at the limb. Arm or leg: the limb falls off, 20 damage. Head or torso: instant death. The blast itself is harmless (no physics damage to anyone else or to the room). |
| Tablet | A Tool given on claim (and again after each respawn while the room is owned). Equip, then click / tap / controller trigger opens the menu. |
| Harddrives | All types are on the list from the start with unlimited uses (testing). Collecting comes later. |
| Bob's movement | A ceiling gantry (claw machine): two rails, a crossbeam, a carriage. The column telescopes through a sleeve; the body turns and aims. |
| Architecture | Approach 1: the server owns the rules, timing and effects and publishes Bob's state; each client animates Bob (and the googly eyes, following, the copy's flinch) locally. |
| Right arm | Tools hang from the right hand: losing the right arm means no tablet until respawn. Kept on purpose. |
| Death screen | Every death in the game: instant cut to black, ear ringing (rbxassetid://9069161602), other sounds silenced, fade back in on respawn. |
| Extras chosen | The copy flinches (head follows the needle, twitch on injection). The doorway shutter closes while Bob is working. |
| Extras declined | Red warning lamp, lab log on the tablet. |
| Theme | The Factory look (MenuAssets.Themes.Factory colours and Oswald) for the tablet, Bob's screen and the claim sign, whatever MenuAssets.THEME is. |

## Room 1 as it exists

Room 1 is the walled box the user built from loose Parts in Workspace (they stay loose; this work does not regroup them):
interior about x 32.3 to 59.2, z 16.8 to 54.6, floor top y 0.35, ceiling underside y 22.55. The x = 32.3 wall has the
observation window (z 18.5 to 40.6, y 2.9 to 11.8) and an open doorway (z 40.7 to 44.6, y 0 to 6.4). The operator stands
outside the window with the tablet. BobTheInjector, Tablet, ExplosiveHardDrive and the avatar model thxalloverme123 are
parked outside the room (x 0 to 22) and unwelded; Bob's 39 parts and the tablet's 7 are unanchored with no welds.

## What gets built in Studio (studio/build_lab.luau, run once)

All new pieces go in a Model `Workspace.Room1` (ModelStreamingMode Persistent, because StreamingEnabled is on and every
client needs Bob, the copy and the zone at all times). Each marker is a part the user may drag; code reads positions from
them, never from numbers in code.

| Piece | What it is |
|---|---|
| `Room1.Zone` | Invisible box filling the room interior. CanCollide, CanQuery, CanTouch false. "Is a player in the room" = the player's HumanoidRootPart is inside this box. |
| `Room1.Chair` | Factory-style patient chair (dark steel), at x 51.5, z 35 (toward the back of the room, in view of the window), facing the window (-X). Bob's needle tip is 12 studs from his column, so this leaves him room to reach the front and both sides from inside the gantry's travel. Holds an Attachment `SubjectSpot` where the copy's HumanoidRootPart goes. |
| `Room1.ClaimButton` | A panel outside the window next to the doorway with a ProximityPrompt (`ObjectText` "Room 1") and a SurfaceGui sign: "ROOM 1 / FREE" or "ROOM 1 / <display name>". |
| `Room1.Shutter` | A steel shutter in the doorway. Open: transparent and not collidable. Closed: solid. |
| `Room1.Gantry` | Two ceiling rails along Z near the long walls, a `Crossbeam` spanning X, a `Carriage` on the crossbeam, and a `Sleeve` (a short open tube hanging from the carriage that hides the column's top as it extends). |
| `Room1.BobHome` | Invisible marker: Bob's carriage position when idle (above and beside the chair). |
| `Room1.BobTheInjector` | Bob, moved in under the carriage at BobHome and rewired (below). |

At run time LabServer adds the copy as the Model `Room1.Subject` (absent while the room is free) and keeps the attribute
`Room1.Owner` (the owner's UserId, 0 when free).

Bob is rewired into welded groups, every part Anchored (clients move them by CFrame), CanCollide false, CanTouch false,
CanQuery false:

| Group | Parts |
|---|---|
| `Column` | The CorrodedMetal plates and cores around x 20.7, z 60.8 (the vertical tube). Slides along the vertical axis inside the sleeve: extend = down, retract = up. |
| `Body` | The black Foil hose segments, the head, the nozzle, `DisplayPanel` and `GooglyEyesForBob`. Rotates about the column's bottom pivot (yaw to aim, plus the cosmetic swing). |
| `Needle` | The MeshPart needle. Slides along its own axis out of the nozzle. |
| `Eyes` | The two white discs (fixed to Body) and the two black pupils (moved by the eye simulation, within the disc plane). |

The build script adds Attachments the animator reads instead of hard-coded offsets: `ColumnPivot` (column axis at the
column's bottom), `NeedleBase` and `NeedleTip` (the needle's two ends at rest), and an `EyeCenter` per eye. Bob's screen is
a SurfaceGui on DisplayPanel's large black face: a black background, amber Oswald text, two lines (a headline and a detail).

The Tablet model becomes a Tool `ServerStorage.Tablet`: Handle = its PrimaryPart, the other parts welded to it,
unanchored, CanCollide false, Massless, a Grip that holds it flat in front of the player.

The ExplosiveHardDrive part moves to `ReplicatedStorage.LabAssets.HardDrives.Explosive` as the picture shown for that entry
in the tablet's list (in a ViewportFrame). The avatar model thxalloverme123 is left where it is (it was a placement
reference; the copy replaces it).

The tablet menu is a template `ReplicatedStorage.TabletMenu` (ScreenGui), built in Factory style by the same script, so it
can be restyled in Studio as long as the element names stay.

## Code

| File | Runs on | Job |
|---|---|---|
| `src/ReplicatedStorage/LabConfig.luau` | both | The settings the user edits (below). |
| `src/ServerScriptService/LabServer.server.luau` | server | Claim and release, the copy, the tablet, the RequestInjection remote, the injection sequence, the shutter, death linking, RespawnTime. |
| `src/ServerScriptService/HardDriveEffects.luau` | server | One function per Harddrive id, applied to a list of bodies at once. Explosive first. |
| `src/StarterPlayer/StarterPlayerScripts/LabClient/init.client.luau` | client | Wires the modules below; the claim prompt's text for this player. |
| `.../LabClient/TabletMenu.luau` | client | The tablet menu. |
| `.../LabClient/BobAnimator.luau` | client | Bob's gantry, column, body, needle, swing and screen; following; the copy's flinch. |
| `.../LabClient/GooglyEyes.luau` | client | The pupil simulation (pure maths, unit-tested). |
| `src/StarterPlayer/StarterPlayerScripts/DeathScreen.client.luau` | client | The death screen, for every death. |
| `studio/build_lab.luau` | Studio | The one-time build above. |

`default.project.json` gains a `ReplicatedStorage` entry (`$path` src/ReplicatedStorage, `$ignoreUnknownInstances` true, so
the Studio-built templates stay). Remotes live in `ReplicatedStorage.LabRemotes`, created by LabServer.

### LabConfig

```lua
return {
	RESPAWN_TIME = 5,          -- seconds dead before respawning (sets Players.RespawnTime)
	LIMB_DAMAGE = 20,          -- Explosive on an arm or leg
	FUSE_SECONDS = 3,          -- Explosive's fuse, from the needle leaving the limb to the blast
	LOST_LIMB_SECONDS = 10,    -- how long a blown-off limb lies on the floor
	Timings = { Move = 2, NeedleOut = 0.4, Hold = 1, NeedleIn = 0.4, Return = 1.5 },
	FOLLOW_DISTANCE = 8,       -- how far Bob keeps his eyes from a player he follows (studs)
	Sounds = {
		DeathRing = "rbxassetid://9069161602",
		FuseBeep = "rbxassetid://118464872816736",
		NeedleHiss = "rbxassetid://8375254457",
		BobMotor = "rbxassetid://18627683806",   -- loops while Bob is moving
	},
	HardDrives = {             -- the tablet lists them in this order
		{ id = "Explosive", name = "EXPLOSIVE" },
	},
}
```

Lab sounds go in the SFX SoundGroup (so the Sound Effects slider applies), except DeathRing, which must stay audible while
everything else is silenced.

### Limbs

The game is R6 only (the user's decision, 2026-10-06): every character and every copy is R6. The six limb keys map to
their part and the joint that holds it on:

| Key | Part | Joint |
|---|---|---|
| Head | Head | Torso.Neck |
| Torso | Torso | none (always fatal) |
| LeftArm | Left Arm | Torso."Left Shoulder" |
| RightArm | Right Arm | Torso."Right Shoulder" |
| LeftLeg | Left Leg | Torso."Left Hip" |
| RightLeg | Right Leg | Torso."Right Hip" |

A limb is "lost" when its joint no longer exists. This table lives in LabConfig (both sides need it: the server to break
joints and validate, the client to aim the needle and grey out lost limbs).

## Claiming and the copy (LabServer)

- **Claim:** the ClaimButton prompt is triggered by a player with a character while the room is free. The player becomes
  the owner. LabServer builds the copy with
  `Players:CreateHumanoidModelFromDescription(humanoid:GetAppliedDescription(), Enum.HumanoidRigType.R6)` (no web calls,
  an exact match of the character), names it `Subject`, hides its name tag, anchors its HumanoidRootPart at the chair's
  SubjectSpot, plays the R6 sit animation (rbxassetid://178130996) through its Animator, sets its Health
  and MaxHealth to the player's, parents it to Room1 and sets `Room1.Owner`. A clone of ServerStorage.Tablet goes into the
  player's Backpack.
- **Release:** the owner triggers the prompt again, or leaves the game. The copy and the owner's tablet are destroyed, any
  injection is cancelled, Bob is set to Standby and the room is free.
- **Respawn while owning:** on CharacterAdded, the old copy is destroyed, a fresh one is seated and a fresh tablet is given.
- **Death link:** the copy's Humanoid.Died sets the owner's Health to 0; the owner's Humanoid.Died sets the copy's Health
  to 0. Effects are applied to both bodies by HardDriveEffects directly (not by watching one and copying to the other).
  Damage is `Health -= n` on both, not TakeDamage, so a spawn ForceField cannot make the two drift apart.
- **No regeneration:** health does not regenerate (an empty Script `StarterCharacterScripts.Health` replaces Roblox's default
  healing script, game-wide), so the owner cannot heal while the copy, which has no such script, does not.
- **The prompt per player:** LabClient sets the prompt's ActionText locally ("Claim Room 1" when free, "Release Room 1"
  for the owner) and disables it locally for everyone else while the room is owned. The server still checks every trigger.
- `Players.RespawnTime` is set from LabConfig.RESPAWN_TIME at startup (MenuServer's respawn already waits for it).

## The tablet menu (TabletMenu)

Opens when the player has the Tablet equipped and activates it (click, tap, controller trigger). Closes on the X button,
controller B, unequipping, or Confirm.

- Header: "BOB-LINK / ROOM 1" on the left; Bob's state on the right ("STANDBY", "MOVING", "INJECTING") with a dot; the X.
- Left, "INJECTIONS": one entry per LabConfig.HardDrives item, each a ViewportFrame of its brick plus its name. The picked
  one has the amber outline.
- Right, "TARGET (FACING YOU)": the R6 body drawn front-on (the copy faces the window, so its left arm is on the right of
  the screen), six buttons labelled HEAD, TORSO, L ARM, R ARM, L LEG, R LEG. A lost limb is greyed out, reads LOST and
  cannot be picked. The picked limb is amber.
- CONFIRM under the diagram: inactive until a Harddrive and a limb are picked, then reads e.g. "CONFIRM: EXPLOSIVE INTO
  LEFT ARM". Pressing it calls `LabRemotes.RequestInjection:InvokeServer(hardDriveId, limbKey)`. On success the menu closes.
  On refusal the reason shows in the header line for a few seconds.
- While Bob is not on Standby the menu opens read-only: CONFIRM is inactive and the header shows his state.
- Hover and click sounds: the menu's existing `SoundService.MenuSfxHover` and `MenuSfxConfirm`, looked up by name.
- Scale-only layout inside the phone safe area; every button at least 40 px tall on a phone; works with controller
  selection (GuiService).

## An injection (LabServer)

`RequestInjection(player, hardDriveId, limbKey)` validates, starts the sequence in its own thread and returns at once
`(true)` or `(false, reason)`. Refusals: not the owner, no copy, Bob busy, unknown Harddrive, unknown limb, limb lost.

Bob's state is published as attributes on `Room1.BobTheInjector`: `State` ("Standby", "Moving", "Injecting", "Returning"),
`Target` (limb key or ""), `HardDrive` (id or ""), `PhaseStart` (workspace:GetServerTimeNow() when the phase began). The
server waits out each phase with the LabConfig timings; clients animate the same phases from these attributes.

| Phase | Duration | What happens |
|---|---|---|
| Moving | Move (2 s) | Shutter closes. Bob travels from wherever he is to the injection pose for the limb. Screen: "TARGET: LEFT ARM" / "EXPLOSIVE". |
| Injecting | NeedleOut + Hold + NeedleIn (1.8 s) | Needle slides out into the limb, holds (NeedleHiss), slides back. Screen: "INJECTING" / limb. The copy twitches. |
| (effect) | starts at the end of Injecting | HardDriveEffects[id]({ copy, ownerCharacter }, limbKey) runs in its own thread. |
| Returning | Return (1.5 s) | Bob goes home. Screen: "RETURNING". |
| Standby | until the next request | Shutter opens. Screen: "STANDBY" (slow pulse). |

The shutter is moved by the server (a 0.4 s tween down from the doorway's top when closing, back up and transparent when
opening); it is the one moving thing the server animates, since it must block players for real.

The owner dying, the copy being replaced, or a release cancels the sequence: the state goes straight to Returning, then
Standby. A running effect stops if its bodies are gone.

## Explosive (HardDriveEffects)

For each body still alive and still holding the limb: a red Highlight on the limb's parts blinks, and FuseBeep plays from
the limb, both speeding up over FUSE_SECONDS. Then, per body: an Explosion at the limb (BlastPressure 0,
DestroyJointRadiusPercent 0, so it is only the flash and Roblox's own explosion sound), and:

- arm or leg: the limb's joint is destroyed, its parts are unanchored and collidable and fall; they are removed after
  LOST_LIMB_SECONDS; Health -= LIMB_DAMAGE;
- head or torso: Health = 0.

No extra remote tells clients about the blast: the Explosion instance replicates, and BobAnimator gives the eyes a spin
impulse when one appears inside Room1.Zone (seen through workspace.DescendantAdded).

## Bob on the client (BobAnimator)

Every client moves its own copy of Bob's anchored parts by CFrame each frame (RenderStepped). The server never moves
them, so the clients' changes stand.

- **Pose:** carriage X/Z (clamped to the gantry's travel), column extension (0 = fully up, as built; positive = down; the
  needle reaches seated limb heights with the sleeve still hiding the column's top), body yaw about ColumnPivot, needle
  extension along NeedleBase to NeedleTip. The crossbeam follows the carriage's Z.
- **Injection pose for a limb:** approach direction per limb from the copy's facing: Head, Torso and both legs from the
  front; LeftArm from the copy's left; RightArm from its right. The needle tip stops 0.5 studs short of the limb's
  surface, at the limb's centre height; the carriage, extension and yaw follow from that and from the NeedleTip offset.
  The needle then extends 1.5 studs into the limb.
- **Following (State = Standby):** if a player's HumanoidRootPart is inside Room1.Zone, Bob moves so that his eyes are
  FOLLOW_DISTANCE (horizontally) from the closest such player, on his current side of them, and eases toward that spot
  (speed-limited, so he lags and never goes straight onto them). The distance is measured from his eyes, not his
  carriage: his body reaches about 10 studs out from the column, so a carriage-based distance would put his head on the
  player's. His body yaws and his pupils are pulled toward that player's head. With nobody
  in the zone he eases back to BobHome and the pupils are left to gravity. The copy never counts.
- **Phases:** on a State change the animator eases from wherever Bob is to the phase's end pose over the phase's time
  (using PhaseStart, so a client that joins late lands in the right place).
- **Swing (flexibility):** the body swings about ColumnPivot on a damped spring driven by the carriage's acceleration, so
  it trails and settles when Bob starts and stops. ponytail: whole-body swing; bend individual hose segments if it reads
  as too stiff.
- **Screen:** set from the attributes above; STANDBY pulses.
- **Sounds:** BobMotor loops from the carriage while Bob is moving (its volume follows his speed, silent when still);
  NeedleHiss plays from the needle during Hold. Both are client-side and in the SFX group.
- **Copy flinch:** while State is Moving or Injecting, the copy's head turns toward the needle tip (Neck C0, clamped to
  70 degrees of yaw and 35 of pitch, smoothed). During Hold the target limb's joint jitters a few degrees. Back to facing
  forward over 0.5 s on Standby. Client-side only.

## Googly eyes (GooglyEyes)

Per eye, the pupil's offset from the eye centre is a 2D point in the disc's plane, limited to a circle of radius
(white radius - pupil radius). Each frame: acceleration = gravity (projected into the plane) + a pull toward the watched
target's direction (when there is one) - the eye's own acceleration in world space (so Bob's moves jolt the pupils) - damping.
At the rim the pupil bounces back with some energy lost. A spin impulse adds a tangential velocity. Pure maths: step(state,
inputs, dt) -> state, tested on its own (the pupil never leaves the circle; with no target it settles at the bottom).

## Death screen (DeathScreen)

On the local character's Humanoid.Died, in the same frame: a full-screen black Frame (ScreenGui with IgnoreGuiInset and
ScreenInsets None, DisplayOrder above everything) goes fully opaque; every SoundGroup in SoundService is set to volume 0
(their volumes are saved); the character's default death sound is silenced (its "Died" Sound gets Volume 0 as soon as it
appears in the character); DeathRing plays at full volume from SoundService (in no group) and fades to silence over
RESPAWN_TIME. On the next CharacterAdded the black fades out over 1.5 s and the SoundGroups go back to their saved volumes.

## Error handling

The menu's rule holds: every module is loaded and called through pcall; a failure warns once in Output and never stops
the rest of the game (a broken tablet menu does not stop claiming; a broken BobAnimator leaves Bob still but injections
still work; a broken DeathScreen leaves Roblox's normal death). The server trusts nothing from clients: every
RequestInjection and prompt trigger is re-checked against the owner, the copy, Bob's state, the Harddrive and the limb.

## Testing

The same kind as the menu's: Luau test scripts in tests/, run in Studio playtests through the Studio connection, each
printing PASS or stopping with what went wrong. Scripts get Studio-only TestHooks where tests need their state.

| Test | Checks |
|---|---|
| `lab_config` (server) | LabConfig loads; timings positive; the limb helpers work on an R6 body. |
| `lab_claim` (server) | Claim seats a copy on the player's rig at SubjectSpot and gives one tablet; a second claim by another player is refused; respawn gives a fresh copy and tablet; release and leaving clean up. |
| `lab_inject` (server) | The phase sequence and its timings; Explosive into LeftArm removes the left arm from both bodies and takes 20 from both; Head kills both; each refusal reason; a release mid-sequence cancels it. |
| `tablet_menu` (client) | Opens on activate; CONFIRM inactive until both picks; lost limbs greyed and unpickable; read-only while Bob is busy; closes on Confirm. |
| `bob_animator` (client) | At the end of NeedleOut, the needle tip is inside the target limb's bounding box or within 0.75 studs of it; Bob ends at BobHome after Returning; follows a player in the zone and stays at least FOLLOW_DISTANCE - 1 from them; ignores a player outside it. |
| `googly_eyes` (Edit) | Random inputs never push a pupil outside its circle; with no target it settles at the bottom. |
| `death_screen` (client) | Black is fully opaque on the frame of death; DeathRing plays; SoundGroups at 0 then restored; black gone after respawn. |

Human checks: how Bob's motion and the eyes feel, sounds, the phone emulator, a controller.

## Not in this version

Collecting Harddrives and using them up, more Harddrive types, more rooms and multiplayer rules, the red warning lamp, the
lab log, regrouping Room 1's walls into a model. The broken loading screen in Studio (the deleted hazard stripe code) is a
separate fix, parked at the user's request.
