-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet). One case per playtest:
-- pick it with CASE below, then run the whole file as an execute_luau call.
-- Drives the menu through MainMenuClient's Studio-only TestHook and observes the real SceneDirector, camera and GUI.
--   A   round trip Menu -> Settings -> Credits -> Menu -> Settings. Every stop cuts the camera onto the room's marker
--       (within 0.05 studs; sway only rotates) behind a (nearly) opaque Fader, toggles Root and Back, and ends with
--       the Fader fully clear. It leaves the menu in Settings with a click counter on Back for A2.
--   A2  run AFTER A, once Back was clicked for real (user_mouse_input moveTo the Back button, then a left click):
--       exactly one click reached Back and the menu is back on Menu. Needs no fresh playtest, only A's.
--   B   mashing: goTo Settings, Credits, Menu back to back. Only the first starts; Settings wins and nothing queues.
--   C   Play mid-transition (PLAY_DELAY seconds after goTo SCENE; 0.1 is mid fade-out, 0.6 mid fade-in). Play
--       wins: the character spawns, the menu is gone, and the cancelled transition never touches Root, Back, the
--       Fader or the camera again. With PLAY_DELAY 0.5 or more the room's content is already up when Play is
--       pressed (the settings board, or the credit avatars): that is asserted first, so the "nothing is left behind"
--       checks afterwards are real and not vacuously true. Run it for SCENE "Settings" and for SCENE "Credits".
--       Read the console afterwards: it must have no errors. It also checks that ButtonB is unbound afterwards and that
--       every emitter and light in both rooms is switched off (after proving some were running before Play).
--   D   controller path. Without a gamepad nothing forces a selection; the MenuBack action (ButtonB) is bound in a room
--       and unbound on Menu. With the TestHook's gamepad mode on, every cut moves the selection: BACK in a room, the
--       Settings or Credits button on the way back to the menu. The bound function sinks only the Begin state (End
--       passes), and Begin goes back to Menu.
--   E   blur: MenuBlur (Size 6) only on Menu, in Settings and in Credits it is absent or Size 0 while the colour grade
--       stays, and with Screen Effects off neither exists in any scene. Restores Screen Effects.
--   F   a click that beats the room: with workspace.SettingsRoom detached (client side only, standing in for a room that
--       has not streamed in yet) goTo refuses at once, then opens Settings by itself when the room is back. A refused
--       click is forgotten once the player picks another scene. Ends on Menu. Expect two SceneDirector warnings.
local CASE = "A"
local PLAY_DELAY = 0.1
local SCENE = "Settings"

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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

-- ButtonB is bound to the MenuBack action.
local function backBound()
	local info = ContextActionService:GetBoundActionInfo("MenuBack")
	return next(info) ~= nil and table.find(info.inputTypes, Enum.KeyCode.ButtonB) ~= nil
end

-- Nothing is bound under the MenuBack name.
local function backUnbound()
	return next(ContextActionService:GetBoundActionInfo("MenuBack")) == nil
end

-- The emitters and lights under both rooms: how many there are, and how many are still switched on.
local function roomEffects()
	local total, on = 0, 0
	for _, roomName in { "SettingsRoom", "CreditsRoom" } do
		local room = workspace:FindFirstChild(roomName)
		assert(room, "workspace." .. roomName .. " missing")
		for _, item in room:GetDescendants() do
			if item:IsA("ParticleEmitter") or item:IsA("Light") then
				total += 1
				if item.Enabled then
					on += 1
				end
			end
		end
	end
	return total, on
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

-- The Size of the one MenuBlur, or nil when there is none.
local function blurSize()
	assert(countNamed("MenuBlur") <= 1, "more than one MenuBlur: " .. countNamed("MenuBlur"))
	local blur = Lighting:FindFirstChild("MenuBlur")
	return blur and blur.Size
end

-- No visible blur: absent or Size 0.
local function sharp()
	local size = blurSize()
	return size == nil or size == 0
end

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
	-- MainMenu has IgnoreGuiInset = true, so AbsolutePosition is already 58 px above the viewport y that
	-- user_mouse_input uses: aim at the centre's AbsolutePosition as it is (no extra -58).
	print(("scenes A: now in Settings; Back centre is at (%.0f, %.0f), so user_mouse_input moveTo that point"):format(centre.X, centre.Y))
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
	assert(SCENE == "Settings" or SCENE == "Credits", "SCENE must be Settings or Credits")
	assert(hook:Invoke("goTo", SCENE) == true, "goTo(" .. SCENE .. ") should start a transition")
	task.wait(PLAY_DELAY)
	-- Past the cut (0.4s) the scene's content is up. Prove it, so the cleanup checks below can fail.
	if PLAY_DELAY >= 0.5 then
		if SCENE == "Settings" then
			local gui = playerGui:FindFirstChild("SettingsBoardGui")
			assert(gui and gui.Enabled, "the settings board should be up before Play is pressed, or the cleanup check proves nothing")
		else
			local folder = workspace.CreditsRoom:FindFirstChild("CreditAvatars")
			assert(
				folder and #folder:GetChildren() >= 1,
				"the credit avatars should be up before Play is pressed, or the cleanup check proves nothing"
			)
		end
	end
	-- The rooms are running (emitters and lights on), whatever Play comes in the middle of; and once the cut is done
	-- ButtonB is bound to BACK. Proved first, so the "switched off afterwards" checks below can fail.
	local effectsTotal, effectsOn = roomEffects()
	assert(effectsOn > 0, ("the rooms should have running emitters or lights before Play (%d of %d are on)"):format(effectsOn, effectsTotal))
	if PLAY_DELAY >= 0.5 then
		assert(backBound(), "ButtonB (MenuBack) should be bound in a room before Play is pressed, or the unbind check proves nothing")
	end
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
	-- Play unbinds ButtonB and switches the rooms' emitters and lights off (client side).
	assert(backUnbound(), "ButtonB (MenuBack) is still bound after Play")
	local _, stillOn = roomEffects()
	assert(stillOn == 0, stillOn .. " emitters or lights in the rooms are still on after Play")

	-- The cancelled transition never grabs the camera back: once the character owns it, no frame sits on the room shot.
	local shotPosition = if SCENE == "Settings" then settingsPosition else creditsPosition
	for _ = 1, 20 do
		RunService.Heartbeat:Wait()
		local distance = (camera.CFrame.Position - shotPosition).Magnitude
		assert(distance > 5, "camera is still on the " .. SCENE .. " shot after Play (" .. distance .. " studs)")
	end
	assert(camera.CameraType == Enum.CameraType.Custom, "camera should stay Custom after Play")
elseif CASE == "D" then
	local menuBase = camera:GetAttribute("MenuBaseCFrame")
	assert(typeof(menuBase) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing")
	local menuTarget = menuBase.Position
	local buttons = root.Buttons
	expectSettled("Menu", menuTarget, 1)
	assert(backUnbound(), "ButtonB (MenuBack) must not be bound on the Menu")

	-- Without a gamepad: ButtonB is bound in a room anyway, and nobody is given a selection box.
	GuiService.SelectedObject = nil
	goAndSettle("Settings", settingsPosition)
	assert(backBound(), "MenuBack should be bound to ButtonB in Settings")
	if not UserInputService.GamepadEnabled then
		assert(GuiService.SelectedObject ~= back, "a mouse or touch player must not be given a selection")
	end
	goAndSettle("Menu", menuTarget)
	assert(backUnbound(), "MenuBack should be unbound again on the Menu")

	-- With a gamepad (the TestHook makes SceneDirector act as if the last input was one).
	hook:Invoke("gamepad", true)
	local ok, err = pcall(function()
		GuiService.SelectedObject = buttons.Play
		goAndSettle("Settings", settingsPosition)
		assert(GuiService.SelectedObject == back, "Settings should select BACK, the selection is " .. tostring(GuiService.SelectedObject))
		assert(backBound(), "MenuBack should be bound in Settings")
		goAndSettle("Credits", creditsPosition)
		assert(GuiService.SelectedObject == back, "Credits should select BACK, the selection is " .. tostring(GuiService.SelectedObject))
		assert(backBound(), "MenuBack should still be bound in Credits")
		goAndSettle("Menu", menuTarget)
		assert(
			GuiService.SelectedObject == buttons.Credits,
			"coming back from Credits should select the Credits button, the selection is " .. tostring(GuiService.SelectedObject)
		)
		assert(backUnbound(), "MenuBack should be unbound on the Menu")
		goAndSettle("Settings", settingsPosition)
		goAndSettle("Menu", menuTarget)
		assert(
			GuiService.SelectedObject == buttons.Settings,
			"coming back from Settings should select the Settings button, the selection is " .. tostring(GuiService.SelectedObject)
		)

		-- The ButtonB function: the release passes, the press is sunk and goes back to the Menu.
		goAndSettle("Settings", settingsPosition)
		assert(hook:Invoke("back", "End") == Enum.ContextActionResult.Pass, "releasing ButtonB must pass")
		task.wait(0.3)
		assert(sceneIsSettled("Settings", settingsPosition), "releasing ButtonB must not leave Settings: " .. describeState(settingsPosition))
		assert(hook:Invoke("back", "Begin") == Enum.ContextActionResult.Sink, "pressing ButtonB must be sunk")
		expectSettled("Menu", menuTarget, 3)
		assert(backUnbound(), "MenuBack should be unbound after going back with ButtonB")
		assert(GuiService.SelectedObject == buttons.Settings, "going back with ButtonB should select the Settings button")
	end)
	pcall(hook.Invoke, hook, "gamepad", false)
	GuiService.SelectedObject = nil
	assert(ok, err)
elseif CASE == "E" then
	local MenuSettings = require(clientScript:WaitForChild("MenuSettings", 10))
	local menuBase = camera:GetAttribute("MenuBaseCFrame")
	assert(typeof(menuBase) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing")
	local menuTarget = menuBase.Position
	expectSettled("Menu", menuTarget, 1)

	local function gradeOnly(where)
		assert(sharp(), where .. " must not be blurred, MenuBlur.Size is " .. tostring(blurSize()))
		assert(countNamed("MenuColorCorrection") == 1, "the colour grade should stay in " .. where)
	end
	local function blurredMenu()
		assert(blurSize() == 6, "the Menu should have MenuBlur at Size 6, got " .. tostring(blurSize()))
		assert(countNamed("MenuColorCorrection") == 1, "the Menu should have the colour grade")
	end
	local function noEffects(where)
		assert(
			waitFor(function()
				return countNamed("MenuBlur") == 0 and countNamed("MenuColorCorrection") == 0
			end, 1),
			"Screen Effects off should leave neither blur nor grade in " .. where
		)
	end

	blurredMenu()
	local ok, err = pcall(function()
		goAndSettle("Settings", settingsPosition)
		gradeOnly("Settings")
		goAndSettle("Credits", creditsPosition)
		gradeOnly("Credits")
		goAndSettle("Menu", menuTarget)
		blurredMenu()

		-- Screen Effects off: nothing in any scene.
		MenuSettings.set("ScreenEffects", false)
		noEffects("the Menu")
		goAndSettle("Settings", settingsPosition)
		noEffects("Settings")
		-- Switched on again inside a room: the grade returns, the blur does not.
		MenuSettings.set("ScreenEffects", true)
		assert(
			waitFor(function()
				return countNamed("MenuColorCorrection") == 1
			end, 1),
			"the colour grade should return when Screen Effects goes on in Settings"
		)
		gradeOnly("Settings after Screen Effects went on")
		goAndSettle("Menu", menuTarget)
		blurredMenu()
	end)
	MenuSettings.set("ScreenEffects", true)
	assert(ok, err)
elseif CASE == "F" then
	local menuBase = camera:GetAttribute("MenuBaseCFrame")
	assert(typeof(menuBase) == "CFrame", "Camera attribute MenuBaseCFrame (a CFrame) missing")
	local menuTarget = menuBase.Position
	local settingsRoom, creditsRoom = workspace.SettingsRoom, workspace.CreditsRoom
	expectSettled("Menu", menuTarget, 1)

	local ok, err = pcall(function()
		-- Leg 1: the room is not there yet. goTo is refused at once (it must never wait), then Settings opens by itself.
		settingsRoom.Parent = nil
		local started = os.clock()
		local result = hook:Invoke("goTo", "Settings")
		assert(result == false, "goTo with the room missing should be refused, got " .. tostring(result))
		assert(os.clock() - started < 0.5, "a refused goTo must not wait for the room (" .. (os.clock() - started) .. "s)")
		task.wait(0.5)
		assert(sceneIsSettled("Menu", menuTarget), "a refused goTo must leave the menu alone: " .. describeState(menuTarget))
		settingsRoom.Parent = workspace
		expectSettled("Settings", settingsPosition, 3)
		goAndSettle("Menu", menuTarget)

		-- Leg 2: the player picks another scene while the room is missing, so its late arrival must not pull them away.
		creditsRoom.Parent = nil
		assert(hook:Invoke("goTo", "Credits") == false, "goTo with the Credits room missing should be refused")
		goAndSettle("Settings", settingsPosition)
		creditsRoom.Parent = workspace
		task.wait(1.5)
		assert(sceneIsSettled("Settings", settingsPosition), "the late Credits room pulled the player away: " .. describeState(settingsPosition))
		goAndSettle("Menu", menuTarget)
	end)
	settingsRoom.Parent = workspace
	creditsRoom.Parent = workspace
	assert(ok, err)
else
	error("unknown CASE " .. tostring(CASE))
end

return "PASS"
