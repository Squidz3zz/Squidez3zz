# Gore System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Limb integrity with flesh variants, dangling and severed limbs, an R6 ragdoll and corpses, bleeding, and a stronger blood spray with glossy splats on walls and glass. The server decides, and every player sees the same bodies.

**Architecture:**
- **Server:** a `Gore` package in ServerScriptService owns state: integrity, states, chance rolls, the copy link, flesh welding, ragdoll joints, corpses and bleeding. It publishes each body's state as attributes.
- **Client:** `GoreClient` draws the cosmetics from those attributes and from BoomEvent: skin chunks, the crawl force, drips, pools, spray, mist and splats.
- **The lab:** it is rewired to go through `Gore`.

**Tech Stack:** Roblox Studio, Luau, Roblox Studio MCP tools, git.

**Spec:** `docs/superpowers/specs/2026-10-08-gore-system-design.md`. Read it first. Earlier context: `docs/superpowers/specs/2026-10-06-room1-injection-lab-design.md` and `docs/RECOVERY.md`.

## Global Constraints

### Studio and the place
- Use only the Studio instance named "Untitled Experience (placeId: 95688118364991)". Others may be open; never touch them. Call `list_roblox_studios` first, because ids change.
- **Never save or publish.** The controller asks the user to save after Tasks 4 and 8.
- If RenderStepped stops or the viewport is 1x1, the screen is locked: report BLOCKED.
- `ReplicatedFirst.LoadingScreen` is known broken (parked). Ignore it.

### Scripts
- Disk is the source of truth, in the Rojo layout. A folder with `init.luau` becomes a ModuleScript whose children are its sibling files.
- Push with `multi_edit` or by setting `.Source`, then confirm a checksum (LF-normalised) matches disk.
- Before editing a Studio script, `script_read` it and compare it with disk. If it differs, stop and report.
- Studio-built data (the extracted flesh pieces) is made by `studio/build_gore.luau`. It is safe to re-run and leaves the user's original FleshChart untouched.

### Tests
- Tests live in `tests/`, run in the datamodel their suffix names, as the committed file's text (there is no loadstring; paste it or byte-check a ModuleScript copy). They use `assert` and end with `return "PASS ..."`.
- A test that needs a player presses Play by firing `ReplicatedStorage.PlayPressed` from the Client. It claims Room 1 with `ServerScriptService.LabServer.TestHook:Invoke("claim", player)`.
- A server test may `require(ServerScriptService.Gore)`. Since it's the same ModuleScript, it shares the game's state.
- Chance rolls come from one `Random` held by Gore. Studio-only `Gore.seed(n)` reseeds it, so seeded cases repeat.
- After each task, rerun the earlier gore tests plus lab_claim A/C, lab_inject (all), tablet_menu A, bob_animator A-C, boom tests, death_screen, menu_client and scenes A. Some lab assertions change in Task 3; update them there.

### Values (verbatim from the spec, as `GoreConfig` fields)
- `GORE_LEVEL = 2`, `TORN_AT = 60`, `SEVER_CHANCE = 0.25`, `TORSO_OPEN_CHANCE = 0.35`, `SKULL_BLAST_CHANCE = 0.4`.
- `EXPLOSIVE_POWER = 150`, `BLAST_RADIUS = 6`. Falloff is `power * (1 - d/radius)^2`.
- `BIG_HIT = 30` (limb damage = 2 × health lost; a fall splits it across both legs).
- `LIMP_SPEED = 8`, `CRAWL_SPEED = 3`.
- `CORPSE_LIFE = 120`, `CORPSES_PER_PLAYER = 4`.
- `BLEED_PER_OPEN_LIMB = 0.83` (from 2 open limbs up), `DRIP_AFTER_DEATH = 30`, `POOL_MAX = 4`.
- `SPLAT_LIFE = 90`, `SPLAT_MAX = 150`, `BLOOD_DECALS = {}`.
- `CHUNKS_MIN = 6`, `CHUNKS_MAX = 10`, `CHUNK_REST = 5`.
- States: `"Intact"`, `"Torn"`, `"Broken"`, `"Severed"`, `"Destroyed"`.
- Body attributes:
  - `Gore_<Limb>` (state), `GoreHP_<Limb>` (integrity), `GoreVariant_<Limb>` (1 or 2);
  - `GoreTorsoOpen` (bool), `GoreSkull` (`"shown"`/`"blasted"`), `GoreDiedAt` (server time).
  - Limb names are the `LabConfig.LIMB_KEYS`.
- CollectionService tag `GoreBody` on every tracked body. Corpses live in `Workspace.Corpses`, each a Model named `Corpse` with attribute `GoreOwner` (UserId).
- Gore levels:
  - **2:** everything.
  - **1:** no flesh, bone or chunks (a severed limb leaves a plain stump).
  - **0:** the 2026-10-08 behaviour: limbs drop off, simple blood, no bleeding. Ragdolls and corpses stay at every level.

### Fault isolation and trust
- Every Gore call from other code is pcall'd and warns once. If Gore fails to load, the lab falls back to today's behaviour.
- The server trusts nothing from clients. BoomEvent stays server-to-client only.

### Commits
Branch `feature/gore`. End every commit message with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus
1. **A corpse is blasted.** Corpses stay tracked: an explosion tears or severs their limbs further (no Health, no bleeding damage) without errors. Test: Task 2, case R-F.
2. **Dying while downed or with dangling limbs.** The ragdoll starts from the current joints: no Motor6D is left, no duplicate BallSockets, and dangling limbs stay attached. Test: Task 2, case R-D.
3. **The owner leaves, or the copy is replaced, while its corpse exists.** The corpse lives out its 120 s and is cleaned up, with no errors. Test: Task 3, case L-D.
4. **Gore level 1 and 0.** Level 1 welds no flesh pieces and makes no chunks. Level 0 detaches the injected limb like before, with no bleeding. Tests: Task 5, case F-G; Task 7, case B-D.
5. **Linked bodies where one is dead.** A gore change still lands identically on both, and on the dead one only as visuals. Test: Task 3, case L-E.

---

### Task 1: GoreConfig and the integrity core

**Files:**
- Create: `src/ReplicatedStorage/GoreConfig.luau`
- Create: `src/ServerScriptService/Gore/init.luau`
- Create: `src/ServerScriptService/Gore/Integrity.luau`
- Test: `tests/gore_integrity.server.luau`
- Modify: `docs/RECOVERY.md`

**Interfaces (Produces):**
- **`GoreConfig`:** every value under Global Constraints, with a header comment in MenuAssets style.
  - `GoreConfig.get(name: string): any`. Every gore reader, server and client, uses it.
  - In Studio only, it returns an attribute override set on the GoreConfig ModuleScript itself, if one exists; otherwise the table value. BLOOD_DECALS is overridden as a comma-separated string.
  - Server tests set these attributes, and they replicate to clients. This is the "test hook" that Tasks 2, 5, 7 and 8 use for CORPSE_LIFE, GORE_LEVEL and BLOOD_DECALS.
- **`Gore` (ModuleScript `ServerScriptService.Gore`):**
  - `track(body: Model): ()` sets the attributes (Intact, HP 100), the tag, and `Humanoid.BreakJointsOnDeath = false`.
  - `link(a: Model, b: Model): ()` and `unlink(body: Model): ()`.
  - `damageLimb(body: Model, key: string, amount: number, cause: string): ()`.
  - `explode(position: Vector3, power: number, radius: number): ()`.
  - `hurt(body: Model, amount: number): ()`: Health damage marked as gore-caused, so big hits skip it.
  - `stateOf(body, key): string?` and `integrityOf(body, key): number?`.
  - `copyState(from: Model, to: Model): ()`.
  - `onStateChanged(fn: (body: Model, key: string, old: string, new: string, info: { cause: string, severed: boolean?, torsoOpened: boolean?, skullBlasted: boolean? }) -> ()): ()`: listeners in later tasks.
  - Studio only: `seed(n: number): ()`.
- **Rules:** as in the spec's "Limbs, integrity and states".
  - The torso-open and skull rolls happen in Integrity and are published as `GoreTorsoOpen` / `GoreSkull`.
  - For a linked pair, every decision is made once on the first body and applied identically to the other, without a second roll.
  - `explode` damages every tracked body, corpses included (Review Focus 1).

- [ ] **Step 1: Write `tests/gore_integrity.server.luau`.** Use Server playtest R6 bodies from `Players:CreateHumanoidModelFromDescription(HumanoidDescription.new(), R6)`, placed at known spots. Cases:
  - **I-A thresholds:** `damageLimb(b, "LeftArm", 40, "hit")` leaves it Intact (60); +1 makes it Torn; +60 makes it Broken (cause "hit" never severs). Torso at 0 is "Destroyed", Health 0.
  - **I-B explode falloff:** at 0 / 1.5 / 3 studs from limb centres, the damage is 150 / 84.4 / 37.5 (±0.5).
  - **I-C sever:** `seed(1)` with a fixed outcome table. Find seeds giving sever and not-sever, assert both outcomes and that repeating a seed repeats it.
  - **I-D torso:** a torn torso hit by explode opens on the seeded "open" roll, stays sealed on the other, and never opens from `damageLimb(..., "hit")`. Legs at Severed never set `GoreTorsoOpen`.
  - **I-E skull:** a destroyed head gives `GoreSkull` "blasted" or "shown" by seed.
  - **I-F link:** link a and b, explode at a's LeftArm. b's states, HP, variants and `GoreTorsoOpen` equal a's.
  - **I-G copyState:** a fresh body gets every attribute of a damaged one.
  - **I-H big hits:** a 30-health drop not made by `hurt` damages a random limb by 60. A drop right after Freefall splits 30/30 over both legs. `hurt(b, 40)` triggers nothing.
- [ ] **Step 2: Run it.** Expected: FAIL (Gore missing).
- [ ] **Step 3: Implement GoreConfig, Gore and Integrity,** then push (the Gore folder becomes a ModuleScript with a child ModuleScript).
- [ ] **Step 4: Run it.** Expected: PASS for every case.
- [ ] **Step 5: Commit** `feat(gore): limb integrity, states, the link and big hits`.

---

### Task 2: Dangling limbs, severing, movement, ragdoll and corpses

**Files:**
- Create: `src/ServerScriptService/Gore/Ragdoll.luau`
- Create: `src/ServerScriptService/GoreServer.server.luau`
- Create: `src/StarterPlayer/StarterPlayerScripts/GoreClient.client.luau` (this task: the crawl force only)
- Modify: `Gore/init.luau` (wire Ragdoll to `onStateChanged`), `docs/RECOVERY.md`
- Test: `tests/gore_ragdoll.server.luau`, `tests/gore_crawl.client.luau`

**Interfaces:**
- **Consumes:** Task 1.
- **Produces, from Ragdoll** (called by Gore on state changes):
  - `loosen(body, key)` swaps a Motor6D for a BallSocketConstraint, with limits: shoulder 70° cone / 45° twist, hip 50° / 30°, neck 40° / 30°.
  - `sever(body, key)` detaches the limb (it keeps flesh welded by Part B), applies the fling (move it from HardDriveEffects: server network owner, 15–30 studs/s, 20–60° up, random spin), and removes it after `LabConfig.LOST_LIMB_SECONDS`.
  - `die(body)` loosens every remaining joint, makes all parts collide, and creates the corpse:
    - it moves every child of the body into `Workspace.Corpses.Corpse` (server-owned, attributes kept, `GoreDiedAt` set);
    - it caps each owner at `CORPSES_PER_PLAYER`, oldest first;
    - after `CORPSE_LIFE`, the corpse sinks (no collisions, a 2 s tween down 4 studs) and is destroyed.
  - Movement: one leg Broken/Severed sets `WalkSpeed = LIMP_SPEED` and `JumpHeight = 0`; both legs set the attribute `GoreDowned = true` on the character.
- **GoreServer:** calls `Gore.track` on every player character on CharacterAdded.
- **GoreClient:** for the local character with `GoreDowned`, it sets `PlatformStand` and drives a LinearVelocity on HumanoidRootPart at `CRAWL_SPEED` along `Humanoid.MoveDirection` (horizontal).

- [ ] **Step 1: Write the tests.**
  - `tests/gore_ragdoll.server.luau`:
    - **R-A:** a Broken LeftArm has no Motor6D (`LabConfig.limbJoint` is nil) and a BallSocketConstraint joining Torso and Left Arm; the arm is still in the body.
    - **R-B:** a Severed LeftLeg is out of the body and moves more than 2 studs horizontally within 0.5 s.
    - **R-C:** with one leg out, WalkSpeed is 8 and JumpHeight 0; with both, `GoreDowned` is true.
    - **R-D (Review Focus 2):** a body with a dangling arm dies. It has no Motor6D, exactly one BallSocket per joint, and the dangling arm is still attached.
    - **R-E corpse:** a player character dies. `Workspace.Corpses` holds a Corpse with `GoreOwner` = UserId and the body's parts. The respawned character is new. Run 5 deaths: at most 4 corpses. With `CORPSE_LIFE` overridden to 3 s through a Studio test hook, the corpse is gone after 6 s.
    - **R-F (Review Focus 1):** `Gore.explode` at a corpse's arm sets that arm to Broken or Severed, with no errors and no Health change.
  - `tests/gore_crawl.client.luau`: with the server setting `GoreDowned`, PlatformStand is true. Holding the move direction (set by the test) moves the root about 3 studs/s, ±1.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run them, plus Task 1.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(gore): dangling and severed limbs, limping and crawling, ragdolls and corpses`.

---

### Task 3: Rewire the lab through Gore

**Files:**
- Modify:
  - `src/ServerScriptService/HardDriveEffects.luau`: Explosive calls `Gore.hurt(body, LIMB_DAMAGE)` and `Gore.explode(centre, EXPLOSIVE_POWER, BLAST_RADIUS)` instead of destroying joints and flinging.
  - `LabServer.server.luau`: `Gore.track` the copy, `Gore.link(copy, ownerCharacter)`, and `Gore.copyState(ownerCharacter, newCopy)` instead of R25's limb mirroring. Drop tablets when the right arm is Broken or Severed. Unlink on release.
  - `src/ReplicatedStorage/LabConfig.luau`: `isLost` is true only when `Gore_<Limb> == "Severed"`. If the attribute is absent, fall back to the joint check, for level 0 and old bodies.
  - The affected lab tests.
- Test: `tests/lab_gore.server.luau` and updates to `lab_inject` A/E/G and `lab_claim` E.

**Interfaces:**
- **Consumes:** Tasks 1–2.
- **Level 0:** the Explosive behaves as on 2026-10-08 (detach, fling, simple blood).

- [ ] **Step 1: Write `tests/lab_gore.server.luau`.**
  - **L-A:** an injection into LeftArm leaves the copy's and the owner's LeftArm in the same state (Broken or Severed), with identical torso and head integrity.
  - **L-B:** a Broken LeftArm can be injected again (`LabConfig.isLost` false), and the tablet menu's `lost.LeftArm` is false.
  - **L-C:** a Broken RightArm drops the tablet.
  - **L-D (Review Focus 3):** the owner dies, the copy's corpse exists, and the owner releases. The corpse is still there and gone after its life (use the test-hook life). No errors.
  - **L-E (Review Focus 5):** the owner dies, then the copy is blasted before respawn. The owner's corpse shows the same state change.
  - Update lab_inject A, E and G and lab_claim E to the new outcomes. A limb is "lost" only when severed. A "copy keeps lost limbs" check becomes "the copy takes on the owner's gore".
- [ ] **Step 2: Run the new and updated tests.** Expected: FAIL where the behaviour changed.
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run all lab, gore and regression tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(lab): the Explosive and the copy link go through Gore`.

---

### Task 4: Extract the flesh pieces from the user's chart

**Files:**
- Create: `studio/build_gore.luau` (run it in Edit)
- Modify: `docs/RECOVERY.md`
- Test: `tests/gore_pieces.edit.luau`

**Interfaces (Produces):**
- `ServerStorage.Gore.FleshChart`: the user's `Workspace.Mesh.FleshChart`, moved untouched. The emptied `Workspace.Mesh` folder is removed.
- `ServerStorage.Gore.Pieces.<Limb>.<Variant1|Variant2|Death>`:
  - Models of cloned pieces. Each piece is a non-collidable, massless, unanchored copy, with attribute `Offset` (CFrame relative to the R6 part it belongs to) and attribute `Layer` (`"flesh"` or `"deep"`).
  - Deep pieces are `Ribcage`, `Skull`, the bone unions and `Stub*`.
  - The torso's variants are named `Sealed` (the one with TorsoFilling) and `Open` (without it), not Variant1/2.
  - `Death` holds the stub or death pieces.
  - `Pieces.FullBody.Variant1` holds every limb's full-body pieces.
- How a piece's limb is found:
  - From its name (HeadFlesh/Skull → Head; Torso model children, Ribcage and TorsoFilling → Torso; Leftarm*/LeftArm union → LeftArm; and so on).
  - For `Stub1`, from the chart model it sits in (RightArm models → RightArm).
- How offsets are found: from the chart body's own Torso flesh, mapped through `SizingModel` (FullBodyFleshSizing against the real R6 dummy `SizingModel.thxalloverme123`). So each piece's offset is relative to the matching R6 part of that dummy.

- [ ] **Step 1: Write `tests/gore_pieces.edit.luau`.**
  - Every limb has `Variant1`, `Variant2` (the torso has `Sealed`/`Open`) and `Death` with at least one flesh piece.
  - `Torso.Open` has no TorsoFilling; `Torso.Sealed` has it.
  - Ribcage exists only in the Open and Death torso.
  - Each arm or leg `Death` holds a `Stub*`.
  - Every piece has `Offset` and `Layer`.
  - Placing `Pieces.LeftArm.Variant1` on the SizingModel dummy's Left Arm puts each piece within 0.2 studs of where the same piece sits in `FullBodyFleshSizing`.
  - The FleshChart in ServerStorage has the same descendant count as the original. A second build run changes nothing.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Write and run the build.**
- [ ] **Step 4: Run the test.** Expected: PASS. Then take a screen_capture of the dummy with Variant1 on every limb, and describe it.
- [ ] **Step 5: Commit** `feat(gore): extract the flesh pieces from the user's FleshChart`. Controller: ask the user to save.

---

### Task 5: Flesh on bodies

**Files:**
- Create: `src/ServerScriptService/Gore/Flesh.luau`
- Modify: `Gore/init.luau` (wire Flesh to `onStateChanged`), `docs/RECOVERY.md`
- Test: `tests/gore_flesh.server.luau`

**Interfaces:**
- **Consumes:** Task 4's pieces; Task 1's state changes.
- **Produces, at `GORE_LEVEL == 2`:**
  - **Torn:** hide the R6 part (Transparency 1, plus its decals, the face, and clothing on that part) and weld clones of `Pieces.<Limb>.Variant<GoreVariant>` at `part.CFrame * Offset`. Flesh layer only, except as below.
  - **Torso:**
    - Sealed while torn and not `GoreTorsoOpen`.
    - On `GoreTorsoOpen`, swap to `Open` pieces plus Ribcage. Destroyed is Open plus Ribcage.
  - **Head:** Destroyed uses `Death` pieces, with Skull only when `GoreSkull == "shown"`.
  - **Severed:** the flying limb keeps its flesh, and `Death`'s Stub is welded to the torso at that joint.
  - **All six limbs torn or worse:** every limb uses `Pieces.FullBody.Variant1`'s piece for it. The torso and head deep-layer rules still apply.
  - Nothing is ever un-revealed.
- **Level 1:** no pieces are welded. A severed limb leaves its stump as a plain dark-red block at the joint.

- [ ] **Step 1: Write `tests/gore_flesh.server.luau`.**
  - **F-A:** a torn LeftArm has Transparency 1 and its Variant pieces welded within 0.2 studs of their offset.
  - **F-B:** a torn torso has no Ribcage; with `GoreTorsoOpen` it has Ribcage and the Open pieces.
  - **F-C:** both legs severed with the torso intact gives no torso pieces and no Ribcage.
  - **F-D:** destroyed head with skull "shown" has a Skull; "blasted" has none.
  - **F-E:** a severed arm leaves a Stub welded at the shoulder.
  - **F-F:** all six torn uses FullBody pieces.
  - **F-G (Review Focus 4):** at `GORE_LEVEL = 1` (set via the Studio hook), a torn limb gets no pieces and stays visible.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run it, plus Tasks 1–3.** Expected: PASS. Capture the copy in the chair after injecting each limb, and describe it.
- [ ] **Step 5: Commit** `feat(gore): flesh variants, the sealed and open torso, skull and stubs`.

---

### Task 6: Skin chunks

**Files:**
- Modify: `src/StarterPlayer/StarterPlayerScripts/GoreClient.client.luau`
- Test: `tests/gore_chunks.client.luau` (with a server step)

**Interfaces:**
- **Consumes:** the `Gore_<Limb>` attribute changes on any `GoreBody`-tagged model.
- **Produces** (client-only, level 2): on a change to Torn or Severed, `CHUNKS_MIN`–`CHUNKS_MAX` small chunks are thrown from the part:
  - each is a wedge or block 0.2–0.5 studs, coloured by the part's skin, or by the shirt/pants colour on clothed parts (sampling the BodyColors part colour is enough);
  - they fly outward at 10–25 studs/s with random spin, colliding with the world but not with bodies;
  - they rest `CHUNK_REST` s, then fade over 1 s and are destroyed;
  - at most 200 chunks live at once.

- [ ] **Step 1: Write `tests/gore_chunks.client.luau`.** After a server `damageLimb` makes the copy's LeftArm Torn:
  - within 0.5 s, 6–10 chunk parts exist near it;
  - they all move away from the arm;
  - they are gone after `CHUNK_REST` + 1.5 s;
  - no chunks are made at level 1.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run it.** Expected: PASS. Capture a tear, and describe it.
- [ ] **Step 5: Commit** `feat(gore): skin chunks burst off a tearing limb`.

---

### Task 7: Bleeding, drips and pools

**Files:**
- Create: `src/ServerScriptService/Gore/Bleeding.luau`
- Modify: `GoreServer.server.luau` (a 0.25 s tick), `GoreClient.client.luau`, `docs/RECOVERY.md`
- Test: `tests/gore_bleed.server.luau`, `tests/gore_drips.client.luau`

**Interfaces:**
- **Bleeding (server, level ≥ 1):** for a living tracked body with n ≥ 2 open limbs, `Gore.hurt(body, BLEED_PER_OPEN_LIMB * n * dt)`. A linked pair is hurt identically.
- **GoreClient (level ≥ 1):** every open limb of a living body, and of a corpse until `GoreDiedAt + DRIP_AFTER_DEATH`, emits drips:
  - a ParticleEmitter in the limb, dark red, falling under gravity;
  - a pool under the body (a raycast down from the torso) as a glossy dark-red disc, growing to `POOL_MAX` studs while the body drips;
  - the pool stays with the corpse's life, or for `SPLAT_LIFE` for living bodies after the dripping stops.

- [ ] **Step 1: Write the tests.**
  - **B-A:** 2 open limbs lose 1.66 ± 0.1 health/s over 3 s.
  - **B-B:** 1 open limb loses none.
  - **B-C:** a linked pair loses identical health.
  - **B-D (Review Focus 4):** level 0 loses none.
  - **Client:** a bleeding copy has a drip emitter on each open limb; a pool grows under it, wider at 6 s than at 2 s and no wider than `POOL_MAX`; a corpse stops dripping after `DRIP_AFTER_DEATH`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run them, plus Tasks 1–6.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(gore): bleeding damage, drips and pools`.

---

### Task 8: The stronger spray, and splats on walls and glass

**Files:**
- Modify:
  - `src/ServerScriptService/Booms.luau`: `at(position, blood, direction?)`, sending the direction.
  - `HardDriveEffects.luau`: passes the direction (limb centre minus torso centre; the body's LookVector for the torso or head).
  - `BoomClient.client.luau`: the blood part moves out.
  - `GoreClient.client.luau`: the blood burst, spray, mist and splats.
  - `GoreConfig`, `docs/RECOVERY.md`, and the boom tests.
- Test: `tests/gore_blood.client.luau` (with a server step)

**Interfaces:**
- **Spray:** `LabAssets.Blood.Spray` is emitted at about 2× its EmitCount, with speed 40–90, aimed in a 45° cone along the direction. Mist is bigger, more opaque and lasts about 3 s. The user's blood sounds play.
- **Splats:**
  - about 12 rays in a 60° cone along the direction, up to 14 studs, plus 4 downward;
  - a hit counts only on `IsGrounded()` parts, excluding bodies, corpses, Bob, `Room1.Shutter` and the boom;
  - each splat is a glossy dark-red base (glass-like or reflective, chosen by eye) plus a random `BLOOD_DECALS` decal, rotated randomly;
  - on near-vertical surfaces it's stretched 1.5–2.5× along the surface's downward direction;
  - it gets a small random lift;
  - it lasts `SPLAT_LIFE`, with at most `SPLAT_MAX`, oldest first.

- [ ] **Step 1: Write `tests/gore_blood.client.luau`.**
  - **S-A:** a blood boom 3 studs from a wall, aimed at it, puts ≥2 splats on the wall, flat on it, each longer vertically than wide.
  - **S-B:** a head blast on the seated copy, aimed at the window (−X), puts ≥1 splat on the observation glass.
  - **S-C:** the spray droplet speed range is 40–90.
  - **S-D:** with `BLOOD_DECALS = { "rbxassetid://1" }` (test override), each splat has a Decal with that texture.
  - **S-E:** nothing lands on the Shutter or on a body.
  - **S-F:** 200 splats requested leave at most 150.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement and push.**
- [ ] **Step 4: Run every gore, lab, boom and regression test.** Expected: PASS. Capture splats on the glass from outside the window, and describe them.
- [ ] **Step 5: Commit** `feat(gore): forceful spray, thick mist, glossy splats on walls and glass`. Controller: remind the user to add BLOOD_DECALS IDs and to save.
