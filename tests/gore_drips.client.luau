-- Run in the Client datamodel during a playtest, with the server step tests/gore_drips.server.luau. Start a fresh playtest, run
-- tests/fire_play.client.luau (it presses Play) and wait for the character, then, in this order:
--   A-1  Client, CASE = "A-1": arms the check (a watcher that keeps running) and returns at once
--   S    Server: tests/gore_drips.server.luau (a fresh copy in Room 1: LeftArm Torn, RightArm Broken, LeftLeg Severed; killed
--        8 s later)
--   A-2  Client, CASE = "A-2": waits for the watcher's verdict (about 20 s) and returns it
-- On this player's screen (GoreClient's drips are ParticleEmitters named GoreDrip; its pools are parts named GorePool, in
-- Workspace.GorePools):
--   D-A  1 s after the copy's limbs open, each open limb drips: an enabled GoreDrip in the Left Arm and in the Right Arm, and
--        for the severed LeftLeg one in the Torso's stump attachment GoreDrip_LeftLeg (none in the flying leg); the intact
--        Head, Torso and RightLeg have none enabled
--   D-B  a pool lies under the copy's torso, wider 6 s after the limbs opened than 2 s after, and never wider than POOL_MAX
--   D-C  the corpse still drips 1 s after the death, and with DRIP_AFTER_DEATH 3 (an override set here, on this client's
--        GoreConfig only, and always removed) has no enabled GoreDrip 4.5 s after it; its pool is still there
--   D-D  a bleeding body walking (the server step's walker, 4 s at 16 studs/s) drips but starts at most 2 pools near its
--        floor (x 5940 to 6060, z 6000): one while it stands before it walks and one once it stops are fine, a stream is not
-- The verdict sits in the PlayerGui attribute GD_Result; A-2 returns "PASS gore_drips (D-A to D-D; ...)".
local CASE = "A-1"
local AFTER_DEATH = 3

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
local GoreConfig = require(configModule)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local RESULT = "GD_Result"

-- The GoreDrip directly in `holder` when it is enabled.
local function drips(holder: Instance?): boolean
	local emitter = holder and holder:FindFirstChild("GoreDrip")
	return emitter ~= nil and emitter:IsA("ParticleEmitter") and emitter.Enabled
end

local function enabledIn(root: Instance): number
	local n = 0
	for _, thing in root:GetDescendants() do
		if thing.Name == "GoreDrip" and thing:IsA("ParticleEmitter") and thing.Enabled then
			n += 1
		end
	end
	return n
end

-- The GorePool nearest below `torso` (within 6 studs), or nil.
local function poolUnder(torso: BasePart): BasePart?
	local best, bestDistance = nil, 6
	local folder = workspace:FindFirstChild("GorePools")
	for _, thing in if folder then folder:GetChildren() else {} do
		if thing.Name == "GorePool" and thing:IsA("BasePart") then
			local d = (thing.Position - torso.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = thing, d
			end
		end
	end
	return best
end

if CASE == "A-1" then
	playerGui:SetAttribute(RESULT, "running")
	configModule:SetAttribute("DRIP_AFTER_DEATH", AFTER_DEATH)
	local room = workspace:WaitForChild("Room1", 10)
	assert(room, "Workspace.Room1 missing")

	-- D-D, watched from now on: every pool that appears near the walker's floor, and whether the walker drips while it walks.
	local walkerPools, walkerDripped, watching = 0, false, true
	local added = workspace.DescendantAdded:Connect(function(thing)
		if thing.Name == "GorePool" and thing:IsA("BasePart") then
			local at = thing.Position
			if math.abs(at.X - 6000) <= 60 and math.abs(at.Z - 6000) <= 10 then
				walkerPools += 1
			end
		end
	end)
	task.spawn(function()
		while watching do
			local walk = workspace:FindFirstChild("GoreDripsWalk")
			local walker = walk and walk:FindFirstChild("Walker")
			if walker and walk:GetAttribute("Walked") ~= true and enabledIn(walker) > 0 then
				walkerDripped = true
			end
			task.wait(0.1)
		end
	end)

	-- Waits for a copy's LeftArm to change to Torn (a copy that arrives torn does not count); returns the time and the copy.
	local function opened(timeout: number): (number?, Model?)
		local seen: { [Instance]: any } = {}
		local deadline = os.clock() + timeout
		while os.clock() < deadline do
			local subject = room:FindFirstChild("Subject")
			if subject then
				local state = subject:GetAttribute("Gore_LeftArm")
				if state == "Torn" and seen[subject] ~= nil and seen[subject] ~= "Torn" then
					return os.clock(), subject
				end
				seen[subject] = state or false
			end
			RunService.Heartbeat:Wait()
		end
		return nil, nil
	end

	task.spawn(function()
		local ok, err = pcall(function()
			local t0, copy = opened(60)
			assert(t0 and copy, "the copy's LeftArm never turned Torn: run tests/gore_drips.server.luau")
			local torso = copy:WaitForChild("Torso", 2) :: BasePart
			local leg = copy:FindFirstChild("Left Leg")
			-- D-A
			task.wait(math.max(0, t0 + 1 - os.clock()))
			assert(drips(copy:FindFirstChild("Left Arm")), "D-A: the torn Left Arm does not drip")
			assert(drips(copy:FindFirstChild("Right Arm")), "D-A: the broken Right Arm does not drip")
			assert(drips(torso:FindFirstChild("GoreDrip_LeftLeg")), "D-A: the severed LeftLeg's stump does not drip")
			assert(not (leg and leg.Parent and enabledIn(leg) > 0), "D-A: the flying Left Leg drips")
			for _, name in { "Head", "Right Leg" } do
				assert(not drips(copy:FindFirstChild(name)), "D-A: the intact " .. name .. " drips")
			end
			assert(not drips(torso), "D-A: the intact Torso drips")
			-- D-B
			local poolMax = GoreConfig.get("POOL_MAX")
			local widest = 0
			local function width(): number
				local pool = poolUnder(torso)
				local w = if pool then math.max(pool.Size.Y, pool.Size.Z) else 0
				widest = math.max(widest, w)
				return w
			end
			task.wait(math.max(0, t0 + 2 - os.clock()))
			local at2 = width()
			assert(at2 > 0, "D-B: no GorePool under the copy 2 s after its limbs opened")
			task.wait(math.max(0, t0 + 6 - os.clock()))
			local at6 = width()
			assert(at6 > at2, ("D-B: the pool is %.2f studs across at 6 s, %.2f at 2 s"):format(at6, at2))
			-- D-C: the copy dies (its torso moves into a corpse).
			local corpse
			local deadline = os.clock() + 15
			while os.clock() < deadline do
				width()
				local parent = torso.Parent
				if parent and parent.Name == "Corpse" then
					corpse = parent
					break
				end
				task.wait(0.1)
			end
			assert(corpse, "D-C: the copy never died into a corpse")
			local diedAt = corpse:GetAttribute("GoreDiedAt")
			local function waitUntilAge(age: number)
				while workspace:GetServerTimeNow() - diedAt < age do
					width()
					task.wait(0.1)
				end
			end
			waitUntilAge(1)
			assert(enabledIn(corpse) > 0, "D-C: the corpse does not drip 1 s after the death")
			waitUntilAge(AFTER_DEATH + 1.5)
			assert(enabledIn(corpse) == 0, ("D-C: the corpse has %d enabled drips %.1f s after the death"):format(enabledIn(corpse), AFTER_DEATH + 1.5))
			assert(poolUnder(torso), "D-C: the corpse's pool is gone")
			assert(widest <= poolMax + 1e-3, ("D-B: the pool grew to %.2f studs, more than POOL_MAX %d"):format(widest, poolMax))
			-- D-D: the walker comes and goes.
			local walk = workspace:WaitForChild("GoreDripsWalk", 15)
			assert(walk, "D-D: no GoreDripsWalk: run tests/gore_drips.server.luau")
			while walk.Parent and walk:GetAttribute("Walked") ~= true do
				task.wait(0.1)
			end
			assert(walkerDripped, ("D-D: the walking body never dripped (%d pools near it)"):format(walkerPools))
			assert(walkerPools <= 2, ("D-D: the walking body started %d pools"):format(walkerPools))
			return ("pool %.2f at 2 s, %.2f at 6 s, widest %.2f; the walker started %d pools"):format(at2, at6, widest, walkerPools)
		end)
		added:Disconnect()
		watching = false
		configModule:SetAttribute("DRIP_AFTER_DEATH", nil)
		playerGui:SetAttribute(RESULT, if ok then "PASS gore_drips (D-A to D-D; " .. err .. ")" else "FAIL " .. tostring(err))
	end)
	return "armed: now run tests/gore_drips.server.luau, then CASE A-2"
elseif CASE == "A-2" then
	local deadline = os.clock() + 40
	while playerGui:GetAttribute(RESULT) == "running" and os.clock() < deadline do
		task.wait(0.2)
	end
	local result = playerGui:GetAttribute(RESULT)
	playerGui:SetAttribute(RESULT, nil)
	configModule:SetAttribute("DRIP_AFTER_DEATH", nil)
	assert(type(result) == "string" and string.sub(result, 1, 4) == "PASS", tostring(result))
	return result
end
error("unknown CASE " .. CASE)
