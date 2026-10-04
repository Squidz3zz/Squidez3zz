-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet).
-- Observes the real effects of MenuCamera on the live camera/Lighting (the test never calls start/stop on its own
-- module copy), drives VolumeSlider.setAlpha/attach on live Instances, then presses Play through the TestHook.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local TOLERANCE = 0.001
local RADIUS = 60
local HEIGHT = 30
local REVOLUTION_SECONDS = 60

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.1)
	end
	return predicate()
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or TOLERANCE)
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")
local root = menu:FindFirstChild("Root")
assert(root, "MainMenu.Root missing")

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
local hook = clientScript and clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")

-- Camera: scriptable, blurred, orbiting the focus point.
local camera = workspace.CurrentCamera
assert(camera, "workspace.CurrentCamera missing")
local isScriptable = waitFor(function()
	return camera.CameraType == Enum.CameraType.Scriptable
end, 3)
assert(isScriptable, "camera not Scriptable (CameraType is " .. camera.CameraType.Name .. ")")

local blur = Lighting:FindFirstChild("MenuBlur")
assert(blur and blur:IsA("BlurEffect"), "Lighting.MenuBlur (BlurEffect) missing")
assert(near(blur.Size, 16, 0.01), "MenuBlur.Size should be 16, got " .. blur.Size)
assert(blur.Enabled, "MenuBlur should be enabled")

-- The orbit centre is published by MenuServer as a Workspace attribute (see MenuCamera); the origin when unset.
local focusAttribute = workspace:GetAttribute("MenuCameraFocus")
local focus = if typeof(focusAttribute) == "Vector3" then focusAttribute else Vector3.zero

local function orbitSample()
	local position = camera.CFrame.Position
	local relative = position - focus
	return {
		position = position,
		radius = Vector3.new(relative.X, 0, relative.Z).Magnitude,
		height = relative.Y,
		angle = math.atan2(relative.Z, relative.X),
		time = os.clock(),
	}
end

local first = orbitSample()
assert(near(first.radius, RADIUS, 0.5), "orbit radius should be " .. RADIUS .. ", got " .. first.radius)
assert(near(first.height, HEIGHT, 0.5), "orbit height should be " .. HEIGHT .. ", got " .. first.height)
local toFocus = (focus - first.position).Unit
assert(toFocus:Dot(camera.CFrame.LookVector) > 0.999, "camera should look at the focus point")

task.wait(1)
local second = orbitSample()
local moved = (second.position - first.position).Magnitude
assert(moved > 0.5, "camera should orbit: moved only " .. moved .. " studs in 1s")
assert(near(second.radius, RADIUS, 0.5), "orbit radius drifted to " .. second.radius)
assert(near(second.height, HEIGHT, 0.5), "orbit height drifted to " .. second.height)

-- One revolution per 60s: the angle advances by 2*pi/60 per second (generous tolerance for frame timing).
local deltaAngle = (second.angle - first.angle + math.pi) % (2 * math.pi) - math.pi
local expectedAngle = 2 * math.pi / REVOLUTION_SECONDS * (second.time - first.time)
assert(
	math.abs(deltaAngle) > expectedAngle * 0.7 and math.abs(deltaAngle) < expectedAngle * 1.3,
	string.format("orbit rate off: moved %.4f rad, expected about %.4f rad", math.abs(deltaAngle), expectedAngle)
)

-- Slider: setAlpha acts only on the Instances it is given (this test's module copy shares no state with the game's).
local sliderModule = clientScript:WaitForChild("VolumeSlider", 10)
assert(sliderModule and sliderModule:IsA("ModuleScript"), "VolumeSlider ModuleScript missing")
local VolumeSlider = require(sliderModule)
assert(type(VolumeSlider.attach) == "function", "VolumeSlider.attach missing")
assert(type(VolumeSlider.setAlpha) == "function", "VolumeSlider.setAlpha missing")

local slider = root.SettingsPanel.Slider
local music = SoundService:FindFirstChild("Music")
assert(music and music:IsA("SoundGroup"), "SoundService.Music (SoundGroup) missing")
local originalVolume = music.Volume

local function expectAlpha(label, alpha)
	assert(near(music.Volume, alpha), label .. ": Music.Volume should be " .. alpha .. ", got " .. music.Volume)
	assert(
		near(slider.Fill.Size.X.Scale, alpha),
		label .. ": Fill.Size.X.Scale should be " .. alpha .. ", got " .. slider.Fill.Size.X.Scale
	)
	assert(
		near(slider.Knob.Position.X.Scale, alpha),
		label .. ": Knob.Position.X.Scale should be " .. alpha .. ", got " .. slider.Knob.Position.X.Scale
	)
	-- Only the X scale follows alpha; the rest of the layout is untouched.
	assert(slider.Fill.Size.X.Offset == 0, label .. ": Fill.Size.X.Offset should stay 0")
	assert(slider.Fill.Size.Y == UDim.new(1, 0), label .. ": Fill.Size.Y should stay {1, 0}")
	assert(slider.Knob.Position.X.Offset == 0, label .. ": Knob.Position.X.Offset should stay 0")
	assert(slider.Knob.Position.Y == UDim.new(0.5, 0), label .. ": Knob.Position.Y should stay {0.5, 0}")
end

VolumeSlider.setAlpha(slider, music, 0.25)
expectAlpha("setAlpha 0.25", 0.25)

VolumeSlider.setAlpha(slider, music, 1.7)
expectAlpha("setAlpha 1.7 clamps to 1", 1)

VolumeSlider.setAlpha(slider, music, -3)
expectAlpha("setAlpha -3 clamps to 0", 0)

-- attach starts from the group's current volume (checked on a throwaway copy so the live slider is not touched).
local group = Instance.new("SoundGroup")
group.Volume = 0.8
local sliderCopy = slider:Clone()
VolumeSlider.attach(sliderCopy, group)
assert(near(sliderCopy.Fill.Size.X.Scale, 0.8), "attach: Fill should start at the group volume 0.8")
assert(near(sliderCopy.Knob.Position.X.Scale, 0.8), "attach: Knob should start at the group volume 0.8")
assert(near(group.Volume, 0.8), "attach should not change the group volume")
sliderCopy:Destroy()
group:Destroy()

VolumeSlider.setAlpha(slider, music, originalVolume)
expectAlpha("restore", originalVolume)

-- Play: stop() restores the camera and removes the blur without making Play wait for the fade.
local startedAt = os.clock()
assert(hook:Invoke("play") == true, "play() should start the Play flow")
local invokeTime = os.clock() - startedAt
assert(invokeTime < 0.3, "play() should not wait for the blur fade (took " .. invokeTime .. "s)")
assert(
	camera.CameraType == Enum.CameraType.Custom,
	"camera should be Custom as soon as Play starts, got " .. camera.CameraType.Name
)

local blurGone = waitFor(function()
	return Lighting:FindFirstChild("MenuBlur") == nil
end, 1.5)
assert(blurGone, "MenuBlur should be removed within 1.5s of Play")

local menuClosed = waitFor(function()
	return playerGui:FindFirstChild("MainMenu") == nil and playerGui:GetAttribute("MenuOpen") == false
end, 20)
assert(menuClosed, "menu did not close after Play")
assert(camera.CameraType == Enum.CameraType.Custom, "camera should be Custom after the menu closes")
assert(Lighting:FindFirstChild("MenuBlur") == nil, "MenuBlur should be gone after the menu closes")

-- The orbit loop is disconnected: once the player's character owns the camera, no frame is placed back on the orbit.
assert(waitFor(function()
	return player.Character ~= nil
end, 10), "character never spawned")
for _ = 1, 15 do
	RunService.RenderStepped:Wait()
	local sample = orbitSample()
	local onOrbit = near(sample.radius, RADIUS, 1) and near(sample.height, HEIGHT, 1)
	assert(not onOrbit, "camera is still being driven along the orbit after Play")
end

return "PASS"
