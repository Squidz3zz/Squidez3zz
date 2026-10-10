# Gore Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Injections hit only their limb.
- A torn head or an opened torso kills instantly.
- Torn limbs keep bloodied cloth scraps.
- Dangling limbs collide with the world.
- No-bone legs count as useless.
- External hits land on the limb actually hit (`Gore.hit`, then a touch guess, then the Torso).
- Roblox Explosions go through gore, with a ragdoll push.
- Every external hit draws blood.

**Architecture:** This builds on the gore package from `2026-10-08-gore-system.md`.
- Server-side gameplay changes live in `Gore/Integrity.luau` (damage routing, the hit watcher) and `Gore/init.luau` (new API, listeners), plus `Ragdoll`, `Flesh` and `ExplosionReplacer`.
- Client cosmetics live in `GoreClient`.
- Hits reach clients as a `GoreHit` attribute; there is no new remote for blood. The only new remote is the reset request.

**Tech Stack:** Roblox Studio, Luau, Roblox Studio MCP tools, git.

**Spec:** `docs/superpowers/specs/2026-10-10-gore-followups-design.md` (sections 1-8). Read it first. It amends `docs/superpowers/specs/2026-10-08-gore-system-design.md`, which still holds otherwise.

## Global Constraints

Everything in the Global Constraints of `docs/superpowers/plans/2026-10-08-gore-system.md` still applies: Studio and the place, scripts, tests, the TestHook, fault isolation, commits and never saving. In addition:

**Playtest limits.** Studio has crashed from graphics memory before.
- Run ONE playtest at a time.
- Take at most 2 screen_captures per task.
- Delete test folders.
- Leave no GoreConfig overrides behind.

**Captures.** The menu hides the scene, so for any capture inside a playtest, on the Client only:
- hide the menu UI;
- turn off its Blur and ColorCorrection;
- use a Scriptable camera, re-asserted right before the capture.

**Known console noise to ignore:**
- "trying to set locked parent!"
- "Missing Head"
- a Classic Radio error
- WelderPart asset-require messages
- qPerfectionWeld GetConnectedParts lines

Don't touch WelderPart or NukeRocketLauncher; the user is checking them.

**New GoreConfig values:**
- `HIT_SCALE = 0.5`
- `BLAST_PUSH = 60`
- `TOUCH_WINDOW = 0.2`

`BIG_HIT` is removed.

**Explosion power:** `EXPLOSIVE_POWER * math.clamp(BlastPressure / 500000, 0.3, 2)`.

**`GoreHit` attribute:** `"<Limb>|<damage>|<n>"`, where `n` counts up per body.

**Damage kinds:**
- Internal: Bob's injections, through `Gore.blastLimb`.
- External: everything else.

## Review Focus
1. **Two arm injections in a row** leave the body alive (bleeding aside): no torso or head change. Test: Task 1, A-C.
2. **A hat or other accessory gets shot.** `Gore.hit(handle, d)` lands on the limb the accessory is welded to. Test: Task 2, H-B.
3. **Standing on the floor while shot by a hitscan tool.** The floor touching the legs must not count as a touch, so the hit goes to the Torso. Test: Task 2, H-D.
4. **A free-model rocket launcher whose Explosion keeps DestroyJointRadiusPercent 1.** Nobody's limbs fly off plain. Bodies inside the joint radius die and ragdoll. Test: Task 3, E-A.
5. **Gore level 0.** Hits still take health and give a plain spurt, with no flesh or scraps; explosions still don't snap joints. Tests: Task 2, H-G; Task 3, E-E.

---

### Task 1: Aimed injections and instant deaths (spec sections 1-2)

**Files:**
- Modify: `src/ServerScriptService/Gore/init.luau`, `src/ServerScriptService/HardDriveEffects.luau`, `docs/RECOVERY.md`
- Test: `tests/gore_aim.server.luau` (new). Update `tests/lab_gore.server.luau` and `tests/lab_inject.server.luau` wherever they assume torso or head damage from an arm injection.

**Interfaces:**
- Produces: `Gore.blastLimb(body: Model, key: string, power: number)`, which calls `Integrity.damageLimb(body, key, power, "explosion")`. The link copies the result to the partner. It does not set `GoreHit`.
- Produces: an `onStateChanged` listener registered after Flesh's. At GORE_LEVEL ≥ 1 it calls `Gore.hurt(body, math.huge)` when Head becomes Torn/Broken/Destroyed, or when the torso becomes open.

- [ ] **Step 1: Write `tests/gore_aim.server.luau`.** Each case is driven through the TestHook on two linked test bodies.
  - **A-A:** `blastLimb(copy, "LeftArm", 150)`. Afterwards, Torso, Head, RightArm, LeftLeg and RightLeg are each `"Intact"` with `GoreHP` 100 on both bodies, and LeftArm is Broken or Severed on both.
  - **A-B:** `explode(at LeftArm, 150, 6)` still tears the Torso, proving the radius blast is unchanged for external use.
  - **A-C:** two arm blasts (LeftArm, then RightArm) leave both humanoids with health > 0.
  - **A-D:** `damageLimb(body, "Head", 45, "hit")` (Torn) makes health 0 within 0.2 s, and the body becomes a corpse.
  - **A-E:** with `TORSO_OPEN_CHANCE` overridden to 1, `blastLimb(body, "Torso", 50)` (Torn and open) gives health 0.
  - **A-F:** with the chance at 0, the same blast leaves Torso `"Torn"`, `GoreTorsoOpen` false, and health > 0.
  - **A-G:** at GORE_LEVEL 0, a Torn head does not kill through this rule.
- [ ] **Step 2: Run it.** Expected: FAIL (`blastLimb` is missing).
- [ ] **Step 3: Implement.** Add `blastLimb` and the death listener in `Gore/init.luau`. In `HardDriveEffects.Explosive` at levels 1-2, replace `Gore.explode(...)` with `Gore.blastLimb(copy, limbKey, EXPLOSIVE_POWER)`, keeping the booms, LIMB_DAMAGE and the level 0 path. Update the Explosive's header comment and RECOVERY.
- [ ] **Step 4: Run** gore_aim, gore_integrity, gore_flesh, lab_gore (all), lab_inject A and D-J, and lab_claim. Expected: PASS, with the lab tests updated for the aimed blast.
- [ ] **Step 5: Commit** `feat(gore): injections hit only their limb; a torn head or opened torso kills`.

### Task 2: External hits land where they hit (spec section 6)

**Files:**
- Modify:
  - `src/ServerScriptService/Gore/Integrity.luau` (the watcher, plus a new `Integrity.hit`)
  - `src/ServerScriptService/Gore/init.luau`
  - `src/ReplicatedStorage/GoreConfig.luau`
  - `src/ServerScriptService/GoreServer.server.luau` (reset remote)
  - `docs/RECOVERY.md`
- Create: `src/StarterPlayer/StarterPlayerScripts/GoreReset.client.luau`
- Test: `tests/gore_hits.server.luau` (new), `tests/gore_reset.client.luau` (new). Update `tests/gore_integrity.server.luau` for the removed BIG_HIT and random limb.

**Interfaces:**
- Produces: `Gore.hit(part: BasePart, damage: number)`.
  - It finds the body and limb by walking up from `part`. A part under an Accessory maps to the R6 part its Handle is welded to, via the weld's other part.
  - It takes health with `Gore.hurt(body, damage)` if the body is alive.
  - It applies `damageLimb(body, key, damage * HIT_SCALE, "hit")` and calls `markHit`.
  - It does nothing for a part that isn't on a GoreBody, or for `damage <= 0`.
- Produces: `markHit(body, key, damage)` (local to Integrity, exported as `Integrity.markHit`). It sets `GoreHit = key .. "|" .. damage .. "|" .. n`. Task 3 and Task 6 use it.
- Produces: `ReplicatedStorage.GoreReset`, a RemoteEvent created by GoreServer. On FireServer, the sender's own character, if alive, gets `Gore.hurt(character, math.huge)`.
- The watcher now handles every unknown drop (no minimum), in this order:
  1. In the fall window, both legs take `drop * HIT_SCALE`, cause "fall".
  2. Else, the last limb touched within `TOUCH_WINDOW` s by a BasePart that is not Anchored, `not IsGrounded()`, and not a descendant of the same body. Track this with one Touched connection per limb part, set up in `track`.
  3. Else, the Torso.

  Cases 2 and 3 use cause "hit". Every case calls `markHit`.

- [ ] **Step 1: Write the tests.**
  - **H-A:** `Gore.hit(torso, 30)` three times leaves Torso Intact, Intact, then Torn (HP 85, 70, 55). No other limb changes. Health drops by exactly 90.
  - **H-B:** `Gore.hit(hat.Handle, 40)` on a body wearing an Accessory on the Head damages Head (GoreHP 80).
  - **H-C:** a corpse: `Gore.hit(corpseLeftArm, 200)` makes LeftArm Broken (never Severed, over 10 seeds), with no error.
  - **H-D:** standing on the floor, `humanoid:TakeDamage(30)` damages the Torso (HP 85), not a leg.
  - **H-E:** an unanchored ball touches the RightLeg, then within 0.1 s `TakeDamage(30)` damages RightLeg.
  - **H-F:** `GoreHit` changes on each hit and names the limb.
  - **H-G:** at GORE_LEVEL 0, `Gore.hit` takes health and changes no limb state.
  - **Reset (client):** `GoreReset:FireServer()` kills the player's character, no limb leaves Intact, and the body ragdolls (a corpse appears).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Add `HIT_SCALE = 0.5` and `TOUCH_WINDOW = 0.2` to GoreConfig, and remove `BIG_HIT` (and its comment).
  - GoreReset.client calls `StarterGui:SetCore("ResetButtonCallback", bindable)`, retrying with pcall until it succeeds. The bindable fires the RemoteEvent.
  - Add a RECOVERY section, "Calling the gore system from a weapon", with the server raycast and Touched examples from the spec, the "never also call TakeDamage" rule, and the RemoteEvent note.
- [ ] **Step 4: Run** gore_hits, gore_reset, gore_integrity (updated), gore_ragdoll, gore_flesh, gore_bleed, lab_gore L-A and death_screen. Expected: PASS.
- [ ] **Step 5: Commit** `feat(gore): Gore.hit, hits land on the limb they hit, reset without gore`.

### Task 3: Roblox Explosions through gore, with a ragdoll push (spec section 7)

**Files:**
- Modify: `src/ServerScriptService/ExplosionReplacer.server.luau`, `src/ServerScriptService/Gore/init.luau` (and Integrity's `explode`, to call `markHit` per limb hit), `src/ReplicatedStorage/GoreConfig.luau` (`BLAST_PUSH = 60`), `docs/RECOVERY.md`
- Test: `tests/gore_explosions.server.luau` (new)

**Interfaces:**
- Consumes: `Gore.explode`, `Gore.hurt`, `Integrity.markHit` (Task 2).
- Produces: `Gore.roblox(explosion: Explosion)`, called by ExplosionReplacer in the same frame the Explosion is added. Wrap it in pcall and warn once.
  1. Read `jointRadius = BlastRadius * DestroyJointRadiusPercent`, then set `DestroyJointRadiusPercent = 0`.
  2. Collect the living GoreBodies whose Torso is within `jointRadius`.
  3. Call `Gore.explode(Position, power, BlastRadius)`.
  4. Kill each collected body with `Gore.hurt(body, math.huge)`.
  5. On the next Heartbeat, push every corpse (in `Workspace.Corpses`) with a part within `BlastRadius`: set each of its parts' `AssemblyLinearVelocity += unit(part.Position - Position) * BLAST_PUSH * (1 - d / BlastRadius)`.
- ExplosionReplacer keeps its current boom behaviour for visible explosions. `Gore.roblox` runs for every Explosion, visible or not.

- [ ] **Step 1: Write `tests/gore_explosions.server.luau`.** Each case uses a tracked R6 test body standing on a test floor, with an `Instance.new("Explosion")` parented to Workspace.
  - **E-A:** an Explosion 2 studs from the body with the defaults (BlastRadius 4, DestroyJointRadiusPercent 1):
    - the body dies and a corpse exists;
    - no limb part of the body or the corpse is in Workspace on its own (no plain flung limbs);
    - at least one limb is Torn or worse;
    - the corpse's Torso is moving away from the blast at more than 5 studs/s on the frame after.
  - **E-B:** with DestroyJointRadiusPercent 0 and BlastRadius 8, an Explosion 5 studs away leaves the body alive and tears its nearest limb.
  - **E-C:** an existing corpse 3 studs from an Explosion has its limbs damaged further and is pushed.
  - **E-D:** `GoreHit` is set on each body that had a limb hit.
  - **E-E:** at GORE_LEVEL 0, every body's Motor6Ds or sockets are still in place after an E-A blast.
- [ ] **Step 2: Run it.** Expected: FAIL. A Roblox Explosion snaps the joints and limbs fly plain.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** gore_explosions, the boom tests (A-1/B/A-2, X, Y, C-1/C/C-2), gore_ragdoll, gore_aim and lab_inject A. Expected: PASS. Take one capture of a corpse thrown by an Explosion and describe it.
- [ ] **Step 5: Commit** `feat(gore): Roblox explosions tear limbs and throw ragdolls instead of snapping joints`.

### Task 4: Torn cloth scraps (spec section 3)

**Files:**
- Modify: `src/ServerScriptService/Gore/Flesh.luau`, `docs/RECOVERY.md`
- Test: add cases F-I to F-L to `tests/gore_flesh.server.luau`

**Interfaces:**
- Produces: inside `Flesh.dress`, at GORE_LEVEL 2, after the set is welded, it adds 3-5 parts named `GoreScrap` to the same off-body folder before the folder swaps in.
- Clothing that covers each limb:

  | Limb | Clothing |
  |---|---|
  | arms | Shirt |
  | legs | Pants |
  | Torso | Shirt and Pants |
  | Head | none |

- Each scrap:
  - Size: a WedgePart or Part, 0.3-0.7 × 0.3-0.7 × 0.05 studs.
  - Look: dark red (about RGB 60, 10, 10). A `Texture` on each of its two large faces uses the template image, with `Color3` about RGB 150, 40, 40.
  - Patch: `StudsPerTileU/V` and `OffsetStudsU/V` place it inside that limb's front-face region of the standard classic clothing template (585×559). Take the region coordinates from Roblox's creator documentation for classic Shirt/Pants templates, and check the result by eye.
  - Placement: welded to the R6 part, near the joint end (top 35% of an arm or leg; top or bottom edge of the torso), 0.05-0.15 studs outside the part's surface, at a random rotation.
  - Physics: Massless, CanCollide, CanQuery and CanTouch all off.
- No clothing, or an empty template, means no scraps, and the flesh is unchanged.

- [ ] **Step 1: Write the cases.**
  - **F-I:** a body with a Shirt (any template id) has its LeftArm torn: 3-5 `GoreScrap` parts in LeftArm's GoreFlesh. Each has a Texture whose `Texture` equals the ShirtTemplate, each is within the top 35% of the arm, and each is welded.
  - **F-J:** a body with no Shirt or Pants, torn LeftArm: no scraps.
  - **F-K:** severing the LeftArm keeps its scraps on the flying part, and the Torso stub gets none.
  - **F-L:** at GORE_LEVEL 1, no scraps.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** gore_flesh (all cases), gore_chunks and lab_gore L-A. Expected: PASS. Take one capture of a clothed torn arm on the lab copy and describe whether the scraps show the sleeve.
- [ ] **Step 5: Commit** `feat(gore): torn limbs keep bloodied scraps of their clothing`.

### Task 5: Colliding dangling limbs and no-bone legs (spec sections 4-5)

**Files:**
- Modify: `src/ServerScriptService/Gore/Ragdoll.luau`, `docs/RECOVERY.md`
- Test: add cases R-G to R-J to `tests/gore_ragdoll.server.luau`

**Interfaces:**
- Produces: `Ragdoll.loosen` adds a `GoreCollider` Part to the limb, set up as follows:
  - size of the limb, Transparency 1, CanCollide true, CanQuery and CanTouch false, Massless;
  - welded to the limb;
  - given `noCollide(body, collider)` pairs with every part of the body.
- Produces: `limp(body)` counts a leg as unsupporting when it is Broken or Severed, or Torn with `GoreVariant_<Leg> == 1`:
  - one unsupporting leg → LIMP_SPEED and no jump;
  - two → `GoreDowned`.
- `limp` is also run on every leg state change (Torn included), not only loosen and sever.

- [ ] **Step 1: Write the cases.**
  - **R-G:** a body lying on a test floor with a Broken LeftArm. After 2 s, the LeftArm's lowest point is not below the floor top by more than 0.1 studs, and its collider is welded and non-colliding with the body.
  - **R-H:** one leg Torn with variant 1 (seeded, or variant set before the tear): WalkSpeed equals LIMP_SPEED and `GoreDowned` is not true.
  - **R-I:** both legs Torn variant 1 → `GoreDowned`. Variant 1 on one leg plus Broken on the other → `GoreDowned`.
  - **R-J:** one leg Torn variant 2 alone: WalkSpeed is unchanged.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** gore_ragdoll (all cases), gore_crawl, gore_flesh and lab_gore L-A. Expected: PASS.
- [ ] **Step 5: Commit** `feat(gore): dangling limbs hit the ground; no-bone legs cannot hold the body`.

### Task 6: Blood on every external hit (spec section 8)

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/GoreClient.client.luau`, `docs/RECOVERY.md`
- Test: `tests/gore_hitblood.client.luau` and `tests/gore_hitblood.server.luau` (new; the server step calls `Gore.hit`)

**Interfaces:**
- Consumes: `GoreHit` (Task 2) and the Task 8 blood functions in GoreClient (the burst, splats and level rules).
- Produces: the GoreClient body watcher also listens for `GoreHit`. It spurts from that limb's part (or the Torso stump, if that limb has been severed), aimed from the Torso centre toward the limb, or the Torso's LookVector for the Torso. The spurt depends on damage:

  | Damage | Particles | Splats |
  |---|---|---|
  | < 20 | 8 droplets, speed 10-25, plus one drip | none |
  | 20-60 | half a Task 8 spray, speed 25-50 | 1-2 (6 rays, reach 8) |
  | > 60 | the full Task 8 spray | Task 8 splats |

  At level 0: the < 20 spurt only, with no splats.

- [ ] **Step 1: Write the tests.**
  - **HB-A:** after a server `Gore.hit(LeftArm, 10)`, a client `BloodBurst` exists at LeftArm within 0.3 s, and there are no new splats.
  - **HB-B:** after `Gore.hit(Torso, 80)`, splats are added near the body.
  - **HB-C:** Bob's injection (lab_inject A) changes no `GoreHit`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** gore_hitblood, gore_blood, the boom tests C-1/C/C-2 and gore_drips. Expected: PASS. Take one capture of a hit spurt and describe it.
- [ ] **Step 5: Commit** `feat(gore): every external hit draws blood from the limb it hit`.
