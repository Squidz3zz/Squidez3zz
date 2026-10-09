-- Run in the Server datamodel of a running playtest, with the player spawned: start the playtest, run
-- tests/fire_play.client.luau (it presses Play), then this. Set CASE below:
--   "all"   (default) R-A to R-F, on R6 bodies built here (30 studs apart, far from the rooms: x 3030 and up, y 300, z 3000,
--           anchored, each standing on a floor of its own) and, for R-E, on the player's own character (it dies 6 times,
--           with Players.RespawnTime at 1 s while it runs).
--   "down"  the server step for tests/gore_crawl.client.luau: breaks both legs of the player's character ("hit"), so it is
--           downed.
--   "kill"  kills the player's character (it respawns whole), to clean up after "down".
-- A test that requires Gore gets its own copy of the module, so every case drives the game's own Gore through
-- ServerScriptService.GoreServer.TestHook ("call", fnName, ...).
--   R-A dangling  a Broken LeftArm has no Motor6D (LabConfig.limbJoint is nil) but one BallSocketConstraint joining Torso and
--                 Left Arm (shoulder limits: 70 degree cone, 45 degree twist); the arm is still in the body, collides
--                 (CanCollide) but not with its own body (a NoCollisionConstraint with every other part of it)
--   R-B sever     a Severed LeftLeg (an explosion, HIT_SEED) is out of the body, owned by the server, moves more than 2 studs
--                 sideways within 0.5 s, and is gone after LabConfig.LOST_LIMB_SECONDS
--   R-C movement  one leg Broken: WalkSpeed 8 (LIMP_SPEED), JumpHeight 0, not downed; the other Severed too: GoreDowned true
--   R-D dying     a body with a dangling LeftArm and a dangling RightLeg dies: its corpse has no Motor6D, exactly one
--                 BallSocket per joint (neck limits 40 / 30, hips 50 / 30), the dangling arm still attached by its socket,
--                 every limb colliding, its attributes kept (with GoreDiedAt) and the GoreBody tag; the emptied body keeps
--                 only its Humanoid, and the corpse has a still one (no state machine, Health 0)
--   R-E corpse    the player's character dies: Workspace.Corpses holds a Corpse with GoreOwner = the player's UserId and the
--                 body's parts (server-owned, no Motor6D); the respawned character is new, whole and tracked. After 5 deaths
--                 at most 4 of the player's corpses remain (the oldest went). With CORPSE_LIFE overridden to 3 s (an
--                 attribute on GoreConfig, Studio only) the corpse sinks (no collisions, moving down) and is gone after 6 s
--   R-F blasted   Gore.explode at a corpse's left arm (two corpses, seeded both ways) leaves that arm Broken (still attached)
--                 or Severed (out of the corpse), with no Gore error or warning in the output and Health still 0
-- It removes its bodies and the corpses it made, and returns "PASS gore_ragdoll".
local CASE = "all"

local CollectionService = game:GetService("CollectionService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HIT_SEED = 3 -- first roll 0.181: an explosion that breaks a limb severs it
local MISS_SEED = 1 -- first roll 0.948: it only breaks

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
local GoreConfig = require(configModule)

local server = ServerScriptService:FindFirstChild("GoreServer")
local hook = server and server:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

-- Waits (at most `timeout` seconds) for check() to return something truthy, and returns it.
local function waitFor(check: () -> any, timeout: number): any
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = check()
		if value then
			return value
		end
		task.wait()
	end
	return check()
end

local player = waitFor(function()
	return Players:GetPlayers()[1]
end, 10)
local function aliveHumanoid(): Humanoid?
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

if CASE == "down" or CASE == "kill" then
	assert(waitFor(aliveHumanoid, 15), "the player has no live character: run tests/fire_play.client.luau first")
	local character = player.Character
	if CASE == "down" then
		gore("damageLimb", character, "LeftLeg", 100, "hit")
		gore("damageLimb", character, "RightLeg", 100, "hit")
		assert(character:GetAttribute("GoreDowned") == true, "down: both legs broken should set GoreDowned")
		return "PASS gore_ragdoll down"
	end
	gore("hurt", character, math.huge)
	assert(waitFor(function()
		return player.Character ~= character and aliveHumanoid()
	end, LabConfig.RESPAWN_TIME + 10), "kill: the player did not respawn")
	return "PASS gore_ragdoll kill"
end

local JOINTS = {
	Neck = { part = "Head", cone = 40, twist = 30 },
	["Left Shoulder"] = { part = "Left Arm", cone = 70, twist = 45 },
	["Right Shoulder"] = { part = "Right Arm", cone = 70, twist = 45 },
	["Left Hip"] = { part = "Left Leg", cone = 50, twist = 30 },
	["Right Hip"] = { part = "Right Leg", cone = 50, twist = 30 },
}
local PART_NAMES = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local old = workspace:FindFirstChild("GoreRagdollTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreRagdollTest"
folder.Parent = workspace

local count = 0
-- A fresh R6 body standing (root anchored) on a floor of its own, tracked by the game's Gore. floorDrop: how far below its
-- feet the floor is (0 when omitted).
local function newBody(floorDrop: number?): Model
	count += 1
	local x = 3000 + 30 * count
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = "Body" .. count
	body.HumanoidRootPart.Anchored = true
	body:PivotTo(CFrame.new(x, 300, 3000))
	body.Parent = folder
	local floor = Instance.new("Part")
	floor.Name = "Floor" .. count
	floor.Anchored = true
	floor.Size = if floorDrop then Vector3.new(60, 1, 60) else Vector3.new(20, 1, 20)
	floor.Position = Vector3.new(x, 296.5 - (floorDrop or 0), 3000)
	floor.Parent = folder
	-- A Humanoid whose Health reaches 0 before its first step never dies (no Died), so it steps first.
	task.wait(0.1)
	gore("track", body)
	return body
end

-- The BallSocketConstraints under `root` that join `a` and `b` (either way round).
local function socketsBetween(root: Instance, a: BasePart, b: BasePart): { BallSocketConstraint }
	local found = {}
	for _, thing in root:GetDescendants() do
		if thing:IsA("BallSocketConstraint") then
			local p0 = thing.Attachment0 and thing.Attachment0.Parent
			local p1 = thing.Attachment1 and thing.Attachment1.Parent
			if (p0 == a and p1 == b) or (p0 == b and p1 == a) then
				table.insert(found, thing)
			end
		end
	end
	return found
end

local function countClass(root: Instance, className: string): number
	local n = 0
	for _, thing in root:GetDescendants() do
		if thing:IsA(className) then
			n += 1
		end
	end
	return n
end

local function limits(socket: BallSocketConstraint, joint: string, label: string)
	local want = JOINTS[joint]
	assert(socket.LimitsEnabled and math.abs(socket.UpperAngle - want.cone) < 1e-3, ("%s: %s cone is %s, expected %d"):format(label, joint, tostring(socket.UpperAngle), want.cone))
	assert(
		socket.TwistLimitsEnabled and math.abs(socket.TwistUpperAngle - want.twist) < 1e-3 and math.abs(socket.TwistLowerAngle + want.twist) < 1e-3,
		("%s: %s twist is %s to %s, expected -%d to %d"):format(label, joint, tostring(socket.TwistLowerAngle), tostring(socket.TwistUpperAngle), want.twist, want.twist)
	)
end

-- True when `a` and `b` have a NoCollisionConstraint between them (anywhere under root).
local function noCollide(root: Instance, a: BasePart, b: BasePart): boolean
	for _, thing in root:GetDescendants() do
		if thing:IsA("NoCollisionConstraint") and ((thing.Part0 == a and thing.Part1 == b) or (thing.Part0 == b and thing.Part1 == a)) then
			return true
		end
	end
	return false
end

-- Kills a test body through Gore.hurt and returns its corpse (the Model in Workspace.Corpses its Torso moved into).
local function kill(body: Model, label: string): Model
	local torso = body:FindFirstChild("Torso")
	gore("hurt", body, math.huge)
	local corpse = waitFor(function()
		local parent = torso.Parent
		return if parent and parent ~= body and parent.Parent == workspace:FindFirstChild("Corpses") then parent else nil
	end, 3)
	assert(corpse and corpse.Name == "Corpse", label .. ": no Corpse in Workspace.Corpses holds the dead body's Torso")
	return corpse
end

local made: { Model } = {} -- corpses this test made, removed at the end

-- R-A dangling.
local severedLeg: BasePart?, severedAt = nil, 0
do
	local b = newBody()
	local arm = b["Left Arm"]
	gore("damageLimb", b, "LeftArm", 100, "hit")
	assert(b:GetAttribute("Gore_LeftArm") == "Broken", "R-A: 100 hit damage should break the left arm")
	assert(LabConfig.limbJoint(b, "LeftArm") == nil, "R-A: a Broken LeftArm still has its Motor6D")
	assert(arm.Parent == b, "R-A: the dangling arm left the body")
	local sockets = socketsBetween(b, b.Torso, arm)
	assert(#sockets == 1, "R-A: expected one BallSocketConstraint joining Torso and Left Arm, found " .. #sockets)
	limits(sockets[1], "Left Shoulder", "R-A")
	task.wait(0.5)
	assert(arm.CanCollide, "R-A: the dangling arm should collide with the world")
	for _, other in b:GetChildren() do
		if other:IsA("BasePart") and other ~= arm then
			assert(noCollide(b, arm, other), "R-A: the dangling arm collides with its own " .. other.Name)
		end
	end
	assert(LabConfig.limbJoint(b, "RightArm") and LabConfig.limbJoint(b, "LeftLeg"), "R-A: the other joints should stay Motor6Ds")
end

-- R-B sever.
do
	local b = newBody(30)
	local leg = b["Left Leg"]
	gore("seed", HIT_SEED)
	gore("damageLimb", b, "LeftLeg", 150, "explosion")
	assert(b:GetAttribute("Gore_LeftLeg") == "Severed", "R-B: the explosion with HIT_SEED should sever the left leg")
	severedAt = os.clock()
	assert(leg.Parent and not leg:IsDescendantOf(b), "R-B: the severed leg is still in the body")
	assert(#socketsBetween(workspace, b.Torso, leg) == 0 and LabConfig.limbJoint(b, "LeftLeg") == nil, "R-B: the severed leg is still joined to the torso")
	assert(leg:GetNetworkOwner() == nil, "R-B: the severed leg should be owned by the server")
	local start = leg.Position
	task.wait(0.5)
	local moved = (leg.Position - start) * Vector3.new(1, 0, 1)
	assert(moved.Magnitude > 2, ("R-B: the severed leg moved %.2f studs sideways in 0.5 s, expected more than 2"):format(moved.Magnitude))
	severedLeg = leg
end

-- R-C movement.
do
	local b = newBody()
	local humanoid = b.Humanoid
	gore("damageLimb", b, "LeftLeg", 100, "hit")
	assert(humanoid.WalkSpeed == GoreConfig.LIMP_SPEED and humanoid.WalkSpeed == 8, "R-C: one broken leg should set WalkSpeed 8, got " .. humanoid.WalkSpeed)
	assert(humanoid.JumpHeight == 0, "R-C: one broken leg should set JumpHeight 0, got " .. humanoid.JumpHeight)
	assert(b:GetAttribute("GoreDowned") ~= true, "R-C: one broken leg should not down the body")
	gore("seed", HIT_SEED)
	gore("damageLimb", b, "RightLeg", 150, "explosion")
	assert(b:GetAttribute("Gore_RightLeg") == "Severed", "R-C: the explosion with HIT_SEED should sever the right leg")
	assert(b:GetAttribute("GoreDowned") == true, "R-C: both legs out should set GoreDowned")
	assert(humanoid.WalkSpeed == 8 and humanoid.JumpHeight == 0, "R-C: the downed body should keep WalkSpeed 8 and JumpHeight 0")
end

-- R-D dying with dangling limbs.
do
	local b = newBody()
	local arm = b["Left Arm"]
	gore("damageLimb", b, "LeftArm", 100, "hit")
	gore("damageLimb", b, "RightLeg", 100, "hit")
	assert(#socketsBetween(b, b.Torso, arm) == 1, "R-D: the arm should dangle before the death")
	local corpse = kill(b, "R-D")
	table.insert(made, corpse)
	task.wait(0.5)
	assert(countClass(corpse, "Motor6D") == 0, "R-D: the corpse still has a Motor6D")
	assert(countClass(corpse, "BallSocketConstraint") == 5, "R-D: expected 5 BallSockets in the corpse, found " .. countClass(corpse, "BallSocketConstraint"))
	local torso = corpse:FindFirstChild("Torso")
	for joint, spec in JOINTS do
		local part = corpse:FindFirstChild(spec.part)
		assert(part, "R-D: the corpse has no " .. spec.part)
		local sockets = socketsBetween(corpse, torso, part)
		assert(#sockets == 1, ("R-D: expected one BallSocket for %s, found %d"):format(joint, #sockets))
		limits(sockets[1], joint, "R-D")
	end
	assert(arm.Parent == corpse and socketsBetween(corpse, torso, arm)[1].Enabled, "R-D: the dangling arm should still be attached")
	for _, name in PART_NAMES do
		local part = corpse:FindFirstChild(name)
		assert(part and part.CanCollide and not part.Anchored, "R-D: " .. name .. " should collide and be loose")
	end
	assert(corpse:FindFirstChild("HumanoidRootPart"), "R-D: the root should move into the corpse")
	local still = corpse:FindFirstChildOfClass("Humanoid")
	assert(still and not still.EvaluateStateMachine and still.Health == 0, "R-D: the corpse should have a still Humanoid (no state machine, Health 0)")
	local left = b:GetChildren()
	assert(#left == 1 and left[1]:IsA("Humanoid"), "R-D: the dead body should keep only its Humanoid, it has " .. #left .. " children")
	assert(type(corpse:GetAttribute("GoreDiedAt")) == "number", "R-D: the corpse has no GoreDiedAt")
	assert(corpse:GetAttribute("Gore_LeftArm") == "Broken" and corpse:GetAttribute("GoreHP_RightLeg") == 0, "R-D: the corpse lost the body's gore attributes")
	assert(CollectionService:HasTag(corpse, "GoreBody"), "R-D: the corpse should keep the GoreBody tag")
	assert(corpse:GetAttribute("GoreOwner") == nil, "R-D: a body that is no player's should have no GoreOwner")
end

-- R-F a corpse is blasted.
do
	local problems = {}
	local logging = LogService.MessageOut:Connect(function(message, kind)
		if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and string.find(message, "Gore") then
			table.insert(problems, message)
		end
	end)
	for _, seed in { HIT_SEED, MISS_SEED } do
		local corpse = kill(newBody(), "R-F")
		table.insert(made, corpse)
		task.wait(1) -- it settles on its floor
		local humanoid = corpse:FindFirstChildOfClass("Humanoid")
		local arm = corpse["Left Arm"]
		gore("seed", seed)
		local ok, err = pcall(gore, "explode", arm.Position, GoreConfig.EXPLOSIVE_POWER, GoreConfig.BLAST_RADIUS)
		assert(ok, "R-F: Gore.explode at a corpse failed: " .. tostring(err))
		local state = corpse:GetAttribute("Gore_LeftArm")
		assert(state == "Broken" or state == "Severed", "R-F: the blasted corpse's left arm is " .. tostring(state))
		if state == "Severed" then
			assert(not arm:IsDescendantOf(corpse) and #socketsBetween(workspace, corpse.Torso, arm) == 0, "R-F: the severed arm is still on the corpse")
		else
			assert(arm.Parent == corpse and #socketsBetween(corpse, corpse.Torso, arm) == 1, "R-F: the broken arm should still hang from one socket")
		end
		assert(humanoid.Health == 0, "R-F: the blast changed the corpse's Health to " .. humanoid.Health)
	end
	task.wait(0.5)
	logging:Disconnect()
	assert(#problems == 0, "R-F: Gore complained: " .. table.concat(problems, " | "))
end

-- R-E a player's corpses.
do
	assert(waitFor(aliveHumanoid, 15), "R-E: the player has no live character: run tests/fire_play.client.luau first")
	local userId = player.UserId
	local corpses = workspace:WaitForChild("Corpses", 1)
	local function mine(): { Model }
		local list = {}
		for _, corpse in if corpses then corpses:GetChildren() else {} do
			if corpse:GetAttribute("GoreOwner") == userId then
				table.insert(list, corpse)
			end
		end
		return list
	end
	for _, corpse in mine() do
		corpse:Destroy() -- left by an earlier run
	end
	local savedRespawn = Players.RespawnTime
	Players.RespawnTime = 1

	-- One death of the player's current character; returns its corpse once the player has respawned.
	local function die(index: number): Model
		local character = player.Character
		assert(character:GetAttribute("Gore_Torso") == "Intact" and CollectionService:HasTag(character, "GoreBody"), ("R-E death %d: the character is not tracked by Gore"):format(index))
		local torso = character.Torso
		gore("hurt", character, math.huge)
		local corpse = waitFor(function()
			local parent = torso.Parent
			return if parent and parent:IsA("Model") and parent.Name == "Corpse" and parent.Parent == workspace:FindFirstChild("Corpses") then parent else nil
		end, 3)
		assert(corpse, ("R-E death %d: no Corpse in Workspace.Corpses holds the character's Torso"):format(index))
		corpses = corpse.Parent
		table.insert(made, corpse)
		assert(corpse:GetAttribute("GoreOwner") == userId, ("R-E death %d: GoreOwner is %s, expected %d"):format(index, tostring(corpse:GetAttribute("GoreOwner")), userId))
		for _, name in { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart" } do
			local part = corpse:FindFirstChild(name)
			assert(part and part:IsA("BasePart"), ("R-E death %d: the corpse has no %s"):format(index, name))
			assert(part:GetNetworkOwner() == nil, ("R-E death %d: the corpse's %s is not owned by the server"):format(index, name))
		end
		assert(corpse:FindFirstChildOfClass("Humanoid") and countClass(corpse, "Motor6D") == 0, ("R-E death %d: the corpse has no Humanoid, or a Motor6D"):format(index))
		local fresh = waitFor(function()
			return player.Character ~= character and aliveHumanoid() and player.Character
		end, 10)
		assert(fresh, ("R-E death %d: the player did not respawn"):format(index))
		assert(fresh:FindFirstChild("Torso") and LabConfig.limbJoint(fresh, "LeftArm"), ("R-E death %d: the respawned character is not whole"):format(index))
		assert(waitFor(function()
			return fresh:GetAttribute("Gore_Torso") == "Intact"
		end, 2), ("R-E death %d: the respawned character is not tracked"):format(index))
		return corpse
	end

	local first = die(1)
	for index = 2, 5 do
		die(index)
	end
	local left = mine()
	assert(#left == 4, ("R-E: after 5 deaths %d of the player's corpses remain, expected 4"):format(#left))
	assert(first.Parent == nil, "R-E: the oldest corpse should have gone")

	configModule:SetAttribute("CORPSE_LIFE", 3)
	local ok, err = pcall(function()
		local corpse = die(6)
		-- Its age, from GoreDiedAt (die() returns after the respawn, a moment after the death).
		local diedAt = corpse:GetAttribute("GoreDiedAt")
		local function waitUntilAge(age: number)
			task.wait(math.max(0, age - (workspace:GetServerTimeNow() - diedAt)))
		end
		waitUntilAge(2.8)
		local torso = corpse:FindFirstChild("Torso")
		local before = torso.Position.Y
		assert(torso.CanCollide, "R-E: the corpse stopped colliding before CORPSE_LIFE")
		waitUntilAge(4.6) -- 1.6 s into the sinking
		assert(corpse.Parent ~= nil, "R-E: the corpse went before it finished sinking")
		assert(not torso.CanCollide and torso.Anchored, "R-E: a sinking corpse should be anchored with no collisions")
		assert(torso.Position.Y < before - 1, ("R-E: the sinking corpse moved from %.2f to %.2f, expected down"):format(before, torso.Position.Y))
		waitUntilAge(6)
		assert(corpse.Parent == nil, "R-E: with CORPSE_LIFE 3 the corpse should be gone after 6 s")
	end)
	configModule:SetAttribute("CORPSE_LIFE", nil)
	Players.RespawnTime = savedRespawn
	assert(ok, err)
end

-- R-B, finished: the severed leg is removed after LOST_LIMB_SECONDS.
assert(waitFor(function()
	return severedLeg.Parent == nil
end, math.max(0, LabConfig.LOST_LIMB_SECONDS + 2 - (os.clock() - severedAt))), "R-B: the severed leg is still there after LOST_LIMB_SECONDS")

for _, corpse in made do
	corpse:Destroy()
end
folder:Destroy()
return ("PASS gore_ragdoll (R-A to R-F; HIT_SEED %d, MISS_SEED %d)"):format(HIT_SEED, MISS_SEED)
