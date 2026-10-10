# Gore follow-ups: aimed injections, instant deaths, cloth scraps, colliding limbs, no-bone legs

An addition to `2026-10-08-gore-system-design.md` (the "gore spec"). Everything there still holds unless this file says otherwise.
Approved section by section with the user on 2026-10-10 (sections 1-5, then 6-8 after their multiplayer tests).

## What the user asked for

1. No instant death after two limb explosions.
2. An injection damages only the injected limb: the other limbs, the torso and the head are untouched (no torso rip, no head
   change). Explosions outside an injection may still spread. A head showing its flesh variant (bone or no bone), or a
   ripped-open torso, kills instantly. Torn limbs keep some of their clothing, bloodied, so the flesh and cloth blend.
3. Dangling limbs collide with the ground (no clipping through it, also while crawling).
4. Both legs unable to hold the body (no-bone variant, broken or severed, in any mix) -> crawl. One alone -> still standing.

Cause of (1), found in the code: the Explosive is a radius blast (`Gore.explode`, power 150, radius 6) at the limb, so blowing
an arm also hits the torso with about 84, which tears it; a second injection destroys it, which kills. Fixing (2) fixes (1).

## 1. Aimed injections

- New `Gore.blastLimb(body, key, power)`: `Integrity.damageLimb(body, key, power, "explosion")` on that one limb only. No
  radius and no falloff. Because the cause is "explosion", the existing rolls all stay: SEVER_CHANCE for an arm or a leg,
  TORSO_OPEN_CHANCE for the torso, SKULL_BLAST_CHANCE for a destroyed head.
- The link copies the outcome to the partner as it does today (`damageLimb` applies one outcome to both linked bodies), so
  the Explosive blasts the copy's limb once and the owner gets the identical result.
- `HardDriveEffects.Explosive` (GORE_LEVEL 1 or 2) calls `Gore.blastLimb(copy, limbKey, EXPLOSIVE_POWER)` in place of
  `Gore.explode(...)`. The booms, blood, health loss (LIMB_DAMAGE) and level 0 path are unchanged.
- `Gore.explode` is unchanged and still used for every explosion that is not an injection (ExplosionReplacer and so on).
- This also removes the deferred Task 3 minor about explode's partner skip dropping the copy's own hit.

## 2. Instant deaths

- A body dies at once (through `Gore.hurt(body, health)`, so the big-hit watcher ignores it, the ragdoll, corpse, death
  screen and the lab's link death all run as for any gore death) when:
  - its head's state becomes Torn or worse (any flesh variant shows), or
  - its torso becomes open (`GoreTorsoOpen` turns true).
- A torn but sealed torso does not kill.
- Applies at GORE_LEVEL 1 and 2 (the states exist at both; at level 1 no flesh is drawn, but the rule is gameplay). Level 0
  is unchanged.
- Hooked as an `onStateChanged` listener (after Flesh, so the flesh is on the body as it dies). Both linked bodies get the same
  state, so both die.

## 3. Torn cloth scraps (GORE_LEVEL 2)

- When `Flesh.dress` dresses a limb (Torn or worse) and the body wears clothing covering that limb, it adds 3 to 5 scraps to
  the same `GoreFlesh` folder:
  - Shirt: the arms and the torso. Pants: the legs and the torso. The head never gets scraps. A bare limb gets none.
  - Each scrap is a small thin ragged part (a wedge or block, about 0.3-0.7 studs, 0.05 thick), clustered near the joint end
    of the limb (shoulder or hip; the torso's top and bottom edges), slightly outside the flesh, at random angles. Massless,
    non-colliding, welded to the R6 part like the flesh pieces.
  - Look: a `Texture` on its outward faces showing the ShirtTemplate or PantsTemplate image, offset so the patch comes from
    that limb's own region of the standard R6 clothing template (a left-arm scrap shows the left sleeve), tinted dark red
    (Texture.Color3 about RGB 150, 40, 40) over a dark red part, so it reads as blood-soaked fabric.
- Scraps are part of the dressed set, so they are rebuilt with it (Torn -> Broken), fly off with a severed limb and move into
  the corpse. The bone stub gets none.
- Made on the server, so everyone sees the same scraps. Positions are random per body; a linked copy gets its own (cosmetic).
- No clothing, or a template that cannot be read: no scraps; the flesh is unaffected (the existing "missing pieces never
  hide the limb" rule holds).

## 4. Dangling limbs collide

- When a limb loosens (Broken), Ragdoll gives it a `GoreCollider`: an invisible (Transparency 1), CanCollide part the size of
  the limb, welded to it, CanQuery and CanTouch off, Massless.
- It gets the same no-collide pairs with its own body that the dangling limb already gets, so it never snags on the body.
- Needed because the Humanoid keeps switching CanCollide off on its own character's limbs.
- It goes where the limb goes (into the corpse; off with it if later severed).

## 5. No-bone legs

- A leg is **unsupporting** when it is Broken or Severed, or Torn with `GoreVariant_<Leg> == 1` (Variant1, flesh with no bone).
- One unsupporting leg: limp (LIMP_SPEED, no jumping), as a broken leg does today.
- Both unsupporting, in any mix: `GoreDowned` and the crawl, as two broken legs do today.
- Variant2 legs (with bone) and Intact legs support. The no-bone leg variants stay in the game.

## 6. External damage lands where it hit (added 2026-10-10 after the user's multiplayer tests)

There are two kinds of damage:
- **Internal:** the game's own mechanic, Bob's injections. They hit only the injected limb (section 1).
- **External:** everything else (weapons, explosions, falls, scripts). Covered by sections 6-8.

Causes found in the code:
- A weapon's `Humanoid:TakeDamage` only tells the server "health dropped by N", not where. So the big-hit watcher picks a
  random limb, and only for drops of 30 or more.
- Resetting drops health to 0, which counts as a 100 hit, so a random limb tears.

### `Gore.hit(part, damage)`
New and server-only, for the user's own weapons, called in place of `TakeDamage`:
- `part` is the exact part hit. An accessory's Handle, or any part welded under a limb, is traced back to that limb. A part
  not on a tracked body does nothing.
- The body loses `damage` health through `Gore.hurt`, so the watcher does not count it twice. A body that is already dead
  loses no health; a corpse still takes the limb damage.
- That limb, and only that limb, takes `damage * HIT_SCALE` integrity, with cause "hit".
- RECOVERY.md documents it with a server example (raycast and Touched). It also says never to call TakeDamage as well, and
  that a client weapon must go through a RemoteEvent the server validates.

### Unknown hits
These are any other health drop not made by the gore system. The limb is chosen in this order:
1. During or just after a fall (the existing window): both legs, as today.
2. Otherwise, the limb most recently touched (within 0.2 s) by a part that is not anchored, not grounded and not part of the
   same body. This catches projectiles, thrown things and another character's held tool.
3. Otherwise, the Torso.

The limb is never random. There is no minimum any more: every drop counts, so BIG_HIT is removed.

### Toughness ("Tough", the user's choice)
- New GoreConfig `HIT_SCALE = 0.5`, so a limb loses half the damage.
- A 30-damage hit takes 15: flesh shows on the 3rd hit and the limb breaks around the 7th.
- A 100-damage sniper hit takes 50, which tears the limb in one.
- Falls use it too.

### Severing
Only explosions roll SEVER_CHANCE. A hit that breaks a limb leaves it Broken (dangling); a hit never drops a limb off plain.

### Reset
- A client script sets `StarterGui:SetCore("ResetButtonCallback", ...)` to fire a RemoteEvent.
- The server kills that player's own living character through `Gore.hurt`, with no limb damage.
- The ragdoll and death screen run as usual.
- The server only acts on the sender's own character, and only while it is alive.

### Dead bodies
`Gore.hit` and explosions still damage a corpse's limbs: flesh, dangling, and severing by explosions. There is no health to
take.

## 7. Explosions (external)

`ExplosionReplacer` already adds the user's boom to every server Explosion. Now, the moment one is added, it also:
- Sets its `DestroyJointRadiusPercent` to 0, so Roblox never snaps joints: no plain limbs flying, no head knocked off.
- Runs `Gore.explode(position, power, BlastRadius)`, with `power = EXPLOSIVE_POWER * clamp(BlastPressure / 500000, 0.3, 2)`.
  Limbs near it tear, show flesh, break, or sever by chance, with chunks and spray.
- Keeps the kill Roblox would have done. A living body whose Torso is within `BlastRadius * DestroyJointRadiusPercent` (the
  maker's original value) dies through `Gore.hurt`. Other bodies take only the limb damage, plus whatever the maker's own
  `Explosion.Hit` handler does.
- Leaves its BlastPressure physics alone, so bodies are still shoved.

After the blast:
- Death from a blast always ragdolls (the gore death).
- Right after, the corpse's parts get a push away from the blast, and so does every other corpse within the radius. The push
  is a velocity of `BLAST_PUSH * (1 - d / radius)`, with a new GoreConfig `BLAST_PUSH = 60` (tuned by eye). So whole
  ragdolls are thrown, not limbs.
- Corpses take the blast's limb damage too.
- Bob's injections stay aimed (section 1) and never make an Explosion.

## 8. Blood on every external hit

- Every external hit sets the attribute `GoreHit` on the body. That covers `Gore.hit`, an unknown hit, an explosion's limb
  hit and a fall.
- The value is `"<Limb>|<damage>|<n>"`. `n` counts up, so two equal hits still change the attribute.
- GoreClient watches `GoreHit` on every GoreBody and spurts blood from that limb, aimed away from the body, sized by damage:

  | Damage | Blood |
  |---|---|
  | under 20 | a small puff and a drip |
  | 20-60 | a short spray and a splat |
  | over 60 | a full Task 8 spray with splats |

- The same splat cap, timers and gore-level rules apply. Level 0 gets a small plain spurt and no splats.
- No new RemoteEvent: attributes replicate to every player.
- Bob's injections keep their own blood burst and do not set `GoreHit`.
- Parked for the user's next update, not built now: new bleeding particles based on the user's YouTube reference
  (https://www.youtube.com/watch?v=c92Al_PPr7M).

## Testing

- Aimed injection: an arm injection leaves the torso, head and other limbs at 100 integrity and Intact; the copy and owner
  match. `Gore.explode` still spreads to nearby limbs.
- Instant death: a head damaged to Torn dies at once; a torso opened (TORSO_OPEN_CHANCE forced to 1) dies at once; a torn
  sealed torso (chance 0) lives; level 0 unchanged.
- Two arm injections: the body lives (bleeding aside).
- Scraps: a clothed torn arm has 3-5 scraps near the shoulder with the Shirt image and the tint; a bare arm has none; scraps
  leave with a severed arm; level 1 has none.
- Collider: a dangling arm of a body lying on the floor rests on the floor, not inside it.
- Legs: one Variant1 torn leg limps and does not crawl; two Variant1 legs, or Variant1 + Broken, are downed; a Variant2 leg
  alone changes nothing.
- Gore.hit:
  - 30-damage hits on a torso part leave the torso Intact, then Intact, then Torn; no other limb changes.
  - An accessory Handle maps to its limb.
  - Health drops by exactly the damage.
  - A corpse's limb still takes the damage.
- Unknown hits: a TakeDamage with a projectile touching the left leg damages the left leg. With nothing touching, the Torso.
- Reset: no limb changes state, and the body ragdolls.
- Explosions: a default Roblox Explosion next to a body:
  - leaves every Motor6D or socket in place (no plain flung limbs);
  - tears the nearest limbs;
  - kills a body inside the maker's joint radius and ragdolls it;
  - pushes its corpse away.
- Blood: an external hit sets GoreHit, and the client spurts from that limb.
- Update the existing tests that assumed:
  - the radius blast for injections (lab_gore, lab_inject);
  - the big-hit watcher's random limb and 30 minimum (gore_integrity).

## Out of scope

- The flake where Health 0 sometimes never fires Died (a known Task 2 issue) stays for the final review.
