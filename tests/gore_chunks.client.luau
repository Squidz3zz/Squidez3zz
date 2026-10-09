-- Run in the Client datamodel during a playtest, with the server step tests/gore_chunks.server.luau. Start a fresh playtest, run
-- tests/fire_play.client.luau (it presses Play) and wait for the character, then, in this order:
--   A-1  Client, CASE = "A-1": arms the check (a watcher that keeps running) and returns at once
--   S    Server: tests/gore_chunks.server.luau (claims Room 1 for a whole copy, tears its LeftArm, then 2 s later its RightArm)
--   A-2  Client, CASE = "A-2": waits for the watcher's verdict (about 8 s) and returns it
-- A skin chunk is a part named GoreChunk that GoreClient adds to Workspace. The watcher checks, on this player's screen:
--   K-A  within 0.5 s of the copy's LeftArm turning Torn, GoreConfig CHUNKS_MIN to CHUNKS_MAX (6 to 10) chunks appear within
--        3 studs of that arm
--   K-B  each of them flies off at 10 to 25 studs/s, away from the arm: as it appears, its speed away from the arm centre is
--        at least 10 studs/s (gravity bends them down right after, so where they are later says less)
--   K-C  CHUNK_REST + 1.5 s after the tear they are all gone
--   K-D  with GORE_LEVEL 1 (an override set here, on this client's GoreConfig only, and always removed) the RightArm tearing
--        adds no chunk anywhere within 0.5 s
-- The verdict sits in the PlayerGui attribute GC_Result; A-2 returns "PASS gore_chunks (K-A to K-D; ...)".
local CASE = "A-1"
local NEAR = 3
local WINDOW = 0.5
local SPEED = NumberRange.new(10, 25)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
local GoreConfig = require(configModule)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local RESULT = "GC_Result"

if CASE == "A-1" then
	playerGui:SetAttribute(RESULT, "running")
	local room = workspace:WaitForChild("Room1", 10)
	assert(room, "Workspace.Room1 missing")

	-- Every chunk that appears: when, where and how fast (its speed is set once it is in, so read after GoreClient is done).
	local chunks = {}
	local added = workspace.DescendantAdded:Connect(function(thing)
		if thing.Name == "GoreChunk" and thing:IsA("BasePart") then
			local entry = { part = thing, at = os.clock(), from = thing.Position, velocity = Vector3.zero }
			table.insert(chunks, entry)
			task.defer(function()
				entry.velocity = thing.AssemblyLinearVelocity
			end)
		end
	end)

	-- Waits for the copy's limb to change to Torn (a copy that arrives torn does not count); returns the time and the arm.
	local function tearOf(key: string, partName: string, timeout: number): (number?, BasePart?)
		local seen: { [Instance]: any } = {}
		local deadline = os.clock() + timeout
		while os.clock() < deadline do
			local subject = room:FindFirstChild("Subject")
			if subject then
				local state = subject:GetAttribute("Gore_" .. key)
				if state == "Torn" and seen[subject] ~= nil and seen[subject] ~= "Torn" then
					return os.clock(), subject:FindFirstChild(partName) :: BasePart?
				end
				seen[subject] = state or false
			end
			RunService.Heartbeat:Wait()
		end
		return nil, nil
	end

	local function within(t0: number): { any }
		local found = {}
		for _, entry in chunks do
			if entry.at >= t0 - 0.1 and entry.at <= t0 + WINDOW then
				table.insert(found, entry)
			end
		end
		return found
	end

	task.spawn(function()
		local ok, err = pcall(function()
			local left, arm = tearOf("LeftArm", "Left Arm", 60)
			assert(left and arm, "the copy's LeftArm never turned Torn: run tests/gore_chunks.server.luau")
			local centre = arm.Position
			task.wait(WINDOW + 0.1)
			-- K-A
			local near = {}
			for _, entry in within(left) do
				if (entry.from - centre).Magnitude <= NEAR then
					table.insert(near, entry)
				end
			end
			local low, high = GoreConfig.get("CHUNKS_MIN"), GoreConfig.get("CHUNKS_MAX")
			assert(#near >= low and #near <= high, ("K-A: %d chunks near the torn arm within %.1f s, expected %d to %d"):format(#near, WINDOW, low, high))
			-- K-B
			local least = math.huge
			for i, entry in near do
				local speed = entry.velocity.Magnitude
				local away = entry.velocity:Dot((entry.from - centre).Unit)
				least = math.min(least, away)
				assert(speed >= SPEED.Min - 0.01 and speed <= SPEED.Max + 0.01, ("K-B: chunk %d flies at %.1f studs/s"):format(i, speed))
				assert(away >= SPEED.Min - 0.01, ("K-B: chunk %d moves away from the arm at only %.1f studs/s"):format(i, away))
			end
			-- K-D
			configModule:SetAttribute("GORE_LEVEL", 1)
			local right = tearOf("RightArm", "Right Arm", 10)
			assert(right, "the copy's RightArm never turned Torn")
			task.wait(WINDOW)
			configModule:SetAttribute("GORE_LEVEL", nil)
			local extra = within(right)
			assert(#extra == 0, ("K-D: %d chunks appeared at GORE_LEVEL 1"):format(#extra))
			-- K-C
			task.wait(math.max(0, left + GoreConfig.get("CHUNK_REST") + 1.5 - os.clock()))
			for i, entry in near do
				assert(entry.part.Parent == nil, ("K-C: chunk %d is still there %.1f s after the tear"):format(i, os.clock() - left))
			end
			return ("%d chunks, each moving away from the arm at %.1f studs/s or more"):format(#near, least)
		end)
		configModule:SetAttribute("GORE_LEVEL", nil)
		added:Disconnect()
		playerGui:SetAttribute(RESULT, if ok then "PASS gore_chunks (K-A to K-D; " .. err .. ")" else "FAIL " .. tostring(err))
	end)
	return "armed: now run tests/gore_chunks.server.luau, then CASE A-2"
elseif CASE == "A-2" then
	local deadline = os.clock() + 30
	while playerGui:GetAttribute(RESULT) == "running" and os.clock() < deadline do
		task.wait(0.2)
	end
	local result = playerGui:GetAttribute(RESULT)
	playerGui:SetAttribute(RESULT, nil)
	assert(type(result) == "string" and string.sub(result, 1, 4) == "PASS", tostring(result))
	return result
end
error("unknown CASE " .. CASE)
