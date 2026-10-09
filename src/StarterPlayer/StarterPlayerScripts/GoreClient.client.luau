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
-- Drips and pools (GORE_LEVEL 1 and up). Every DRIP_TICK seconds, each GoreBody that is alive (a living Humanoid), or a corpse
-- younger than GoreConfig DRIP_AFTER_DEATH (from its GoreDiedAt), drips from each open limb (Torn, Broken or Severed): a
-- ParticleEmitter named GoreDrip of dark-red drops falling under gravity, in the limb part, or for a severed limb in an
-- Attachment GoreDrip_<Limb> on the Torso where the limb hung (the flying limb drips no more). Once a body stops dripping its
-- emitters are switched off. The emptied character a death leaves behind (no Torso) is skipped.
-- While a body drips, a pool grows under it: a glossy dark-red disc (a part named GorePool in Workspace.GorePools) where a ray
-- straight down from the Torso (POOL_REACH studs, past bodies and chunks; pools can't be hit) meets something that
-- collides. It starts POOL_START studs across and widens by POOL_GROW studs a second for each dripping limb, up to GoreConfig
-- POOL_MAX. A body that has moved POOL_MOVE studs from its pool starts a new one there. A corpse's pools stay as long as the
-- corpse; any other body's pool stays SPLAT_LIFE seconds after it last grew. At most POOL_CAP pools at once; the oldest goes
-- first.
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
		-- A severed limb drips from its stump now (below), not from the limb flying off.
		local drip = state == "Severed" and part and part:FindFirstChild("GoreDrip")
		if drip then
			drip:Destroy()
		end
	end)
end

CollectionService:GetInstanceAddedSignal("GoreBody"):Connect(watchBody)
for _, body in CollectionService:GetTagged("GoreBody") do
	watchBody(body)
end

local OPEN = { Torn = true, Broken = true, Severed = true }
local DRIP_TICK = 0.25
local DRIP_COLOR = Color3.fromRGB(95, 0, 0)
local POOL_COLOR = Color3.fromRGB(70, 0, 0)
local POOL_START = 0.5
local POOL_GROW = 0.15
local POOL_REACH = 20
local POOL_MOVE = 1.5
local POOL_THICK = 0.05
local POOL_CAP = 40
-- Where a severed limb's stump drips from, in the Torso's space: just inside the top of the limb as it hung.
local STUMP_AT = {
	LeftArm = Vector3.new(-1.5, 0.9, 0),
	RightArm = Vector3.new(1.5, 0.9, 0),
	LeftLeg = Vector3.new(-0.5, -1.1, 0),
	RightLeg = Vector3.new(0.5, -1.1, 0),
}

type Pool = { part: BasePart, torso: BasePart, size: number, lastDrip: number, corpse: boolean }
local pools: { Pool } = {} -- oldest first
local poolOf: { [BasePart]: Pool } = setmetatable({}, { __mode = "k" }) :: any
local poolFolder: Folder? = nil

local function newDrip(): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "GoreDrip"
	emitter.Texture = "rbxasset://textures/smallWhiteCircle.png"
	emitter.Color = ColorSequence.new(DRIP_COLOR)
	emitter.Size = NumberSequence.new(0.12, 0.08)
	emitter.LightInfluence = 1
	emitter.Rate = 10
	emitter.Lifetime = NumberRange.new(0.2, 0.35)
	emitter.Speed = NumberRange.new(0, 1)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Acceleration = Vector3.new(0, -workspace.Gravity, 0)
	return emitter
end

local function dripping(body: Model): boolean
	local diedAt = body:GetAttribute("GoreDiedAt")
	if diedAt then
		return workspace:GetServerTimeNow() < diedAt + GoreConfig.get("DRIP_AFTER_DEATH")
	end
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Grows the pool under `torso` by `grow` (studs across), or starts one.
local function pour(torso: BasePart, grow: number, params: RaycastParams)
	local hit = workspace:Raycast(torso.Position, Vector3.new(0, -POOL_REACH, 0), params)
	if not hit then
		return
	end
	local pool = poolOf[torso]
	if not pool or not pool.part.Parent or (pool.part.Position - hit.Position).Magnitude > POOL_MOVE then
		if not (poolFolder and poolFolder.Parent) then
			poolFolder = Instance.new("Folder")
			poolFolder.Name = "GorePools"
			poolFolder.Parent = workspace
		end
		while #pools >= POOL_CAP do
			table.remove(pools, 1).part:Destroy()
		end
		local part = Instance.new("Part")
		part.Name = "GorePool"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Glass
		part.Reflectance = 0.2
		part.Color = POOL_COLOR
		-- The disc's axis (X) along the surface normal, lifted a little (a random bit more, so overlapping pools don't flicker).
		local normal = hit.Normal
		local side = if math.abs(normal.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
		part.CFrame = CFrame.fromMatrix(hit.Position + normal * (POOL_THICK / 2 + random:NextNumber(0.005, 0.02)), normal, normal:Cross(side).Unit)
		pool = { part = part, torso = torso, size = POOL_START, lastDrip = 0, corpse = false }
		poolOf[torso] = pool
		table.insert(pools, pool)
		part.Parent = poolFolder
	else
		pool.size = math.min(GoreConfig.get("POOL_MAX"), pool.size + grow)
	end
	pool.part.Size = Vector3.new(POOL_THICK, pool.size, pool.size)
	pool.lastDrip = os.clock()
end

local function dripTick(dt: number)
	local level = GoreConfig.get("GORE_LEVEL")
	local bodies = CollectionService:GetTagged("GoreBody")
	local params: RaycastParams? = nil
	for _, body in bodies do
		local torso = body:FindFirstChild("Torso")
		if not (body:IsA("Model") and torso and torso:IsA("BasePart")) then
			continue
		end
		local on = level >= 1 and dripping(body)
		local flowing = 0
		for _, key in LabConfig.LIMB_KEYS do
			local state = body:GetAttribute("Gore_" .. key)
			local open = on and OPEN[state] == true
			local holder: Instance? = if state == "Severed" then torso:FindFirstChild("GoreDrip_" .. key) else LabConfig.limbParts(body, key)[1]
			if open and not holder and STUMP_AT[key] then
				local stump = Instance.new("Attachment")
				stump.Name = "GoreDrip_" .. key
				stump.Position = STUMP_AT[key]
				stump.Parent = torso
				holder = stump
			end
			local emitter = holder and holder:FindFirstChild("GoreDrip")
			if open and holder and not emitter then
				emitter = newDrip()
				emitter.Parent = holder
			end
			if emitter then
				(emitter :: ParticleEmitter).Enabled = open
			end
			if open and holder then
				flowing += 1
			end
		end
		if flowing > 0 then
			if not params then
				params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.RespectCanCollide = true
				local skip: { Instance } = table.clone(bodies)
				if chunkFolder then
					table.insert(skip, chunkFolder)
				end
				params.FilterDescendantsInstances = skip
			end
			pour(torso, flowing * POOL_GROW * dt, params :: RaycastParams)
		end
	end
	-- A corpse's pools go with the corpse; the others SPLAT_LIFE after they last grew.
	local life = GoreConfig.get("SPLAT_LIFE")
	for index = #pools, 1, -1 do
		local pool = pools[index]
		local owner = pool.torso.Parent
		if owner then
			pool.corpse = owner:GetAttribute("GoreDiedAt") ~= nil
		end
		local gone = if pool.corpse then owner == nil else os.clock() - pool.lastDrip > life
		if gone or not pool.part.Parent then
			pool.part:Destroy()
			table.remove(pools, index)
		end
	end
end

task.spawn(function()
	local dripWarned = false
	while true do
		local ok, err = pcall(dripTick, task.wait(DRIP_TICK))
		if not ok and not dripWarned then
			dripWarned = true
			warn("GoreClient: drips failed: " .. tostring(err))
		end
	end
end)

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
