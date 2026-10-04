-- MenuCamera: the camera behind the menu. It holds a fixed base CFrame (the map shot, or a room shot set with
-- setBase) and sways a couple of degrees toward the mouse, with a blur and a colour grade over the picture.
-- start() takes over the camera and adds the effects; stop() gives the camera back and removes them.
-- stop() never yields: it is on the Play path, which must not wait for the blur fade.
--
-- Where the map shot is: add an anchored Part named MenuCameraShot to Workspace and the camera sits at that part's
-- CFrame; without one it uses a default angle. MenuServer reads the part at startup and publishes its CFrame as the
-- Workspace attribute MenuCameraShot, which is what this module reads (the part itself may not be streamed in yet,
-- because StreamingEnabled is on), so move the part in Studio, not while the game runs.
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
local GRADE_SATURATION = -0.15
local GRADE_TINT = Color3.fromRGB(255, 235, 210)
local MAX_SWAY = math.rad(2) -- at most this much yaw and this much pitch
local SWAY_SPEED = 6 -- smoothing: alpha = 1 - exp(-SWAY_SPEED * dt)

local MenuCamera = {}

-- { camera, base, pitch, yaw, swayConnection, effectsConnection } while the menu camera runs, nil otherwise.
-- pitch and yaw are the smoothed sway angles in radians.
local active = nil

local function removeEffects()
	for _, child in Lighting:GetChildren() do
		if child.Name == "MenuBlur" or child.Name == "MenuColorCorrection" then
			child:Destroy()
		end
	end
end

-- Adds whichever effect is missing, so it never stacks a second copy beside one that is already there.
local function ensureEffects()
	if not Lighting:FindFirstChild("MenuBlur") then
		local blur = Instance.new("BlurEffect")
		blur.Name = "MenuBlur"
		blur.Size = BLUR_SIZE
		blur.Parent = Lighting
	end
	if not Lighting:FindFirstChild("MenuColorCorrection") then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "MenuColorCorrection"
		grade.Contrast = GRADE_CONTRAST
		grade.Saturation = GRADE_SATURATION
		grade.TintColor = GRADE_TINT
		grade.Parent = Lighting
	end
end

local function syncEffects()
	if MenuSettings.get("ScreenEffects") then
		ensureEffects()
	else
		removeEffects()
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
-- Does nothing while the menu camera is not running, so a late call can never grab the camera back after Play.
function MenuCamera.setBase(cf)
	if active then
		place(active, cf)
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

	local state = { camera = camera }
	camera.CameraType = Enum.CameraType.Scriptable
	-- Never yields: the menu must open at once, even if the server has not published a map shot.
	place(state, MenuCamera.menuBase())

	state.effectsConnection = MenuSettings.changed("ScreenEffects"):Connect(syncEffects)
	state.swayConnection = RunService.RenderStepped:Connect(function(deltaTime)
		sway(state, deltaTime)
	end)
	active = state

	syncEffects()
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
