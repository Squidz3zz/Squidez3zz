-- MenuCamera: the slowly orbiting, blurred camera behind the main menu.
-- start() takes over the camera and adds a BlurEffect to Lighting; stop() gives the camera back and fades the blur out.
-- stop() never yields: it is on the Play path, which must not wait for the fade.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ORBIT_RADIUS = 60
local ORBIT_HEIGHT = 30
local SECONDS_PER_REVOLUTION = 60
local BLUR_SIZE = 16
local BLUR_FADE = TweenInfo.new(0.4)

local MenuCamera = {}

-- { camera, connection, blur } while the orbit runs, nil otherwise.
local active = nil

function MenuCamera.start()
	if active then
		return
	end

	local camera = workspace.CurrentCamera
	assert(camera, "MenuCamera.start: workspace.CurrentCamera is missing")

	local focusPart = workspace:FindFirstChild("MenuCameraFocus")
	local focus = if focusPart and focusPart:IsA("BasePart") then focusPart.Position else Vector3.zero

	-- A blur left over from an earlier run (still fading out) must not linger beside the new one.
	local oldBlur = Lighting:FindFirstChild("MenuBlur")
	if oldBlur then
		oldBlur:Destroy()
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = "MenuBlur"
	blur.Size = BLUR_SIZE
	blur.Parent = Lighting

	local angle = 0
	local function place()
		local offset = Vector3.new(math.cos(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, math.sin(angle) * ORBIT_RADIUS)
		camera.CFrame = CFrame.lookAt(focus + offset, focus)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	place()
	local connection = RunService.RenderStepped:Connect(function(deltaTime)
		angle += deltaTime * 2 * math.pi / SECONDS_PER_REVOLUTION
		place()
	end)

	active = { camera = camera, connection = connection, blur = blur }
end

function MenuCamera.stop()
	if not active then
		return
	end
	local state = active
	active = nil

	state.connection:Disconnect()
	state.camera.CameraType = Enum.CameraType.Custom

	local tween = TweenService:Create(state.blur, BLUR_FADE, { Size = 0 })
	tween.Completed:Once(function()
		state.blur:Destroy()
	end)
	tween:Play()
end

return MenuCamera
