# Gore system: design

Date: 2026-10-08. Status: approved in conversation, awaiting review of this written spec.

## Goal

Make the game "extremely gory" with a damage system every body shares:
- limbs that tear open to show the user's flesh models, dangle from broken bones, or by chance rip off;
- an R6 ragdoll on every death, with bodies left lying around;
- bleeding that drips, pools and kills;
- a much stronger blood spray that paints floors, walls and the observation glass with glossy, gross splats.

It extends the Room 1 lab (docs/superpowers/specs/2026-10-06-room1-injection-lab-design.md), the boom and blood work merged on
2026-10-08, and the existing link between the copy and its owner.

## Platform note

Heavy realistic blood is only allowed in 17+ ("Restricted") experiences, and Roblox's Community Standards still limit extreme
gore; exposed bone or ribcage may be moderated even at 17+. The user is responsible for checking the current rules before
publishing. `GoreConfig.GORE_LEVEL` (below) lets them tone everything down without code changes.

## Decisions (from the brainstorm)

| Topic | Decision |
|---|---|
| Architecture | The server decides: integrity, states, flesh, broken limbs, ragdolls, corpses and bleeding damage live on the server and replicate, so every player sees the same bodies. Only cosmetic effects (skin chunks, drips, pools, spray, mist, splats) are drawn on each client. |
| Flesh chart | When a limb is damaged, only that limb's normal R6 part is hidden and replaced by its pieces from Variant 1 or 2 of the user's FleshChart (random), welded where the SizingModel shows. A severed limb leaves its DeathBodyModel stub. |
| Damage sources | Explosions (every limb in the blast, more when closer), big hits (any single loss of 30+ health), and a simple function for future weapons and viruses. |
| Tear-off | An explosion that breaks an arm or leg severs it 25% of the time; otherwise it dangles. |
| Broken limbs | One leg broken or gone: half speed, no jumping. Both legs: collapse and drag yourself slowly. Right arm broken or gone: the tablet is dropped. |
| Bleeding | With 2+ open limbs, death in about 60 s; each extra open limb is faster. |
| Corpses | Every death ragdolls. Bodies stay 2 minutes; at most 4 per player (oldest first). |
| Splat look | A glossy, wet dark-red base. Blood decals are left out for now (the user's call); they may be layered on later. |
| Skin chunks | When a limb tears, chunks of skin burst off it before the flesh shows. |
| Torso | Stays sealed when torn; only an explosion's chance rips it open. Legs never open it. |
| Head | When destroyed, a chance also blows the skull apart (flesh only). |
| Gore level | One setting: 2 full, 1 blood and dangling only, 0 the earlier simple version. |
| Build order | Three parts, each reviewed and mergeable: (A) integrity, broken limbs, ragdoll; (B) flesh and skin chunks; (C) blood. |

## Limbs, integrity and states

Limb keys are `LabConfig.LIMB_KEYS` (Head, Torso, LeftArm, RightArm, LeftLeg, RightLeg); R6 only. Every body the gore system
tracks (player characters, Room 1 copies) has integrity 100 per limb.

| State | When | Notes |
|---|---|---|
| Intact | integrity > TORN_AT (60) | normal skin |
| Torn | integrity ≤ 60 | the flesh variant replaces the skin (Part B), with a skin-chunk burst. An open wound. |
| Broken (arms and legs) | integrity ≤ 0 | still torn; the bone breaks and the limb dangles |
| Severed (arms and legs) | when an explosion breaks it, with SEVER_CHANCE (0.25) | the limb is detached and flung (existing fling), showing flesh; the bone stub appears at the joint. An open wound. |
| Destroyed (Head, Torso) | integrity ≤ 0 | fatal |

Rules:
- States only ever move forward (Intact → Torn → Broken/Severed or Destroyed).
- An open wound is Torn, Broken or Severed.
- A severed limb has no integrity left to damage.
- Damaging a Broken limb with an explosion rolls SEVER_CHANCE again.

**Torso:**
- Torn means **sealed** (the TorsoVariant with TorsoFilling).
- Each time an explosion damages the torso and leaves it torn, TORSO_OPEN_CHANCE (0.35) rolls. On a hit it becomes **open**: the open-cavity variant, with the ribcage showing.
- A destroyed torso is always open.
- Legs never open the torso.

**Head:** when destroyed, SKULL_BLAST_CHANCE (0.4) rolls. On a hit the skull is blasted (flesh only). Otherwise the skull shows.

### Damage
- **`Gore.damageLimb(body, key, amount, cause)`** is the one function everything uses. `cause` is "explosion", "hit" or a
  future name, and only "explosion" can sever or open the torso.
- **`Gore.explode(position, power, radius)`** damages every tracked limb whose centre is within `radius`, by
  `power × (1 − d/radius)²`.
  - The Explosive uses EXPLOSIVE_POWER 150 and BLAST_RADIUS 6, so the injected limb always breaks.
  - Example: an arm blast does about 84 to the torso (torn) and about 63 to the head (torn).
- **Big hits.** A single Health drop of BIG_HIT (30) or more that the gore system did not cause damages limbs by 2 × the
  health lost:
  - a fall (the humanoid was in Freefall within the last 0.5 s) splits it across both legs;
  - otherwise one random limb takes it.
- **Big hits ignore the gore system's own damage.** Health changes made by the gore system or the lab (the Explosive's
  LIMB_DAMAGE, bleeding, link mirroring) are marked so the big-hit watcher skips them.
- **Health damage is unchanged:**
  - the Explosive still does LIMB_DAMAGE (20) for an arm or leg;
  - a destroyed head or torso sets Health to 0;
  - bleeding is added on top (below).

### The link
- LabServer registers each owner's character and copy as a linked pair. Every gore change on either body (damage, state,
  variant pick, chance roll) is decided once and applied to both identically.
- A newly built copy takes on the owner's whole current gore state: states, variants, torso open, skull, and stubs.
- This replaces the lab's earlier one-way limb mirroring and its R25 rule.
- `LabConfig.isLost` changes meaning: a limb is lost only when it is **Severed**; a dangling limb can still be injected.

## Flesh (Part B)

**Assets:**
- The user's `Workspace.Mesh.FleshChart` moves untouched to `ServerStorage.Gore.FleshChart`, kept as the reference.
- `studio/build_gore.luau` extracts each limb's pieces into `ServerStorage.Gore.Pieces.<Limb>.<Variant1|Variant2|Death>`, each
  piece stored with its CFrame relative to the R6 body part it belongs to:
  - a piece belongs to the limb by where it sits on its chart body, relative to that body's Torso;
  - alignment comes from the SizingModel, where the flesh pieces sit around a real R6 dummy;
  - re-running the build regenerates the pieces from the chart, so the user can edit the chart.
- Deep-layer pieces are tagged so the rules can show or hide them: Ribcage, Skull, the bone unions and Stub1.

**Applying:**
- **Torn limb:** its R6 part is hidden (Transparency 1; clothing and decals hidden too). The chosen variant's pieces are welded
  on (Massless, no collisions).
- **Torso:** sealed uses the variant with TorsoFilling; open uses the variant without it, plus the Ribcage.
- **Destroyed head:** uses the head's Death pieces, without the Skull when SKULL_BLAST_CHANCE hit.
- **Severed limb:** the flying limb shows its flesh; the Death model's Stub is welded at the shoulder or hip.
- **All six limbs torn or worse:** every limb shows flesh (the full-body variant's limb pieces). The ribcage and skull still
  follow the torso and head rules.

**Skin chunks (client):** when a limb turns Torn (or is severed), 6–10 small chunks in that part's colours fly out from it
with tumbling physics, rest about 5 s and fade over 1 s. The colours are the skin plus the shirt or pants colour where the
clothing covers the part.

## Broken limbs, ragdoll and corpses (Part A)

- **Dangling:**
  - A broken arm or leg's Motor6D is replaced by a BallSocketConstraint with natural limits (shoulder or hip cone, twist
    limits) on matching attachments, so it hangs and flops.
  - The broken limb collides with the world but not with its own body.
  - The copy's broken limbs dangle off the chair.
- **Movement:**
  - One leg Broken or Severed: WalkSpeed 8 (half), no jumping.
  - Both legs: the character is downed: PlatformStand with the torso low, moved by a gentle force at 3 studs/s along its
    MoveDirection.
  - Right arm Broken or Severed: the tablet is dropped (the existing right-arm rule, extended to Broken).
- **Ragdoll on every death** (all players and copies):
  - BreakJointsOnDeath is false on every tracked body.
  - On Died, every Motor6D becomes a BallSocketConstraint (with neck, shoulder and hip limits), and all parts collide.
  - Gore stays on the body.
- **Corpses:**
  - On death the body's parts move into a Model under `Workspace.Corpses`, owned by the server, before MenuServer's respawn
    removes the old character.
  - Corpses last CORPSE_LIFE (120 s), then sink (no collisions, eased down) and are destroyed.
  - At most CORPSES_PER_PLAYER (4); the oldest goes first.
  - The new copy is seated as usual; the old one stays where it fell.

## Blood (Part C)

- **Bleeding (server):**
  - With n ≥ 2 open limbs, the body loses BLEED_PER_OPEN_LIMB (0.83) × n health per second: about 60 s with 2.
  - Linked bodies bleed identically.
  - It stops at death.
- **Drips (client):**
  - Every open limb drips dark-red drops while the body is alive, and for 30 s after death.
  - Drops landing below grow a wet pool (Foil, R17) under the body, up to 4 studs across.
- **Spray (client):**
  - A limb blast fires a forceful jet: about 2× the current droplets at 40–90 studs/s, in a cone pointing away from the body.
    The direction is limb centre minus torso centre; a torso or head blast uses the body's facing.
  - A thicker mist: bigger, more opaque, lasting about 3 s.
  - The user's blood sounds play as now.
  - `Booms.at(position, blood, direction?)` gains the direction.
- **Splats (client):**
  - About 12 rays in a 60° cone along the spray, up to 24 studs (24, not 14: the seated copy's head is about 19 studs from the glass; Task 8), plus 4 downward rays.
  - Wherever they hit a fixed surface, a splat sticks: the floor, the walls, the chair, or the observation glass from inside.
    A fixed surface is `IsGrounded()`, excluding bodies, Bob, the Shutter and the boom.
  - On walls and glass the splats are stretched 1.5–2.5× downward along the surface, like running blood.
  - Each splat is a wet, dark-red base (Foil, chosen by eye: glass and reflective plastic go purple in sunlight; ruling R17)
    with no decal (decals are left out for now), rotated randomly.
  - Splats are lifted slightly with a small random offset so overlapping ones don't flicker.
  - SPLAT_LIFE 90 s, SPLAT_MAX 150 (oldest first).

## Gore levels

| Level | What it gives |
|---|---|
| 2 (default) | Everything above |
| 1 | Blood, bleeding, dangling, tear-offs, ragdolls and corpses; no flesh, bone, ribcage, skull or skin chunks (a severed limb leaves a plain stump) |
| 0 | The 2026-10-08 behaviour: limbs drop off, simple blood, no bleeding; ragdolls and corpses stay |

## Code

| File | Job |
|---|---|
| `src/ReplicatedStorage/GoreConfig.luau` | Every number above and the gore level |
| `src/ServerScriptService/Gore/init.luau` (ModuleScript `Gore`) | The public API: `damageLimb`, `explode`, `track(body)`, `link(a, b)`, `stateOf(body, key)` |
| `src/ServerScriptService/Gore/Integrity.luau` | Integrity, states, chance rolls (one Random per server, seedable from a Studio-only TestHook), big hits, the link |
| `src/ServerScriptService/Gore/Flesh.luau` | Welding pieces, hiding skin, deep-layer rules, stubs (Part B) |
| `src/ServerScriptService/Gore/Ragdoll.luau` | Dangling joints, movement effects, death ragdoll, corpses |
| `src/ServerScriptService/Gore/Bleeding.luau` | Bleed damage (Part C) |
| `src/ServerScriptService/GoreServer.server.luau` | Tracks every player character on spawn, bleeding ticks, corpse cleanup |
| `src/StarterPlayer/StarterPlayerScripts/GoreClient.client.luau` | Skin chunks, drips, pools, spray, mist, splats; the blood part of BoomClient moves here |
| `studio/build_gore.luau` | Moves the FleshChart and extracts the pieces (Part B) |

What clients read:
- Every tracked body (character, copy, corpse) carries attributes `Gore_<Limb>` (state), `GoreVariant_<Limb>`, `GoreTorsoOpen`
  and `GoreSkull`, plus `GoreDiedAt` on corpses.
- Tracked bodies have the CollectionService tag `GoreBody`.

The lab is rewired:
- HardDriveEffects' Explosive calls `Gore.explode` at the limb instead of destroying joints.
- LabServer links each owner and copy, and builds copies with the owner's gore.
- BobAnimator's needle aims at a dangling limb's live position (its injection goal is latched as now).

## Error handling

- The usual rule: every module call is pcall'd and warns once; a failure never stops the rest.
- If the gore system fails to load, the lab falls back to today's behaviour.
- Bad or missing chart pieces skip the flesh for that limb (the limb then stays skin).
- Clients ignore malformed attributes.
- Every cosmetic effect is capped.

## Testing

Studio tests as before, run in playtests from the committed files. A Studio-only TestHook seeds the gore Random so chance
results repeat.

**Part A:**
- states and thresholds;
- explosion falloff, and big hits including falls;
- the 25% sever (seeded both ways);
- the link: identical states on the copy and the owner, including a respawned copy taking on gore;
- dangling joints (BallSocket, not Motor6D);
- WalkSpeed 8 with one leg, downed with both;
- the tablet dropped on a broken right arm;
- the death ragdoll (no Motor6D left), corpses moved to Workspace.Corpses;
- the lifetime and the 4-corpse cap;
- isLost only for Severed.

**Part B:**
- the extracted pieces exist for every limb and variant;
- a torn limb's skin is hidden, with its pieces within 0.2 studs of their SizingModel offset;
- the sealed torso has no Ribcage, and an open one has it;
- legs never open the torso;
- the skull and skull-blast (seeded);
- the stub at the joint when severed;
- chunks appear on the client.

**Part C:**
- the bleed rate (2 open limbs → 1.66 ± 0.1 health/s), nothing with 1;
- drips and a pool under a bleeding body;
- a blast near a wall puts splats on it, stretched downward;
- a head blast in the chair puts splats on the observation glass;
- the caps;
- the splat base is Foil (as chosen, R17) and drawn as a disc or oval, not a rod.

**Human checks:** the look of the flesh, the chunks and the blood; the sounds; the phone emulator.

## Not in this version

- R15.
- Gore on non-player NPCs other than copies.
- Saving gore between sessions.
- Healing or bandages.
- New sounds (the user may add some to LabAssets.Blood later).
