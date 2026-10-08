# Room 1 Injection Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Room 1: claim it, get a linked copy of your avatar in the patient chair and a tablet, and make Bob the Injector inject Harddrives (Explosive first) into the copy's limbs, with every effect mirrored onto your real character; Bob follows and watches players in the room with bouncy googly eyes; every death cuts to black with ear ringing.

**Architecture:**
- **Server (`LabServer`, `HardDriveEffects`):** owns the rules: claim and release, the copy, the tablet, validating each request, the injection's phases and timing, the effects (applied to the copy and the owner together), the doorway shutter. It publishes Bob's state as attributes.
- **Client (`LabClient` with `TabletMenu`, `BobAnimator`, `GooglyEyes`; `DeathScreen`):** draws the tablet menu, animates Bob locally from the published state (gantry, column, body, needle, swing, eyes, following, the copy's flinch), and shows the death screen.
- **Studio (`studio/build_lab.luau`):** builds Room 1's new pieces and rewires the user's hand-built Bob and tablet once.

**Tech Stack:** Roblox Studio, Luau, Roblox Studio MCP tools, git.

**Spec:** `docs/superpowers/specs/2026-10-06-room1-injection-lab-design.md`. Read it first; this plan pins names, positions and tests the spec leaves open.

## Global Constraints

### Studio and the place
- Call `list_roblox_studios` first; the id changes on every Studio restart. The place is "Untitled Experience" (placeId 95688118364991).
- **Never save or publish** the place. The controller asks the user to save after Tasks 2 and 6.
- If RenderStepped stops firing or the viewport is 1x1, the screen is locked: stop and report BLOCKED.
- `ReplicatedFirst.LoadingScreen` in Studio is known to differ from disk (the user deleted its hazard stripe function; the fix is parked). Do not touch or "fix" it; the menu opens without it.

### Scripts
- Disk is the source of truth, Rojo layout (`default.project.json`):
  - `src/ReplicatedStorage/<Name>.luau` → ModuleScript in ReplicatedStorage (mapping added in Task 1).
  - `src/ServerScriptService/<Name>.server.luau` → Script; `<Name>.luau` → ModuleScript.
  - `src/StarterPlayer/StarterPlayerScripts/LabClient/init.client.luau` → LocalScript `LabClient`, sibling `.luau` files → its child ModuleScripts. `DeathScreen.client.luau` → LocalScript.
- Push a script with an Edit find-or-create that sets `.Source` from a `[====[ ... ]====]` long string, then check `#Source` equals the file's length after normalising CRLF to LF (`core.autocrlf` is true).
- Before editing an existing script, `script_read` the Studio copy; if it differs from disk (after LF normalisation), stop and report.
- Studio-built things (Room 1's pieces, Bob's rewiring, the Tablet tool, the TabletMenu template) are made by `studio/build_lab.luau` and applied live by running it. The script must be safe to run again (it finds what it already built instead of duplicating).

### Tests
- `.luau` snippets in `tests/`, run with `execute_luau` in the datamodel the suffix names (`.edit`, `.server`, `.client`). Each uses `assert(cond, "message")` and ends with `return "PASS ..."`. Multi-case files have a `local CASE = "X"` selector at the top.
- A server or client lab test needs a spawned character: start a fresh playtest, run `tests/fire_play.client.luau` (presses Play), wait for the character, then run the test.
- Studio-only hooks are `BindableFunction`s named `TestHook` under their script, created only when `RunService:IsStudio()`. Never `_G`.
- After each task, rerun every earlier lab test plus `menu_client` and `scenes` (case A) in fresh playtests; all must still PASS.

### Fault isolation (the menu's rule)
- Every module load and call from `LabClient` is pcall'd; a failure warns once in Output and never stops the rest (no tablet menu ≠ no claiming; no BobAnimator ≠ no injections).
- The server trusts nothing from clients: every prompt trigger and `RequestInjection` is re-checked.

### Values (verbatim from the spec, plus positions pinned here)
- `RESPAWN_TIME = 5`, `LIMB_DAMAGE = 20`, `FUSE_SECONDS = 3`, `LOST_LIMB_SECONDS = 10`, `FOLLOW_DISTANCE = 8` (from Bob's eyes; at 6 his needle tip reaches the player's head).
- `Timings = { Move = 2, NeedleOut = 0.4, Hold = 1, NeedleIn = 0.4, Return = 1.5 }`.
- Sounds: `DeathRing = "rbxassetid://9069161602"`, `FuseBeep = "rbxassetid://110057943333877"`, `NeedleHiss = "rbxassetid://8375254457"`, `BobMotor = "rbxassetid://18627683806"`. All in `SoundService.SFX` except DeathRing (no group).
- The game is R6 only (user decision): every character and copy is R6; no R15 code paths. Copy rig: `Enum.HumanoidRigType.R6`. Sit animation: `rbxassetid://178130996`.
- Room 1 interior: x 32.3–59.2, z 16.8–54.6, floor top y 0.35, ceiling underside y 22.55. Observation side is x < 32.3.
- Chair: seat centre (51.5, –, 35), facing -X (toward the window). This leaves Bob's 12-stud reach room on the front and both sides.
- Gantry travel (carriage centre): x 35.5–56, z 19.2–52.2. BobHome marker at (56, 20.25, 48.5), LookVector -X.
- Bob as built: column top y 23.01, column bottom y 10.30, needle tip y 6.64 and 12.02 studs (horizontally) from the column axis, needle horizontal and radial. `MAX_EXTENSION = 6`, `NEEDLE_OUT = 1.5`.
- Bob's states: `"Standby"`, `"Moving"`, `"Injecting"`, `"Returning"`.
- Refusal strings (shown on the tablet): `"NOT YOUR ROOM"`, `"NO SUBJECT"`, `"BOB IS BUSY"`, `"UNKNOWN HARDDRIVE"`, `"UNKNOWN LIMB"`, `"LIMB ALREADY LOST"`. Claim refusals: `"ROOM 1 IS TAKEN"`, `"NO CHARACTER"`.

### Look
- Factory, whatever `MenuAssets.THEME` says: backdrop RGB(16,14,12), panel RGB(38,36,34), amber RGB(255,150,30), text white, muted text RGB(220,208,190), Oswald (bold for titles), uppercase labels. Dark steel parts: Metal or DiamondPlate, Color RGB(58,55,52).

### Commits
- Branch `feature/room1-lab`. End every commit message with a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The room is released, or the owner dies, while the fuse is burning.** Expect the fuse to stop on both bodies (glow removed, no blast, no damage) and no errors. Test: Task 4 case I-F.
2. **Confirm pressed twice in a row** (two requests before Bob moves). Expect the second refused with "BOB IS BUSY" and exactly one injection. Test: Task 4 case I-E.
3. **The owner leaves the game mid-injection.** Expect `Owner = 0`, the copy gone, Bob back on Standby after Return, the shutter open, no errors. Test: Task 4 case I-H.
4. **The right arm is blown off while the tablet is held.** Expect the tablet gone from the character and Backpack, the menu closed, and a tablet back after respawn. Tests: Task 4 case I-G, Task 6 case T-E.
5. **Death while the tablet menu is open.** Expect the black screen above the menu, and the menu closed after respawn. Test: Task 6 case T-F.

---

### Task 1: LabConfig and the limb table

**Files:**
- Create: `src/ReplicatedStorage/LabConfig.luau`
- Modify: `default.project.json` (add `"ReplicatedStorage": { "$className": "ReplicatedStorage", "$ignoreUnknownInstances": true, "$path": "src/ReplicatedStorage" }`), `docs/RECOVERY.md` (add the script)
- Test: `tests/lab_config.server.luau`

**Interfaces:**
- **Produces `LabConfig`** (ModuleScript `ReplicatedStorage.LabConfig`):
  - The values under Global Constraints: `RESPAWN_TIME`, `LIMB_DAMAGE`, `FUSE_SECONDS`, `LOST_LIMB_SECONDS`, `FOLLOW_DISTANCE`, `Timings`, `Sounds`, and `HardDrives = { { id = "Explosive", name = "EXPLOSIVE" } }`.
  - `LIMB_KEYS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }`.
  - `limbParts(body: Model, key: string): { BasePart }`: the limb's parts that are still in the body, per the spec's Limbs table (R6 only).
  - `limbJoint(body: Model, key: string): JointInstance?`: the joint that holds the limb on (nil for Torso, or when it is gone).
  - `isLost(body: Model, key: string): boolean`: true when the limb's joint is gone (Head and the four limbs) or when none of its parts remain in the body. Torso is never "lost" while the body is alive.
  - `limbCentre(body: Model, key: string): Vector3?`: the centre of the limb's parts' combined bounding box, nil if lost.
  - A header comment like MenuAssets', explaining each value for the user.

- [ ] **Step 1: Write the failing test `tests/lab_config.server.luau`.** In a running playtest's Server datamodel (no character needed), require `ReplicatedStorage.LabConfig` and:
  - assert every `Timings` value and `FUSE_SECONDS` > 0; `#HardDrives >= 1`; each Sounds value matches `^rbxassetid://%d+$`.
  - build an R6 model with `Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)`, parent it to workspace; for every key in `LIMB_KEYS`: `#limbParts >= 1`, `isLost == false`, `limbCentre ~= nil`; `limbJoint` non-nil for every key except Torso.
  - destroy the body's LeftArm joint: `isLost(body, "LeftArm") == true`, `limbCentre(body, "LeftArm") == nil` once its part is reparented out of the body (reparent it to workspace in the test); the other keys stay `false`.
  - destroy the model; `return "PASS lab_config"`.
- [ ] **Step 2: Run it.** Expected: FAIL (LabConfig missing).
- [ ] **Step 3: Implement LabConfig**, add the Rojo mapping and the RECOVERY line, push.
- [ ] **Step 4: Run it.** Expected: `PASS lab_config`.
- [ ] **Step 5: Commit** `feat(lab): LabConfig with the lab's settings and the limb table`.

---

### Task 2: Build Room 1's pieces and rewire Bob and the tablet

**Files:**
- Create: `studio/build_lab.luau` (run it in Edit to apply)
- Modify: `docs/RECOVERY.md` (how to rebuild; that Bob, the tablet and the walls exist only in the place file)
- Test: `tests/lab_build.edit.luau`

**Interfaces:**
- **Consumes:** Workspace's `BobTheInjector`, `Tablet`, `ExplosiveHardDrive` as they are now (see the spec's "Room 1 as it exists").
- **Produces** (everything Anchored unless stated; every Bob and gantry part CanCollide/CanTouch/CanQuery false):
  - `Workspace.Room1` (Model, `ModelStreamingMode = Persistent`), attribute `Owner = 0`.
  - `Room1.Zone`: Part, CFrame (45.75, 11.45, 35.7), Size (26.9, 22.2, 37.8), Transparency 1, CanCollide/CanTouch/CanQuery false.
  - `Room1.Chair` (Model): factory chair (seat, back on the +X side, legs), seat centre at x 51.5, z 35, facing -X; part `Seat` (the seat block) holds Attachment `SubjectSpot` (at the seat's top centre, its CFrame facing -X).
  - `Room1.ClaimButton` (Model): a panel on the outside face of the window wall next to the doorway, about (31.8, 3.5, 48.5), facing -X, with part `Button` holding `ProximityPrompt` named `ClaimPrompt` (`ObjectText` "Room 1", `ActionText` "Claim Room 1", `HoldDuration` 0, `MaxActivationDistance` 8, `RequiresLineOfSight` false), and a SurfaceGui `Sign` on the panel with TextLabel `Text` ("ROOM 1 / FREE"), Factory style.
  - `Room1.Shutter`: Part filling the doorway (measure it: the opening at x ≈ 32.3, z ≈ 40.7–45.0, y 0.35–≈6.4), Material Metal, Color RGB(58,55,52), open state: Transparency 1, CanCollide false. Attribute `ClosedCFrame` (CFrame) = its in-the-doorway CFrame.
  - `Room1.Gantry` (Model): `RailA` and `RailB` (along Z at x 33.8 and 57.7, y 22.05, size (1, 1, 37.8)), `Crossbeam` (spans x 33.8–57.7, y 21.15, 0.8 tall, 1.2 deep), `Carriage` (3 × 1 × 3, y 20.25), `Sleeve` (6.4 × 6 × 6.4, y 16.75; wide enough to hide the column's fins, which reach 2.95 studs from its axis). At BobHome's X/Z.
  - `Room1.BobHome`: invisible Part (1,1,1) at (56, 20.25, 48.5), LookVector -X.
  - `Room1.BobTheInjector` (Model), moved so the column axis is at BobHome's X/Z (Y unchanged), turned so the needle points along BobHome's LookVector, attributes `State = "Standby"`, `Target = ""`, `HardDrive = ""`, `PhaseStart = 0`. Children:
    - `Column` (Model): every direct CorrodedMetal part; the largest renamed `Core`, holding Attachment `ColumnPivot` at the column axis, at the column's lowest Y, with an upright orientation (UpVector +Y, LookVector = the needle's horizontal direction).
    - `Body` (Model): the Foil hose segments, the Metal head and nozzle, `DisplayPanel`'s parts, and the two eye whites renamed `EyeWhiteL` / `EyeWhiteR` (L/R from Bob's own view looking along the needle) each holding Attachment `EyeCenter`. DisplayPanel's black Metal part renamed `Screen`, holding SurfaceGui `Display` on its large face that points away from the column, with TextLabels `Headline` ("STANDBY") and `Detail` (""), amber Oswald on black.
    - `Needle`: the MeshPart, holding Attachments `NeedleBase` and `NeedleTip` at its two ends (tip = the end farther from the column axis).
    - `Pupils` (Model): the two black discs renamed `PupilL` / `PupilR` (paired to the nearest white).
  - `ServerStorage.Tablet` (Tool): `Handle` = the tablet's PrimaryPart; the other parts welded (WeldConstraint) to it; all unanchored, CanCollide false, Massless; a Grip that holds it in front of the chest, screen up toward the face.
  - `ReplicatedStorage.LabAssets.HardDrives.Explosive`: the ExplosiveHardDrive part (anchored), moved and renamed.
  - The old `Workspace.Tablet` and `Workspace.ExplosiveHardDrive` are gone (moved); `Workspace.BobTheInjector` is now under Room1.

- [ ] **Step 1: Write the failing test `tests/lab_build.edit.luau`.** Assert every name and class above exists; `Room1.ModelStreamingMode == Persistent`; every BasePart under BobTheInjector and Gantry is Anchored and CanCollide false; `#Column` parts == 16; the needle tip's horizontal distance from `ColumnPivot` is within 0.1 of 12.02; `SubjectSpot.WorldCFrame.LookVector` is within 0.01 of (-1, 0, 0); Zone's size/CFrame as above; the Tablet tool has a Handle and every other part is welded to it; a raycast from (30, 3, Shutter's z) to (35, 3, same z) with Shutter set to its ClosedCFrame and CanCollide true hits Shutter (restore it to open after); running `studio/build_lab.luau` a second time leaves the descendant count of Room1 unchanged.
- [ ] **Step 2: Run it.** Expected: FAIL (Room1 missing).
- [ ] **Step 3: Write `studio/build_lab.luau`** and run it in Edit. Bob's parts are told apart only by class, material and colour as listed above (never by absolute position). The whole Bob is moved with one pivot change before grouping.
- [ ] **Step 4: Run the test.** Expected: PASS. Take a `screen_capture` of Room 1 through the window (move the Edit camera; leave it there) to check the chair, the gantry and Bob look right.
- [ ] **Step 5: Commit** `feat(lab): build Room 1's chair, gantry, claim button, shutter, and rewire Bob and the tablet`. Controller: ask the user to save the place (Ctrl+S).

---

### Task 3: Claiming, the copy and the link

**Files:**
- Create: `src/ServerScriptService/LabServer.server.luau`
- Create: `src/StarterPlayer/StarterPlayerScripts/LabClient/init.client.luau` (this task: the claim prompt's per-player text only)
- Modify: `docs/RECOVERY.md`
- Test: `tests/lab_claim.server.luau`, `tests/lab_claim.client.luau`

**Interfaces:**
- **Consumes:** LabConfig (Task 1); Room1, ClaimPrompt, Sign, SubjectSpot, ServerStorage.Tablet (Task 2).
- **Produces:**
  - `Room1.Owner` (UserId or 0), the copy as `Room1.Subject` (Model; absent when free), `Sign.Text` "ROOM 1 / FREE" or "ROOM 1 / <DisplayName>".
  - `Players.RespawnTime = LabConfig.RESPAWN_TIME` at startup.
  - Internal (Task 4 uses them in the same script): `claim(player): (boolean, string?)` (toggles: the owner calling it releases and returns `true`), `release(player): ()`, `ownerPlayer(): Player?`, `copy(): Model?`, and a local callback slot `onLinkBroken: (() -> ())?` that Task 4 fills; Task 3 calls it on release, the owner leaving, the owner dying and the copy being replaced.
  - `TestHook` (Studio only): `Invoke("claim", player) -> (ok, reason)`, `Invoke("release", player)`, `Invoke("state") -> { owner: number, hasCopy: boolean }`.
- **Behaviour:** as the spec's "Claiming and the copy". The copy: `CreateHumanoidModelFromDescription(humanoid:GetAppliedDescription(), Enum.HumanoidRigType.R6)`, named `Subject`, `DisplayDistanceType = None`, HumanoidRootPart anchored with CFrame = SubjectSpot.WorldCFrame offset upward so the seated copy sits on the seat, the sit animation playing (looped) through its Animator, Health/MaxHealth copied. Tablet: one clone in the Backpack (never two). Death link both ways (`Health = 0`). Respawn while owning: fresh copy and tablet on CharacterAdded. Release and PlayerRemoving: destroy the copy and the owner's tablets (Backpack and character), `Owner = 0`.
- **LabClient (client):** on start and whenever `Room1.Owner` changes, set `ClaimPrompt.Enabled` and `ActionText` locally: free → enabled "Claim Room 1"; owner is you → enabled "Release Room 1"; otherwise disabled.

- [ ] **Step 1: Write the failing tests.**
  - `tests/lab_claim.server.luau` (player spawned): 
    - **C-A:** `claim` → true; `Owner == player.UserId`; `Room1.Subject` exists with `Humanoid.RigType == Enum.HumanoidRigType.R6`; its HumanoidRootPart is Anchored and within 3 studs of SubjectSpot; after 1 s the lowest point of its leg parts is between seat top − 0.2 and seat top + 0.6 and above the floor; exactly one Tablet in Backpack + character; `Sign.Text == "ROOM 1 / " .. player.DisplayName`.
    - **C-B (toggle):** with the room claimed, `TestHook:Invoke("claim", player)` again returns `true` and the room is free: `Owner == 0`, no Subject, no Tablet in Backpack or character, `Sign.Text == "ROOM 1 / FREE"`. ("ROOM 1 IS TAKEN" needs a second player; it is a one-line check, reviewed by reading.)
    - **C-C:** claim, then `player.Character.Humanoid.Health = 0`; within 1 s the copy's Humanoid.Health == 0; after `RESPAWN_TIME + 3` s a new character exists, a new Subject (a different instance) is seated, and exactly one Tablet exists.
    - **C-D:** claim, then the copy's `Humanoid.Health = 0`; within 1 s the player's Humanoid.Health == 0. Wait for respawn (as C-C), then `release`: room free.
  - `tests/lab_claim.client.luau`: with the room free, `ClaimPrompt.Enabled == true` and `ActionText == "Claim Room 1"`; after a server-side claim (run C-A first), `ActionText == "Release Room 1"`.
- [ ] **Step 2: Run them.** Expected: FAIL (no LabServer).
- [ ] **Step 3: Implement** LabServer (claiming part) and LabClient's prompt text; push both.
- [ ] **Step 4: Run them** in fresh playtests (C-A, C-B, client, C-C, C-D). Expected: PASS each. Plus the menu regression tests.
- [ ] **Step 5: Commit** `feat(lab): claim Room 1, seat a linked copy and hand out the tablet`.

---

### Task 4: Injections, the shutter and Explosive

**Files:**
- Modify: `src/ServerScriptService/LabServer.server.luau`
- Create: `src/ServerScriptService/HardDriveEffects.luau`
- Modify: `docs/RECOVERY.md`
- Test: `tests/lab_inject.server.luau`

**Interfaces:**
- **Consumes:** Task 3's internals; LabConfig `limbParts`, `limbJoint`, `isLost`, `limbCentre`.
- **Produces:**
  - `ReplicatedStorage.LabRemotes` (Folder) with `RequestInjection` (RemoteFunction): `InvokeServer(hardDriveId: string, limbKey: string) -> (boolean, string?)`. Returns at once; refusals use the strings under Global Constraints, checked in this order: not owner, no copy, busy (State ≠ "Standby" or a sequence starting), unknown Harddrive, unknown limb, limb lost (on the copy).
  - Bob's attributes (`State`, `Target`, `HardDrive`, `PhaseStart` = `workspace:GetServerTimeNow()`) through the phases in the spec's table: Moving (Move) → Injecting (NeedleOut + Hold + NeedleIn) → effect thread started → Returning (Return) → Standby (`Target` and `HardDrive` back to "").
  - Shutter: closes (0.4 s tween from 6.5 studs above `ClosedCFrame` to it, Transparency 0, CanCollide true) when Moving starts; opens (tween back up, then Transparency 1, CanCollide false) when Standby is set.
  - Cancelling (from `onLinkBroken`): the running sequence stops at its next wait; State goes to Returning for Return seconds, then Standby.
  - `HardDriveEffects.Explosive(bodies: { Model }, limbKey: string, stillLinked: () -> boolean): ()`: yields about FUSE_SECONDS. Per body still holding the limb: a red `Highlight` named `FuseGlow` on each limb part, blinking faster over the fuse, and FuseBeep (a Sound in the limb's first part, SFX group) replayed at a rising rate. If `stillLinked()` turns false, remove every glow and return with no blast. At the end, per body: `Explosion` at `limbCentre` (BlastPressure 0, BlastRadius 4, DestroyJointRadiusPercent 0); arm/leg: destroy `limbJoint`, set the parts unanchored, CanCollide true, parent them to Workspace, remove after LOST_LIMB_SECONDS (`Debris`), `Health -= LIMB_DAMAGE`; Head/Torso: `Health = 0`.
  - LabServer passes `{ copy, ownerCharacter }` and a `stillLinked` that is true while the same copy and character are both still in place.
  - Right arm: whenever the owner's RightArm joint is destroyed (any cause), destroy their Tablet tools (character and Backpack).
  - `TestHook` adds `Invoke("inject", player, id, limb) -> (ok, reason)` (the same path as the remote) and `Invoke("state")` gains `bobState`.

- [ ] **Step 1: Write the failing test `tests/lab_inject.server.luau`** (player spawned and claimed; each case starts from Standby with a fresh, fully-limbed copy; a case that kills waits for respawn and reclaims):
  - **I-A (phases):** inject Explosive/LeftArm → `(true)`; sample `State` and `PhaseStart`: Moving at once, Injecting at 2 ± 0.3 s, Returning at 3.8 ± 0.3 s, Standby at 5.3 ± 0.3 s; Shutter CanCollide true during Moving, false after Standby.
  - **I-B (limb):** after I-A's injection plus FUSE_SECONDS + 0.5 s: `isLost(copy, "LeftArm")` and `isLost(character, "LeftArm")`; both Healths are 80; a `FuseGlow` existed on both during the fuse (sample at 1 s into it); no `FuseGlow` left after.
  - **I-C (lost limb refused):** inject into LeftArm again → `(false, "LIMB ALREADY LOST")`.
  - **I-D (head):** inject Explosive/Head; after the sequence and fuse, both Humanoids are dead.
  - **I-E (double request):** two `inject` calls back to back → first `(true)`, second `(false, "BOB IS BUSY")`.
  - **I-F (fuse cut):** inject LeftLeg; 1 s after Returning starts (the fuse began when Injecting ended) call `release`; after FUSE_SECONDS + 1 s: no `FuseGlow` anywhere, the player's LeftLeg is not lost and Health is unchanged, no Explosion was created (count `workspace.DescendantAdded` Explosions).
  - **I-G (right arm):** reclaim, equip the tablet (`humanoid:EquipTool`), inject RightArm; after the blast: no Tablet in the character or Backpack.
  - **I-H (owner leaves):** covered here by calling the same cleanup PlayerRemoving uses through `release` mid-Moving: `Owner == 0`, Subject gone, State Standby within Return + 0.5 s, Shutter open. (Leaving can't be scripted in a solo playtest.)
  - **I-I (refusals):** an unknown id → "UNKNOWN HARDDRIVE"; limb "Tail" → "UNKNOWN LIMB"; with the room released → "NOT YOUR ROOM".
- [ ] **Step 2: Run it.** Expected: FAIL (no "inject" hook action).
- [ ] **Step 3: Implement** RequestInjection, the sequence, the shutter, cancelling, the right-arm rule and HardDriveEffects; push.
- [ ] **Step 4: Run each case** (fresh playtests where a case needs one). Expected: PASS. Rerun Task 3's tests.
- [ ] **Step 5: Commit** `feat(lab): Bob's injection sequence, the doorway shutter and the Explosive harddrive`.

---

### Task 5: The death screen

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/DeathScreen.client.luau`
- Modify: `docs/RECOVERY.md`
- Test: `tests/death_screen.client.luau`

**Interfaces:**
- **Consumes:** LabConfig `Sounds.DeathRing`, `RESPAWN_TIME` (if LabConfig is missing: no ring, 5 s).
- **Produces:** `PlayerGui.DeathScreen` (ScreenGui, IgnoreGuiInset true, ScreenInsets None, DisplayOrder 100, ResetOnSpawn false) with Frame `Black` (full screen, black, Transparency 1 when idle); `SoundService.DeathRing` (Sound, no SoundGroup).
- **Behaviour:** the spec's "Death screen". In the Humanoid.Died handler (same frame): Black transparency 0; every SoundGroup under SoundService: save its Volume (attribute `DeathSavedVolume`), set it to 0; DeathRing volume 1, play, tween volume to 0 over RESPAWN_TIME. Every character's `Died` Sound (from Roblox's character sounds) gets Volume 0 as it appears. On CharacterAdded after a death: tween Black to transparency 1 over 1.5 s; restore each group's saved Volume.

- [ ] **Step 1: Write the failing test `tests/death_screen.client.luau`**, three calls:
  - **D-1 (client, arm):** connect `Humanoid.Died` → on the next RenderStepped record `Black.BackgroundTransparency`, `DeathRing.IsPlaying`, and each SoundGroup's Volume as PlayerGui attributes; return.
  - **D-2 (server):** `player.Character.Humanoid.Health = 0`.
  - **D-3 (client, check):** the recorded transparency is 0, ring playing, all groups 0; then wait for the new character + 2 s: Black transparency 1, every group's Volume equals its `DeathSavedVolume`.
- [ ] **Step 2: Run it.** Expected: FAIL (no DeathScreen).
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run it.** Expected: PASS. Run Task 4 case I-D again and take a `screen_capture` right after the blast (expect black).
- [ ] **Step 5: Commit** `feat(game): death cuts to black with ear ringing`.

---

### Task 6: The tablet menu

**Files:**
- Modify: `studio/build_lab.luau` (adds the template), then run it
- Create: `src/StarterPlayer/StarterPlayerScripts/LabClient/TabletMenu.luau`
- Modify: `src/StarterPlayer/StarterPlayerScripts/LabClient/init.client.luau` (wiring to the Tablet tool)
- Test: `tests/tablet_menu.client.luau`

**Interfaces:**
- **Consumes:** LabConfig; `LabRemotes.RequestInjection` (Task 4); `ReplicatedStorage.LabAssets.HardDrives.<id>` (Task 2); `SoundService.MenuSfxHover` / `MenuSfxConfirm` by name (may be missing: then silent).
- **Produces the template** `ReplicatedStorage.TabletMenu` (ScreenGui, ResetOnSpawn false, Enabled false), Factory style, matching the brainstorm mockup: `Root` → `Header` (`Title` "BOB-LINK / ROOM 1", `Status`, `Close`), `Injections` (`List`: ScrollingFrame with `EntryTemplate`, a hidden TextButton holding ViewportFrame `Icon` and TextLabel `Label`), `Target` (TextButtons `Head`, `Torso`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`, laid out front-on, so `RightArm` and `RightLeg` are on the screen's left; labels "HEAD", "TORSO", "L ARM", "R ARM", "L LEG", "R LEG"), `Confirm`. Scale-only, inside the safe area, every button at least 40 px tall at a 667 × 375 viewport, UISizeConstraint so it never grows past 760 px wide.
- **Produces `TabletMenu`:**
  - `init(opts: { template: ScreenGui, playerGui: PlayerGui, config: LabConfig, room: Model, remote: RemoteFunction }): ()` clones the template into PlayerGui and builds one entry per `HardDrives` item.
  - `open(): ()`, `close(): ()`, `isOpen(): boolean`.
  - `pickHardDrive(id: string): ()`, `pickLimb(key: string): ()` (ignored for a lost limb or while read-only).
  - `confirm(): (boolean, string?)`: does nothing and returns `(false, "INCOMPLETE")` unless both are picked and not read-only; otherwise invokes the remote; on `true` closes the menu; on `false` shows the reason in `Status` for 3 s.
  - `view(): { open: boolean, hardDrive: string?, limb: string?, confirmActive: boolean, readOnly: boolean, lost: { [string]: boolean }, status: string }`.
  - Read-only while Bob's `State ~= "Standby"`; lost limbs from `LabConfig.isLost(room.Subject, key)`, refreshed on open and when the Subject or its joints change. `Status` shows Bob's state ("STANDBY", "MOVING", "INJECTING", "RETURNING") unless a refusal is showing. `Confirm` text: "CONFIRM: <NAME> INTO <LIMB WORDS>" (e.g. "CONFIRM: EXPLOSIVE INTO LEFT ARM"), or "PICK A HARDDRIVE AND A LIMB".
  - Controller: B (ButtonB) closes; buttons are selectable.
- **LabClient wiring:** when a Tool named `Tablet` is in the character: its `Activated` opens the menu; `Unequipped` or the tool leaving the character closes it; the menu also closes when the character dies.

- [ ] **Step 1: Write the failing test `tests/tablet_menu.client.luau`** (player spawned and claimed, Bob on Standby):
  - **T-A:** require a test copy of TabletMenu and `init` it with the real template; `open()`; `view().confirmActive == false`; `pickHardDrive("Explosive")` → still false; `pickLimb("LeftArm")` → true and `Confirm.Text == "CONFIRM: EXPLOSIVE INTO LEFT ARM"`.
  - **T-B:** `confirm()` → `true`; `isOpen() == false`; reopen: `readOnly == true` and `Status.Text == "MOVING"` (or "INJECTING"); wait for Standby + the fuse.
  - **T-C:** `view().lost.LeftArm == true`; `pickLimb("LeftArm")` leaves `limb` nil.
  - **T-D:** a refusal: release the room on the server, then `confirm()` with picks → `(false, "NOT YOUR ROOM")` and `Status.Text == "NOT YOUR ROOM"`; reclaim.
  - **T-E:** the real LabClient: equip the Tablet, activate it (`tool:Activate()`), the real menu opens; inject RightArm through the server hook; after the blast the real menu is closed.
  - **T-F:** with the real menu open, kill the character from the server: DeathScreen's `Black` has a higher DisplayOrder than the menu's ScreenGui; after respawn the menu is closed.
  - Layout check: every TextButton in `Root` has `AbsoluteSize.Y >= 40` with the real viewport (report the viewport size); take a `screen_capture` of the open menu.
- [ ] **Step 2: Run it.** Expected: FAIL (no TabletMenu).
- [ ] **Step 3: Add the template to `build_lab.luau` and run it; implement TabletMenu and the wiring; push.**
- [ ] **Step 4: Run it.** Expected: PASS each case. Report the screenshot to the controller.
- [ ] **Step 5: Commit** `feat(lab): the tablet menu for picking a harddrive and a limb`. Controller: ask the user to save the place.

---

### Task 7: Googly eye physics

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/LabClient/GooglyEyes.luau`
- Test: `tests/googly_eyes.edit.luau`

**Interfaces:**
- **Produces `GooglyEyes`** (pure maths, no Instances):
  - `new(radius: number): Eye` where `Eye = { offset: Vector2, velocity: Vector2, radius: number }` (offset starts at the bottom: `(0, -radius)`).
  - `step(eye: Eye, gravity: Vector2, pull: Vector2, accel: Vector2, dt: number): ()`: all vectors already in the eye's plane (x = right, y = up). Acceleration = `gravity + pull * PULL - accel - velocity * DAMPING`; integrate in sub-steps of at most 1/240 s (clamp `dt` to 1/20); if `|offset| > radius`, put it back on the rim and reflect the outward part of the velocity, scaled by `RESTITUTION`.
  - `spin(eye: Eye, speed: number): ()`: add `speed` studs/s along the rim's tangent at the current offset.
  - Tunables at the top: `PULL`, `DAMPING`, `RESTITUTION` (start 60, 4, 0.55).

- [ ] **Step 1: Write the failing test `tests/googly_eyes.edit.luau`** (require the module from its script in Studio):
  - **G-A:** 2000 steps of random `accel` (magnitude up to 400), random `dt` (0 to 0.1), gravity (0, -196.2): `offset.Magnitude <= radius + 1e-6` after every step.
  - **G-B:** from a random offset, 3 s of 1/60 steps with gravity (0, -196.2), no pull, no accel: offset within 0.01 of (0, -radius).
  - **G-C:** with pull (1, 0) and no gravity, 3 s: `offset.X > 0.9 * radius`.
  - **G-D:** `spin(eye, 20)` then one step: the speed is greater than 15.
- [ ] **Step 2: Run it.** Expected: FAIL (module missing).
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(lab): googly eye physics`.

---

### Task 8: BobAnimator, part 1: poses, phases, screen and sounds

**Files:**
- Create: `src/StarterPlayer/StarterPlayerScripts/LabClient/BobAnimator.luau`
- Modify: `LabClient/init.client.luau` (start it)
- Test: `tests/bob_animator.client.luau` (cases B-A to B-C)

**Interfaces:**
- **Consumes:** Task 2's rig names and attachments; Task 4's attributes; LabConfig.
- **Produces `BobAnimator`:**
  - `readRig(room: Model): Rig`, captured from the parts as built (the home pose). `Rig = { homePivot: CFrame (ColumnPivot's world CFrame at home), home: Pose, offsets: { [BasePart]: CFrame } (each Column, Body, Needle, Pupils and Gantry part relative to homePivot), tipLocal: Vector3 (NeedleTip in homePivot's frame), needleDirLocal: Vector3 (unit, NeedleBase → NeedleTip, in that frame), travel: { minX, maxX, minZ, maxZ }, MAX_EXTENSION: 6, NEEDLE_OUT: 1.5 }`. ColumnPivot's LookVector is the needle's horizontal direction (Task 2), so `home.yaw` is the pivot's heading.
  - `Pose = { x: number, z: number, extension: number, yaw: number }`: carriage centre X/Z, column extension (0 = as built, positive = down), yaw = world heading of `needleDirLocal` (radians about +Y, 0 = facing -Z, same convention as `CFrame.Angles(0, yaw, 0)`).
  - `applyPose(rig: Rig, pose: Pose, needle: number, swing: Vector2): ()`: places the Crossbeam (z), Carriage and Sleeve (x, z), the Column (x, z, down by extension), the Body (about ColumnPivot: yaw, then the swing tilt, pitch = swing.X and roll = swing.Y in radians), and the Needle pushed `needle` studs along its axis. `swing` is (0, 0) in this task.
  - `injectionPose(rig: Rig, copy: Model, limbKey: string): Pose?`: nil if the limb is lost. Algorithm:
    ```lua
    local f = copy.HumanoidRootPart.CFrame -- the copy faces f.LookVector
    local d = (limbKey == "LeftArm" and f.RightVector) or (limbKey == "RightArm" and -f.RightVector) or -f.LookVector
    d = Vector3.new(d.X, 0, d.Z).Unit -- the direction the needle points
    local restTip = LabConfig.limbCentre(copy, limbKey) - d * rig.NEEDLE_OUT -- extending NEEDLE_OUT lands the tip on the limb's centre
    local yaw = math.atan2(-d.X, -d.Z) -- the pivot (and so the needle) faces along d
    local tipOffset = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(rig.tipLocal)
    local extension = (rig.homePivot.Y + rig.tipLocal.Y) - restTip.Y
    return { x = restTip.X - tipOffset.X, z = restTip.Z - tipOffset.Z, extension = math.clamp(extension, 0, rig.MAX_EXTENSION), yaw = yaw }
    ```
    The carriage centre is the column axis (Task 2 lines them up), so `x`/`z` place both.
  - `start(room: Model, config: LabConfig): ()` (idempotent) and `stop(): ()`. Each RenderStepped: read `State`, `Target`, `PhaseStart`; ease (smoothstep) from the pose Bob was in when the phase began to the phase's end pose over the phase's time, measured with `workspace:GetServerTimeNow() - PhaseStart`:
    - Moving → `injectionPose`, needle 0.
    - Injecting → same pose; needle 0 → NEEDLE_OUT over NeedleOut, held for Hold, back to 0 over NeedleIn. NeedleHiss (a Sound in Needle, SFX group) plays at the start of Hold.
    - Returning → the home pose.
    - Standby → hold (Task 9 adds following here).
  - Screen: `Headline` / `Detail`: Standby "STANDBY" / "" (Headline transparency pulsing slowly); Moving "TARGET: <LIMB WORDS>" / HardDrive name; Injecting "INJECTING" / limb words; Returning "RETURNING" / "".
  - BobMotor: a looped Sound in Carriage (SFX group), volume = `math.clamp(speed / 6, 0, 1) * 0.6`, where speed is the carriage's studs/s.

- [ ] **Step 1: Write the failing test `tests/bob_animator.client.luau`** (player spawned and claimed):
  - **B-A (reach):** `readRig`, then for each of the six limbs `injectionPose(rig, room.Subject, key)` is non-nil, inside the travel limits, and has `0 <= extension <= 6`.
  - **B-B (needle in the limb):** start an injection of Explosive/LeftLeg through the server hook (`TestHook:Invoke("inject", ...)` from a Server call, then this Client call): wait until `GetServerTimeNow() >= PhaseStart(Injecting) + NeedleOut + 0.05`; the NeedleTip's WorldPosition is inside the LeftLeg's bounding box or within 0.75 studs of it; `Screen.Display.Headline.Text == "INJECTING"`.
  - **B-C (home):** after Standby + 0.2 s: ColumnPivot's world X/Z is within 0.2 of BobHome's and `Headline.Text == "STANDBY"`.
- [ ] **Step 2: Run it.** Expected: FAIL (no BobAnimator).
- [ ] **Step 3: Implement, wire into LabClient (pcall'd), push.**
- [ ] **Step 4: Run it.** Expected: PASS. If B-A fails because a pose is out of reach, move the Chair in `build_lab.luau` (and the Global Constraints value) rather than widening the travel limits, then rerun Task 2's and Task 3's tests. Take two `screen_capture`s through the window: one mid-Moving, one at Hold.
- [ ] **Step 5: Commit** `feat(lab): Bob travels the gantry, aims and injects`.

---

### Task 9: BobAnimator, part 2: following, swing, eyes and the copy's flinch

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/LabClient/BobAnimator.luau`
- Test: `tests/bob_animator.client.luau` (cases B-D to B-G)

**Interfaces:**
- **Consumes:** GooglyEyes (Task 7); Room1.Zone.
- **Produces, in BobAnimator:**
  - **Following (Standby only):** the closest player HumanoidRootPart inside Zone (`Zone.CFrame:PointToObjectSpace` within half the size on every axis; the copy is not a player) is the watched player. Target: the spot where Bob's eyes (the midpoint of the two EyeCenters, horizontally) are FOLLOW_DISTANCE from the player, on Bob's current side, with Bob yawed toward the player — i.e. carriage = player X/Z − dir × (eyeReach + FOLLOW_DISTANCE), dir = (player − carriage).Unit, eyeReach = the eyes' horizontal distance from the column axis — clamped to the travel limits; the carriage moves toward it at most 4 studs/s with easing; yaw turns toward the player at most 90°/s; extension eases so the needle tip sits at the player's head height (clamped). No watched player → ease back to the home pose.
  - **Swing:** a damped spring on `swing: Vector2` driven by the carriage's acceleration (in Bob's frame), clamped to 12° each way, passed to `applyPose`.
  - **Eyes:** one `GooglyEyes.new(radius)` per pupil, radius = (white diameter − pupil diameter) / 2 from the parts' sizes. Each frame: gravity, Bob's eye acceleration and the pull toward the watched player's head (zero when none, or when not on Standby) are projected into the eye plane (`EyeCenter`'s RightVector and UpVector); the pupil goes at `EyeCenter.WorldCFrame` + offset in that plane, keeping its built distance along the normal. An Explosion appearing inside Zone calls `spin(eye, 25)` on both.
  - **Flinch:** while State is Moving or Injecting, the copy's neck joint (`LabConfig.limbJoint(copy, "Head")`) C0 is rotated so the head turns toward NeedleTip, clamped to 70° yaw and 35° pitch, smoothed; during Hold the target limb's joint C0 gets a random few-degree jitter; on Standby both ease back to their built C0 over 0.5 s. Client-side only; the original C0s are saved when the copy appears.

- [ ] **Step 1: Write the failing test cases** in `tests/bob_animator.client.luau`:
  - **B-D (follow):** move the local character into the room at (40, 3.5, 25) (set the HumanoidRootPart CFrame); within 8 s the horizontal distance from Bob's eyes (midpoint of the EyeCenters) to the player is between FOLLOW_DISTANCE − 1 and FOLLOW_DISTANCE + 1.5, and it never came closer than FOLLOW_DISTANCE − 1 (sample every frame).
  - **B-E (outside):** move the character outside at (25, 3.5, 30); within 6 s ColumnPivot X/Z is within 0.5 of BobHome's.
  - **B-F (eyes):** every frame for 5 s across B-D and B-E, each pupil's distance from its EyeCenter (in the eye plane) is at most the radius + 0.01.
  - **B-G (flinch):** during an injection of Explosive/LeftArm, at the end of Moving the copy's Neck C0 differs from its built C0 by more than 5°; 1 s after Standby it is within 1°.
- [ ] **Step 2: Run them.** Expected: FAIL (B-D: Bob doesn't move on Standby).
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run every bob_animator case** (B-A to B-G), then every lab test and the menu regression tests, each in fresh playtests as needed. Expected: PASS. Take a `screen_capture` of Bob watching the player.
- [ ] **Step 5: Commit** `feat(lab): Bob follows and watches with googly eyes; the copy flinches`.
