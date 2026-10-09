-- LabServer: Room 1's server side: claiming the room, the linked copy of the owner, the tablet, and the injections.
-- A player triggers the claim prompt on the panel outside the window and becomes the owner (Room1.Owner holds their UserId, 0 when
-- free; the sign reads "ROOM 1 / FREE" or "ROOM 1 / <display name>"). A copy of their avatar sits in the chair as Room1.Subject, and a
-- Tablet goes into their Backpack. Whatever kills one of them kills the other. The copy is built with the owner's gore and then
-- linked to the owner's character through the gore system (Gore.copyState, then Gore.link), so every gore change on either lands
-- on both. The owner triggering the prompt again, or leaving the game, frees the room and removes the copy and the tablet; when the
-- owner respawns, a fresh copy and a fresh tablet are made. Without Gore the lab runs as it did before it.
-- Spawning and respawning players is MenuServer's job; this script only sets Players.RespawnTime at startup and reacts to CharacterAdded.
--
-- Injections: the owner's tablet calls ReplicatedStorage.LabRemotes.RequestInjection(hardDriveId, limbKey). Everything is checked
-- here (nothing from a client is trusted), then Bob's sequence runs on its own: Moving, Injecting, the Harddrive's effect
-- (HardDriveEffects, on the copy and the owner at once), Returning, Standby. The server only publishes Bob's phase as attributes on
-- Room1.BobTheInjector (State, Target, HardDrive, PhaseStart); each client animates him from them. The doorway shutter is the one
-- thing the server moves itself, because it must really block the door: it closes when Bob sets off and opens on Standby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
-- A broken HardDriveEffects must not stop claiming: every injection is then refused as an unknown Harddrive.
local effectsLoaded, HardDriveEffects = pcall(require, script.Parent:WaitForChild("HardDriveEffects", 5))
if not effectsLoaded then
	warn("LabServer: HardDriveEffects did not load, so every injection is refused: " .. tostring(HardDriveEffects))
	HardDriveEffects = {}
end
local goreLoaded, Gore = pcall(require, script.Parent:WaitForChild("Gore", 5))
if not goreLoaded then
	warn("LabServer: Gore did not load, so Room 1 runs without gore: " .. tostring(Gore))
	Gore = nil
end

Players.RespawnTime = LabConfig.RESPAWN_TIME

local SIT_ANIMATION = "rbxassetid://178130996"
-- How far above SubjectSpot (the seat's top centre) the copy's HumanoidRootPart goes so that the sitting copy rests on the seat.
local SEAT_LIFT = 1.5
-- When open, the shutter waits this far above the doorway (inside the wall); closing slides it down over SHUTTER_TIME seconds.
local SHUTTER_RISE = 6.5
local SHUTTER_TIME = 0.4
-- A respawned character gets its look (colours, clothes) a moment after it appears (about 0.2 s in Studio); the copy waits at most this
-- long for it.
local LOOK_WAIT = 10
local Timings = LabConfig.Timings

local room = workspace:WaitForChild("Room1")
local bob = room:WaitForChild("BobTheInjector")
local shutter = room:WaitForChild("Shutter") :: BasePart
local shutterClosed: CFrame = shutter:GetAttribute("ClosedCFrame") or shutter.CFrame
local shutterOpen = shutterClosed + Vector3.new(0, SHUTTER_RISE, 0)

local owner: Player? = nil
local subject: Model? = nil
-- Bumped whenever the copy is replaced or the room is released, so a copy that was still being built (it takes a moment) notices it is
-- stale when it is done and throws itself away.
local generation = 0
-- The owner's CharacterAdded, Died and right-arm connections; they go when the room is released.
local ownerConnections: { RBXScriptConnection } = {}

-- Bob stops what he is doing (filled in further down). Called when the room is released, the owner leaves, the owner dies and the
-- copy is replaced, sometimes twice for one event (a release after the owner died), so it must be safe to call again.
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

-- Gore[fnName](...), pcall'd: false when Gore is missing or the call failed (the first failure warns).
local goreWarned = false
local function gore(fnName: string, ...: any): boolean
	if not Gore then
		return false
	end
	local ok, err = pcall(Gore[fnName], ...)
	if not ok and not goreWarned then
		goreWarned = true
		warn("LabServer: Gore." .. fnName .. " failed: " .. tostring(err))
	end
	return ok
end

-- Through Gore.hurt, so the gore system's big-hit watcher does not count the death as a hit.
local function killHumanoidOf(model: Model?)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and not gore("hurt", model, math.huge) then
		humanoid.Health = 0
	end
end

local function alive(model: Instance?): boolean
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
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
	-- Its corpse counts toward the owner's (GoreConfig.CORPSES_PER_PLAYER).
	model:SetAttribute("GoreOwner", player.UserId)
	-- The copy is the owner as they are now: it takes on their whole gore (a release and a new claim keep a dangling limb
	-- dangling and a ripped-off one off). Before the link, which copies each change across without comparing the two.
	local character = humanoid.Parent :: Model
	gore("copyState", character, model)
	-- Without Gore (or at GORE_LEVEL 0, where blasts blow limbs off with no gore) an arm or a leg the owner has lost is missing on
	-- the copy too.
	for _, key in { "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
		if character and LabConfig.isLost(character, key) then
			local joint = LabConfig.limbJoint(model, key)
			if joint then
				joint:Destroy()
			end
			for _, part in LabConfig.limbParts(model, key) do
				part:Destroy()
			end
		end
	end
	root.Anchored = true
	model:PivotTo(spot.WorldCFrame * CFrame.new(0, SEAT_LIFT, 0))
	model.Parent = room
	subject = model
	gore("link", model, character)

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
		gore("unlink", subject)
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

-- Starts listening for `character`'s look to arrive and returns a function that waits for it (at most `timeout` seconds; true when
-- it came). Call it the moment the character appears: CharacterAppearanceLoaded may fire before the first yield, and
-- player:HasAppearanceLoaded() still says true from the previous character, so it cannot be asked instead.
local function lookArrival(player: Player, character: Model): (number) -> boolean
	local arrived = false
	local connection = player.CharacterAppearanceLoaded:Connect(function(loaded)
		arrived = arrived or loaded == character
	end)
	return function(timeout)
		local deadline = os.clock() + timeout
		while not arrived and os.clock() < deadline and character.Parent do
			task.wait()
		end
		connection:Disconnect()
		return arrived
	end
end

-- For the owner's current character, on the claim and after every respawn: the tablet, the death link and a fresh copy. Yields.
-- After a respawn, `waitForLook` (from lookArrival) holds the copy back until the character wears its look: built any earlier, the
-- copy comes out black and bare.
local function setUpCharacter(player: Player, character: Model, waitForLook: ((number) -> boolean)?): string
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
	-- Tools hang from the right hand: with the right arm Broken (dangling) or gone, whatever did it, the owner has no tablet until
	-- they respawn. Either way its Motor6D leaves the Torso, which is when this runs.
	local function dropTabletsIfNoRightArm()
		local broken = character:GetAttribute("Gore_RightArm") == "Broken"
		if player.Character == character and (broken or LabConfig.isLost(character, "RightArm")) then
			clearTablets(player:FindFirstChildOfClass("Backpack"))
			clearTablets(character)
		end
	end
	local torso = character:WaitForChild("Torso", 5)
	if torso then
		table.insert(ownerConnections, torso.ChildRemoved:Connect(dropTabletsIfNoRightArm))
	end
	giveTablet(player)
	dropTabletsIfNoRightArm()
	if waitForLook and not waitForLook(LOOK_WAIT) then
		warn("LabServer: " .. player.Name .. "'s look did not arrive within " .. LOOK_WAIT .. " s, so the copy may not match")
	end
	-- The room may have been released, or the character replaced, while the look loaded.
	if owner ~= player or player.Character ~= character then
		return "stale"
	end
	return seatCopy(player, humanoid)
end

-- Claiming toggles: the owner claiming again releases. Returns (true) or (false, reason).
local warnedR6 = false
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
	-- The lab is R6 only (the copy, the limb table, the tablet's body). Checked before anything yields, so another rig is refused at
	-- once instead of stalling on a Torso it does not have.
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		if not warnedR6 then
			warnedR6 = true
			warn("LabServer: " .. player.Name .. " is not R6, so Room 1 refuses them: set Game Settings > Avatar > Avatar Type to R6")
		end
		return false, "R6 ONLY"
	end

	owner = player
	room:SetAttribute("Owner", player.UserId)
	setSign("ROOM 1 / " .. player.DisplayName)
	table.insert(
		ownerConnections,
		player.CharacterAdded:Connect(function(newCharacter)
			local status = setUpCharacter(player, newCharacter, lookArrival(player, newCharacter))
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

-- The doorway shutter. Closing: it appears above the doorway, solid at once, and slides down into it. Opening: it slides back up,
-- then vanishes and stops blocking. A new move cancels one still running.
local shutterTween: Tween? = nil
local function moveShutter(close: boolean)
	if shutterTween then
		shutterTween:Cancel()
	end
	if close then
		if shutter.Transparency >= 1 then
			shutter.CFrame = shutterOpen
		end
		shutter.Transparency = 0
		shutter.CanCollide = true
	end
	local tween = TweenService:Create(shutter, TweenInfo.new(SHUTTER_TIME), { CFrame = if close then shutterClosed else shutterOpen })
	if not close then
		tween.Completed:Connect(function(playback)
			if playback == Enum.PlaybackState.Completed then
				shutter.Transparency = 1
				shutter.CanCollide = false
			end
		end)
	end
	shutterTween = tween
	tween:Play()
end

-- Bumped by every injection and every cancel: a sequence that wakes up to a different number was cancelled and stops there.
local sequence = 0
-- The limbs whose fuse is burning (limb key -> the sequence that lit it). Refused like a lost limb: the fuse outlasts Bob's trip home,
-- so without this he could be sent to inject a limb that is about to blow off.
local fusing: { [string]: number } = {}

local function setPhase(state: string)
	bob:SetAttribute("PhaseStart", workspace:GetServerTimeNow())
	bob:SetAttribute("State", state)
end

local function returnHome(mine: number)
	setPhase("Returning")
	task.wait(Timings.Return)
	if mine == sequence then
		bob:SetAttribute("Target", "")
		bob:SetAttribute("HardDrive", "")
		setPhase("Standby")
		moveShutter(false)
	end
end

local function runSequence(mine: number, player: Player, body: Model, character: Model?, hardDriveId: string, limbKey: string)
	bob:SetAttribute("Target", limbKey)
	bob:SetAttribute("HardDrive", hardDriveId)
	setPhase("Moving")
	moveShutter(true)
	task.wait(Timings.Move)
	if mine ~= sequence then
		return
	end
	setPhase("Injecting")
	task.wait(Timings.NeedleOut + Timings.Hold + Timings.NeedleIn)
	if mine ~= sequence then
		return
	end
	task.spawn(function()
		fusing[limbKey] = mine
		local ok, err = pcall(HardDriveEffects[hardDriveId], { body, character }, limbKey, function()
			return subject == body and player.Character == character and alive(body) and alive(character)
		end)
		if fusing[limbKey] == mine then
			fusing[limbKey] = nil
		end
		if not ok then
			warn("LabServer: the " .. hardDriveId .. " effect failed: " .. tostring(err))
		end
	end)
	returnHome(mine)
end

-- Bob drops what he is doing and goes home. Safe to call again: on Standby, or already Returning, there is nothing to stop (a
-- burning effect stops by itself, because its link is broken, so its limb no longer counts as fusing).
onLinkBroken = function()
	table.clear(fusing)
	local state = bob:GetAttribute("State")
	if state == "Moving" or state == "Injecting" then
		sequence += 1
		task.spawn(returnHome, sequence)
	end
end

local function listed(hardDriveId: any): boolean
	for _, entry in LabConfig.HardDrives do
		if entry.id == hardDriveId then
			return true
		end
	end
	return false
end

-- RequestInjection. Checks everything in this order, then starts the sequence and returns at once. The sequence sets State to
-- "Moving" before its first wait, so a second request in the same moment already finds Bob busy.
local function inject(player: Player, hardDriveId: any, limbKey: any): (boolean, string?)
	local body = subject
	if player ~= owner then
		return false, "NOT YOUR ROOM"
	elseif not (body and alive(body)) then
		return false, "NO SUBJECT"
	elseif bob:GetAttribute("State") ~= "Standby" then
		return false, "BOB IS BUSY"
	elseif not (listed(hardDriveId) and typeof(HardDriveEffects[hardDriveId]) == "function") then
		return false, "UNKNOWN HARDDRIVE"
	elseif not LabConfig.Limbs[limbKey] then
		return false, "UNKNOWN LIMB"
	elseif LabConfig.isLost(body, limbKey) or fusing[limbKey] then
		return false, "LIMB ALREADY LOST"
	end
	sequence += 1
	task.spawn(runSequence, sequence, player, body, player.Character, hardDriveId, limbKey)
	return true
end

local remotes = ReplicatedStorage:FindFirstChild("LabRemotes") or Instance.new("Folder")
remotes.Name = "LabRemotes"
local requestInjection = (remotes:FindFirstChild("RequestInjection") or Instance.new("RemoteFunction")) :: RemoteFunction
requestInjection.Name = "RequestInjection"
requestInjection.OnServerInvoke = inject
requestInjection.Parent = remotes
remotes.Parent = ReplicatedStorage

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
-- Bob starts on Standby, set here rather than trusted from the place file: this script owns the state it publishes.
bob:SetAttribute("Target", "")
bob:SetAttribute("HardDrive", "")
setPhase("Standby")

if RunService:IsStudio() then
	-- Test hook for tests/lab_claim.server.luau and tests/lab_inject.server.luau (execute_luau cannot reach this script's locals).
	local linkCalls = 0
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, player, hardDriveId, limbKey)
		if action == "claim" then
			return claim(player)
		elseif action == "release" then
			release(player)
		elseif action == "inject" then
			return inject(player, hardDriveId, limbKey)
		elseif action == "state" then
			return { owner = if owner then owner.UserId else 0, hasCopy = subject ~= nil, bobState = bob:GetAttribute("State") }
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
