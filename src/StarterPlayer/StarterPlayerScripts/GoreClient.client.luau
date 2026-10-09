-- GoreClient: the gore system on each player's own screen.
--
-- Skin chunks (GORE_LEVEL 2 only): whenever a limb of any GoreBody (a character, a copy, a corpse) changes to Torn or Severed,
-- GoreConfig CHUNKS_MIN to CHUNKS_MAX chunks of skin burst off it: small wedges and blocks (CHUNK_SIZE studs a side) in the
-- limb's BodyColors colour, thrown out from where the part is at that moment (a severed limb is already flying) at CHUNK_SPEED
-- studs per second, away from the torso and a little up, tumbling. They hit the world but not bodies (a NoCollisionConstraint
-- with the limb itself and with each part directly in a GoreBody within NEAR_BODIES studs: its R6 parts and root, not the
-- flesh or accessories, which never collide), lie there until CHUNK_REST seconds after the burst, fade out over 1 s and are
-- gone. At most CHUNK_CAP live at once; the oldest goes first. They are this client's own parts (named GoreChunk, in
-- Workspace.GoreChunks): nobody else sees them, and the server never knows.
--
-- Crawling: once the server marks the local character GoreDowned (both legs broken or gone), the character goes PlatformStand
-- (it falls down and can no longer stand or walk) and drags itself along the ground at GoreConfig CRAWL_SPEED (studs per
-- second) the way the player steers (Humanoid.MoveDirection, kept level). The pull is a LinearVelocity (in an Attachment
-- named GoreCrawl on the HumanoidRootPart) as strong as the body's weight, enough to drag the body but gentle. It stops when
-- the character dies.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig"))
local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))

local CHUNK_SIZE = NumberRange.new(0.2, 0.5)
local CHUNK_SPEED = NumberRange.new(10, 25)
local CHUNK_SPIN = 20 -- radians per second, at most
local CHUNK_CAP = 200
local NEAR_BODIES = 50
local FADE = TweenInfo.new(1)

local player = Players.LocalPlayer
local random = Random.new()
local live: { BasePart } = {} -- oldest first
local chunkFolder: Folder? = nil

-- The parts a burst from `source` must not hit: the source and every BasePart directly in a GoreBody within NEAR_BODIES studs.
-- Gathered once per burst and shared by its chunks.
local function bodyPartsNear(source: BasePart): { BasePart }
	local origin = source.Position
	local parts = { source }
	for _, body in CollectionService:GetTagged("GoreBody") do
		for _, part in body:GetChildren() do
			if part:IsA("BasePart") and part ~= source and (part.Position - origin).Magnitude < NEAR_BODIES then
				table.insert(parts, part)
			end
		end
	end
	return parts
end

-- ponytail: one constraint per chunk per nearby body part (a few hundred per burst); a client collision group if it ever shows.
local function noCollide(chunk: BasePart, others: { BasePart })
	for _, other in others do
		local constraint = Instance.new("NoCollisionConstraint")
		constraint.Part0 = chunk
		constraint.Part1 = other
		constraint.Parent = chunk
	end
end

local function forget(chunk: BasePart)
	local index = table.find(live, chunk)
	if index then
		table.remove(live, index)
	end
end

local function burst(body: Model, key: string, part: BasePart)
	if not (chunkFolder and chunkFolder.Parent) then
		chunkFolder = Instance.new("Folder")
		chunkFolder.Name = "GoreChunks"
		chunkFolder.Parent = workspace
	end
	local colours = body:FindFirstChildOfClass("BodyColors")
	local colour = if colours then (colours :: any)[key .. "Color3"] else part.Color
	local torso = body:FindFirstChild("Torso")
	local outward = if torso and torso ~= part then part.Position - torso.Position else Vector3.zero
	outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.zero
	local rest = GoreConfig.get("CHUNK_REST")
	local bodyParts = bodyPartsNear(part)
	for _ = 1, random:NextInteger(GoreConfig.get("CHUNKS_MIN"), GoreConfig.get("CHUNKS_MAX")) do
		while #live >= CHUNK_CAP do
			table.remove(live, 1):Destroy()
		end
		local direction = random:NextUnitVector() + outward + Vector3.yAxis * 0.5
		direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.yAxis
		local chunk = Instance.new(if random:NextNumber() < 0.5 then "WedgePart" else "Part") :: BasePart
		chunk.Name = "GoreChunk"
		chunk.Size = Vector3.new(
			random:NextNumber(CHUNK_SIZE.Min, CHUNK_SIZE.Max),
			random:NextNumber(CHUNK_SIZE.Min, CHUNK_SIZE.Max),
			random:NextNumber(CHUNK_SIZE.Min, CHUNK_SIZE.Max)
		)
		chunk.Color = colour:Lerp(Color3.new(), random:NextNumber(0, 0.2)) -- a little shading so they read as separate bits
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.CFrame = CFrame.new(part.Position + direction * 0.5) * CFrame.fromOrientation(random:NextNumber(0, 6.3), random:NextNumber(0, 6.3), 0)
		noCollide(chunk, bodyParts)
		chunk.Parent = chunkFolder
		-- Once in Workspace: set before, a wedge (centre of mass off its middle) would start a little off this speed.
		chunk.AssemblyAngularVelocity = random:NextUnitVector() * random:NextNumber(0, CHUNK_SPIN)
		chunk.AssemblyLinearVelocity = direction * random:NextNumber(CHUNK_SPEED.Min, CHUNK_SPEED.Max)
		table.insert(live, chunk)
		chunk.Destroying:Once(function()
			forget(chunk)
		end)
		task.delay(rest, function()
			if chunk.Parent then
				TweenService:Create(chunk, FADE, { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(chunk, rest + FADE.Time)
	end
end

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watchBody(body: Instance)
	if watched[body] or not body:IsA("Model") then
		return
	end
	watched[body] = true
	-- The limb parts, kept after they leave the body (a severed limb flies off into Workspace as its state changes).
	local parts: { [string]: BasePart } = {}
	local function partOf(key: string): BasePart?
		parts[key] = LabConfig.limbParts(body, key)[1] or parts[key]
		return parts[key]
	end
	for _, key in LabConfig.LIMB_KEYS do
		partOf(key)
	end
	body.AttributeChanged:Connect(function(name)
		local key = string.match(name, "^Gore_(.+)$")
		if not (key and LabConfig.Limbs[key]) then
			return
		end
		local part = partOf(key)
		local state = body:GetAttribute(name)
		if (state == "Torn" or state == "Severed") and part and part.Parent and GoreConfig.get("GORE_LEVEL") >= 2 then
			burst(body, key, part)
		end
	end)
end

CollectionService:GetInstanceAddedSignal("GoreBody"):Connect(watchBody)
for _, body in CollectionService:GetTagged("GoreBody") do
	watchBody(body)
end

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
