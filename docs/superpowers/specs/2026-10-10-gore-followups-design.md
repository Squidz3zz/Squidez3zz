# Gore follow-ups: aimed injections, instant deaths, cloth scraps, colliding limbs, no-bone legs

An addition to `2026-10-08-gore-system-design.md` (the "gore spec"). Everything there still holds unless this file says otherwise.
Approved section by section with the user on 2026-10-10.

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
- The existing gore, lab and boom tests are updated where they assumed the radius blast (lab_gore, lab_inject).

## Out of scope

- The flake where Health 0 sometimes never fires Died (a known Task 2 issue) stays for the final review.
