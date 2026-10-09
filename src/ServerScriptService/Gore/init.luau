-- Gore: the gore system's server side, and the one way other server scripts reach it (require ServerScriptService.Gore). It
-- keeps score of every tracked body's limbs and publishes it on the body as attributes, which every player's client reads:
--   Gore_<Limb>         the limb's state: "Intact", "Torn" (an open wound), "Broken" (an arm or a leg; it dangles), "Severed"
--                       (an arm or a leg; ripped off) or "Destroyed" (the head or the torso; fatal). States only move forward.
--   GoreHP_<Limb>       its integrity: 100 when whole; damage takes it down, past 0 too (it is not stopped at 0)
--   GoreVariant_<Limb>  which of the two flesh variants (1 or 2) the limb shows, picked when it first stops being Intact
--   GoreTorsoOpen       false while the torso is whole or sealed, true once it is ripped open
--   GoreSkull           only once the head is destroyed: "blasted" (blown apart) or "shown"
-- <Limb> is each of LabConfig.LIMB_KEYS (Head, Torso, LeftArm, RightArm, LeftLeg, RightLeg). Tracked bodies carry the
-- CollectionService tag GoreBody. The numbers (when a limb tears, the chances, the blast) are GoreConfig's.
--
--   Gore.track(body)                    starts tracking an R6 body: every limb Intact at 100, GoreTorsoOpen false (a body
--                                       already tracked keeps what it has), the GoreBody tag, Humanoid.BreakJointsOnDeath off,
--                                       and the big-hit watcher: one drop of GoreConfig.BIG_HIT health or more, made by
--                                       anything but Gore.hurt, damages a random limb (not a severed one) by twice the health
--                                       lost ("hit"), or both legs by the health lost each when the humanoid was in Freefall
--                                       within the last 0.5 s ("fall").
--   Gore.link(a, b), Gore.unlink(body)  links two bodies (a player's character and their copy) so every gore change on
--                                       either is decided once and lands identically on both; unlink (or destroying either
--                                       body) ends it.
--   Gore.damageLimb(body, key, amount, cause)
--                                       the one way limbs are damaged. cause is "explosion", "hit", "fall" or a future name;
--                                       only "explosion" can sever an arm or a leg or open the torso. Ignored for an untracked
--                                       body, an unknown limb, an amount that is not above 0, or a Severed or Destroyed limb.
--   Gore.explode(position, power, radius)
--                                       damages every limb of every tracked body (corpses too) whose centre is within radius,
--                                       by power * (1 - distance / radius)^2, as "explosion".
--   Gore.hurt(body, amount)             takes health from the body as gore damage, which the big-hit watcher ignores. Any
--                                       health the gore system or the lab takes should go through this.
--   Gore.stateOf(body, key), Gore.integrityOf(body, key)
--                                       the limb's state and integrity, or nil when the body is not tracked.
--   Gore.copyState(from, to)            tracks `to` and gives it all of `from`'s gore (states, integrity, variants, the
--                                       torso and the skull), with "copy" as the cause.
--   Gore.onStateChanged(fn)             fn(body, key, old, new, info) runs, in order, whenever a limb's state changes on a
--                                       body (each linked body gets its own call), and when a torn torso rips open (then old
--                                       and new are both "Torn"). info: cause; severed = true when it was severed;
--                                       torsoOpened = true when the torso opened just now; skullBlasted = true or false when
--                                       the head was destroyed just now. A listener that fails warns once and the rest still
--                                       run.
--   Gore.seed(n)                        Studio only (nil in the live game): reseeds the Random behind every chance roll, so
--                                       a test's rolls repeat.
-- A script that requires Gore from Studio's command bar (or a test) gets its own copy: its own Random, links, listeners and
-- big-hit watchers. Tests reach the game's copy through ServerScriptService.GoreServer.TestHook.
local RunService = game:GetService("RunService")

local Integrity = require(script:WaitForChild("Integrity"))

return {
	track = Integrity.track,
	link = Integrity.link,
	unlink = Integrity.unlink,
	damageLimb = Integrity.damageLimb,
	explode = Integrity.explode,
	hurt = Integrity.hurt,
	stateOf = Integrity.stateOf,
	integrityOf = Integrity.integrityOf,
	copyState = Integrity.copyState,
	onStateChanged = Integrity.onStateChanged,
	seed = if RunService:IsStudio() then Integrity.seed else nil,
}
