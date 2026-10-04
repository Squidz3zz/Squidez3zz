-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet), as the FIRST execute_luau
-- call there: the harness resets CameraType after every execute_luau call, so anything that measures the camera has
-- to run before another call has been made.
-- Before running it, move the mouse into a screen corner with user_mouse_input (case B2 needs a real offset; with no
-- mouse tool, set SKIP_B2 below and check the tilt by eye with screenshots instead).
-- Observes the real effects of MenuCamera on the live camera/Lighting (the test never calls start/stop on its own
-- module copy). MenuSettings keeps its state in LocalPlayer attributes, so this test's copy of it drives the game's.
--   A   scriptable camera, MenuBlur (Size 6) and MenuColorCorrection exist, MenuBaseCFrame is the menu shot
--   B   sway stays within 2 degrees yaw + 2 degrees pitch of the base, and the position never leaves the base
--   B2  with the mouse in a corner the camera really tilts, toward the mouse, by the amount the spec formula gives
--   C   Camera Sway off: the camera settles back onto the base
--   D   Screen Effects off/on removes and re-adds both effects, never stacking duplicates
--   E   Play: stop() hands the camera back, removes the effects, and a later Screen Effects toggle adds nothing
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SKIP_B2 = false

local player = Players.LocalPlayer

local MAX_SWAY_DEGREES = 2.83 -- the diagonal of 2 degrees yaw and 2 degrees pitch
local ANGLE_SLACK = 0.05
local POSITION_TOLERANCE = 0.01

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

-- atan2 of the cross product: exact for tiny angles, where acos of a float32 dot product is not.
local function angleBetween(a, b)
	return math.deg(math.atan2(a:Cross(b).Magnitude, a:Dot(b)))
end

local function countNamed(name)
	local count = 0
	for _, child in Lighting:GetChildren() do
		if child.Name == name then
			count += 1
		end
	end
	return count
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "MainMenuClient missing")
local hook = clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")

-- (A) The camera and effects.
local camera = workspace.CurrentCamera
assert(camera, "workspace.CurrentCamera missing")
local isScriptable = waitFor(function()
	return camera.CameraType == Enum.CameraType.Scriptable
end, 3)
assert(isScriptable, "camera not Scriptable (CameraType is " .. camera.CameraType.Name .. ")")

local blur = Lighting:FindFirstChild("MenuBlur")
assert(blur and blur:IsA("BlurEffect"), "Lighting.MenuBlur (BlurEffect) missing")
assert(math.abs(blur.Size - 6) <= 0.01, "MenuBlur.Size should be 6, got " .. blur.Size)
assert(blur.Enabled, "MenuBlur should be enabled")

local grade = Lighting:FindFirstChild("MenuColorCorrection")
assert(grade and grade:IsA("ColorCorrectionEffect"), "Lighting.MenuColorCorrection (ColorCorrectionEffect) missing")
assert(math.abs(grade.Contrast - 0.1) <= 0.001, "MenuColorCorrection.Contrast should be 0.1, got " .. grade.Contrast)
assert(
	math.abs(grade.Saturation - -0.15) <= 0.001,
	"MenuColorCorrection.Saturation should be -0.15, got " .. grade.Saturation
)
local tint = grade.TintColor
assert(
	math.abs(tint.R * 255 - 255) < 0.5 and math.abs(tint.G * 255 - 235) < 0.5 and math.abs(tint.B * 255 - 210) < 0.5,
	"MenuColorCorrection.TintColor should be RGB(255, 235, 210), got " .. tostring(tint)
)
assert(grade.Enabled, "MenuColorCorrection should be enabled")

local base = camera:GetAttribute("MenuBaseCFrame")
assert(typeof(base) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing, got " .. typeof(base))
-- The base is the server's MenuCameraShot, or the default angle when there is no marker.
local shot = workspace:GetAttribute("MenuCameraShot")
local expectedBase = if typeof(shot) == "CFrame" then shot else CFrame.lookAt(Vector3.new(0, 40, 80), Vector3.zero)
assert(
	(base.Position - expectedBase.Position).Magnitude <= POSITION_TOLERANCE
		and angleBetween(base.LookVector, expectedBase.LookVector) <= 0.01,
	"MenuBaseCFrame should be the MenuCameraShot (or the default angle), got " .. tostring(base)
)

local settingsModule = clientScript:WaitForChild("MenuSettings", 10)
assert(settingsModule and settingsModule:IsA("ModuleScript"), "MainMenuClient.MenuSettings (ModuleScript) missing")
local MenuSettings = require(settingsModule)
assert(MenuSettings.get("CameraSway") == true, "CameraSway should start on")
assert(MenuSettings.get("ScreenEffects") == true, "ScreenEffects should start on")
assert(not pcall(MenuSettings.get, "NoSuchSetting"), "MenuSettings.get should reject an unknown setting")
assert(not pcall(MenuSettings.set, "CameraSway", "yes"), "MenuSettings.set should reject a non-boolean value")
assert(MenuSettings.get("CameraSway") == true, "a rejected set must not change the setting")

-- (B) Sway never leaves the 2 degree box around the base, and never moves the camera's position.
local maxAngle = 0
for _ = 1, 60 do
	RunService.RenderStepped:Wait()
	local frame = camera.CFrame
	maxAngle = math.max(maxAngle, angleBetween(frame.LookVector, base.LookVector))
	local drift = (frame.Position - base.Position).Magnitude
	assert(drift <= POSITION_TOLERANCE, "camera position drifted " .. drift .. " studs off the base")
end
assert(
	maxAngle <= MAX_SWAY_DEGREES + ANGLE_SLACK,
	string.format("sway reached %.3f degrees, the limit is %.2f", maxAngle, MAX_SWAY_DEGREES)
)

-- (B2) Mouse in a corner: the camera must really tilt (case B alone passes with no sway at all), toward the mouse.
if SKIP_B2 then
	warn("sway test: B2 skipped (SKIP_B2); verify the tilt by eye")
else
	local viewport = camera.ViewportSize
	local mouse = UserInputService:GetMouseLocation()
	local nx = math.clamp((mouse.X - viewport.X / 2) / (viewport.X / 2), -1, 1)
	local ny = math.clamp((mouse.Y - viewport.Y / 2) / (viewport.Y / 2), -1, 1)
	assert(
		math.abs(nx) >= 0.8 and math.abs(ny) >= 0.8,
		string.format(
			"B2 needs the mouse in a screen corner (run user_mouse_input first): mouse is at %s in a %s viewport",
			tostring(mouse),
			tostring(viewport)
		)
	)
	task.wait(1)
	local minAngle = math.huge
	local worstError = 0
	-- The spec's target rotation for this mouse position; after 1s the smoothing has converged onto it.
	local expectedLook = (base * CFrame.Angles(-ny * math.rad(2), -nx * math.rad(2), 0)).LookVector
	for _ = 1, 10 do
		RunService.RenderStepped:Wait()
		local look = camera.CFrame.LookVector
		minAngle = math.min(minAngle, angleBetween(look, base.LookVector))
		worstError = math.max(worstError, angleBetween(look, expectedLook))
	end
	assert(minAngle >= 1.0, string.format("mouse in a corner, but the camera only tilted %.3f degrees (need 1.0)", minAngle))
	assert(
		worstError <= 0.15,
		string.format("camera is %.3f degrees away from the sway the mouse position calls for", worstError)
	)
end

-- (C) Camera Sway off: the camera settles back onto the base, even though the mouse is still in the corner.
local swayOk, swayError = pcall(function()
	local changes = 0
	local connection = MenuSettings.changed("CameraSway"):Connect(function()
		changes += 1
	end)
	MenuSettings.set("CameraSway", false)
	assert(MenuSettings.get("CameraSway") == false, "MenuSettings.get should report CameraSway off")
	task.wait(1.5)
	connection:Disconnect()
	assert(changes == 1, "MenuSettings.changed('CameraSway') should fire once per change, fired " .. changes .. " times")
	RunService.RenderStepped:Wait()
	local angle = angleBetween(camera.CFrame.LookVector, base.LookVector)
	assert(angle <= 0.05, string.format("CameraSway is off but the camera is still %.3f degrees off the base", angle))
	assert(
		(camera.CFrame.Position - base.Position).Magnitude <= POSITION_TOLERANCE,
		"CameraSway is off but the camera position moved"
	)
end)
MenuSettings.set("CameraSway", true)
assert(swayOk, swayError)
assert(MenuSettings.get("CameraSway") == true, "MenuSettings.get should report CameraSway on again")

-- (D) Screen Effects off removes both effects, on re-adds them, and fast toggling never stacks duplicates.
local effectsOk, effectsError = pcall(function()
	MenuSettings.set("ScreenEffects", false)
	local gone = waitFor(function()
		return Lighting:FindFirstChild("MenuBlur") == nil and Lighting:FindFirstChild("MenuColorCorrection") == nil
	end, 1)
	assert(gone, "MenuBlur / MenuColorCorrection should be removed within 1s of ScreenEffects off")

	MenuSettings.set("ScreenEffects", true)
	local back = waitFor(function()
		return Lighting:FindFirstChild("MenuBlur") ~= nil and Lighting:FindFirstChild("MenuColorCorrection") ~= nil
	end, 1)
	assert(back, "MenuBlur / MenuColorCorrection should reappear within 1s of ScreenEffects on")
	assert(math.abs(Lighting.MenuBlur.Size - 6) <= 0.01, "re-added MenuBlur should have Size 6")

	for _ = 1, 3 do
		MenuSettings.set("ScreenEffects", false)
		MenuSettings.set("ScreenEffects", true)
	end
	task.wait(0.5)
	assert(countNamed("MenuBlur") == 1, "expected exactly one MenuBlur, found " .. countNamed("MenuBlur"))
	assert(
		countNamed("MenuColorCorrection") == 1,
		"expected exactly one MenuColorCorrection, found " .. countNamed("MenuColorCorrection")
	)
end)
MenuSettings.set("ScreenEffects", true)
assert(effectsOk, effectsError)

-- (E) Play: stop() is non-yielding, hands the camera back and removes the effects for good.
local startedAt = os.clock()
assert(hook:Invoke("play") == true, "play() should start the Play flow")
assert(os.clock() - startedAt < 0.3, "play() should not wait for the blur fade (took " .. os.clock() - startedAt .. "s)")
assert(
	camera.CameraType == Enum.CameraType.Custom,
	"camera should be Custom as soon as Play starts, got " .. camera.CameraType.Name
)
assert(Lighting:FindFirstChild("MenuColorCorrection") == nil, "MenuColorCorrection should be gone as soon as Play starts")
local blurGone = waitFor(function()
	return Lighting:FindFirstChild("MenuBlur") == nil
end, 1.5)
assert(blurGone, "MenuBlur should be removed within 1.5s of Play")

-- The Screen Effects listener is disconnected: a toggle after Play must not bring the effects back.
MenuSettings.set("ScreenEffects", false)
MenuSettings.set("ScreenEffects", true)
task.wait(0.5)
assert(Lighting:FindFirstChild("MenuBlur") == nil, "toggling ScreenEffects after Play re-added MenuBlur")
assert(Lighting:FindFirstChild("MenuColorCorrection") == nil, "toggling ScreenEffects after Play re-added MenuColorCorrection")

-- The sway loop is disconnected: once the character owns the camera, no frame is placed back on the menu base.
assert(waitFor(function()
	return player.Character ~= nil
end, 10), "character never spawned")
for _ = 1, 15 do
	RunService.RenderStepped:Wait()
	local distance = (camera.CFrame.Position - base.Position).Magnitude
	assert(distance > 0.5, "camera is still being driven onto the menu base after Play")
end
assert(camera.CameraType == Enum.CameraType.Custom, "camera should stay Custom after Play")

return "PASS"
