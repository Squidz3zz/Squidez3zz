-- Run in the Server datamodel during a playtest, one case at a time (set CASE below). It needs a spawned character: start a
-- fresh playtest, run tests/fire_play.client.luau in the Client datamodel (it presses Play), wait for the character, then run this.
-- Every case starts by releasing the room, so it begins free.
--   A  claim seats a linked R6 copy on the chair, facing the window, with the sit animation, and gives one tablet; the sign names
--      the owner. LEAVES THE ROOM CLAIMED, because tests/lab_claim.client.luau checks the "Release Room 1" state after it.
--   B  claiming again (as the owner) releases: no copy, no tablet (even one held in the hand), free sign, Owner 0
--   C  the owner dying kills the copy; after the respawn a new copy sits, wearing the owner's look (not black), and there is
--      one tablet again
--   D  the copy dying kills the owner; after the respawn, releasing frees the room
--   E  the copy takes on the owner's gore: with SEVER_CHANCE 1 (an override on GoreConfig, removed however the case ends) claim,
--      blow the owner's left arm off (Explosive through the TestHook, the fuse waited out), release, claim again: the new copy
--      has every Gore attribute of the owner (states, integrity, variants, torso, skull) and no left arm either (as the tablet
--      menu sees Room1.Subject), removed outright (no left arm was flung into Workspace by the claim); its other limbs are not
--      lost and its health is the owner's. Leaves the room free and the player without a left arm, so run it last (or respawn
--      before A-D).
-- ("ROOM 1 IS TAKEN" needs a second player, and the owner leaving is PlayerRemoving: both are checked by reading LabServer.)
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))

local FLOOR_TOP = 0.35
local RESPAWN_WAIT = 5 + 3 -- LabConfig.RESPAWN_TIME + 3

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
assert(waitFor(aliveHumanoid, 15), "the player has no live character: run tests/fire_play.client.luau first")

local room = workspace:FindFirstChild("Room1")
assert(room, "Workspace.Room1 missing")
local labServer = ServerScriptService:FindFirstChild("LabServer")
local hook = labServer and labServer:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.LabServer.TestHook (BindableFunction) missing")
local seat = room.Chair.Seat
local spot = seat.SubjectSpot
local signText = room.ClaimButton.Sign.Text
local seatTop = seat.Position.Y + seat.Size.Y / 2

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

-- The lowest point of the copy's two leg parts (each box measured along the world axes).
local function lowestLegY(subject)
	local low = math.huge
	for _, name in { "Left Leg", "Right Leg" } do
		local part = subject:FindFirstChild(name)
		assert(part, "the copy has no " .. name)
		local cf, size = part.CFrame, part.Size
		local halfY = (cf.RightVector:Abs() * size.X + cf.UpVector:Abs() * size.Y + cf.LookVector:Abs() * size.Z).Y / 2
		low = math.min(low, cf.Position.Y - halfY)
	end
	return low
end

local function subjectOf()
	return room:FindFirstChild("Subject")
end

-- A copy that is seated: alive, R6, root anchored within 3 studs of SubjectSpot.
local function assertSeated(subject, what)
	assert(subject and subject:IsA("Model"), what .. ": Room1.Subject missing")
	local humanoid = subject:FindFirstChildOfClass("Humanoid")
	assert(humanoid and humanoid.RigType == Enum.HumanoidRigType.R6, what .. ": the copy is not an R6 humanoid")
	assert(humanoid.Health > 0, what .. ": the copy is dead")
	local root = subject:FindFirstChild("HumanoidRootPart")
	assert(root and root.Anchored, what .. ": the copy's HumanoidRootPart is not anchored")
	assert((root.Position - spot.WorldPosition).Magnitude <= 3, what .. ": the copy is not at SubjectSpot")
end

-- The copy wears the owner's look: the same body colours and the same shirt and pants (a copy built before a respawned
-- character's appearance arrives is black and bare).
local function assertLooksLike(subject, character, what)
	local mine, theirs = subject:FindFirstChildOfClass("BodyColors"), character:FindFirstChildOfClass("BodyColors")
	assert(mine and theirs, what .. ": BodyColors missing on the copy or the character")
	assert(mine.TorsoColor3 == theirs.TorsoColor3 and mine.HeadColor3 == theirs.HeadColor3, what .. ": the copy's body colours " .. tostring(mine.TorsoColor3) .. " are not the owner's " .. tostring(theirs.TorsoColor3))
	for _, class in { "Shirt", "Pants" } do
		local a, b = subject:FindFirstChildOfClass(class), character:FindFirstChildOfClass(class)
		local template = if class == "Shirt" then "ShirtTemplate" else "PantsTemplate"
		assert((a and a[template]) == (b and b[template]), what .. ": the copy's " .. class .. " is not the owner's")
	end
end

local function assertFree(what)
	assert(room:GetAttribute("Owner") == 0, what .. ": Owner should be 0, is " .. tostring(room:GetAttribute("Owner")))
	assert(subjectOf() == nil, what .. ": Room1.Subject should be gone")
	assert(tabletCount() == 0, what .. ": there should be no tablet, found " .. tabletCount())
	assert(signText.Text == "ROOM 1 / FREE", what .. ": the sign says '" .. signText.Text .. "'")
	local state = hook:Invoke("state")
	assert(state.owner == 0 and state.hasCopy == false, what .. ": the hook's state is not free")
end

-- Start every case free.
hook:Invoke("release", player)
assertFree("start")

if CASE == "A" then
	local ok, reason = hook:Invoke("claim", player)
	assert(ok == true, "claim refused: " .. tostring(reason))
	assert(room:GetAttribute("Owner") == player.UserId, "Owner should be the player's UserId")
	local subject = subjectOf()
	assertSeated(subject, "A")
	assertLooksLike(subject, player.Character, "A")
	local humanoid = subject.Humanoid
	assert(humanoid.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None, "the copy's name tag should be hidden")
	local mine = aliveHumanoid()
	assert(humanoid.MaxHealth == mine.MaxHealth and humanoid.Health == mine.Health, "the copy's health should match the player's")
	assert(subject.HumanoidRootPart.CFrame.LookVector:Dot(Vector3.new(-1, 0, 0)) > 0.9, "the copy should face -X (the window)")
	task.wait(1)
	local low = lowestLegY(subject)
	assert(low >= seatTop - 0.2 and low <= seatTop + 0.6, ("legs' lowest point %.2f is not on the seat (top %.2f)"):format(low, seatTop))
	assert(low > FLOOR_TOP, "the legs are below the floor")
	local playing = false
	for _, track in humanoid.Animator:GetPlayingAnimationTracks() do
		playing = playing or (track.Animation.AnimationId == "rbxassetid://178130996" and track.Looped)
	end
	assert(playing, "the sit animation is not playing (looped) on the copy's Animator")
	assert(tabletCount() == 1, "there should be exactly one tablet, found " .. tabletCount())
	assert(signText.Text == "ROOM 1 / " .. player.DisplayName, "the sign says '" .. signText.Text .. "'")
	local state = hook:Invoke("state")
	assert(state.owner == player.UserId and state.hasCopy == true, "the hook's state is not claimed")
	return ("PASS lab_claim A (legs %.2f on seat top %.2f)"):format(low, seatTop)
elseif CASE == "B" then
	assert(hook:Invoke("claim", player) == true, "claim refused")
	hook:Invoke("watchLink")
	-- Hold the tablet in the hand: the release must destroy that one too.
	local tool = player:FindFirstChildOfClass("Backpack"):FindFirstChild("Tablet")
	assert(tool, "no tablet in the Backpack after the claim")
	aliveHumanoid():EquipTool(tool)
	task.wait(0.2)
	assert(tool.Parent == player.Character, "the tablet did not reach the hand")
	assert(hook:Invoke("claim", player) == true, "the owner claiming again should return true (and release)")
	assertFree("B")
	assert(hook:Invoke("linkCalls") == 1, "onLinkBroken should have been called once by the release, was " .. hook:Invoke("linkCalls"))
	return "PASS lab_claim B"
elseif CASE == "C" then
	assert(hook:Invoke("claim", player) == true, "claim refused")
	hook:Invoke("watchLink")
	local first = subjectOf()
	assertSeated(first, "C before")
	local oldCharacter = player.Character
	oldCharacter.Humanoid.Health = 0
	assert(waitFor(function()
		return first.Humanoid.Health == 0
	end, 1), "the copy did not die within 1 s of the owner")
	assert(hook:Invoke("linkCalls") >= 1, "onLinkBroken should be called when the owner dies")
	task.wait(RESPAWN_WAIT)
	local newCharacter = player.Character
	assert(newCharacter and newCharacter ~= oldCharacter, "no new character after the respawn time")
	assert(aliveHumanoid(), "the new character is not alive")
	assert(room:GetAttribute("Owner") == player.UserId, "the room should still be owned after the respawn")
	local second = subjectOf()
	assert(second and second ~= first, "there should be a new Subject, a different instance")
	assertSeated(second, "C after")
	assertLooksLike(second, newCharacter, "C after the respawn")
	assert(first.Parent == nil, "the dead copy should have been destroyed")
	assert(tabletCount() == 1, "there should be exactly one tablet after the respawn, found " .. tabletCount())
	assert(hook:Invoke("linkCalls") >= 2, "onLinkBroken should be called again when the copy is replaced")
	return "PASS lab_claim C"
elseif CASE == "D" then
	assert(hook:Invoke("claim", player) == true, "claim refused")
	local subject = subjectOf()
	assertSeated(subject, "D before")
	local oldCharacter = player.Character
	subject.Humanoid.Health = 0
	assert(waitFor(function()
		return oldCharacter.Humanoid.Health == 0
	end, 1), "the player did not die within 1 s of the copy")
	task.wait(RESPAWN_WAIT)
	assert(player.Character and player.Character ~= oldCharacter and aliveHumanoid(), "no live new character after the respawn time")
	assertSeated(subjectOf(), "D after")
	hook:Invoke("release", player)
	assertFree("D after release")
	return "PASS lab_claim D"
elseif CASE == "E" then
	local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
	configModule:SetAttribute("SEVER_CHANCE", 1)
	local ok, result = pcall(function()
		local character = player.Character
		assert(not LabConfig.isLost(character, "LeftArm"), "the player has already lost the left arm: respawn first")
		assert(hook:Invoke("claim", player) == true, "claim refused")
		local injected, reason = hook:Invoke("inject", player, "Explosive", "LeftArm")
		assert(injected == true, "the injection was refused: " .. tostring(reason))
		local Timings = LabConfig.Timings
		local fuseOut = Timings.Move + Timings.NeedleOut + Timings.Hold + Timings.NeedleIn + LabConfig.FUSE_SECONDS + 1
		assert(waitFor(function()
			return character:GetAttribute("Gore_LeftArm") == "Severed"
		end, fuseOut), "the player's left arm was not blown off")
		assert(LabConfig.isLost(character, "LeftArm"), "the player's Severed left arm should be lost")
		hook:Invoke("release", player)
		assertFree("E after release")
		-- A left arm the claim flings into Workspace (instead of removing it) would land here.
		local flung = 0
		local watch = workspace.ChildAdded:Connect(function(child)
			if child.Name == "Left Arm" then
				flung += 1
			end
		end)
		local claimed = hook:Invoke("claim", player)
		task.wait(0.5)
		watch:Disconnect()
		assert(claimed == true, "the second claim was refused")
		local subject = subjectOf()
		assertSeated(subject, "E")
		for _, prefix in { "Gore_", "GoreHP_", "GoreVariant_" } do
			for _, key in LabConfig.LIMB_KEYS do
				local name = prefix .. key
				assert(subject:GetAttribute(name) == character:GetAttribute(name), ("the new copy's %s is %s, the owner's %s"):format(name, tostring(subject:GetAttribute(name)), tostring(character:GetAttribute(name))))
			end
		end
		for _, name in { "GoreTorsoOpen", "GoreSkull" } do
			assert(subject:GetAttribute(name) == character:GetAttribute(name), "the new copy's " .. name .. " is not the owner's")
		end
		assert(LabConfig.isLost(subject, "LeftArm") and not subject:FindFirstChild("Left Arm"), "the new copy has a left arm, but its owner lost theirs")
		assert(LabConfig.isLost(room.Subject, "LeftArm"), "the tablet menu would show the left arm as whole")
		assert(flung == 0, "the claim flung " .. flung .. " left arm(s) into Workspace: the copy's should be removed outright")
		for _, key in LabConfig.LIMB_KEYS do
			assert(key == "LeftArm" or not LabConfig.isLost(subject, key), "the new copy has lost its " .. key .. " too")
		end
		local health, copyHealth = aliveHumanoid().Health, subject.Humanoid.Health
		assert(copyHealth == health, ("the copy's health %s is not the owner's %s"):format(copyHealth, health))
		hook:Invoke("release", player)
		return ("PASS lab_claim E (the new copy took on the owner's gore, no left arm; torso %s; health %s on both)"):format(tostring(subject:GetAttribute("Gore_Torso")), health)
	end)
	configModule:SetAttribute("SEVER_CHANCE", nil)
	assert(ok, result)
	return result
end
error("unknown CASE " .. tostring(CASE))
