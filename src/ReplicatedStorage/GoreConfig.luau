-- GoreConfig: the one place to edit the gore system: how much a limb takes before it tears or breaks, the chances of a limb
-- ripping off, the torso opening and the skull blowing apart, how hard blasts and big hits are, how broken legs slow a body
-- down, how long corpses, pools and splats of blood stay, and how gory the game is (GORE_LEVEL). It lives in ReplicatedStorage
-- because both sides read it: the server (the damage rules, broken limbs, corpses and bleeding, in ServerScriptService.Gore)
-- and every player's client (the skin chunks, drips, pools, spray and splats).
--
-- Every limb (the head, the torso, both arms and both legs) starts with 100 integrity, and damage takes it down. Integrity is
-- not health: a body's health only drops when its head or torso is destroyed, or from bleeding.
--   TORN_AT             at this integrity or below, a limb is Torn: an open wound that shows the flesh. At 0 or below an arm or
--                       a leg is Broken (it dangles) and the head or the torso is Destroyed (that kills).
--   SEVER_CHANCE        the chance (0 to 1) that an explosion which breaks an arm or a leg rips it off instead (Severed). A
--                       broken arm or leg hit by another explosion rolls again. Other damage (a hit, a fall) never rips one off.
--   TORSO_OPEN_CHANCE   a torn torso stays sealed; each time an explosion damages it and leaves it torn, this is the chance it
--                       rips open (the ribcage shows). A destroyed torso is always open. Legs never open it.
--   SKULL_BLAST_CHANCE  when the head is destroyed, the chance the skull is blown apart too (only flesh is left) instead of
--                       showing.
--
-- Damage to limbs (integrity):
--   EXPLOSIVE_POWER     what Room 1's Explosive does to a limb right at the centre of its blast.
--   BLAST_RADIUS        how far (studs) a blast reaches. A limb whose centre is d studs from the blast takes
--                       power * (1 - d / radius)^2: with 150 and 6 that is 150 at 0 studs, about 84 at 1.5 and 37.5 at 3, so the
--                       injected limb always breaks and the torso next to it tears.
--   BIG_HIT             one drop of health this big or bigger, from anything except the gore system itself, also hurts a limb
--                       by twice the health lost: one random limb, or both legs (half each) when the body was falling.
--
-- Broken legs:
--   LIMP_SPEED          walk speed (studs per second) with one leg broken or gone; no jumping.
--   CRAWL_SPEED         with both legs broken or gone the body falls down and drags itself along at this speed.
--
-- Corpses (every death leaves one):
--   CORPSE_LIFE         seconds a corpse lies there before it sinks away.
--   CORPSES_PER_PLAYER  at most this many corpses per player; the oldest goes first.
--
-- Blood:
--   BLEED_PER_OPEN_LIMB health lost per second for each open limb (torn, broken or severed), from two open limbs up: with two
--                       that is death in about a minute.
--   DRIP_AFTER_DEATH    seconds open limbs keep dripping after death.
--   POOL_MAX            how wide (studs) a pool of blood under a body can grow.
--   SPLAT_LIFE          seconds a splat of blood stays on a floor, a wall or the glass.
--   SPLAT_MAX           at most this many splats at once (on each player's screen); the oldest goes first.
--
-- Skin chunks (when a limb tears):
--   CHUNKS_MIN, CHUNKS_MAX  how many chunks of skin burst off (a random number from one to the other).
--   CHUNK_REST              seconds they lie still before they fade out.
--
-- GORE_LEVEL: how gory the whole game is, as one number.
--   2  everything: flesh and bone, skin chunks, dangling and ripped-off limbs, bleeding and blood.
--   1  blood, bleeding, dangling and ripped-off limbs, but no flesh, bone or skin chunks (a ripped-off limb leaves a plain
--      stump).
--   0  the simple version from before: an exploded limb just drops off, simple blood, no bleeding.
--   Every level keeps the ragdolls and the corpses. Heavy blood is only allowed in 17+ experiences, and Roblox may still
--   remove extreme gore: check Roblox's current rules before you publish, and turn this down if you need to.
--
-- GoreConfig.get(name) is how every gore script reads these. In Studio only, an attribute with the same name on this
-- ModuleScript (select it, then Properties -> Attributes) wins over the value written here, so you or a test can try another
-- value during a playtest without editing this file. The tests remove theirs when they finish. In the live game attributes are
-- ignored: only the values below count.
local RunService = game:GetService("RunService")

local GoreConfig = {
	GORE_LEVEL = 2,

	TORN_AT = 60,
	SEVER_CHANCE = 0.25,
	TORSO_OPEN_CHANCE = 0.35,
	SKULL_BLAST_CHANCE = 0.4,

	EXPLOSIVE_POWER = 150,
	BLAST_RADIUS = 6,
	BIG_HIT = 30,

	LIMP_SPEED = 8,
	CRAWL_SPEED = 3,

	CORPSE_LIFE = 120,
	CORPSES_PER_PLAYER = 4,

	BLEED_PER_OPEN_LIMB = 0.83,
	DRIP_AFTER_DEATH = 30,
	POOL_MAX = 4,
	SPLAT_LIFE = 90,
	SPLAT_MAX = 150,

	CHUNKS_MIN = 6,
	CHUNKS_MAX = 10,
	CHUNK_REST = 5,
}

local studio = RunService:IsStudio()

function GoreConfig.get(name: string): any
	if studio then
		local override = script:GetAttribute(name)
		if override ~= nil then
			return override
		end
	end
	return GoreConfig[name]
end

return GoreConfig
