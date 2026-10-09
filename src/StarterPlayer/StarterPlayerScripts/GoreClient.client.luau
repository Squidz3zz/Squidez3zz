-- GoreClient: the gore system on each player's own screen. For now it only makes a downed character crawl: once the server
-- marks the local character GoreDowned (both legs broken or gone), the character goes PlatformStand (it falls down and can no
-- longer stand or walk) and drags itself along the ground at GoreConfig CRAWL_SPEED (studs per second) the way the player
-- steers (Humanoid.MoveDirection, kept level). The pull is a LinearVelocity (in an Attachment named GoreCrawl on the
-- HumanoidRootPart) as strong as the body's weight, enough to drag the body but gentle. It stops when the character dies.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig"))

local player = Players.LocalPlayer

local function crawl(character: Model, humanoid: Humanoid, root: BasePart)
	if character:GetAttribute("GoreDowned") ~= true or humanoid.Health <= 0 or root:FindFirstChild("GoreCrawl") then
		return
	end
	humanoid.PlatformStand = true
	local mass = 0
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			mass += part:GetMass()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "GoreCrawl"
	local pull = Instance.new("LinearVelocity")
	pull.Attachment0 = attachment
	pull.RelativeTo = Enum.ActuatorRelativeTo.World
	pull.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	pull.PrimaryTangentAxis = Vector3.xAxis
	pull.SecondaryTangentAxis = Vector3.zAxis
	pull.MaxForce = mass * workspace.Gravity
	pull.Parent = attachment
	attachment.Parent = root
	local step
	step = RunService.PreSimulation:Connect(function()
		if humanoid.Health <= 0 or not attachment:IsDescendantOf(character) then
			step:Disconnect()
			attachment:Destroy()
			return
		end
		local move = humanoid.MoveDirection * GoreConfig.get("CRAWL_SPEED")
		pull.PlaneVelocity = Vector2.new(move.X, move.Z)
	end)
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not (humanoid and root) then
		return
	end
	character:GetAttributeChangedSignal("GoreDowned"):Connect(function()
		crawl(character, humanoid, root)
	end)
	crawl(character, humanoid, root)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
