-- BoomClient: this player's side of every explosion. The server's Booms.at fires ReplicatedStorage.BoomEvent with a position
-- (anything that is not a finite Vector3 is ignored) and whether it bleeds, and here each boom:
--   * looks and sounds like the user's explosion: an Attachment "Boom" in workspace.Terrain at the position gets a clone of every
--     ParticleEmitter in ReplicatedStorage.LabAssets.Explosion (still switched off: each fires once, :Emit(its EmitCount
--     attribute, default DEFAULT_EMIT_COUNT), after its EmitDelay attribute, default 0) and of every Sound there (all played
--     together, in SoundService.SFX). To tune a burst, change the emitter's EmitCount attribute in Studio. The attachment goes
--     once the longest particle (lifetime + delay) and the longest sound (TimeLength / PlaybackSpeed) are over, plus LINGER.
--     Without LabAssets.Explosion it warns once and shows and plays nothing (the shake still runs). An asset that fails to copy,
--     fire or play is skipped with a warning (once per asset); the rest of the boom still runs and the attachment still goes.
--   * bleeds, for a limb blast: the same is done with LabAssets.Blood (its emitters Spray and Mist, and any Sound dropped into the
--     folder) in the same attachment, and the blood splats the floor: SplatCount rays (an attribute of the folder, like SplatLife
--     and SplatColor) from the blast toward a random point up to SPLAT_REACH studs to the side and SPLAT_DROP studs down, past
--     every player's character, the copy (Room1.Subject) and Bob. Each ray that hits something anchored puts a thin disc of
--     SplatColor flat on it (none on a loose part, such as a blown-off limb, which would leave the splat hanging in the air once
--     it is gone); it fades out over its last SPLAT_FADE seconds and goes after SplatLife seconds. At most MAX_SPLATS stay, the
--     oldest going first. The splats are only on this player's screen. Without LabAssets.Blood it warns once and limb blasts do
--     not bleed.
--   * shakes the camera, unless the Settings board's Screen Effects switch is off (LocalPlayer's MenuSetting_ScreenEffects is
--     false): strength 1 within FULL_SHAKE_DISTANCE of the character's HumanoidRootPart (of the camera with no character),
--     falling linearly to 0 at NO_SHAKE_DISTANCE, then fading to 0 over SHAKE_SECONDS. Every frame, after the camera scripts, the
--     camera gets a random turn and offset on top; the next frame takes it off before the camera scripts run, so a still camera
--     comes back exactly where it was. A boom during another's shake keeps whichever shake is stronger at that moment.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local FULL_SHAKE_DISTANCE = 10 -- studs: a boom this close (or closer) shakes at full strength
local NO_SHAKE_DISTANCE = 80 -- studs: a boom this far (or farther) does not shake at all
local SHAKE_SECONDS = 0.6 -- how long a shake lasts, fading to nothing
local SHAKE_ANGLE = math.rad(2.5) -- the largest turn of the camera at full strength
local SHAKE_OFFSET = 0.4 -- studs: the largest move of the camera at full strength
local DEFAULT_EMIT_COUNT = 20 -- particles for an emitter with no EmitCount attribute
local LINGER = 0.5 -- seconds the attachment stays after its last particle and sound are over
local SPLAT_REACH = 4 -- studs: how far to the side of the blast a splat can land
local SPLAT_DROP = 10 -- studs: how far below the blast a splat looks for a floor
local SPLAT_SIZE = NumberRange.new(1, 2.2) -- studs: a splat's diameter, picked at random in this range
local SPLAT_THICKNESS = 0.04 -- studs
local SPLAT_LIFT = 0.01 -- studs of air under a splat, so it does not flicker against the surface
local SPLAT_FADE = 5 -- seconds a splat takes to fade out at the end of its life
local MAX_SPLATS = 60 -- splats at once on this screen; the oldest go first

local player = Players.LocalPlayer
local random = Random.new()

local function finite(n: number): boolean
	return n == n and math.abs(n) ~= math.huge
end

local warned = {}
local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

-- fn(...), and if it fails a warning (once per asset) instead of an error.
local function try(asset: Instance, fn, ...)
	local ok, problem = pcall(fn, ...)
	if not ok then
		warnOnce(asset:GetFullName(), ("BoomClient: skipped %s: %s"):format(asset:GetFullName(), tostring(problem)))
	end
end

-- Every splat made so far that may still be there, oldest first.
local splats: { BasePart } = {}

local function splatter(position: Vector3, blood: Instance, boom: Attachment)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local skip: { Instance } = { boom }
	for _, other in Players:GetPlayers() do
		table.insert(skip, other.Character)
	end
	local room = workspace:FindFirstChild("Room1")
	table.insert(skip, room and room:FindFirstChild("Subject"))
	table.insert(skip, room and room:FindFirstChild("BobTheInjector"))
	params.FilterDescendantsInstances = skip
	local color = blood:GetAttribute("SplatColor")
	if typeof(color) ~= "Color3" then
		color = Color3.fromRGB(80, 0, 0)
	end
	local life = tonumber(blood:GetAttribute("SplatLife")) or 20
	for _ = 1, tonumber(blood:GetAttribute("SplatCount")) or 4 do
		local angle, reach = random:NextNumber(0, 2 * math.pi), random:NextNumber(0, SPLAT_REACH)
		local hit = workspace:Raycast(position, Vector3.new(math.cos(angle) * reach, -SPLAT_DROP, math.sin(angle) * reach), params)
		if hit and hit.Instance.Anchored then
			local size = random:NextNumber(SPLAT_SIZE.Min, SPLAT_SIZE.Max)
			local splat = Instance.new("Part")
			splat.Name = "BloodSplat"
			splat.Shape = Enum.PartType.Cylinder
			splat.Size = Vector3.new(SPLAT_THICKNESS, size, size)
			-- A cylinder's axis is its X: lay that along the surface's normal, just off the surface.
			local across = hit.Normal:Cross(if math.abs(hit.Normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
			splat.CFrame = CFrame.fromMatrix(hit.Position + hit.Normal * (SPLAT_THICKNESS / 2 + SPLAT_LIFT), hit.Normal, across)
			splat.Color = color
			splat.Material = Enum.Material.SmoothPlastic
			splat.Anchored = true
			splat.CanCollide = false
			splat.CanTouch = false
			splat.CanQuery = false
			splat.Parent = workspace
			table.insert(splats, splat)
			if #splats > MAX_SPLATS then
				table.remove(splats, 1):Destroy()
			end
			local fade = math.min(SPLAT_FADE, life)
			task.delay(life - fade, function()
				TweenService:Create(splat, TweenInfo.new(fade, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
			end)
			task.delay(life, splat.Destroy, splat)
		end
	end
end

local function show(position: Vector3, blood: boolean)
	local assets = ReplicatedStorage:FindFirstChild("LabAssets")
	local folders: { Instance } = {}
	for _, name in (if blood then { "Explosion", "Blood" } else { "Explosion" }) do
		local folder = assets and assets:FindFirstChild(name)
		if folder then
			table.insert(folders, folder)
		else
			warnOnce(name, ("BoomClient: ReplicatedStorage.LabAssets.%s is missing, so booms go without it"):format(name))
		end
	end
	if #folders == 0 then
		return
	end
	local boom = Instance.new("Attachment")
	boom.Name = "Boom"
	boom.Position = position -- Terrain sits at the origin, so this is the world position
	boom.Parent = workspace.Terrain
	local group = SoundService:FindFirstChild("SFX")
	local over = 0
	for _, folder in folders do
		for _, asset in folder:GetChildren() do
			try(asset, function()
				if asset:IsA("ParticleEmitter") then
					local emitter = asset:Clone()
					emitter.Parent = boom
					local delay = tonumber(asset:GetAttribute("EmitDelay")) or 0
					over = math.max(over, delay + asset.Lifetime.Max)
					local count = tonumber(asset:GetAttribute("EmitCount")) or DEFAULT_EMIT_COUNT
					task.delay(delay, try, asset, emitter.Emit, emitter, count)
				elseif asset:IsA("Sound") then
					local sound = asset:Clone()
					sound.SoundGroup = group
					sound.TimePosition = 0 -- from the start, even if the original was left part-played (a preview in Studio)
					sound.Parent = boom
					sound:Play()
					if sound.PlaybackSpeed > 0 then
						-- A fresh clone may not know its length yet (0); the loaded original does.
						over = math.max(over, math.max(sound.TimeLength, asset.TimeLength) / sound.PlaybackSpeed)
					end
				end
			end)
		end
	end
	task.delay(over + LINGER, boom.Destroy, boom)
	local gore = blood and assets:FindFirstChild("Blood")
	if gore then
		try(gore, splatter, position, gore, boom)
	end
end

-- The shake now playing: its strength when it began, and when.
local shakeStrength, shakeStart = 0, 0
local function shakeLeft(now: number): number
	return shakeStrength * math.max(0, 1 - (now - shakeStart) / SHAKE_SECONDS)
end

local function shake(position: Vector3)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local from = if root then root.Position elseif camera then camera.CFrame.Position else position
	local distance = (position - from).Magnitude
	local strength = math.clamp((NO_SHAKE_DISTANCE - distance) / (NO_SHAKE_DISTANCE - FULL_SHAKE_DISTANCE), 0, 1)
	local now = os.clock()
	if strength > shakeLeft(now) then
		shakeStrength, shakeStart = strength, now
	end
end

-- The camera as the camera scripts left it this frame, and as the shake left it.
local unshaken: CFrame, shaken: CFrame? = CFrame.identity, nil
RunService:BindToRenderStep("BoomShakeUndo", Enum.RenderPriority.Camera.Value - 1, function()
	local camera = workspace.CurrentCamera
	if shaken and camera and camera.CFrame == shaken then
		camera.CFrame = unshaken
	end
	shaken = nil
end)
RunService:BindToRenderStep("BoomShake", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = workspace.CurrentCamera
	local amount = shakeLeft(os.clock())
	if amount <= 0 or not camera or player:GetAttribute("MenuSetting_ScreenEffects") == false then
		return
	end
	local turn = CFrame.fromAxisAngle(random:NextUnitVector(), random:NextNumber(-1, 1) * SHAKE_ANGLE * amount)
	local move = random:NextUnitVector() * random:NextNumber(0, SHAKE_OFFSET * amount)
	unshaken = camera.CFrame
	shaken = unshaken * CFrame.new(move) * turn
	camera.CFrame = shaken
end)

ReplicatedStorage:WaitForChild("BoomEvent").OnClientEvent:Connect(function(position, blood)
	if typeof(position) ~= "Vector3" or not (finite(position.X) and finite(position.Y) and finite(position.Z)) then
		return
	end
	shake(position)
	show(position, blood == true)
end)

-- Loaded now, so the first boom has its sounds and particles at once.
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("LabAssets", 10)
	if assets and assets:WaitForChild("Explosion", 10) then
		pcall(ContentProvider.PreloadAsync, ContentProvider, assets:GetChildren())
	end
end)
