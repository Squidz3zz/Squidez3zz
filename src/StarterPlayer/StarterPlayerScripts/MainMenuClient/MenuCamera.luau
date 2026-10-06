-- MenuCamera: the camera behind the menu. It holds a fixed base CFrame (the map shot, or a room shot set with
-- setBase) and sways a couple of degrees toward the mouse, with a blur and a colour grade over the picture.
-- start() takes over the camera and adds the effects; stop() gives the camera back and removes them.
-- stop() never yields: it is on the Play path, which must not wait for the blur fade.
-- The grade covers every scene, the blur only the scenes setBase asks it for (the Menu: in the rooms the 3D board and
-- the avatars are the interface and must stay sharp). Screen Effects off removes both everywhere.
-- The grade's tint and saturation come from the menu theme (MenuAssets.THEME): warm in Factory, cool and nearly neutral in
-- SterileBright. They only colour the menu screens; stop() removes the grade, so gameplay never sees it.
--
-- Where the map shot is: add a Part named MenuCameraShot to Workspace and the camera sits at that part's CFrame,
-- looking out of the part's Front face (the way its LookVector points); without one it uses a default angle.
-- MenuServer anchors and hides the part at startup, reads it and publishes its CFrame as the Workspace attribute
-- MenuCameraShot, which is what this module reads (the part itself may not be streamed in yet, because StreamingEnabled
-- is on), so move the part in Studio, not while the game runs. To place it from what the Studio editor camera sees
-- right now, run this in the command bar:
--   local p = workspace:FindFirstChild("MenuCameraShot") or Instance.new("Part"); p.Name = "MenuCameraShot"; p.Size = Vector3.new(1,1,1); p.Anchored = true; p.CFrame = workspace.CurrentCamera.CFrame; p.Parent = workspace
--
-- The current base is also published as the attribute MenuBaseCFrame on the camera, so tests (which get their own copy
-- of this module) can read it.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuSettings = require(script.Parent.MenuSettings)

local DEFAULT_BASE = CFrame.lookAt(Vector3.new(0, 40, 80), Vector3.zero)
local BLUR_SIZE = 6
local BLUR_FADE = TweenInfo.new(0.4)
local GRADE_CONTRAST = 0.1
-- The Factory grade. The menu theme (MenuAssets.THEME: gradeTint and gradeSaturation) can replace these two, see gradeLook().
local GRADE_SATURATION = -0.15
local GRADE_TINT = Color3.fromRGB(255, 235, 210)
local MAX_SWAY = math.rad(2) -- at most this much yaw and this much pitch
local SWAY_SPEED = 6 -- smoothing: alpha = 1 - exp(-SWAY_SPEED * dt)

local MenuCamera = {}

-- { camera, base, blur, pitch, yaw, swayConnection, effectsConnection } while the menu camera runs, nil otherwise.
-- blur is whether the current scene wants the blur. pitch and yaw are the smoothed sway angles in radians.
local active = nil

local function removeNamed(...)
	local names = { ... }
	for _, child in Lighting:GetChildren() do
		if table.find(names, child.Name) then
			child:Destroy()
		end
	end
end

local function removeEffects()
	removeNamed("MenuBlur", "MenuColorCorrection")
end

-- Adds whichever effect is missing, so it never stacks a second copy beside one that is already there.
local function ensureBlur()
	if not Lighting:FindFirstChild("MenuBlur") then
		local blur = Instance.new("BlurEffect")
		blur.Name = "MenuBlur"
		blur.Size = BLUR_SIZE
		blur.Parent = Lighting
	end
end

-- The grade's tint and saturation: the active theme's gradeTint and gradeSaturation, or the Factory constants above. MenuTheme
-- is read in pcall and every value is type-checked, so a missing or broken theme leaves the Factory grade and the camera never
-- depends on it. Never yields.
local function gradeLook()
	local tint, saturation = GRADE_TINT, GRADE_SATURATION
	local module = script.Parent:FindFirstChild("MenuTheme")
	if module then
		local ok, theme = pcall(function()
			return require(module).get()
		end)
		if ok and type(theme) == "table" then
			if typeof(theme.gradeTint) == "Color3" then
				tint = theme.gradeTint
			end
			if type(theme.gradeSaturation) == "number" then
				saturation = theme.gradeSaturation
			end
		end
	end
	return tint, saturation
end

local function ensureGrade()
	if not Lighting:FindFirstChild("MenuColorCorrection") then
		local tint, saturation = gradeLook()
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "MenuColorCorrection"
		grade.Contrast = GRADE_CONTRAST
		grade.Saturation = saturation
		grade.TintColor = tint
		grade.Parent = Lighting
	end
end

-- The effects the setting and the current scene call for. A blur that is not wanted is removed outright: scene changes
-- happen behind the black Fader, so there is nothing to fade.
local function syncEffects(state)
	if not MenuSettings.get("ScreenEffects") then
		removeEffects()
		return
	end
	ensureGrade()
	if state.blur then
		ensureBlur()
	else
		removeNamed("MenuBlur")
	end
end

-- The map shot published by MenuServer, or the default angle.
function MenuCamera.menuBase()
	local shot = workspace:GetAttribute("MenuCameraShot")
	if typeof(shot) == "CFrame" then
		return shot
	end
	return DEFAULT_BASE
end

local function place(state, base)
	state.base = base
	state.pitch = 0
	state.yaw = 0
	state.camera:SetAttribute("MenuBaseCFrame", base)
	state.camera.CFrame = base
end

-- Cuts to a new base (SceneDirector calls this behind the fader, so the camera snaps and the sway starts over).
-- opts.blur says whether this scene wants the blur (default true): the Menu does, the rooms do not. The colour grade
-- stays either way, and with Screen Effects off there is neither.
-- Does nothing while the menu camera is not running, so a late call can never grab the camera back after Play.
function MenuCamera.setBase(cf, opts)
	if active then
		place(active, cf)
		active.blur = not opts or opts.blur ~= false
		syncEffects(active)
	end
end

-- The mouse's offset from the centre of the viewport as -1..1 on each axis, or nil when there is no sway to apply:
-- Camera Sway is off, there is no mouse, or the player is on touch or a gamepad.
local function mouseOffset(camera)
	if not MenuSettings.get("CameraSway") or not UserInputService.MouseEnabled then
		return nil
	end
	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Touch or string.find(lastInput.Name, "^Gamepad") then
		return nil
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local nx = math.clamp((mouse.X - viewport.X / 2) / (viewport.X / 2), -1, 1)
	local ny = math.clamp((mouse.Y - viewport.Y / 2) / (viewport.Y / 2), -1, 1)
	return nx, ny
end

local function sway(state, deltaTime)
	local nx, ny = mouseOffset(state.camera)
	-- Without a mouse offset the target is no rotation at all, so the camera eases back onto the base.
	local targetPitch = if nx then -ny * MAX_SWAY else 0
	local targetYaw = if nx then -nx * MAX_SWAY else 0
	local alpha = 1 - math.exp(-SWAY_SPEED * deltaTime)
	state.pitch += (targetPitch - state.pitch) * alpha
	state.yaw += (targetYaw - state.yaw) * alpha
	state.camera.CFrame = state.base * CFrame.Angles(state.pitch, state.yaw, 0)
end

function MenuCamera.start()
	if active then
		return
	end

	local camera = workspace.CurrentCamera
	assert(camera, "MenuCamera.start: workspace.CurrentCamera is missing")

	-- Effects left over from an earlier run (the blur may still be fading out) must not linger beside the new ones.
	removeEffects()

	local state = { camera = camera, blur = true }
	camera.CameraType = Enum.CameraType.Scriptable
	-- Never yields: the menu must open at once, even if the server has not published a map shot.
	place(state, MenuCamera.menuBase())

	state.effectsConnection = MenuSettings.changed("ScreenEffects"):Connect(function()
		syncEffects(state)
	end)
	state.swayConnection = RunService.RenderStepped:Connect(function(deltaTime)
		sway(state, deltaTime)
	end)
	active = state

	syncEffects(state)
end

function MenuCamera.stop()
	if not active then
		return
	end
	local state = active
	active = nil

	state.swayConnection:Disconnect()
	-- After this, switching Screen Effects can no longer bring the effects back.
	state.effectsConnection:Disconnect()
	state.camera.CameraType = Enum.CameraType.Custom
	state.camera:SetAttribute("MenuBaseCFrame", nil)

	local grade = Lighting:FindFirstChild("MenuColorCorrection")
	if grade then
		grade:Destroy()
	end
	-- Found by name rather than kept in the state: Screen Effects may have replaced it since start().
	local blur = Lighting:FindFirstChild("MenuBlur")
	if blur then
		local tween = TweenService:Create(blur, BLUR_FADE, { Size = 0 })
		tween.Completed:Once(function()
			blur:Destroy()
		end)
		tween:Play()
	end
end

return MenuCamera
