-- Run in the Server datamodel during a playtest. It needs a spawned character: start a fresh playtest, run
-- tests/fire_play.client.luau in the Client datamodel (it presses Play), wait for the character, then run this. Set CASE below to
-- one case, or "all" (default) for L-A to L-E in order (about a minute and a half).
-- Every case starts the same way: a live character untouched by Gore (one with any gore, or a lost limb, is killed and respawns
-- first) at full health, Bob on Standby with the shutter open, and the room claimed afresh, so the copy is new and whole.
-- A test that requires Gore gets its own copy of the module, so the game's Gore is reached through
-- ServerScriptService.GoreServer.TestHook ("call", fnName, ...). Chances are fixed with GoreConfig overrides (attributes on the
-- module, Studio only), removed again when the case ends.
--   A  (L-A) Explosive into the left arm: the copy's and the owner's left arms end in the same state (Broken or Severed), and
--      the blast was aimed: the torso, the head and the other limbs are Intact at 100 on both (every Gore attribute equal on
--      both). It was one blast, at the copy's arm: the arm took exactly EXPLOSIVE_POWER, and both bodies lost LIMB_DAMAGE health
--      (one open limb does not bleed; BLEED_ALLOWANCE is slack), the same on both
--   B  (L-B) with SEVER_CHANCE 0 the blast leaves both left arms Broken: still on the body, not lost (LabConfig.isLost on
--      Room1.Subject, which is what the tablet menu's lost.LeftArm reads), and a second injection into it is accepted. A release
--      and a new claim build a copy whose left arm is Broken too, dangling from a socket instead of its Motor6D
--   C  (L-C) with SEVER_CHANCE 0 a Broken right arm takes the tablet away, even one held in the hand
--   D  (L-D) with CORPSE_LIFE 4: the owner dies holding the tablet; the copy dies with them and its corpse (GoreOwner = the
--      player's UserId) lies in Workspace.Corpses, and neither corpse holds a Tool. The owner releases the room before the
--      respawn: the copy's corpse is still there, and gone CORPSE_LIFE + 2.5 s after the death. No Gore, LabServer or
--      HardDriveEffects error or warning in the output
--   E  (L-E) the owner dies (and the copy with them); before the respawn a blast at the copy's corpse's left arm (well away
--      from the owner's corpse) changes it, and the owner's corpse shows exactly the same change. After the respawn the new
--      character and the new copy are untouched
--   F  (L-F) a Gore that cannot load does not stop the lab. Not part of "all": it needs its own playtest. In Edit, move
--      ServerScriptService.Gore.Integrity out (to ServerStorage), start the playtest, run tests/fire_play.client.luau, then
--      this with CASE "F"; stop the playtest and put Integrity back in Gore. LabServer's TestHook is there within 15 s of the
--      start, the room can be claimed, the copy and the character carry no Gore attributes, and the Explosive into the left
--      arm takes the old path: both left arms come off into Workspace and both bodies lose LIMB_DAMAGE health
local CASE = "all"

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
local GoreConfig = require(configModule)
local MOVE = LabConfig.Timings.Move
local INJECT = LabConfig.Timings.NeedleOut + LabConfig.Timings.Hold + LabConfig.Timings.NeedleIn
local RETURN = LabConfig.Timings.Return
local FUSE = LabConfig.FUSE_SECONDS
local RESPAWN_WAIT = LabConfig.RESPAWN_TIME + 5
local LIFE = 4 -- L-D's CORPSE_LIFE
local SINK = 2 -- how long a corpse takes to sink (Ragdoll's SINK_TIME)

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
local labServer = ServerScriptService:FindFirstChild("LabServer")
-- LabServer makes its TestHook once it has loaded; L-F needs that within 15 s of the start (time() is seconds since then).
local hook = labServer and labServer:WaitForChild("TestHook", math.max(0.1, 15 - time()))
local hookSeenAt = time()
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.LabServer.TestHook (BindableFunction) missing 15 s into the game")
local function gore(fnName, ...)
	local goreServer = ServerScriptService:FindFirstChild("GoreServer")
	local goreHook = goreServer and goreServer:FindFirstChild("TestHook")
	assert(goreHook and goreHook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook (BindableFunction) missing")
	return goreHook:Invoke("call", fnName, ...)
end

local function inject(limb)
	return hook:Invoke("inject", player, "Explosive", limb)
end

local function subjectOf()
	return room:FindFirstChild("Subject")
end

-- Every Gore attribute a body carries for its limbs, its torso and its skull.
local GORE_NAMES = { "GoreTorsoOpen", "GoreSkull" }
for _, key in LabConfig.LIMB_KEYS do
	for _, prefix in { "Gore_", "GoreHP_", "GoreVariant_" } do
		table.insert(GORE_NAMES, prefix .. key)
	end
end
local function sameGore(a, b, label)
	for _, name in GORE_NAMES do
		assert(a:GetAttribute(name) == b:GetAttribute(name), ("%s: %s is %s on one body and %s on the other"):format(label, name, tostring(a:GetAttribute(name)), tostring(b:GetAttribute(name))))
	end
end

-- Every limb in place and untouched by Gore (a body Gore does not track counts as untouched).
local function whole(body)
	for _, key in LabConfig.LIMB_KEYS do
		local state, hp = body:GetAttribute("Gore_" .. key), body:GetAttribute("GoreHP_" .. key)
		if LabConfig.isLost(body, key) or (state or "Intact") ~= "Intact" or (hp or 100) ~= 100 then
			return false
		end
	end
	return true
end

local function tabletCount()
	local count = 0
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, child in if container then container:GetChildren() else {} do
			if child:IsA("Tool") and child.Name == "Tablet" then
				count += 1
			end
		end
	end
	return count
end

-- The corpse a body part moved into (a Model in Workspace.Corpses), or nil.
local function corpseOf(part)
	local corpses = workspace:FindFirstChild("Corpses")
	local parent = part.Parent
	return if corpses and parent and parent.Parent == corpses then parent else nil
end

-- Runs fn with GoreConfig overrides set, and always removes them again.
local function withOverrides(overrides, fn)
	for name, value in overrides do
		configModule:SetAttribute(name, value)
	end
	local ok, result = pcall(fn)
	for name in overrides do
		configModule:SetAttribute(name, nil)
	end
	if not ok then
		error(result, 0)
	end
	return result
end

-- Every case starts here. Returns the fresh copy, the character and its Humanoid.
local function prepare()
	assert(waitFor(aliveHumanoid, RESPAWN_WAIT), "the player has no live character")
	hook:Invoke("release", player)
	assert(waitFor(function()
		return bob:GetAttribute("State") == "Standby" and room.Shutter.CanCollide == false
	end, RETURN + 1.5), "Bob is not back on Standby with the shutter open")
	if not whole(player.Character) then
		local old = player.Character
		gore("hurt", old, math.huge)
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
	assert(whole(subject), "the fresh copy is not whole")
	return subject, player.Character, humanoid
end

-- Explosive into `key`; returns once the copy's limb is Broken or Severed (the blast).
local function blast(subject, key)
	local ok, reason = inject(key)
	assert(ok == true, "the injection was refused: " .. tostring(reason))
	local state = waitFor(function()
		local s = subject:GetAttribute("Gore_" .. key)
		return (s == "Broken" or s == "Severed") and s
	end, MOVE + INJECT + FUSE + 2)
	assert(state, "the copy's " .. key .. " was never broken or severed (it is " .. tostring(subject:GetAttribute("Gore_" .. key)) .. ")")
	task.wait(0.3)
	return state
end

-- Health a body may have lost (on top of LIMB_DAMAGE) by the time L-A looks, under a second after the blast. One open limb does
-- not bleed, so this is only slack.
local BLEED_ALLOWANCE = 5

local cases = {}

cases.A = function()
	local subject, character, humanoid = prepare()
	local state = blast(subject, "LeftArm")
	assert(character:GetAttribute("Gore_LeftArm") == state, ("L-A: the copy's left arm is %s, the owner's %s"):format(state, tostring(character:GetAttribute("Gore_LeftArm"))))
	for _, key in { "Torso", "Head", "RightArm", "LeftLeg", "RightLeg" } do
		for _, body in { subject, character } do
			local s, hp = body:GetAttribute("Gore_" .. key), body:GetAttribute("GoreHP_" .. key)
			assert(s == "Intact" and hp == 100, ("L-A: %s's %s is %s at %s: the blast should hit only the left arm"):format(body.Name, key, tostring(s), tostring(hp)))
		end
	end
	sameGore(subject, character, "L-A")
	local arm = subject:GetAttribute("GoreHP_LeftArm")
	assert(math.abs(arm - (100 - GoreConfig.EXPLOSIVE_POWER)) < 0.01, ("L-A: the left arm is at %s: not one blast of %d at its centre"):format(tostring(arm), GoreConfig.EXPLOSIVE_POWER))
	local expected = humanoid.MaxHealth - LabConfig.LIMB_DAMAGE
	local copyHealth = subject:FindFirstChildOfClass("Humanoid").Health
	for _, body in { subject, character } do
		local health = body:FindFirstChildOfClass("Humanoid").Health
		assert(health <= expected + 0.01 and health >= expected - BLEED_ALLOWANCE, ("L-A: %s has %s health, expected %s (less what it bled, up to %d)"):format(body.Name, health, expected, BLEED_ALLOWANCE))
		assert(math.abs(health - copyHealth) < 0.01, ("L-A: the owner has %s health, the copy %s: they should bleed the same"):format(health, copyHealth))
	end
	return ("L-A (%s; only the left arm hit)"):format(state)
end

cases.B = function()
	return withOverrides({ SEVER_CHANCE = 0 }, function()
		local subject, character = prepare()
		local state = blast(subject, "LeftArm")
		assert(state == "Broken" and character:GetAttribute("Gore_LeftArm") == "Broken", "L-B: with SEVER_CHANCE 0 both left arms should be Broken")
		assert(subject:FindFirstChild("Left Arm") and character:FindFirstChild("Left Arm"), "L-B: a Broken arm should stay on the body")
		assert(not LabConfig.isLost(room.Subject, "LeftArm"), "L-B: the tablet menu would show the Broken left arm as LOST")
		assert(not LabConfig.isLost(character, "LeftArm"), "L-B: the owner's Broken left arm counts as lost")
		local ok, reason = inject("LeftArm")
		assert(ok == true, "L-B: a second injection into the Broken arm was refused: " .. tostring(reason))
		hook:Invoke("release", player)
		assert(hook:Invoke("claim", player) == true, "L-B: the second claim was refused")
		local again = subjectOf()
		assert(again and again ~= subject, "L-B: no new copy after the second claim")
		sameGore(again, character, "L-B the new copy")
		local torso = again:FindFirstChild("Torso")
		local socket = torso and torso:FindFirstChild("Left Shoulder")
		assert(again:FindFirstChild("Left Arm") and socket and socket:IsA("BallSocketConstraint"), "L-B: the new copy's left arm should dangle from a socket")
		assert(not LabConfig.isLost(again, "LeftArm"), "L-B: the new copy's Broken left arm counts as lost")
		hook:Invoke("release", player)
		return "L-B"
	end)
end

cases.C = function()
	return withOverrides({ SEVER_CHANCE = 0 }, function()
		local subject, character, humanoid = prepare()
		local tool = player:FindFirstChildOfClass("Backpack"):FindFirstChild("Tablet")
		assert(tool, "L-C: no tablet in the Backpack after the claim")
		humanoid:EquipTool(tool)
		assert(waitFor(function()
			return tool.Parent == character
		end, 2), "L-C: the tablet did not reach the hand")
		local state = blast(subject, "RightArm")
		assert(state == "Broken" and character:GetAttribute("Gore_RightArm") == "Broken", "L-C: with SEVER_CHANCE 0 both right arms should be Broken")
		assert(character:FindFirstChild("Right Arm"), "L-C: the Broken right arm should stay on the body")
		assert(waitFor(function()
			return tabletCount() == 0
		end, 1), "L-C: " .. tabletCount() .. " tablet(s) left after the right arm broke")
		hook:Invoke("release", player)
		return "L-C"
	end)
end

cases.D = function()
	return withOverrides({ CORPSE_LIFE = LIFE }, function()
		local problems = {}
		local logging = LogService.MessageOut:Connect(function(message, kind)
			if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and (string.find(message, "Gore") or string.find(message, "LabServer") or string.find(message, "HardDriveEffects")) then
				table.insert(problems, message)
			end
		end)
		local ok, result = pcall(function()
			local subject, character, humanoid = prepare()
			local tool = player:FindFirstChildOfClass("Backpack"):FindFirstChild("Tablet")
			assert(tool, "L-D: no tablet in the Backpack after the claim")
			humanoid:EquipTool(tool)
			assert(waitFor(function()
				return tool.Parent == character
			end, 2), "L-D: the tablet did not reach the hand")
			local copyTorso, ownerTorso = subject.Torso, character.Torso
			gore("hurt", character, math.huge)
			local copyCorpse = waitFor(function()
				return corpseOf(copyTorso)
			end, 3)
			assert(copyCorpse, "L-D: the copy left no corpse in Workspace.Corpses")
			local ownerCorpse = waitFor(function()
				return corpseOf(ownerTorso)
			end, 3)
			assert(ownerCorpse, "L-D: the owner left no corpse in Workspace.Corpses")
			local diedAt = copyCorpse:GetAttribute("GoreDiedAt")
			assert(copyCorpse:GetAttribute("GoreOwner") == player.UserId, "L-D: the copy's corpse has GoreOwner " .. tostring(copyCorpse:GetAttribute("GoreOwner")))
			for _, corpse in { copyCorpse, ownerCorpse } do
				assert(not corpse:FindFirstChildWhichIsA("Tool", true), "L-D: a corpse holds a Tool")
			end
			assert(player.Character == character, "L-D: the player respawned too soon")
			hook:Invoke("release", player)
			assert(room:GetAttribute("Owner") == 0 and subjectOf() == nil, "L-D: the room is not free after the release")
			task.wait(0.5)
			assert(copyCorpse.Parent == workspace.Corpses, "L-D: the release took the copy's corpse away")
			task.wait(math.max(0, diedAt + LIFE + SINK + 0.5 - workspace:GetServerTimeNow()))
			assert(copyCorpse.Parent == nil, ("L-D: the copy's corpse is still there %d s after the death (CORPSE_LIFE %d)"):format(LIFE + SINK, LIFE))
			assert(waitFor(aliveHumanoid, RESPAWN_WAIT), "L-D: the player did not respawn")
		end)
		logging:Disconnect()
		assert(ok, result)
		assert(#problems == 0, "L-D: the output complained: " .. table.concat(problems, " | "))
		return "L-D"
	end)
end

cases.E = function()
	local subject, character = prepare()
	local copyTorso, ownerTorso = subject.Torso, character.Torso
	gore("hurt", character, math.huge)
	local copyCorpse = waitFor(function()
		return corpseOf(copyTorso)
	end, 3)
	local ownerCorpse = waitFor(function()
		return corpseOf(ownerTorso)
	end, 3)
	assert(copyCorpse and ownerCorpse, "L-E: the copy and the owner should both leave a corpse")
	sameGore(copyCorpse, ownerCorpse, "L-E before the blast")
	local arm = copyCorpse:FindFirstChild("Left Arm")
	assert(arm, "L-E: the copy's corpse has no left arm")
	local apart = (ownerCorpse.Torso.Position - arm.Position).Magnitude
	assert(apart > GoreConfig.BLAST_RADIUS + 2, ("L-E: the owner's corpse is %.1f studs from the blast, so its change could be the blast's own"):format(apart))
	assert(player.Character == character, "L-E: the player respawned before the blast")
	gore("explode", arm.Position, GoreConfig.EXPLOSIVE_POWER, GoreConfig.BLAST_RADIUS)
	local state = copyCorpse:GetAttribute("Gore_LeftArm")
	assert(state == "Broken" or state == "Severed", "L-E: the blast left the copy's corpse's left arm " .. tostring(state))
	assert(ownerCorpse:GetAttribute("Gore_LeftArm") == state, ("L-E: the copy's corpse's left arm is %s, the owner's corpse's %s"):format(state, tostring(ownerCorpse:GetAttribute("Gore_LeftArm"))))
	sameGore(copyCorpse, ownerCorpse, "L-E after the blast")
	for _, corpse in { copyCorpse, ownerCorpse } do
		assert(corpse:FindFirstChildOfClass("Humanoid").Health == 0, "L-E: a corpse's Health changed")
	end
	local fresh = waitFor(function()
		local s = subjectOf()
		return aliveHumanoid() and s and s ~= subject and s
	end, RESPAWN_WAIT + 5)
	assert(fresh, "L-E: no new copy after the respawn")
	assert(whole(player.Character) and whole(fresh), "L-E: the corpses' gore reached the new character or the new copy")
	hook:Invoke("release", player)
	return ("L-E (%s on both corpses, %.1f studs apart)"):format(state, apart)
end

cases.F = function()
	local goreModule = ServerScriptService:FindFirstChild("Gore")
	assert(goreModule and not goreModule:FindFirstChild("Integrity"), "L-F: start this playtest with ServerScriptService.Gore.Integrity moved out (see the header)")
	local humanoid = waitFor(aliveHumanoid, RESPAWN_WAIT)
	assert(humanoid, "L-F: the player has no live character")
	hook:Invoke("release", player)
	humanoid.Health = humanoid.MaxHealth
	local ok, reason = hook:Invoke("claim", player)
	assert(ok == true, "L-F: the claim was refused: " .. tostring(reason))
	local subject, character = subjectOf(), player.Character
	assert(subject, "L-F: no Room1.Subject after the claim")
	for _, body in { subject, character } do
		assert(body:GetAttribute("Gore_LeftArm") == nil, "L-F: " .. body.Name .. " carries Gore attributes with no Gore")
	end
	local arms = { subject["Left Arm"], character["Left Arm"] }
	local injected, why = inject("LeftArm")
	assert(injected == true, "L-F: the injection was refused: " .. tostring(why))
	assert(waitFor(function()
		return arms[1].Parent == workspace and arms[2].Parent == workspace
	end, MOVE + INJECT + FUSE + 2), "L-F: the two left arms did not come off into Workspace")
	assert(LabConfig.isLost(subject, "LeftArm") and LabConfig.isLost(character, "LeftArm"), "L-F: both left arms should be lost")
	local expected = character.Humanoid.MaxHealth - LabConfig.LIMB_DAMAGE
	for _, body in { subject, character } do
		local health = body.Humanoid.Health
		assert(math.abs(health - expected) < 0.01, ("L-F: %s has %s health, expected %s"):format(body.Name, health, expected))
	end
	hook:Invoke("release", player)
	return ("L-F (LabServer's TestHook found %.1f s into the game; the old Explosive blew both left arms off)"):format(hookSeenAt)
end

local order = if CASE == "all" then { "A", "B", "C", "D", "E" } else { CASE }
local passed = {}
for _, name in order do
	assert(cases[name], "unknown CASE " .. tostring(name))
	table.insert(passed, cases[name]())
end
return "PASS lab_gore " .. table.concat(passed, ", ")
