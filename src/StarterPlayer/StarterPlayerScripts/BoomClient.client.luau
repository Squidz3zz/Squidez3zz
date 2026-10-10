-- BoomClient: this player's side of every explosion. The server's Booms.at fires ReplicatedStorage.BoomEvent with a position
-- (anything that is not a finite Vector3 is ignored), and here each boom:
--   * looks and sounds like the user's explosion: an Attachment "Boom" in workspace.Terrain at the position gets a clone of every
--     ParticleEmitter in ReplicatedStorage.LabAssets.Explosion (still switched off: each fires once, :Emit(its EmitCount
--     attribute, default DEFAULT_EMIT_COUNT), after its EmitDelay attribute, default 0) and of every Sound there (all played
--     together, in SoundService.SFX). To tune a burst, change the emitter's EmitCount attribute in Studio. The attachment goes
--     once the longest particle (lifetime + delay) and the longest sound (TimeLength / PlaybackSpeed) are over, plus LINGER.
--     Without LabAssets.Explosion it warns once and shows and plays nothing (the shake still runs). An asset that fails to copy,
--     fire or play is skipped with a warning (once per asset); the rest of the boom still runs and the attachment still goes.
--     A limb blast's blood (the spray, the mist, its sounds and the splats) is GoreClient's.
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

local FULL_SHAKE_DISTANCE = 10 -- studs: a boom this close (or closer) shakes at full strength
local NO_SHAKE_DISTANCE = 80 -- studs: a boom this far (or farther) does not shake at all
local SHAKE_SECONDS = 0.6 -- how long a shake lasts, fading to nothing
local SHAKE_ANGLE = math.rad(2.5) -- the largest turn of the camera at full strength
local SHAKE_OFFSET = 0.4 -- studs: the largest move of the camera at full strength
local DEFAULT_EMIT_COUNT = 20 -- particles for an emitter with no EmitCount attribute
local LINGER = 0.5 -- seconds the attachment stays after its last particle and sound are over

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

local function show(position: Vector3)
	local assets = ReplicatedStorage:FindFirstChild("LabAssets")
	local folder = assets and assets:FindFirstChild("Explosion")
	if not folder then
		warnOnce("Explosion", "BoomClient: ReplicatedStorage.LabAssets.Explosion is missing, so booms go without it")
		return
	end
	local boom = Instance.new("Attachment")
	boom.Name = "Boom"
	boom.Position = position -- Terrain sits at the origin, so this is the world position
	boom.Parent = workspace.Terrain
	local group = SoundService:FindFirstChild("SFX")
	local over = 0
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
	task.delay(over + LINGER, boom.Destroy, boom)
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

ReplicatedStorage:WaitForChild("BoomEvent").OnClientEvent:Connect(function(position)
	if typeof(position) ~= "Vector3" or not (finite(position.X) and finite(position.Y) and finite(position.Z)) then
		return
	end
	shake(position)
	show(position)
end)

-- Loaded now, so the first boom has its sounds and particles at once.
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("LabAssets", 10)
	if assets and assets:WaitForChild("Explosion", 10) then
		pcall(ContentProvider.PreloadAsync, ContentProvider, assets:GetChildren())
	end
end)
