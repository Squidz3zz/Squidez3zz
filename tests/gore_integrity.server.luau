-- Run in the Server datamodel of a running playtest (no character needed): start the playtest, then run this.
-- Checks ReplicatedStorage.GoreConfig (its values and the Studio override) and the gore system's integrity core
-- (ServerScriptService.Gore and its Integrity) on R6 bodies built here: 30 studs apart, far from the rooms (x 2030 and up,
-- y 300, z 2000), anchored unless a case needs one to fall. A test that requires Gore gets its own copy of the module, so
-- every case drives the game's own Gore through ServerScriptService.GoreServer.TestHook ("call", fnName, ...): the seeding,
-- the link and the hurt marks are the game's. Only the onStateChanged check in I-A uses this test's own copy (a function
-- cannot go through the hook).
--   I-A thresholds  39 damage leaves an arm Intact (61), 1 more tears it (60), 60 more breaks it (0); "hit" never severs and
--                   integrity goes below 0; a torso at 0 is Destroyed (and open), Health 0, and that death is no big hit
--   I-B falloff     one blast at a left arm's centre: 150 to it (0 studs), 84.4 to the torso (1.5), 37.5 to the right arm (3)
--   I-C sever       a 150 explosion on an arm: Severed with HIT_SEED, Broken with MISS_SEED, the same again on a repeat; a
--                   Broken arm hit by another explosion rolls again; a Severed one takes no more damage
--   I-D torso       a torn torso hit by a blast opens with HIT_SEED and stays sealed with MISS_SEED; "hit" never opens it;
--                   severed legs leave it alone
--   I-E skull       a destroyed head: "blasted" with HIT_SEED, "shown" with MISS_SEED
--   I-F link        a blast at a's left arm lands identically on b (states, integrity, variants, torso, skull), the link
--                   works both ways, and unlink stops it
--   I-G copyState   a fresh body takes on every Gore attribute of a damaged one
--   I-H big hits    a 30-health drop not made by Gore.hurt damages one limb by 60; the same drop while falling (Freefall)
--                   takes 30 from each leg, and so does one right after landing (Freefall ended under 0.5 s ago), on a
--                   body dropped onto a floor of its own; on that body, a drop more than 0.5 s after landing is one hit of
--                   60 again; Gore.hurt(b, 40) damages no limb
-- It removes its bodies at the end and returns "PASS gore_integrity".
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- The fixed outcome table for the seeded cases. Each chance (sever, torso open, skull blast) is the first roll its case
-- makes, so one seed lands all three (its first roll is below 0.25) and another misses all three (at 0.4 or above).
local HIT_SEED = 3
local MISS_SEED = 1

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local LIMB_KEYS = LabConfig.LIMB_KEYS

-- GoreConfig: every value, read directly and through get(), and the Studio override (an attribute on the module).
local configModule = ReplicatedStorage:FindFirstChild("GoreConfig")
assert(configModule and configModule:IsA("ModuleScript"), "ReplicatedStorage.GoreConfig is missing")
local GoreConfig = require(configModule)
local VALUES = {
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
for name, value in VALUES do
	assert(GoreConfig[name] == value, ("GoreConfig.%s is %s, expected %s"):format(name, tostring(GoreConfig[name]), tostring(value)))
	assert(GoreConfig.get(name) == value, ("GoreConfig.get(%q) is %s (an override left on the module?)"):format(name, tostring(GoreConfig.get(name))))
end
configModule:SetAttribute("TORN_AT", 10)
local overridden = GoreConfig.get("TORN_AT")
configModule:SetAttribute("TORN_AT", nil)
assert(overridden == 10, "GoreConfig.get should return the module's attribute in Studio, got " .. tostring(overridden))
assert(GoreConfig.get("TORN_AT") == 60, "GoreConfig.get should fall back to the table once the attribute is gone")

local server = ServerScriptService:FindFirstChild("GoreServer")
local hook = server and server:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

local old = workspace:FindFirstChild("GoreIntegrityTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreIntegrityTest"
folder.Parent = workspace

local count = 0
-- A fresh R6 body at its own spot, tracked by the game's Gore. free: not anchored (it falls).
local function newBody(free: boolean?): Model
	count += 1
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = "Body" .. count
	body.HumanoidRootPart.Anchored = not free
	body:PivotTo(CFrame.new(2000 + 30 * count, 300, 2000))
	body.Parent = folder
	gore("track", body)
	return body
end

local function state(body: Model, key: string): any
	return body:GetAttribute("Gore_" .. key)
end

local function hp(body: Model, key: string): any
	return body:GetAttribute("GoreHP_" .. key)
end

local function expect(body: Model, key: string, wantState: string, wantHp: number?, label: string)
	assert(state(body, key) == wantState, ("%s: %s is %s, expected %s"):format(label, key, tostring(state(body, key)), wantState))
	if wantHp then
		local got = hp(body, key)
		assert(type(got) == "number" and math.abs(got - wantHp) < 1e-6, ("%s: %s integrity is %s, expected %s"):format(label, key, tostring(got), tostring(wantHp)))
	end
end

local function untouched(body: Model, keys: { string }, label: string)
	for _, key in keys do
		expect(body, key, "Intact", 100, label)
	end
end

-- Waits (at most `timeout` seconds) for check() to be true; returns whether it became true.
local function waitFor(check: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not check() do
		if os.clock() > deadline then
			return false
		end
		task.wait()
	end
	return true
end

-- I-A thresholds.
do
	local b = newBody()
	untouched(b, LIMB_KEYS, "I-A track")
	assert(b:GetAttribute("GoreTorsoOpen") == false, "I-A: track should set GoreTorsoOpen false")
	assert(CollectionService:HasTag(b, "GoreBody"), "I-A: track should tag the body GoreBody")
	assert(b.Humanoid.BreakJointsOnDeath == false, "I-A: track should set BreakJointsOnDeath false")

	gore("damageLimb", b, "LeftArm", 39, "hit")
	expect(b, "LeftArm", "Intact", 61, "I-A 39")
	gore("damageLimb", b, "LeftArm", 1, "hit")
	expect(b, "LeftArm", "Torn", 60, "I-A +1")
	local variant = b:GetAttribute("GoreVariant_LeftArm")
	assert(variant == 1 or variant == 2, "I-A: a torn limb should get GoreVariant 1 or 2, got " .. tostring(variant))
	gore("damageLimb", b, "LeftArm", 60, "hit")
	expect(b, "LeftArm", "Broken", 0, "I-A +60")
	for _ = 1, 20 do
		gore("damageLimb", b, "LeftArm", 10, "hit")
	end
	expect(b, "LeftArm", "Broken", -200, "I-A 20 more hits (never severs, not clamped)")
	assert(b:GetAttribute("GoreVariant_LeftArm") == variant, "I-A: the variant changed after it was picked")
	assert(gore("stateOf", b, "LeftArm") == "Broken", "I-A: stateOf disagrees with the attribute")
	assert(gore("integrityOf", b, "LeftArm") == -200, "I-A: integrityOf disagrees with the attribute")
	assert(gore("stateOf", b, "Tail") == nil, "I-A: stateOf an unknown limb should be nil")

	gore("damageLimb", b, "Torso", 100, "hit")
	expect(b, "Torso", "Destroyed", 0, "I-A torso")
	assert(b:GetAttribute("GoreTorsoOpen") == true, "I-A: a destroyed torso should be open")
	assert(b.Humanoid.Health == 0, "I-A: a destroyed torso should leave Health 0, got " .. b.Humanoid.Health)
	task.wait(0.3)
	untouched(b, { "Head", "RightArm", "LeftLeg", "RightLeg" }, "I-A (the gore death is no big hit)")

	-- onStateChanged, through this test's own copy of Gore (it changes the same attributes).
	local Own = require(ServerScriptService:FindFirstChild("Gore"))
	local e = newBody()
	local events = {}
	Own.onStateChanged(function(body, key, from, to, info)
		if body == e then
			table.insert(events, { key = key, from = from, to = to, info = info })
		end
	end)
	Own.damageLimb(e, "RightArm", 50, "hit")
	Own.damageLimb(e, "RightArm", 1, "hit")
	assert(#events == 1, "I-A: expected one onStateChanged call, got " .. #events)
	local event = events[1]
	assert(event.key == "RightArm" and event.from == "Intact" and event.to == "Torn", "I-A: onStateChanged got the wrong change")
	assert(event.info.cause == "hit" and not event.info.severed, "I-A: onStateChanged got the wrong info")
end

-- I-B explosion falloff.
do
	local b = newBody()
	local far = newBody()
	local centre = b["Left Arm"].Position
	local distance = {}
	for _, key in LIMB_KEYS do
		distance[key] = (LabConfig.limbParts(b, key)[1].Position - centre).Magnitude
	end
	gore("explode", centre, 150, 6)
	for key, want in { LeftArm = 150, Torso = 84.4, RightArm = 37.5 } do
		local took = 100 - hp(b, key)
		assert(math.abs(took - want) <= 0.5, ("I-B: %s took %.2f, expected %.1f"):format(key, took, want))
	end
	for _, key in LIMB_KEYS do
		local d = distance[key]
		local want = if d < 6 then 150 * (1 - d / 6) ^ 2 else 0
		local took = 100 - hp(b, key)
		assert(math.abs(took - want) < 0.01, ("I-B: %s at %.2f studs took %.2f, expected %.2f"):format(key, d, took, want))
	end
	expect(b, "Torso", "Torn", nil, "I-B")
	untouched(far, LIMB_KEYS, "I-B (a body 30 studs away)")
end

-- I-C sever, seeded both ways.
do
	for _, outcome in { { seed = HIT_SEED, state = "Severed" }, { seed = MISS_SEED, state = "Broken" } } do
		local first, again = newBody(), newBody()
		for _, b in { first, again } do
			gore("seed", outcome.seed)
			gore("damageLimb", b, "LeftArm", 150, "explosion")
			expect(b, "LeftArm", outcome.state, -50, "I-C seed " .. outcome.seed)
		end
		assert(
			first:GetAttribute("GoreVariant_LeftArm") == again:GetAttribute("GoreVariant_LeftArm"),
			"I-C: repeating seed " .. outcome.seed .. " picked another variant"
		)
	end
	local b = newBody()
	gore("seed", MISS_SEED)
	gore("damageLimb", b, "LeftArm", 150, "explosion")
	expect(b, "LeftArm", "Broken", -50, "I-C broken first")
	gore("seed", HIT_SEED)
	gore("damageLimb", b, "LeftArm", 10, "explosion")
	expect(b, "LeftArm", "Severed", -60, "I-C a broken arm blasted again")
	gore("damageLimb", b, "LeftArm", 10, "explosion")
	expect(b, "LeftArm", "Severed", -60, "I-C a severed arm takes no damage")
end

-- I-D torso.
do
	for _, outcome in { { seed = HIT_SEED, open = true }, { seed = MISS_SEED, open = false } } do
		local b = newBody()
		gore("damageLimb", b, "Torso", 50, "hit")
		expect(b, "Torso", "Torn", 50, "I-D")
		assert(b:GetAttribute("GoreTorsoOpen") == false, "I-D: a hit opened the torso")
		gore("seed", outcome.seed)
		-- 4 studs in front of the torso: about 17 to it (it stays torn), and too little to tear anything else.
		gore("explode", b.Torso.Position + b.Torso.CFrame.LookVector * 4, 150, 6)
		expect(b, "Torso", "Torn", nil, "I-D after the blast")
		assert(
			b:GetAttribute("GoreTorsoOpen") == outcome.open,
			("I-D: seed %d should leave the torso %s"):format(outcome.seed, if outcome.open then "open" else "sealed")
		)
	end
	local b = newBody()
	gore("damageLimb", b, "Torso", 50, "hit")
	for _, seed in { HIT_SEED, MISS_SEED } do
		gore("seed", seed)
		gore("damageLimb", b, "Torso", 5, "hit")
	end
	assert(b:GetAttribute("GoreTorsoOpen") == false, "I-D: damageLimb with cause hit opened the torso")
	local legs = newBody()
	for _, key in { "LeftLeg", "RightLeg" } do
		gore("seed", HIT_SEED)
		gore("damageLimb", legs, key, 150, "explosion")
		expect(legs, key, "Severed", -50, "I-D legs")
	end
	expect(legs, "Torso", "Intact", 100, "I-D severed legs")
	assert(legs:GetAttribute("GoreTorsoOpen") == false, "I-D: severed legs set GoreTorsoOpen")
end

-- I-E skull.
do
	for _, outcome in { { seed = HIT_SEED, skull = "blasted" }, { seed = MISS_SEED, skull = "shown" } } do
		local b = newBody()
		gore("seed", outcome.seed)
		gore("damageLimb", b, "Head", 100, "hit")
		expect(b, "Head", "Destroyed", 0, "I-E")
		assert(b:GetAttribute("GoreSkull") == outcome.skull, ("I-E: seed %d gave GoreSkull %s, expected %s"):format(outcome.seed, tostring(b:GetAttribute("GoreSkull")), outcome.skull))
		assert(b.Humanoid.Health == 0, "I-E: a destroyed head should leave Health 0")
	end
end

-- I-F link, and I-G copyState from the damaged body.
do
	local a, b = newBody(), newBody()
	local function same(label: string)
		for _, key in LIMB_KEYS do
			for _, prefix in { "Gore_", "GoreHP_", "GoreVariant_" } do
				local name = prefix .. key
				assert(a:GetAttribute(name) == b:GetAttribute(name), ("%s: %s is %s on a, %s on b"):format(label, name, tostring(a:GetAttribute(name)), tostring(b:GetAttribute(name))))
			end
		end
		for _, name in { "GoreTorsoOpen", "GoreSkull" } do
			assert(a:GetAttribute(name) == b:GetAttribute(name), ("%s: %s differs"):format(label, name))
		end
	end
	gore("link", a, b)
	gore("seed", HIT_SEED)
	gore("explode", a["Left Arm"].Position, 150, 6)
	assert(state(a, "LeftArm") == "Broken" or state(a, "LeftArm") == "Severed", "I-F: the blast should break or sever a's arm")
	expect(a, "Torso", "Torn", nil, "I-F")
	same("I-F explode")
	gore("damageLimb", b, "RightArm", 30, "hit")
	same("I-F a hit on b")
	gore("unlink", a)
	gore("damageLimb", a, "RightLeg", 1, "hit")
	assert(hp(b, "RightLeg") == hp(a, "RightLeg") + 1, "I-F: unlink should stop the link")

	local c = newBody()
	gore("copyState", a, c)
	for _, pair in { { a, c }, { c, a } } do
		for name, value in pair[1]:GetAttributes() do
			if string.sub(name, 1, 4) == "Gore" then
				assert(pair[2]:GetAttribute(name) == value, ("I-G: %s is %s on one body, %s on the other"):format(name, tostring(value), tostring(pair[2]:GetAttribute(name))))
			end
		end
	end
end

-- I-H big hits.
do
	local b = newBody()
	task.wait(1) -- out of any Freefall from being built (a drop counts as a fall for 0.5 s)
	b.Humanoid.Health -= 30
	local function changed(body: Model): { string }
		local keys = {}
		for _, key in LIMB_KEYS do
			if hp(body, key) ~= 100 then
				table.insert(keys, key)
			end
		end
		return keys
	end
	assert(waitFor(function()
		return #changed(b) > 0
	end, 2), "I-H: a 30-health drop damaged no limb")
	task.wait(0.2)
	local hit = changed(b)
	assert(#hit == 1, "I-H: a 30-health drop should damage one limb, it damaged " .. table.concat(hit, ", "))
	assert(hp(b, hit[1]) == 40, ("I-H: %s should take 60, it is at %s"):format(hit[1], tostring(hp(b, hit[1]))))

	local falling = newBody(true)
	pcall(falling.HumanoidRootPart.SetNetworkOwner, falling.HumanoidRootPart, nil)
	assert(waitFor(function()
		return falling.Humanoid:GetState() == Enum.HumanoidStateType.Freefall
	end, 3), "I-H: the dropped body never entered Freefall")
	falling.Humanoid.Health -= 30
	assert(waitFor(function()
		return #changed(falling) > 0
	end, 2), "I-H: a 30-health drop while falling damaged no limb")
	task.wait(0.2)
	expect(falling, "LeftLeg", "Intact", 70, "I-H fall")
	expect(falling, "RightLeg", "Intact", 70, "I-H fall")
	untouched(falling, { "Head", "Torso", "LeftArm", "RightArm" }, "I-H fall")
	falling:Destroy()

	-- Right after Freefall: fall damage lands on landing, once Freefall has ended. A body dropped about 17 studs onto a floor of
	-- its own (30 studs from any other body).
	local landing = newBody(true)
	local humanoid = landing.Humanoid
	pcall(landing.HumanoidRootPart.SetNetworkOwner, landing.HumanoidRootPart, nil)
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(20, 1, 20)
	floor.Position = Vector3.new(landing.HumanoidRootPart.Position.X, 279.5, 2000)
	floor.Parent = folder
	assert(waitFor(function()
		return humanoid:GetState() == Enum.HumanoidStateType.Freefall
	end, 3), "I-H: the body dropped onto the floor never entered Freefall")
	assert(waitFor(function()
		return humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
	end, 3), "I-H: the body dropped onto the floor never landed")
	local landedAt = os.clock()
	local landedState = humanoid:GetState().Name
	humanoid.Health -= 30
	local dropAfter = os.clock() - landedAt
	assert(waitFor(function()
		return #changed(landing) > 0
	end, 2), "I-H: a 30-health drop right after landing damaged no limb")
	task.wait(0.2)
	local after = {}
	for _, key in LIMB_KEYS do
		table.insert(after, key .. " " .. tostring(hp(landing, key)))
	end
	local afterText = table.concat(after, ", ")
	assert(hp(landing, "LeftLeg") == 70 and hp(landing, "RightLeg") == 70, ("I-H: a drop %.3f s after landing (%s) should take 30 from each leg, got %s"):format(dropAfter, landedState, afterText))
	untouched(landing, { "Head", "Torso", "LeftArm", "RightArm" }, "I-H right after landing")

	-- More than 0.5 s after Freefall ended, a drop is a hit again: one limb takes 60, the legs share nothing.
	task.wait(1)
	local standing = humanoid:GetState()
	assert(standing ~= Enum.HumanoidStateType.Freefall, "I-H: the landed body is falling again")
	local before = {}
	for _, key in LIMB_KEYS do
		before[key] = hp(landing, key)
	end
	local function hits(): { string }
		local keys = {}
		for _, key in LIMB_KEYS do
			if hp(landing, key) ~= before[key] then
				table.insert(keys, key)
			end
		end
		return keys
	end
	humanoid.Health -= 30
	assert(waitFor(function()
		return #hits() > 0
	end, 2), "I-H: a 30-health drop long after landing damaged no limb")
	task.wait(0.2)
	local late = hits()
	assert(#late == 1, ("I-H: a drop long after landing (%s) should damage one limb, it damaged %s"):format(standing.Name, table.concat(late, ", ")))
	assert(before[late[1]] - hp(landing, late[1]) == 60, ("I-H: %s should take 60 long after landing, it took %s"):format(late[1], tostring(before[late[1]] - hp(landing, late[1]))))
	landing:Destroy()
	floor:Destroy()

	local k = newBody()
	task.wait(1)
	gore("hurt", k, 40)
	assert(k.Humanoid.Health == 60, "I-H: Gore.hurt(b, 40) should leave Health 60, got " .. k.Humanoid.Health)
	task.wait(0.3)
	untouched(k, LIMB_KEYS, "I-H (Gore.hurt is no big hit)")
end

folder:Destroy()
return ("PASS gore_integrity (I-A to I-H; HIT_SEED %d, MISS_SEED %d)"):format(HIT_SEED, MISS_SEED)
