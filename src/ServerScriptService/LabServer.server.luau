-- LabServer: Room 1's server side. This part: claiming the room, the linked copy of the owner and the tablet.
-- A player triggers the claim prompt on the panel outside the window and becomes the owner (Room1.Owner holds their UserId, 0 when
-- free; the sign reads "ROOM 1 / FREE" or "ROOM 1 / <display name>"). A copy of their avatar sits in the chair as Room1.Subject, and a
-- Tablet goes into their Backpack. Whatever kills one of them kills the other. The owner triggering the prompt again, or leaving the
-- game, frees the room and removes the copy and the tablet; when the owner respawns, a fresh copy and a fresh tablet are made.
-- Spawning and respawning players is MenuServer's job; this script only sets Players.RespawnTime at startup and reacts to CharacterAdded.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))

Players.RespawnTime = LabConfig.RESPAWN_TIME

local SIT_ANIMATION = "rbxassetid://178130996"
-- How far above SubjectSpot (the seat's top centre) the copy's HumanoidRootPart goes so that the sitting copy rests on the seat.
local SEAT_LIFT = 1.5

local room = workspace:WaitForChild("Room1")

local owner: Player? = nil
local subject: Model? = nil
-- Bumped whenever the copy is replaced or the room is released, so a copy that was still being built (it takes a moment) notices it is
-- stale when it is done and throws itself away.
local generation = 0
-- The owner's CharacterAdded and Died connections; they go when the room is released.
local ownerConnections: { RBXScriptConnection } = {}

-- Task 4 fills this in: Bob stops what he is doing. Called when the room is released, the owner leaves, the owner dies and the copy
-- is replaced.
local onLinkBroken: (() -> ())? = nil

local function linkBroken()
	if onLinkBroken then
		local ok, err = pcall(onLinkBroken)
		if not ok then
			warn("LabServer: onLinkBroken failed: " .. tostring(err))
		end
	end
end

local function find(root: Instance, ...: string): Instance?
	local node: Instance? = root
	for _, name in { ... } do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function ownerPlayer(): Player?
	return owner
end

local function copy(): Model?
	return subject
end

local function setSign(text: string)
	local label = find(room, "ClaimButton", "Sign", "Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function clearTablets(container: Instance?)
	if container then
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == "Tablet" then
				child:Destroy()
			end
		end
	end
end

-- One tablet, never two: the Backpack and the hand are cleared first.
local function giveTablet(player: Player)
	clearTablets(player:FindFirstChildOfClass("Backpack"))
	clearTablets(player.Character)
	local template = ServerStorage:FindFirstChild("Tablet")
	local backpack = player:WaitForChild("Backpack", 5)
	if template and backpack then
		template:Clone().Parent = backpack
	else
		warn("LabServer: no ServerStorage.Tablet or no Backpack, so no tablet for " .. player.Name)
	end
end

local function killHumanoidOf(model: Instance?)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

-- Builds the owner's copy and seats it. Returns "seated", "stale" (the room was released or the copy replaced while it was being
-- built: nothing to do) or "failed". Yields.
local function seatCopy(player: Player, humanoid: Humanoid): string
	generation += 1
	local mine = generation
	if subject then
		subject:Destroy()
		subject = nil
		linkBroken()
	end
	local spot = find(room, "Chair", "Seat", "SubjectSpot")
	if not (spot and spot:IsA("Attachment")) then
		warn("LabServer: Room1.Chair.Seat.SubjectSpot is missing")
		return "failed"
	end
	local built, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(humanoid:GetAppliedDescription(), Enum.HumanoidRigType.R6)
	end)
	if mine ~= generation then
		if built then
			model:Destroy()
		end
		return "stale"
	end
	if not built then
		warn("LabServer: could not build the copy for " .. player.Name .. ": " .. tostring(model))
		return "failed"
	end

	local copyHumanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (copyHumanoid and root) then
		model:Destroy()
		warn("LabServer: the copy has no Humanoid or HumanoidRootPart")
		return "failed"
	end
	model.Name = "Subject"
	model.PrimaryPart = root
	copyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	copyHumanoid.MaxHealth = humanoid.MaxHealth
	copyHumanoid.Health = humanoid.Health
	root.Anchored = true
	model:PivotTo(spot.WorldCFrame * CFrame.new(0, SEAT_LIFT, 0))
	model.Parent = room
	subject = model

	-- Whatever kills the copy kills its owner (the current character: the owner may have respawned since).
	copyHumanoid.Died:Once(function()
		if mine == generation then
			killHumanoidOf(player.Character)
		end
	end)

	local animator = copyHumanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", copyHumanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = SIT_ANIMATION
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play()
	return "seated"
end

local function release(player: Player)
	if not owner or player ~= owner then
		return
	end
	generation += 1
	for _, connection in ownerConnections do
		connection:Disconnect()
	end
	table.clear(ownerConnections)
	if subject then
		subject:Destroy()
		subject = nil
	end
	clearTablets(player:FindFirstChildOfClass("Backpack"))
	clearTablets(player.Character)
	owner = nil
	room:SetAttribute("Owner", 0)
	setSign("ROOM 1 / FREE")
	linkBroken()
end

-- For the owner's current character, on the claim and after every respawn: the tablet, the death link and a fresh copy. Yields.
local function setUpCharacter(player: Player, character: Model): string
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return "failed"
	end
	table.insert(
		ownerConnections,
		humanoid.Died:Once(function()
			if owner == player then
				killHumanoidOf(subject)
				linkBroken()
			end
		end)
	)
	giveTablet(player)
	return seatCopy(player, humanoid)
end

-- Claiming toggles: the owner claiming again releases. Returns (true) or (false, reason).
local function claim(player: Player): (boolean, string?)
	if owner == player then
		release(player)
		return true
	end
	if owner then
		return false, "ROOM 1 IS TAKEN"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return false, "NO CHARACTER"
	end

	owner = player
	room:SetAttribute("Owner", player.UserId)
	setSign("ROOM 1 / " .. player.DisplayName)
	table.insert(
		ownerConnections,
		player.CharacterAdded:Connect(function(newCharacter)
			local status = setUpCharacter(player, newCharacter)
			if status == "failed" then
				warn("LabServer: no copy for " .. player.Name .. " after the respawn, so the room is released")
				release(player)
			end
		end)
	)
	local status = setUpCharacter(player, character)
	if status == "failed" or owner ~= player then
		release(player)
		return false, "NO CHARACTER"
	end
	return true
end

Players.PlayerRemoving:Connect(release)

local prompt = find(room, "ClaimButton", "Button", "ClaimPrompt")
if prompt and prompt:IsA("ProximityPrompt") then
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(claim, player)
		if not ok then
			warn("LabServer: claim failed for " .. player.Name .. ": " .. tostring(err))
			release(player)
		end
	end)
else
	warn("LabServer: Room1.ClaimButton.Button.ClaimPrompt is missing, so nobody can claim the room")
end

room:SetAttribute("Owner", 0)
setSign("ROOM 1 / FREE")

if RunService:IsStudio() then
	-- Test hook for tests/lab_claim.server.luau (execute_luau cannot reach this script's locals).
	local linkCalls = 0
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, player)
		if action == "claim" then
			return claim(player)
		elseif action == "release" then
			release(player)
		elseif action == "state" then
			return { owner = if owner then owner.UserId else 0, hasCopy = subject ~= nil }
		elseif action == "watchLink" then
			-- Counts the calls to onLinkBroken from now on (and still runs the real one, if there is one).
			linkCalls = 0
			local inner = onLinkBroken
			onLinkBroken = function()
				linkCalls += 1
				if inner then
					inner()
				end
			end
		elseif action == "linkCalls" then
			return linkCalls
		else
			error("TestHook: unknown action " .. tostring(action))
		end
	end
	hook.Parent = script
end
