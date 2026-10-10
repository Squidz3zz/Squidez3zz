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
-- While a body drips and its Torso is nearly still (slower than POOL_STILL studs a second: a body walking, falling or
-- slumping only drips until it settles), a pool grows under it: a glossy dark-red disc (a part named GorePool in
-- Workspace.GorePools) where a ray straight down from the Torso (POOL_REACH studs, past bodies and chunks; pools can't be
-- hit) meets something that collides. It starts POOL_START studs across and widens by POOL_GROW studs a second for each
-- dripping limb, up to GoreConfig POOL_MAX. A body that settles POOL_MOVE studs from its pool starts a new one there. A
-- corpse's pools stay as long as the corpse; any other body's pool stays SPLAT_LIFE seconds after it last grew. At most
-- POOL_CAP pools at once: past that the oldest pool that is not a corpse's goes first (the oldest corpse pool only when
-- every pool is a corpse's).
--
-- Blood (every blood boom: BoomEvent with blood true, from the server's Booms.at, with the direction the blood flies; none means
-- down). In an Attachment named BloodBurst in Workspace.Terrain, its up along that direction, go clones of everything in
-- ReplicatedStorage.LabAssets.Blood: the user's blood sounds (every Sound there, played in SoundService.SFX) and its two
-- emitters, each fired once with its EmitCount attribute. Spray becomes a forceful jet: twice the droplets, 1.6 times the size,
-- at SPRAY_SPEED studs per second in a cone SPRAY_CONE degrees across, slowed by SPRAY_DRAG. Mist becomes a thick haze: twice
-- as many, twice the size, more opaque (each transparency squared) and lasting MIST_LIFE seconds. The attachment goes once
-- they and the sounds are over. Then the splats: SPLAT_RAYS rays in a cone SPLAT_CONE degrees across along the direction and
-- SPLAT_DOWN_RAYS more downward, each up to SPLAT_REACH studs. Where one meets a fixed surface (grounded, colliding; never a
-- body, a corpse, Bob, Room1.Shutter, a chunk, a pool or another splat; the floor, the walls, the chair and the observation
-- glass are) a splat sticks: a thin glossy dark-red ellipse (SmoothPlastic, Reflectance 0.2, a SpecialMesh Cylinder, no
-- decal; a part named BloodSplat in Workspace.GoreSplats) SPLAT_SIZE studs across and up to 1.4 times that long, turned at
-- random, lifted a random hair off the surface so overlapping ones don't flicker. On a wall or the glass it runs down:
-- SPLAT_STRETCH times longer down the surface. Each fades out over its
-- last SPLAT_FADE seconds and goes after GoreConfig SPLAT_LIFE; at most SPLAT_MAX at once, the oldest first. At GORE_LEVEL 0
-- the blood is the simple one from before: the emitters as they are and only the downward splats. Without LabAssets.Blood it
-- warns once and blasts do not bleed. Only this player sees them.
-- In Studio, a BindableFunction TestHook in this script: TestHook:Invoke("splatter", position, direction) casts one burst's
-- splat rays and returns how many stuck.
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
local SoundService = game:GetService("SoundService")
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
local POOL_STILL = 2
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
			local index = 1
			for i, other in pools do
				if not other.corpse then
					index = i
					break
				end
			end
			table.remove(pools, index).part:Destroy()
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
		if flowing > 0 and torso.AssemblyLinearVelocity.Magnitude < POOL_STILL then
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

-- Blood bursts: every blood boom (BoomEvent with blood true, from the server's Booms.at) with its direction (nil: down).
local BURST_LINGER = 0.5
local SPRAY_SPEED = NumberRange.new(40, 90)
local SPRAY_CONE = 45 -- degrees across
local SPRAY_LIFE = NumberRange.new(0.3, 0.6)
local SPRAY_DRAG = 4
local MIST_LIFE = NumberRange.new(2.5, 3.5)
local SPLAT_RAYS = 12
local SPLAT_CONE = 60 -- degrees across
local SPLAT_DOWN_RAYS = 4
local SPLAT_DOWN_CONE = 40
local SPLAT_REACH = 24
local SPLAT_SIZE = NumberRange.new(1, 2.4)
local SPLAT_STRETCH = NumberRange.new(1.5, 2.5)
local SPLAT_THICK = 0.04
local SPLAT_FADE = 5
local SPLAT_COLOR = Color3.fromRGB(70, 0, 0)

local splats: { BasePart } = {} -- oldest first
local splatFolder: Folder? = nil
local bloodWarned = false

-- A random direction within `cone` degrees (across) of `direction`.
local function inCone(direction: Vector3, cone: number): Vector3
	local up = if math.abs(direction.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local basis = CFrame.lookAt(Vector3.zero, direction, up)
	return (basis * CFrame.Angles(0, 0, random:NextNumber(0, 2 * math.pi)) * CFrame.Angles(math.rad(random:NextNumber(0, cone / 2)), 0, 0)).LookVector
end

-- Squares every value: a sequence of transparencies turns more opaque but still starts and ends where it did.
local function denser(sequence: NumberSequence): NumberSequence
	local points = {}
	for _, point in sequence.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value ^ 2, point.Envelope))
	end
	return NumberSequence.new(points)
end

local function scaled(sequence: NumberSequence, by: number): NumberSequence
	local points = {}
	for _, point in sequence.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value * by, point.Envelope * by))
	end
	return NumberSequence.new(points)
end

local function splatAt(hit: RaycastResult)
	if not (splatFolder and splatFolder.Parent) then
		splatFolder = Instance.new("Folder")
		splatFolder.Name = "GoreSplats"
		splatFolder.Parent = workspace
	end
	while #splats >= GoreConfig.get("SPLAT_MAX") do
		table.remove(splats, 1):Destroy()
	end
	local normal = hit.Normal
	local size = random:NextNumber(SPLAT_SIZE.Min, SPLAT_SIZE.Max)
	local length, along = size, nil
	if math.abs(normal.Y) < 0.5 then
		-- A wall or the glass: run down it, turned a little either way.
		local down = (-Vector3.yAxis - normal * -normal.Y).Unit
		along = CFrame.fromAxisAngle(normal, math.rad(random:NextNumber(-12, 12))) * down
		length = size * random:NextNumber(SPLAT_STRETCH.Min, SPLAT_STRETCH.Max)
	else
		along = CFrame.fromAxisAngle(normal, random:NextNumber(0, 2 * math.pi)) * normal:Cross(if math.abs(normal.X) < 0.9 then Vector3.xAxis else Vector3.zAxis).Unit
		length = size * random:NextNumber(1, 1.4)
	end
	local splat = Instance.new("Part")
	splat.Name = "BloodSplat"
	-- An ellipse: a cylinder mesh fills the part's whole box (a Cylinder part's face is always round; a squashed sphere mesh
	-- shades like a ball). Its axis is its Y.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = splat
	splat.Anchored = true
	splat.CanCollide = false
	splat.CanQuery = false
	splat.CanTouch = false
	splat.CastShadow = false
	splat.Material = Enum.Material.SmoothPlastic -- Glass renders these pale; a reflective smooth surface stays dark red
	splat.Reflectance = 0.2
	splat.Color = SPLAT_COLOR:Lerp(Color3.new(), random:NextNumber(0, 0.3))
	splat.Size = Vector3.new(size, SPLAT_THICK, length)
	-- Its thin axis (Y) along the normal, its long side (Z) along `along`, centred where the blood hit. Lifted a random little
	-- bit, so overlapping splats don't flicker.
	local centre = hit.Position + normal * (SPLAT_THICK / 2 + random:NextNumber(0.005, 0.03))
	splat.CFrame = CFrame.fromMatrix(centre, normal:Cross(along), normal)
	splat.Parent = splatFolder
	table.insert(splats, splat)
	splat.Destroying:Once(function()
		local index = table.find(splats, splat)
		if index then
			table.remove(splats, index)
		end
	end)
	local life = GoreConfig.get("SPLAT_LIFE")
	local fade = math.min(SPLAT_FADE, life)
	task.delay(life - fade, function()
		if splat.Parent then
			TweenService:Create(splat, TweenInfo.new(fade, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(splat, life)
end

-- Casts the splat rays from `position` and sticks a splat wherever one meets a fixed surface: something grounded that
-- collides, never a body, a corpse, Bob, the Shutter, a chunk, a pool or another splat. Returns how many it made.
local function splatter(position: Vector3, direction: Vector3): number
	local room = workspace:FindFirstChild("Room1")
	local skip: { Instance } = CollectionService:GetTagged("GoreBody")
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	for _, thing in { workspace:FindFirstChild("Corpses"), room and room:FindFirstChild("BobTheInjector"), room and room:FindFirstChild("Shutter"), chunkFolder, poolFolder, splatFolder } do
		if thing then
			table.insert(skip, thing)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local rays: { Vector3 } = {}
	if GoreConfig.get("GORE_LEVEL") >= 1 then
		for _ = 1, SPLAT_RAYS do
			table.insert(rays, inCone(direction, SPLAT_CONE))
		end
	end
	for _ = 1, SPLAT_DOWN_RAYS do
		table.insert(rays, inCone(-Vector3.yAxis, SPLAT_DOWN_CONE))
	end
	local made = 0
	for _, ray in rays do
		local hit = workspace:Raycast(position, ray * SPLAT_REACH, params)
		if hit and hit.Instance:IsGrounded() then
			splatAt(hit)
			made += 1
		end
	end
	return made
end

-- The spray, the mist and the sounds (a clone of everything in LabAssets.Blood) in an Attachment named BloodBurst, its up
-- along the jet; then the splats.
local function bleed(position: Vector3, direction: Vector3)
	local assets = ReplicatedStorage:FindFirstChild("LabAssets")
	local blood = assets and assets:FindFirstChild("Blood")
	if not blood then
		if not bloodWarned then
			bloodWarned = true
			warn("GoreClient: ReplicatedStorage.LabAssets.Blood is missing, so limb blasts do not bleed")
		end
		return
	end
	local full = GoreConfig.get("GORE_LEVEL") >= 1
	local burst = Instance.new("Attachment")
	burst.Name = "BloodBurst"
	local side = direction:Cross(if math.abs(direction.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis).Unit
	burst.CFrame = CFrame.fromMatrix(position, side, direction) -- Terrain sits at the origin: this is the world CFrame
	burst.Parent = workspace.Terrain
	local over = 0
	for _, asset in blood:GetChildren() do
		local ok, err = pcall(function()
			if asset:IsA("ParticleEmitter") then
				local emitter = asset:Clone()
				local count = tonumber(asset:GetAttribute("EmitCount")) or 20
				if full and asset.Name == "Spray" then
					-- A forceful jet: twice the droplets, fast, in a cone along the direction, slowed by the air.
					emitter.EmissionDirection = Enum.NormalId.Top
					emitter.Speed = SPRAY_SPEED
					emitter.SpreadAngle = Vector2.new(SPRAY_CONE / 2, SPRAY_CONE / 2)
					emitter.Lifetime = SPRAY_LIFE
					emitter.Drag = SPRAY_DRAG
					emitter.Size = scaled(emitter.Size, 1.6)
					count *= 2
				elseif full and asset.Name == "Mist" then
					-- A thick mist: bigger, more opaque, lasting about 3 s.
					emitter.Size = scaled(emitter.Size, 2)
					emitter.Transparency = denser(emitter.Transparency)
					emitter.Lifetime = MIST_LIFE
					count *= 2
				end
				emitter.Parent = burst
				over = math.max(over, emitter.Lifetime.Max)
				emitter:Emit(count)
			elseif asset:IsA("Sound") then
				local sound = asset:Clone()
				sound.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
				sound.TimePosition = 0
				sound.Parent = burst
				sound:Play()
				if sound.PlaybackSpeed > 0 then
					over = math.max(over, math.max(sound.TimeLength, asset.TimeLength) / sound.PlaybackSpeed)
				end
			end
		end)
		if not ok and not bloodWarned then
			bloodWarned = true
			warn("GoreClient: skipped " .. asset:GetFullName() .. ": " .. tostring(err))
		end
	end
	Debris:AddItem(burst, over + BURST_LINGER)
	splatter(position, direction)
end

local function finite(v: any): boolean
	return typeof(v) == "Vector3" and math.abs(v.X) + math.abs(v.Y) + math.abs(v.Z) < math.huge -- NaN fails this too
end

task.spawn(function()
	ReplicatedStorage:WaitForChild("BoomEvent").OnClientEvent:Connect(function(position, blood, direction)
		if blood ~= true or not finite(position) then
			return
		end
		direction = if finite(direction) and direction.Magnitude > 0.01 then direction.Unit else -Vector3.yAxis
		local ok, err = pcall(bleed, position, direction)
		if not ok and not bloodWarned then
			bloodWarned = true
			warn("GoreClient: blood failed: " .. tostring(err))
		end
	end)
end)

if RunService:IsStudio() then
	-- For the tests: TestHook:Invoke("splatter", position, direction) casts one burst's splat rays and returns how many stuck.
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, position, direction)
		if action == "splatter" then
			return splatter(position, direction.Unit)
		end
		error("GoreClient.TestHook: unknown action " .. tostring(action))
	end
	hook.Parent = script
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
