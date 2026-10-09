-- Gore: the gore system's server side, and the one way other server scripts reach it (require ServerScriptService.Gore). It
-- keeps score of every tracked body's limbs and publishes it on the body as attributes, which every player's client reads:
--   Gore_<Limb>         the limb's state: "Intact", "Torn" (an open wound), "Broken" (an arm or a leg; it dangles), "Severed"
--                       (an arm or a leg; ripped off) or "Destroyed" (the head or the torso; fatal). States only move forward.
--   GoreHP_<Limb>       its integrity: 100 when whole; damage takes it down, past 0 too (it is not stopped at 0)
--   GoreVariant_<Limb>  which of the two flesh variants (1 or 2) the limb shows, picked when it first stops being Intact
--   GoreTorsoOpen       false while the torso is whole or sealed, true once it is ripped open
--   GoreSkull           only once the head is destroyed: "blasted" (blown apart) or "shown"
--   GoreDowned          true once both legs are Broken or Severed (the body is downed and crawls)
--   GoreDiedAt          the server time (workspace:GetServerTimeNow()) the body died; corpses carry it
--   GoreOwner           on a corpse: the UserId of the player whose character it was (Room 1's copy carries its owner's,
--                       which its corpse keeps)
-- <Limb> is each of LabConfig.LIMB_KEYS (Head, Torso, LeftArm, RightArm, LeftLeg, RightLeg). Tracked bodies carry the
-- CollectionService tag GoreBody. The numbers (when a limb tears, the chances, the blast) are GoreConfig's.
-- What happens to the body itself (Ragdoll, inside Gore, says how):
--   a limb turning Broken dangles: its Motor6D becomes a BallSocketConstraint;
--   a limb turning Severed is ripped off and flung, and goes after LabConfig.LOST_LIMB_SECONDS (one that copyState brings is
--   simply removed: the copy arrives without it);
--   one leg Broken or Severed: WalkSpeed GoreConfig LIMP_SPEED, no jumping; both: GoreDowned (each player's GoreClient makes
--   its own downed character crawl);
--   on death the body ragdolls and its parts move into a corpse in Workspace.Corpses, which stays tracked (blasts still tear
--   it) and goes after GoreConfig CORPSE_LIFE, at most CORPSES_PER_PLAYER per player.
-- And what it looks like (Flesh, inside Gore, says how; GoreConfig GORE_LEVEL 2 only):
--   a limb turning Torn (or worse) is hidden and wears its flesh (ServerStorage.Gore.Pieces): its variant, the sealed torso
--   (the open one, with the ribcage, once GoreTorsoOpen), the destroyed head with or without its skull;
--   a limb turning Severed flies off wearing its flesh, and its bone stub goes on the torso (at level 1, a plain stump).
--
--   Gore.track(body)                    starts tracking an R6 body: every limb Intact at 100, GoreTorsoOpen false (a body
--                                       already tracked keeps what it has), the GoreBody tag, Humanoid.BreakJointsOnDeath off,
--                                       the death ragdoll, and the big-hit watcher: one drop of GoreConfig.BIG_HIT health or
--                                       more, made by anything but Gore.hurt, damages a random limb (not a severed one) by twice
--                                       the health lost ("hit"), or both legs by the health lost each when the humanoid was in
--                                       Freefall within the last 0.5 s ("fall"). ServerScriptService.GoreServer tracks every
--                                       player's character as it spawns.
--   Gore.link(a, b), Gore.unlink(body)  links two bodies (a player's character and their copy) so every gore change on
--                                       either is decided once and lands identically on both; unlink (or destroying either
--                                       body) ends it. The change is worked out on the body it happens to and copied onto the
--                                       other, so the two must match first (copyState, then link). A linked body that dies
--                                       hands its link to its corpse.
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
--   Gore.copyState(from, to)            tracks `to` (as track does) and gives it all of `from`'s gore (states, integrity,
--                                       variants, the torso and the skull), with "copy" as the cause.
--   Gore.onStateChanged(fn)             fn(body, key, old, new, info) runs, in order, whenever a limb's state changes on a
--                                       body (each linked body gets its own call), and when a torn torso rips open (then old
--                                       and new are both "Torn"). info: cause; severed = true when it was severed;
--                                       torsoOpened = true when the torso opened just now; skullBlasted = true or false when
--                                       the head was destroyed just now. A listener that fails warns once and the rest still
--                                       run.
--   Gore.seed(n)                        Studio only (nil in the live game): reseeds the Random behind every chance roll, so
--                                       a test's rolls repeat.
-- A script that requires Gore from Studio's command bar (or a test) gets its own copy: its own Random, links, listeners,
-- big-hit watchers and death watchers. Tests reach the game's copy through ServerScriptService.GoreServer.TestHook.
local RunService = game:GetService("RunService")

-- Every load-time wait has a timeout and fails loudly, so a missing piece fails the require (and its callers fall back)
-- instead of hanging them.
local Integrity = require(script:WaitForChild("Integrity", 5) or error("Gore: Integrity is missing"))
local Ragdoll = require(script:WaitForChild("Ragdoll", 5) or error("Gore: Ragdoll is missing"))
local Flesh = require(script:WaitForChild("Flesh", 5) or error("Gore: Flesh is missing"))

-- Flesh first, while the limb is still on its joint (the stub goes where the joint was). Its own listener, so a failure there
-- (no Pieces) still leaves limbs dangling and coming off.
Integrity.onStateChanged(function(body, key, _old, new)
	Flesh.dress(body, key)
	if new == "Severed" then
		Flesh.stub(body, key)
	end
end)

Integrity.onStateChanged(function(body, key, _old, new, info)
	if new == "Broken" then
		Ragdoll.loosen(body, key)
	elseif new == "Severed" then
		-- copyState builds a body already missing the limb: nothing is flung.
		Ragdoll.sever(body, key, info.cause == "copy")
	end
end)

local function track(body: Model)
	Integrity.track(body)
	Ragdoll.watch(body)
end

return {
	track = track,
	link = Integrity.link,
	unlink = Integrity.unlink,
	damageLimb = Integrity.damageLimb,
	explode = Integrity.explode,
	hurt = Integrity.hurt,
	stateOf = Integrity.stateOf,
	integrityOf = Integrity.integrityOf,
	copyState = function(from: Model, to: Model)
		Integrity.copyState(from, to)
		Ragdoll.watch(to)
	end,
	onStateChanged = Integrity.onStateChanged,
	seed = if RunService:IsStudio() then Integrity.seed else nil,
}
