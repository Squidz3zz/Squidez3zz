-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet). One case per playtest:
-- pick it with CASE below, then run the whole file as an execute_luau call.
-- Drives the menu through MainMenuClient's Studio-only TestHook and observes the real SceneDirector, camera and GUI.
--   A   round trip Menu -> Settings -> Credits -> Menu -> Settings. Every stop cuts the camera onto the room's marker
--       (within 0.05 studs; sway only rotates) behind a (nearly) opaque Fader, toggles Root and Back, and ends with
--       the Fader fully clear. It leaves the menu in Settings with a click counter on Back for A2.
--   A2  run AFTER A, once Back was clicked for real (user_mouse_input moveTo the Back button, then a left click):
--       exactly one click reached Back and the menu is back on Menu. Needs no fresh playtest, only A's.
--   B   mashing: goTo Settings, Credits, Menu back to back. Only the first starts; Settings wins and nothing queues.
--   C   Play mid-transition (PLAY_DELAY seconds after goTo Settings; 0.1 is mid fade-out, 0.6 mid fade-in). Play
--       wins: the character spawns, the menu is gone, and the cancelled transition never touches Root, Back, the
--       Fader or the camera again. Read the console afterwards: it must have no errors.
local CASE = "A"
local PLAY_DELAY = 0.1

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local POSITION_TOLERANCE = 0.05
-- The camera cuts while the Fader is opaque; it is already clearing again on the first frame after the cut.
local CUT_FADER_MAX = 0.2

local player = Players.LocalPlayer

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.05)
	end
	return predicate()
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

local root, back, fader, vignette = menu.Root, menu.Back, menu.Fader, menu.Vignette
local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
local hook = clientScript and clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")
local camera = workspace.CurrentCamera
assert(camera, "workspace.CurrentCamera missing")
assert(
	waitFor(function()
		return camera.CameraType == Enum.CameraType.Scriptable
	end, 3),
	"camera not Scriptable (CameraType is " .. camera.CameraType.Name .. ")"
)

local function markerPosition(roomName, shotName)
	local room = workspace:WaitForChild(roomName, 10)
	local shot = room and room:WaitForChild(shotName, 10)
	assert(shot and shot:IsA("BasePart"), "workspace." .. roomName .. "." .. shotName .. " missing")
	return shot.Position
end

-- One line with everything the scene checks look at, for failure messages.
local function describeState(target)
	return ("MenuScene=%s camera %.3f studs from the target, Root.Visible=%s Back.Visible=%s Fader=%s"):format(
		tostring(playerGui:GetAttribute("MenuScene")),
		(camera.CFrame.Position - target).Magnitude,
		tostring(root.Visible),
		tostring(back.Visible),
		tostring(fader.BackgroundTransparency)
	)
end

-- The scene is `name`, the camera sits at `target`, Root / Back match it and the Fader is fully clear.
local function sceneIsSettled(name, target)
	return playerGui:GetAttribute("MenuScene") == name
		and hook:Invoke("scene") == name
		and (camera.CFrame.Position - target).Magnitude <= POSITION_TOLERANCE
		and root.Visible == (name == "Menu")
		and back.Visible == (name ~= "Menu")
		and fader.BackgroundTransparency == 1
end

-- The Fader reaches 1 a frame before the transition thread wakes up and lets go of its debounce, so a goTo in that
-- very frame is (rightly) refused. Once settled, give it a few frames, and check the scene held.
local function expectSettled(name, target, timeout)
	local settled = waitFor(function()
		return sceneIsSettled(name, target)
	end, timeout)
	assert(settled, ("scene %s did not settle within %ss: %s"):format(name, timeout, describeState(target)))
	task.wait(0.1)
	assert(sceneIsSettled(name, target), ("scene %s did not hold after settling: %s"):format(name, describeState(target)))
end

-- Starts a scene change, watches it frame by frame and checks the fade-cut: the Fader goes (nearly) opaque, the
-- scene attribute flips only behind it, and the result settles within 2s.
local function goAndSettle(name, target)
	assert(hook:Invoke("goTo", name) == true, "goTo(" .. name .. ") should start a transition")
	local darkest = 1
	local faderAtCut = nil
	local deadline = os.clock() + 2
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		local transparency = fader.BackgroundTransparency
		darkest = math.min(darkest, transparency)
		if faderAtCut == nil and playerGui:GetAttribute("MenuScene") == name then
			faderAtCut = transparency
		end
		if sceneIsSettled(name, target) then
			break
		end
	end
	assert(sceneIsSettled(name, target), ("scene %s did not settle within 2s: %s"):format(name, describeState(target)))
	task.wait(0.1) -- see expectSettled
	assert(sceneIsSettled(name, target), ("scene %s did not hold after settling: %s"):format(name, describeState(target)))
	assert(darkest <= 0.01,("the Fader never went opaque during the cut to %s (darkest %.3f)"):format(name, darkest))
	assert(
		faderAtCut and faderAtCut <= CUT_FADER_MAX,
		("the cut to %s happened with the Fader at %s, it must be nearly opaque"):format(name, tostring(faderAtCut))
	)
end

local settingsPosition = markerPosition("SettingsRoom", "SettingsCameraShot")
local creditsPosition = markerPosition("CreditsRoom", "CreditsCameraShot")

if CASE == "A" then
	local menuBase = camera:GetAttribute("MenuBaseCFrame")
	assert(typeof(menuBase) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing")
	local menuTarget = menuBase.Position
	expectSettled("Menu", menuTarget, 1)
	assert(hook:Invoke("scene") == "Menu", "scene should start as Menu")
	assert(hook:Invoke("goTo", "Menu") == false, "goTo the scene you are already in should return false")
	assert(hook:Invoke("goTo", "Nowhere") == false, "goTo an unknown scene should return false")
	expectSettled("Menu", menuTarget, 1)

	goAndSettle("Settings", settingsPosition)
	goAndSettle("Credits", creditsPosition)

	-- Back on the menu: the camera is on the menu shot, which MenuCamera publishes as the base CFrame (it changes
	-- when the scene cuts, so read it once the scene is Menu).
	assert(hook:Invoke("goTo", "Menu") == true, "goTo(Menu) should start a transition")
	assert(
		waitFor(function()
			return playerGui:GetAttribute("MenuScene") == "Menu"
		end, 2),
		"the scene never became Menu"
	)
	local base = camera:GetAttribute("MenuBaseCFrame")
	assert(typeof(base) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing")
	assert((base.Position - menuTarget).Magnitude <= POSITION_TOLERANCE, "the menu shot moved: " .. tostring(base.Position))
	expectSettled("Menu", base.Position, 2)
	assert(root.Visible and not back.Visible, "Menu should show Root and hide Back")

	-- End in Settings, with a counter on Back, for A2's real click.
	goAndSettle("Settings", settingsPosition)
	playerGui:SetAttribute("ScenesTestBackClicks", 0)
	back.Activated:Connect(function()
		playerGui:SetAttribute("ScenesTestBackClicks", (playerGui:GetAttribute("ScenesTestBackClicks") or 0) + 1)
	end)
	local centre = back.AbsolutePosition + back.AbsoluteSize / 2
	print(("scenes A: now in Settings; Back centre is at screen (%.0f, %.0f), so user_mouse_input y is %.0f"):format(centre.X, centre.Y, centre.Y - 58))
elseif CASE == "A2" then
	assert(playerGui:GetAttribute("ScenesTestBackClicks") ~= nil, "run case A first, in this same playtest")
	local clicks = playerGui:GetAttribute("ScenesTestBackClicks")
	assert(clicks == 1, "expected exactly one real click on Back, got " .. tostring(clicks))
	local base = camera:GetAttribute("MenuBaseCFrame")
	assert(typeof(base) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing")
	expectSettled("Menu", base.Position, 3)
	assert(not back.Visible and root.Visible, "after the Back click Root should show and Back should hide")
elseif CASE == "B" then
	assert(hook:Invoke("goTo", "Settings") == true, "the first goTo should start a transition")
	assert(hook:Invoke("goTo", "Credits") == false, "goTo while a transition runs should return false")
	assert(hook:Invoke("goTo", "Menu") == false, "goTo while a transition runs should return false")
	expectSettled("Settings", settingsPosition, 2)
	-- Nothing was queued behind the first transition: the scene stays put.
	task.wait(1.5)
	assert(sceneIsSettled("Settings", settingsPosition), "mashing left an inconsistent state: " .. describeState(settingsPosition))
elseif CASE == "C" then
	assert(hook:Invoke("goTo", "Settings") == true, "goTo(Settings) should start a transition")
	task.wait(PLAY_DELAY)
	assert(hook:Invoke("play") == true, "play() should start the Play flow")

	-- From here Play owns the Fader, Root and Back until Root is destroyed: the transition must not touch them.
	local previousFader = fader.BackgroundTransparency
	local rootGone = false
	local deadline = os.clock() + 10
	while os.clock() < deadline and not rootGone do
		RunService.Heartbeat:Wait()
		if root.Parent == nil then
			rootGone = true
			assert(vignette.Visible == false, "the Vignette should be hidden by the time Root is destroyed")
		else
			assert(root.Visible, "Root was hidden after Play started (the transition touched it)")
			assert(not back.Visible, "Back was shown after Play started (the transition touched it)")
			local transparency = fader.BackgroundTransparency
			assert(
				transparency <= previousFader + 0.0001,
				("the Fader went from %.3f up to %.3f while Play was fading in (a transition fought it)"):format(previousFader, transparency)
			)
			previousFader = transparency
		end
	end
	assert(rootGone, "Root was never destroyed after Play")

	local character = waitFor(function()
		return player.Character
	end, 10)
	assert(character, "player.Character is nil 10s after play()")
	assert(waitFor(function()
		return playerGui:FindFirstChild("MainMenu") == nil
	end, 10), "MainMenu was not destroyed after Play")
	assert(playerGui:GetAttribute("MenuOpen") == false, "MenuOpen should be false after Play")
	assert(
		waitFor(function()
			return playerGui:GetAttribute("MenuScene") == nil
		end, 2),
		"MenuScene should be cleared after Play, got " .. tostring(playerGui:GetAttribute("MenuScene"))
	)
	assert(camera.CameraType == Enum.CameraType.Custom, "CameraType should be Custom after Play, got " .. camera.CameraType.Name)
	assert(camera:GetAttribute("MenuBaseCFrame") == nil, "MenuBaseCFrame should be cleared after Play")

	-- Nothing from Settings or Credits is left behind.
	assert(playerGui:FindFirstChild("SettingsBoardGui") == nil, "SettingsBoardGui is still in PlayerGui after Play")
	local creditsRoom = workspace:FindFirstChild("CreditsRoom")
	local avatars = creditsRoom and creditsRoom:FindFirstChild("CreditAvatars")
	assert(avatars == nil or #avatars:GetChildren() == 0, "CreditsRoom.CreditAvatars should be absent or empty after Play")

	-- The cancelled transition never grabs the camera back: once the character owns it, no frame sits on the room shot.
	for _ = 1, 20 do
		RunService.Heartbeat:Wait()
		local distance = (camera.CFrame.Position - settingsPosition).Magnitude
		assert(distance > 5, "camera is still on the Settings shot after Play (" .. distance .. " studs)")
	end
	assert(camera.CameraType == Enum.CameraType.Custom, "camera should stay Custom after Play")
else
	error("unknown CASE " .. tostring(CASE))
end

return "PASS"
