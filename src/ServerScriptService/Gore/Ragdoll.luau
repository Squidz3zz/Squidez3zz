-- Ragdoll: what the gore system does to bodies (it sits inside Gore, which calls it; Gore's comments say when). It turns a
-- Broken arm or leg into a dangling one, rips a Severed one off and flings it, slows a body down when its legs go, and on every
-- death ragdolls the body and leaves it lying as a corpse.
--   Ragdoll.loosen(body, key)  the limb's Motor6D becomes a BallSocketConstraint (same name, under the Torso) with natural limits
--                              (LIMITS below), so it hangs and flops; the limb collides with the world but not with its own body
--                              (a NoCollisionConstraint with each of the body's other parts).
--   Ragdoll.sever(body, key, remove)
--                              the limb's joint (a Motor6D or a socket) goes and the limb part (with anything welded to it) leaves
--                              the body for Workspace: owned by the server, flung off (FLING_* below) and removed after
--                              LabConfig.LOST_LIMB_SECONDS. With remove (a body built already missing it, as Gore.copyState
--                              builds the lab's copy) the part is simply destroyed: nothing flies.
--   Movement (both of those):  one leg Broken or Severed sets WalkSpeed to GoreConfig LIMP_SPEED and JumpHeight (and JumpPower)
--                              to 0; both legs set the attribute GoreDowned = true on the body, and each player's GoreClient
--                              makes its own downed character crawl.
--   Ragdoll.watch(body)        runs Ragdoll.die(body) when the body's Humanoid dies (once per Humanoid).
--   Ragdoll.die(body)          every remaining Motor6D becomes a socket (the HumanoidRootPart's RootJoint becomes a Weld, so the
--                              invisible root stays inside the torso), every body part is unanchored and collides (not with
--                              the body's other parts), and the corpse is made: a Model named Corpse in Workspace.Corpses (made
--                              when missing) takes every child of the body but its Humanoid and its Tools (a held tool, such as
--                              the lab's tablet, is destroyed), the body's attributes and tags (so it stays a GoreBody that
--                              blasts still tear), its link (Gore.link: the corpse takes the dead body's place), GoreDiedAt
--                              (server time) and, for a player's character, GoreOwner (their UserId; another body keeps any
--                              GoreOwner it had, as the lab's copy carries its owner's). The Humanoid stays
--                              in the emptied body, which is left for whoever removes it (a respawn); the corpse gets a still
--                              Humanoid of its own (Health 0, no state machine) so its clothes keep showing. The corpse's parts
--                              are owned by the server. Each owner (bodies with no owner count as one) keeps at most GoreConfig
--                              CORPSES_PER_PLAYER corpses, the oldest going first. After CORPSE_LIFE seconds a corpse sinks (no
--                              collisions, SINK_DEPTH studs down over SINK_TIME) and is destroyed. A body dies once: a second
--                              call does nothing.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig", 5) or error("Gore: GoreConfig is missing"))
local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig", 5) or error("Gore: LabConfig is missing"))
local Integrity = require(script.Parent:WaitForChild("Integrity", 5) or error("Gore: Integrity is missing"))

-- Each R6 joint's limits, in degrees: how far the limb swings away from hanging straight (a cone) and how far it twists about
-- its own length.
local LIMITS = {
	Neck = { cone = 40, twist = 30 },
	["Left Shoulder"] = { cone = 70, twist = 45 },
	["Right Shoulder"] = { cone = 70, twist = 45 },
	["Left Hip"] = { cone = 50, twist = 30 },
	["Right Hip"] = { cone = 50, twist = 30 },
}
-- A severed arm or leg is flung by Roblox physics, as the lab's Explosive flung a blown-off limb before the gore system: off in
-- a random direction, 20 to 60 degrees above level, at a random speed in FLING_SPEED (studs per second), spinning at up to
-- FLING_SPIN radians per second.
local FLING_SPEED = NumberRange.new(15, 30)
local FLING_SPIN = 15
local SINK_DEPTH = 4
local SINK_TIME = 2

local random = Random.new()
local watched: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local warned = false

local Ragdoll = {}

-- Swaps a Motor6D for a BallSocketConstraint of the same name. Its attachments sit on the joint with their X axes along the
-- limb (down an arm or a leg, up the neck), so the cone limits the swing away from hanging straight and the twist the turn
-- about the limb's length.
local function socket(joint: Motor6D)
	local limit = LIMITS[joint.Name]
	local along = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, if joint.Name == "Neck" then 1 else -1, 0), Vector3.xAxis)
	local limbEnd = Instance.new("Attachment")
	limbEnd.Name = joint.Name .. " Socket"
	limbEnd.CFrame = CFrame.new(joint.C1.Position) * along
	local torsoEnd = Instance.new("Attachment")
	torsoEnd.Name = limbEnd.Name
	-- Where the limb's end sits in the torso's space when the joint is at rest.
	torsoEnd.CFrame = joint.C0 * joint.C1:Inverse() * limbEnd.CFrame
	limbEnd.Parent = joint.Part1
	torsoEnd.Parent = joint.Part0
	local ball = Instance.new("BallSocketConstraint")
	ball.Name = joint.Name
	ball.Attachment0 = torsoEnd
	ball.Attachment1 = limbEnd
	ball.LimitsEnabled = true
	ball.UpperAngle = limit.cone
	ball.TwistLimitsEnabled = true
	ball.TwistLowerAngle = -limit.twist
	ball.TwistUpperAngle = limit.twist
	ball.Parent = joint.Parent
	joint:Destroy()
end

-- `part` stops colliding with each of the body's other parts (once per pair).
local function noCollide(body: Model, part: BasePart)
	local done = {}
	for _, thing in body:GetDescendants() do
		if thing:IsA("NoCollisionConstraint") and (thing.Part0 == part or thing.Part1 == part) then
			done[if thing.Part0 == part then thing.Part1 else thing.Part0] = true
		end
	end
	for _, other in body:GetChildren() do
		if other:IsA("BasePart") and other ~= part and not done[other] then
			local pair = Instance.new("NoCollisionConstraint")
			pair.Name = "GoreNoCollide"
			pair.Part0 = part
			pair.Part1 = other
			pair.Parent = part
		end
	end
end

local function limp(body: Model)
	local out = 0
	for _, key in { "LeftLeg", "RightLeg" } do
		local state = body:GetAttribute("Gore_" .. key)
		if state == "Broken" or state == "Severed" then
			out += 1
		end
	end
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if out > 0 and humanoid then
		humanoid.WalkSpeed = GoreConfig.get("LIMP_SPEED")
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
	if out == 2 then
		body:SetAttribute("GoreDowned", true)
	end
end

local function sink(corpse: Model)
	if not corpse.Parent then
		return
	end
	local info = TweenInfo.new(SINK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, part in corpse:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			TweenService:Create(part, info, { CFrame = part.CFrame - Vector3.new(0, SINK_DEPTH, 0) }):Play()
		end
	end
	Debris:AddItem(corpse, SINK_TIME)
end

function Ragdoll.loosen(body: Model, key: string)
	local joint = LabConfig.limbJoint(body, key)
	if joint and joint:IsA("Motor6D") and LIMITS[joint.Name] then
		local limb = joint.Part1
		socket(joint)
		if limb then
			limb.CanCollide = true
			noCollide(body, limb)
		end
	end
	limp(body)
end

function Ragdoll.sever(body: Model, key: string, remove: boolean?)
	local spec = LabConfig.Limbs[key]
	local torso = body:FindFirstChild("Torso")
	local joint = spec and spec.joint and torso and torso:FindFirstChild(spec.joint)
	if joint then
		joint:Destroy()
	end
	for _, part in LabConfig.limbParts(body, key) do
		if remove then
			part:Destroy()
			continue
		end
		part.Anchored = false
		part.CanCollide = true
		part.Parent = workspace
		pcall(part.SetNetworkOwner, part, nil)
		local heading, climb = random:NextNumber(0, 2 * math.pi), math.rad(random:NextNumber(20, 60))
		local direction = Vector3.new(math.cos(heading) * math.cos(climb), math.sin(climb), math.sin(heading) * math.cos(climb))
		part.AssemblyLinearVelocity = direction * random:NextNumber(FLING_SPEED.Min, FLING_SPEED.Max)
		part.AssemblyAngularVelocity = random:NextUnitVector() * random:NextNumber(0, FLING_SPIN)
		Debris:AddItem(part, LabConfig.LOST_LIMB_SECONDS)
	end
	limp(body)
end

function Ragdoll.die(body: Model)
	if body:GetAttribute("GoreDiedAt") ~= nil then
		return
	end
	body:SetAttribute("GoreDiedAt", workspace:GetServerTimeNow())
	for _, joint in body:GetDescendants() do
		if joint:IsA("Motor6D") then
			if LIMITS[joint.Name] then
				socket(joint)
			else
				local weld = Instance.new("Weld")
				weld.Name = joint.Name
				weld.Part0, weld.Part1, weld.C0, weld.C1 = joint.Part0, joint.Part1, joint.C0, joint.C1
				weld.Parent = joint.Parent
				joint:Destroy()
			end
		end
	end

	local folder = workspace:FindFirstChild("Corpses")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Corpses"
		folder.Parent = workspace
	end
	local corpse = Instance.new("Model")
	corpse.Name = "Corpse"
	for name, value in body:GetAttributes() do
		corpse:SetAttribute(name, value)
	end
	local player = Players:GetPlayerFromCharacter(body)
	if player then
		corpse:SetAttribute("GoreOwner", player.UserId)
	end
	for _, tag in CollectionService:GetTags(body) do
		CollectionService:AddTag(corpse, tag)
	end
	Integrity.relink(body, corpse)
	-- In Workspace before the parts move in, so they never leave it (and keep falling as they were).
	corpse.Parent = folder
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	for _, child in body:GetChildren() do
		if child:IsA("Tool") then
			child:Destroy()
		elseif child ~= humanoid then
			child.Parent = corpse
		end
	end
	-- The Humanoid itself stays with the body, for everything that still holds it (the player's controls and camera, the lab).
	-- The corpse gets a still one (no state machine, so it never stands up), which keeps the clothes showing.
	local still = Instance.new("Humanoid")
	still.RigType = if humanoid then humanoid.RigType else Enum.HumanoidRigType.R6
	still.EvaluateStateMachine = false
	still.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	still.Health = 0
	still.Parent = corpse
	-- Only now: a Humanoid joining a body sets its arms and legs not to collide.
	for _, part in corpse:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = part.Name ~= "HumanoidRootPart"
			noCollide(corpse, part)
		end
	end
	corpse.PrimaryPart = corpse:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, part in corpse:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(part.SetNetworkOwner, part, nil)
		end
	end

	local owner = corpse:GetAttribute("GoreOwner")
	local same = {}
	for _, other in folder:GetChildren() do
		if other:GetAttribute("GoreOwner") == owner then
			table.insert(same, other)
		end
	end
	table.sort(same, function(a, b)
		return (a:GetAttribute("GoreDiedAt") or 0) < (b:GetAttribute("GoreDiedAt") or 0)
	end)
	for index = 1, #same - GoreConfig.get("CORPSES_PER_PLAYER") do
		same[index]:Destroy()
	end
	task.delay(GoreConfig.get("CORPSE_LIFE"), sink, corpse)
end

function Ragdoll.watch(body: Model)
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid and not watched[humanoid] then
		watched[humanoid] = true
		humanoid.Died:Once(function()
			local ok, err = pcall(Ragdoll.die, body)
			if not ok and not warned then
				warned = true
				warn("Gore: the death ragdoll failed: " .. tostring(err))
			end
		end)
	end
end

return Ragdoll
