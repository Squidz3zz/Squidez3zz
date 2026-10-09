-- Integrity: the gore system's rules (it sits inside Gore, which is how other scripts reach it; Gore's comments say what each
-- function does). It keeps each limb's integrity and state, makes the chance rolls, watches for big hits and keeps the link
-- between a player and their copy. Everything it decides goes on the body as attributes, so every client and every later part
-- of the gore system (dangling limbs, flesh, bleeding) reads the same thing. The numbers are GoreConfig's, read through
-- GoreConfig.get. It only decides and publishes: it never moves, detaches or welds anything (listeners on onStateChanged do).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig"))
local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))

local TAG = "GoreBody"
local FULL = 100
-- A health drop counts as a fall when the humanoid was in Freefall this recently (seconds), or still is.
local FALL_WINDOW = 0.5
-- These end Destroyed (and kill); the arms and legs end Broken or Severed.
local VITAL = { Head = true, Torso = true }

type Outcome = { state: string, hp: number, variant: number?, open: boolean, skull: string? }
type Listener = (body: Model, key: string, old: string, new: string, info: { [string]: any }) -> ()

local Integrity = {}

-- Every chance roll comes from this one Random, so a seed repeats them (Studio tests only).
local random = Random.new()
local listeners: { Listener } = {}
-- Linked bodies, both ways round. Not weak: an Instance's Lua wrapper can be collected while the Instance lives, which would
-- drop a link nothing else in Lua holds. A link goes on unlink, or when either body is destroyed.
local partner: { [Model]: Model } = {}
-- Per watched humanoid: the health it last had, the health the gore system took that the watcher has not seen yet, and when
-- it was last in Freefall. Weak is safe here: the watcher's own connections keep the humanoid's wrapper alive until it is
-- destroyed.
local watches: { [Humanoid]: { last: number, pending: number, fellAt: number } } = setmetatable({}, { __mode = "k" }) :: any
local warned = {}

local function warnOnce(key: any, message: string)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

-- Writes one limb's outcome on one body and tells the listeners when its state changed (or the torso just opened). A
-- destroyed head or torso takes the body's health to 0, as gore damage.
local function apply(body: Model, key: string, outcome: Outcome, cause: string)
	local old = body:GetAttribute("Gore_" .. key)
	local opened = key == "Torso" and outcome.open and body:GetAttribute("GoreTorsoOpen") ~= true
	body:SetAttribute("Gore_" .. key, outcome.state)
	body:SetAttribute("GoreHP_" .. key, outcome.hp)
	body:SetAttribute("GoreVariant_" .. key, outcome.variant)
	if key == "Torso" then
		body:SetAttribute("GoreTorsoOpen", outcome.open)
	elseif key == "Head" then
		body:SetAttribute("GoreSkull", outcome.skull)
	end
	if old ~= outcome.state or opened then
		local info = {
			cause = cause,
			severed = outcome.state == "Severed" or nil,
			torsoOpened = opened or nil,
			skullBlasted = if key == "Head" and outcome.state == "Destroyed" then outcome.skull == "blasted" else nil,
		}
		for index, listener in listeners do
			local ok, err = pcall(listener, body, key, old, outcome.state, info)
			if not ok then
				warnOnce(index, "Gore: an onStateChanged listener failed: " .. tostring(err))
			end
		end
	end
	if VITAL[key] and outcome.state == "Destroyed" then
		Integrity.hurt(body, math.huge)
	end
end

-- The big-hit watcher for one humanoid (see GoreConfig.BIG_HIT).
local function watch(humanoid: Humanoid)
	local w = { last = humanoid.Health, pending = 0, fellAt = -math.huge }
	watches[humanoid] = w
	humanoid.StateChanged:Connect(function(old, new)
		if old == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Freefall then
			w.fellAt = os.clock()
		end
	end)
	humanoid.HealthChanged:Connect(function(health)
		local drop = w.last - health
		w.last = health
		-- The part of the drop the gore system made itself (hurt) is not a hit.
		local credit = math.clamp(drop, 0, w.pending)
		w.pending -= credit
		drop -= credit
		local body = humanoid.Parent
		if drop < GoreConfig.get("BIG_HIT") or not (body and body:IsA("Model")) then
			return
		end
		if humanoid:GetState() == Enum.HumanoidStateType.Freefall or os.clock() - w.fellAt <= FALL_WINDOW then
			-- Twice the health lost, split across both legs.
			Integrity.damageLimb(body, "LeftLeg", drop, "fall")
			Integrity.damageLimb(body, "RightLeg", drop, "fall")
		else
			local keys = {}
			for _, key in LabConfig.LIMB_KEYS do
				if body:GetAttribute("Gore_" .. key) ~= "Severed" then
					table.insert(keys, key)
				end
			end
			if #keys > 0 then
				Integrity.damageLimb(body, keys[random:NextInteger(1, #keys)], 2 * drop, "hit")
			end
		end
	end)
end

function Integrity.track(body: Model)
	for _, key in LabConfig.LIMB_KEYS do
		if body:GetAttribute("Gore_" .. key) == nil then
			body:SetAttribute("Gore_" .. key, "Intact")
			body:SetAttribute("GoreHP_" .. key, FULL)
		end
	end
	if body:GetAttribute("GoreTorsoOpen") == nil then
		body:SetAttribute("GoreTorsoOpen", false)
	end
	CollectionService:AddTag(body, TAG)
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		if not watches[humanoid] then
			watch(humanoid)
		end
	end
end

function Integrity.link(a: Model, b: Model)
	Integrity.unlink(a)
	Integrity.unlink(b)
	if a ~= b then
		partner[a] = b
		partner[b] = a
		for _, body in { a, b } do
			body.Destroying:Once(function()
				Integrity.unlink(body)
			end)
		end
	end
end

function Integrity.unlink(body: Model)
	local other = partner[body]
	partner[body] = nil
	if other and partner[other] == body then
		partner[other] = nil
	end
end

-- Hands `from`'s link (if it has one) to `to`: a linked body that dies passes it on to its corpse.
function Integrity.relink(from: Model, to: Model)
	local other = partner[from]
	if other then
		Integrity.link(to, other)
	end
end

function Integrity.damageLimb(body: Model, key: string, amount: number, cause: string)
	local old = body:GetAttribute("Gore_" .. key)
	if old == nil or old == "Severed" or old == "Destroyed" or not (type(amount) == "number" and amount > 0) then
		return
	end
	local explosion = cause == "explosion"
	-- Not clamped: integrity can go below 0.
	local hp = (body:GetAttribute("GoreHP_" .. key) or FULL) - amount
	local new = old
	-- The chance rolls come first and the variant pick last, so each case's first roll is its chance (the tests rely on it).
	if hp <= 0 then
		if VITAL[key] then
			new = "Destroyed"
		elseif explosion and random:NextNumber() < GoreConfig.get("SEVER_CHANCE") then
			new = "Severed"
		else
			new = "Broken"
		end
	elseif old == "Intact" and hp <= GoreConfig.get("TORN_AT") then
		new = "Torn"
	end
	local open = body:GetAttribute("GoreTorsoOpen") == true
	if key == "Torso" and not open then
		open = new == "Destroyed" or (new == "Torn" and explosion and random:NextNumber() < GoreConfig.get("TORSO_OPEN_CHANCE"))
	end
	local skull = body:GetAttribute("GoreSkull")
	if key == "Head" and new == "Destroyed" then
		skull = if random:NextNumber() < GoreConfig.get("SKULL_BLAST_CHANCE") then "blasted" else "shown"
	end
	local variant = body:GetAttribute("GoreVariant_" .. key)
	if old == "Intact" and new ~= "Intact" then
		variant = random:NextInteger(1, 2)
	end
	-- Decided once, on this body; a linked body gets exactly the same.
	local outcome = { state = new, hp = hp, variant = variant, open = open, skull = skull }
	apply(body, key, outcome, cause)
	local other = partner[body]
	if other then
		apply(other, key, outcome, cause)
	end
end

function Integrity.explode(position: Vector3, power: number, radius: number)
	-- Every distance is taken before any damage, so nothing a listener moves changes the blast.
	local hits = {}
	local skip = {}
	for _, body in CollectionService:GetTagged(TAG) do
		if skip[body] then
			continue
		end
		for _, key in LabConfig.LIMB_KEYS do
			local part = LabConfig.limbParts(body, key)[1]
			local distance = if part then (part.Position - position).Magnitude else math.huge
			if distance < radius then
				table.insert(hits, { body = body, key = key, amount = power * (1 - distance / radius) ^ 2 })
				-- ponytail: when both linked bodies are in one blast, the first one (in tag order) takes it and the link
				-- copies it to the other; the lab only ever blasts the copy, so taking the larger of the two is not needed.
				local other = partner[body]
				if other then
					skip[other] = true
				end
			end
		end
	end
	for _, hit in hits do
		Integrity.damageLimb(hit.body, hit.key, hit.amount, "explosion")
	end
end

function Integrity.hurt(body: Model, amount: number)
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0 and type(amount) == "number" and amount > 0) then
		return
	end
	local before = humanoid.Health
	local after = math.max(0, before - amount)
	-- Marked before the change, so the watcher sees it whether HealthChanged runs at once or later.
	local w = watches[humanoid]
	if w then
		w.pending += before - after
	end
	humanoid.Health = after
end

function Integrity.stateOf(body: Model, key: string): string?
	return body:GetAttribute("Gore_" .. key)
end

function Integrity.integrityOf(body: Model, key: string): number?
	return body:GetAttribute("GoreHP_" .. key)
end

function Integrity.copyState(from: Model, to: Model)
	Integrity.track(to)
	for _, key in LabConfig.LIMB_KEYS do
		local state = from:GetAttribute("Gore_" .. key)
		if state ~= nil then
			apply(to, key, {
				state = state,
				hp = from:GetAttribute("GoreHP_" .. key),
				variant = from:GetAttribute("GoreVariant_" .. key),
				open = from:GetAttribute("GoreTorsoOpen") == true,
				skull = from:GetAttribute("GoreSkull"),
			}, "copy")
		end
	end
end

function Integrity.onStateChanged(fn: Listener)
	table.insert(listeners, fn)
end

function Integrity.seed(n: number)
	random = Random.new(n)
end

return Integrity
