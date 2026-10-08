-- Run in the Server datamodel during a playtest, one case at a time (set CASE below). It needs a spawned character: start a
-- fresh playtest, run tests/fire_play.client.luau in the Client datamodel (it presses Play), wait for the character, then run this.
-- Every case starts the same way: a live, whole character (one that lost a limb in an earlier case is killed and respawns first)
-- at full health, Bob on Standby with the shutter open, and the room claimed afresh, so the copy is new and whole. So the cases can
-- also run one after another in the same playtest.
--   A  (I-A, I-B, I-C) Explosive into the left arm: the phases, their timings and the shutter; 1 s into the fuse both left arms
--      glow; after it both are lost and flung (each moved more than 2 studs sideways within 0.5 s of coming off into Workspace),
--      both bodies have lost 20 health, no glow is left, no Explosion instance was made and Booms counted exactly two booms
--      (copy + owner), both with blood (BloodCount + 2); 2 s later both are still at that health (nobody heals over time); a
--      second injection into the same arm is refused "LIMB ALREADY LOST"
--   D  (I-D) Explosive into the head kills both; an injection while the copy is dead is refused "NO SUBJECT"
--   E  (I-E) two requests back to back: the first starts, the second is refused "BOB IS BUSY" and changes nothing
--   F  (I-F) releasing the room 1 s into the fuse stops it: no glow left, no Explosion and no boom, the player's leg and health
--      untouched
--   G  (I-G) blowing off the right arm takes the tablet away, even one held in the hand
--   H  (I-H) releasing mid-Moving (what PlayerRemoving does): free room, Bob back on Standby within Return + 0.5 s, shutter open
--   I  (I-I) refusals: "UNKNOWN HARDDRIVE" (checked before the limb), "UNKNOWN LIMB", and "NOT YOUR ROOM" once released
--   J  (I-J) a limb whose fuse is burning is refused: Explosive into the left leg; back on Standby the fuse still burns on a whole
--      leg, and a second injection into it is refused "LIMB ALREADY LOST"; a release puts the fuse out, and after a fresh claim the
--      left leg can be injected again
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local MOVE = LabConfig.Timings.Move
local INJECT = LabConfig.Timings.NeedleOut + LabConfig.Timings.Hold + LabConfig.Timings.NeedleIn
local RETURN = LabConfig.Timings.Return
local FUSE = LabConfig.FUSE_SECONDS
local SLACK = 0.3
local RESPAWN_WAIT = LabConfig.RESPAWN_TIME + 5

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.1)
	end
	return predicate()
end

local function now()
	return workspace:GetServerTimeNow()
end

local function waitUntil(serverTime)
	local left = serverTime - now()
	if left > 0 then
		task.wait(left)
	end
end

local player = waitFor(function()
	return Players:GetPlayers()[1]
end, 10)
assert(player, "no player in the playtest")
local function aliveHumanoid()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end
assert(waitFor(aliveHumanoid, RESPAWN_WAIT), "the player has no live character: run tests/fire_play.client.luau first")

local room = workspace:FindFirstChild("Room1")
assert(room, "Workspace.Room1 missing")
local bob = room.BobTheInjector
local shutter = room.Shutter
local labServer = ServerScriptService:FindFirstChild("LabServer")
local hook = labServer and labServer:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.LabServer.TestHook (BindableFunction) missing")

local function inject(id, limb)
	return hook:Invoke("inject", player, id, limb)
end

local function refused(expected, ok, reason)
	assert(ok == false and reason == expected, ("expected (false, %q), got (%s, %s)"):format(expected, tostring(ok), tostring(reason)))
end

local function state()
	return bob:GetAttribute("State")
end

local function subjectOf()
	return room:FindFirstChild("Subject")
end

local function shutterOpen()
	return shutter.CanCollide == false and shutter.Transparency == 1
end

local function tabletCount()
	local count = 0
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == "Tablet" then
				count += 1
			end
		end
	end
	return count
end

-- FuseGlows anywhere in Workspace (the copy, the character and any blown-off limb are all in it).
local function glowCount()
	local count = 0
	for _, thing in workspace:GetDescendants() do
		if thing.Name == "FuseGlow" then
			count += 1
		end
	end
	return count
end

-- The first time each State is seen from now on: when (server time) and the PhaseStart it came with.
local function recordPhases()
	local seen = {}
	local connection = bob:GetAttributeChangedSignal("State"):Connect(function()
		local name = state()
		if not seen[name] then
			seen[name] = { at = now(), start = bob:GetAttribute("PhaseStart") }
		end
	end)
	return seen, connection
end

-- Booms made so far (Booms.at counts them on its ModuleScript in Studio).
local boomsModule = ServerScriptService:FindFirstChild("Booms")
assert(boomsModule, "ServerScriptService.Booms missing")
local function boomCount(): number
	return boomsModule:GetAttribute("BoomCount") or 0
end
local function bloodCount(): number
	return boomsModule:GetAttribute("BloodCount") or 0
end

-- Explosions made anywhere in Workspace from now on.
local function countExplosions()
	local blasts = { n = 0 }
	local connection = workspace.DescendantAdded:Connect(function(thing)
		if thing:IsA("Explosion") then
			blasts.n += 1
		end
	end)
	return blasts, connection
end

-- Every case starts here. Returns the fresh copy, the character and its Humanoid.
local function prepare()
	assert(waitFor(aliveHumanoid, RESPAWN_WAIT), "the player has no live character")
	hook:Invoke("release", player)
	assert(waitFor(function()
		return state() == "Standby"
	end, RETURN + 1), "Bob is not back on Standby")
	assert(waitFor(shutterOpen, 1), "the shutter did not open")
	local whole = true
	for _, key in LabConfig.LIMB_KEYS do
		whole = whole and not LabConfig.isLost(player.Character, key)
	end
	if not whole then
		local old = player.Character
		aliveHumanoid().Health = 0
		assert(waitFor(function()
			return player.Character ~= old and aliveHumanoid()
		end, RESPAWN_WAIT), "no new character after the respawn time")
	end
	local humanoid = aliveHumanoid()
	humanoid.Health = humanoid.MaxHealth
	local ok, reason = hook:Invoke("claim", player)
	assert(ok == true, "claim refused: " .. tostring(reason))
	local subject = subjectOf()
	assert(subject, "no Room1.Subject after the claim")
	for _, key in LabConfig.LIMB_KEYS do
		assert(not LabConfig.isLost(subject, key), "the fresh copy has lost its " .. key)
	end
	assert(hook:Invoke("state").bobState == "Standby", "the hook's bobState should be Standby")
	return subject, player.Character, humanoid
end

if CASE == "A" then
	local subject, character, humanoid = prepare()
	local seen, phases = recordPhases()
	local blasts, blastWatch = countExplosions()
	local boomsBefore, bloodBefore = boomCount(), bloodCount()
	local t0 = now()
	local ok, reason = inject("Explosive", "LeftArm")
	assert(ok == true and reason == nil, "the injection was refused: " .. tostring(reason))
	assert(state() == "Moving", "State should be Moving at once, is " .. tostring(state()))
	assert(math.abs(bob:GetAttribute("PhaseStart") - t0) <= SLACK, "Moving's PhaseStart is not now")
	assert(bob:GetAttribute("Target") == "LeftArm" and bob:GetAttribute("HardDrive") == "Explosive", "Target / HardDrive not set")
	assert(hook:Invoke("state").bobState == "Moving", "the hook's bobState should be Moving")
	task.wait(0.5)
	assert(state() == "Moving", "State should still be Moving 0.5 s in")
	assert(shutter.CanCollide == true and shutter.Transparency == 0, "the shutter should be closed (solid) during Moving")

	-- I-B: the fuse starts as Injecting ends (= Returning starts); 1 s into it both left arms glow.
	assert(waitFor(function()
		return seen.Returning
	end, MOVE + INJECT + 1), "Bob never started Returning")
	waitUntil(seen.Returning.start + 1)
	assert(subject["Left Arm"]:FindFirstChild("FuseGlow"), "no FuseGlow on the copy's left arm 1 s into the fuse")
	assert(character["Left Arm"]:FindFirstChild("FuseGlow"), "no FuseGlow on the player's left arm 1 s into the fuse")

	-- The fling: where each left arm is as it comes off (put into Workspace), and how far it went sideways 0.5 s later.
	local flung = {}
	for _, arm in { subject["Left Arm"], character["Left Arm"] } do
		local connection
		connection = arm:GetPropertyChangedSignal("Parent"):Connect(function()
			if arm.Parent == workspace then
				connection:Disconnect()
				local from = arm.Position
				task.delay(0.5, function()
					local moved = arm.Position - from
					table.insert(flung, Vector3.new(moved.X, 0, moved.Z).Magnitude)
				end)
			end
		end)
	end

	assert(waitFor(function()
		return seen.Standby
	end, RETURN + 1), "Bob never got back to Standby")
	local report = {}
	for _, phase in { { "Injecting", MOVE }, { "Returning", MOVE + INJECT }, { "Standby", MOVE + INJECT + RETURN } } do
		local name, expected = phase[1], phase[2]
		local start, at = seen[name].start - t0, seen[name].at - t0
		assert(math.abs(start - expected) <= SLACK, ("%s's PhaseStart is %.2f s in, expected %.2f"):format(name, start, expected))
		assert(math.abs(at - expected) <= SLACK, ("%s was seen %.2f s in, expected %.2f"):format(name, at, expected))
		table.insert(report, ("%s %.2f"):format(name, start))
	end
	assert(bob:GetAttribute("Target") == "" and bob:GetAttribute("HardDrive") == "", "Target / HardDrive should be cleared on Standby")
	task.wait(0.5)
	assert(shutterOpen(), "the shutter should be open (not collidable, invisible) after Standby")

	waitUntil(seen.Returning.start + FUSE + 0.5)
	phases:Disconnect()
	blastWatch:Disconnect()
	assert(LabConfig.isLost(subject, "LeftArm"), "the copy's left arm should be lost")
	assert(LabConfig.isLost(character, "LeftArm"), "the player's left arm should be lost")
	local expectedHealth = humanoid.MaxHealth - LabConfig.LIMB_DAMAGE
	assert(math.abs(subject.Humanoid.Health - expectedHealth) < 0.01, "the copy's health is " .. subject.Humanoid.Health)
	assert(math.abs(humanoid.Health - expectedHealth) < 0.01, "the player's health is " .. humanoid.Health)
	assert(glowCount() == 0, glowCount() .. " FuseGlow(s) left after the blast")
	assert(blasts.n == 0, blasts.n .. " Explosion instance(s) were made: the blast should only call Booms.at")
	local booms = boomCount() - boomsBefore
	assert(booms == 2, "expected 2 booms (copy + owner), got " .. booms)
	local bloods = bloodCount() - bloodBefore
	assert(bloods == 2, "expected 2 blood booms (copy + owner), got " .. bloods)
	assert(waitFor(function()
		return #flung == 2
	end, 2), "the two left arms did not both come off into Workspace")
	for _, distance in flung do
		assert(distance > 2, ("a left arm moved only %.2f studs sideways in the 0.5 s after it came off: not flung"):format(distance))
	end
	-- Nobody heals over time, so the two stay the same.
	task.wait(2)
	local later, copyLater = humanoid.Health, subject.Humanoid.Health
	assert(later == copyLater and math.abs(later - expectedHealth) < 0.01, ("2 s after the blast the player has %s health and the copy %s, both should still have %d"):format(later, copyLater, expectedHealth))

	-- I-C
	refused("LIMB ALREADY LOST", inject("Explosive", "LeftArm"))
	return ("PASS lab_inject I-A I-B I-C (%s; health %d; arms flung %.1f and %.1f studs sideways in 0.5 s)"):format(table.concat(report, ", "), expectedHealth, flung[1], flung[2])
elseif CASE == "D" then
	local subject, character = prepare()
	assert(inject("Explosive", "Head") == true, "the injection was refused")
	task.wait(MOVE + INJECT + FUSE + 0.5)
	assert(subject.Humanoid.Health <= 0, "the copy should be dead")
	assert(character.Humanoid.Health <= 0, "the player should be dead")
	refused("NO SUBJECT", inject("Explosive", "LeftArm"))
	return "PASS lab_inject I-D"
elseif CASE == "E" then
	prepare()
	local first, firstReason = inject("Explosive", "LeftLeg")
	local second, secondReason = inject("Explosive", "RightLeg")
	assert(first == true, "the first request was refused: " .. tostring(firstReason))
	refused("BOB IS BUSY", second, secondReason)
	assert(bob:GetAttribute("Target") == "LeftLeg", "the refused request changed the target")
	hook:Invoke("release", player)
	return "PASS lab_inject I-E"
elseif CASE == "F" then
	local _, character, humanoid = prepare()
	local before = humanoid.Health
	local seen, phases = recordPhases()
	local blasts, blastWatch = countExplosions()
	local boomsBefore = boomCount()
	assert(inject("Explosive", "LeftLeg") == true, "the injection was refused")
	assert(waitFor(function()
		return seen.Returning
	end, MOVE + INJECT + 1), "Bob never started Returning")
	waitUntil(seen.Returning.start + 1)
	assert(character["Left Leg"]:FindFirstChild("FuseGlow"), "the fuse is not burning on the player's left leg")
	hook:Invoke("release", player)
	task.wait(FUSE + 1)
	phases:Disconnect()
	blastWatch:Disconnect()
	assert(glowCount() == 0, glowCount() .. " FuseGlow(s) left after the release")
	assert(not LabConfig.isLost(character, "LeftLeg"), "the player's left leg should not be lost")
	assert(humanoid.Health == before, ("the player's health changed: %s -> %s"):format(before, humanoid.Health))
	assert(blasts.n == 0, blasts.n .. " Explosion(s) were made")
	assert(boomCount() == boomsBefore, (boomCount() - boomsBefore) .. " boom(s) were made")
	return "PASS lab_inject I-F"
elseif CASE == "G" then
	local subject, character, humanoid = prepare()
	local tool = player:FindFirstChildOfClass("Backpack"):FindFirstChild("Tablet")
	assert(tool, "no tablet in the Backpack after the claim")
	humanoid:EquipTool(tool)
	task.wait(0.2)
	assert(tool.Parent == character, "the tablet did not reach the hand")
	local seen, phases = recordPhases()
	assert(inject("Explosive", "RightArm") == true, "the injection was refused")
	assert(waitFor(function()
		return seen.Returning
	end, MOVE + INJECT + 1), "Bob never started Returning")
	waitUntil(seen.Returning.start + FUSE + 0.5)
	phases:Disconnect()
	assert(LabConfig.isLost(subject, "RightArm") and LabConfig.isLost(character, "RightArm"), "both right arms should be lost")
	assert(tabletCount() == 0, tabletCount() .. " tablet(s) left after losing the right arm")
	return "PASS lab_inject I-G"
elseif CASE == "H" then
	prepare()
	assert(inject("Explosive", "LeftArm") == true, "the injection was refused")
	task.wait(0.5)
	assert(state() == "Moving", "State should be Moving 0.5 s in")
	local released = os.clock()
	hook:Invoke("release", player)
	assert(room:GetAttribute("Owner") == 0, "Owner should be 0")
	assert(subjectOf() == nil, "Room1.Subject should be gone")
	assert(state() == "Returning", "a release mid-Moving should send Bob Returning, State is " .. tostring(state()))
	assert(waitFor(function()
		return state() == "Standby"
	end, RETURN + 0.5), "Bob not on Standby within Return + 0.5 s")
	local back = os.clock() - released
	assert(waitFor(shutterOpen, 0.6), "the shutter should be open")
	assert(bob:GetAttribute("Target") == "" and bob:GetAttribute("HardDrive") == "", "Target / HardDrive should be cleared")
	return ("PASS lab_inject I-H (Standby %.2f s after the release)"):format(back)
elseif CASE == "I" then
	prepare()
	local remote = ReplicatedStorage:FindFirstChild("LabRemotes") and ReplicatedStorage.LabRemotes:FindFirstChild("RequestInjection")
	assert(remote and remote:IsA("RemoteFunction"), "ReplicatedStorage.LabRemotes.RequestInjection (RemoteFunction) missing")
	refused("UNKNOWN HARDDRIVE", inject("Nope", "LeftArm"))
	refused("UNKNOWN HARDDRIVE", inject("Nope", "Tail"))
	refused("UNKNOWN LIMB", inject("Explosive", "Tail"))
	assert(state() == "Standby", "a refused request moved Bob")
	hook:Invoke("release", player)
	refused("NOT YOUR ROOM", inject("Explosive", "LeftArm"))
	return "PASS lab_inject I-I"
elseif CASE == "J" then
	local subject = prepare()
	local seen, phases = recordPhases()
	assert(inject("Explosive", "LeftLeg") == true, "the injection was refused")
	assert(waitFor(function()
		return seen.Standby
	end, MOVE + INJECT + RETURN + 1), "Bob never got back to Standby")
	phases:Disconnect()
	assert(subject["Left Leg"]:FindFirstChild("FuseGlow") and not LabConfig.isLost(subject, "LeftLeg"), "the fuse should still be burning on the copy's whole left leg")
	local early = seen.Returning.start + FUSE - now()
	refused("LIMB ALREADY LOST", inject("Explosive", "LeftLeg"))
	prepare()
	assert(inject("Explosive", "LeftLeg") == true, "after a release the left leg should be injectable again")
	hook:Invoke("release", player)
	return ("PASS lab_inject I-J (refused about %.2f s before the blast)"):format(early)
end
error("unknown CASE " .. tostring(CASE))
