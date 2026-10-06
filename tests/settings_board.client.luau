-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet). One case per playtest:
-- pick it with CASE below, then run the whole file as an execute_luau call.
-- Drives the menu through MainMenuClient's Studio-only TestHook and observes the real SettingsBoard on the real board.
--   A   after goTo Settings the SurfaceGui SettingsBoardGui is on the board (Adornee, Face, PixelsPerStud 50, clipped)
--       with every named child, Scale-only layout, uppercase text in the theme's fonts, and sliders / switches that follow the
--       Music / SFX groups and MenuSettings. Also checks mount() reuses the gui. Restores every setting.
--   B1  go to Settings, switch Camera Sway off (so the camera holds still while the mouse moves), count Activated on
--       the Screen Effects switch and print where to click: user_mouse_input moveTo that point, then a left click.
--   B2  run AFTER the real click: exactly one click landed, the switch says OFF, Screen Effects is off and MenuBlur /
--       MenuColorCorrection are gone; after goTo Menu the Vignette is hidden and they are still gone; switching it back
--       on (MenuSettings.set, i.e. from outside the board) restores everything and the text reads ON again.
--   C   after goTo Menu the board is hidden (SettingsBoardGui.Enabled == false) but kept, and going back reuses it.
--   D1  go to Settings, set Music to 0.2, switch Camera Sway off and print the points of a real drag along the Music
--       slider: left end, middle, right end (user_mouse_input: moveTo left, mouseButtonDown, moveTo middle).
--   D2  run at each stage of the drag (set D2_STAGE): "press" right after the button went down at the left end (the
--       volume is near 0, which a wrong cursor-to-slider mapping cannot give), "middle" with the cursor in the middle
--       (about 0.5) and "end" after the drag reached the right end and the button went up (0.9 or more). "end" also
--       restores Music and Camera Sway.
--   E1  regression for the ScreenGui path of VolumeSlider (the SurfaceGui fix must not break it): builds a throwaway
--       ScreenGui slider on a throwaway SoundGroup and prints the points of a real drag along it, like D1.
--   E2  like D2 (D2_STAGE press / middle / end) for that slider; "end" removes the throwaway slider and group.
--   F1  like D1, but the drag starts on the Music ROW's title area, away from the thin track (Music is first set to 0.6,
--       so a press that does not reach the slider cannot give the near-0 value D2's "press" stage wants). Run D2 with
--       the same three stages (press / middle / end) after each step: the stage checks are shared.
--   G1  go to Settings, switch Camera Sway off, count Activated on the Screen Effects row's RowHit and on its Toggle and
--       print where to click: the row's TITLE area, away from the ON / OFF button.
--   G2  run AFTER the real click: exactly one RowHit click, none on the Toggle, Screen Effects is off and the button
--       reads OFF. Restores both settings.
--   Case A also checks the touch targets: every row is at least 40 px high on screen at a 390 px high viewport (scaled to
--   this window), the slider rows are Active (they start the drag) and each switch row has a full-size RowHit button.
-- B and D need a real mouse: they aim with Camera:WorldToViewportPoint at the 3D spot of the control on the board.
-- user_mouse_input coordinates are window relative and GetMouseLocation reads them as (x, y + 58), so y is printed
-- already reduced by 58.
local CASE = "A"
local D2_STAGE = "press"

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local SoundService = game:GetService("SoundService")

-- The board's colours and fonts are the active theme's (MenuAssets.THEME); the checks below read them from here.
local THEME = require(ReplicatedFirst:WaitForChild("MenuAssets", 10)).theme()

local GUI_NAME = "SettingsBoardGui"
local INSET = 58
local TOLERANCE = 0.001

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

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or TOLERANCE)
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
-- The menu is three ScreenGuis in PlayerGui: MainMenu (Root, Back), MainMenuVignette (Vignette), MainMenuFader (Fader).
local function waitForGui(name)
	local gui = waitFor(function()
		return playerGui:FindFirstChild(name)
	end, 10)
	assert(gui, name .. " missing in PlayerGui")
	return gui
end
local menu = waitForGui("MainMenu")
local vignetteGui = waitForGui("MainMenuVignette")
local faderGui = waitForGui("MainMenuFader")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

local root, back, fader, vignette = menu.Root, menu.Back, faderGui.Fader, vignetteGui.Vignette
local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "MainMenuClient missing")
local hook = clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")

local MenuSettings = require(clientScript:WaitForChild("MenuSettings", 10))
local VolumeSlider = require(clientScript:WaitForChild("VolumeSlider", 10))

local settingsRoom = workspace:WaitForChild("SettingsRoom", 10)
local board = settingsRoom and settingsRoom:WaitForChild("Settingsboard", 10)
assert(board and board:IsA("BasePart"), "workspace.SettingsRoom.Settingsboard missing")
local music = SoundService:FindFirstChild("Music")
local sfx = SoundService:FindFirstChild("SFX")
assert(music and music:IsA("SoundGroup"), "SoundService.Music (SoundGroup) missing")
assert(sfx and sfx:IsA("SoundGroup"), "SoundService.SFX (SoundGroup) missing")

-- The scene is `name` and settled: the Fader is clear and, a few frames later, still is (the transition thread lets go
-- of its debounce a moment after the Fader reaches 1, and a goTo in that very frame would be refused).
local function ensureScene(name)
	if playerGui:GetAttribute("MenuScene") ~= name then
		assert(hook:Invoke("goTo", name) == true, "goTo(" .. name .. ") should start a transition")
	end
	local settled = waitFor(function()
		return playerGui:GetAttribute("MenuScene") == name and fader.BackgroundTransparency == 1
	end, 3)
	assert(settled, ("scene %s did not settle within 3s (MenuScene=%s)"):format(name, tostring(playerGui:GetAttribute("MenuScene"))))
	task.wait(0.15)
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

local function effectsPresent()
	return countNamed("MenuBlur") == 1 and countNamed("MenuColorCorrection") == 1
end

local function effectsAbsent()
	return countNamed("MenuBlur") == 0 and countNamed("MenuColorCorrection") == 0
end

-- The gui and the controls under it, or an assert naming what is missing.
local function boardParts()
	local gui = playerGui:FindFirstChild(GUI_NAME)
	assert(gui, GUI_NAME .. " missing in PlayerGui")
	local function child(parent, name, className)
		local found = parent:FindFirstChild(name)
		assert(found, parent.Name .. "." .. name .. " missing")
		assert(found:IsA(className), parent:GetFullName() .. "." .. name .. " should be a " .. className .. ", is " .. found.ClassName)
		return found
	end
	local parts = { gui = gui }
	parts.header = child(gui, "Header", "TextLabel")
	parts.musicSlider = child(child(gui, "MusicRow", "Frame"), "Slider", "Frame")
	parts.sfxSlider = child(child(gui, "SfxRow", "Frame"), "Slider", "Frame")
	parts.swayToggle = child(child(gui, "SwayRow", "Frame"), "Toggle", "TextButton")
	parts.effectsToggle = child(child(gui, "EffectsRow", "Frame"), "Toggle", "TextButton")
	for _, slider in { parts.musicSlider, parts.sfxSlider } do
		child(slider, "Fill", "Frame")
		child(slider, "Knob", "Frame")
	end
	return parts
end

-- Where `guiObject` (at `fraction` across and down it) is in the world, on the face the board's SurfaceGui is on, and
-- where that lands on the screen. Only the Front face is supported: its GUI runs left to right along -X, top to bottom
-- along -Y, and the face is at -Z.
local function screenPointOf(gui, guiObject, fraction)
	assert(gui.Face == Enum.NormalId.Front, "screenPointOf only knows the Front face, the gui is on " .. gui.Face.Name)
	local canvas = gui.AbsoluteSize
	local pixelsPerStud = gui.PixelsPerStud
	local pixel = guiObject.AbsolutePosition + guiObject.AbsoluteSize * fraction
	local right = (pixel.X - canvas.X / 2) / pixelsPerStud
	local up = (canvas.Y / 2 - pixel.Y) / pixelsPerStud
	local world = board.CFrame:PointToWorldSpace(Vector3.new(-right, up, -board.Size.Z / 2))
	local camera = workspace.CurrentCamera
	local viewport, onScreen = camera:WorldToViewportPoint(world)
	assert(onScreen, "the point is not on screen: " .. tostring(viewport))
	return Vector2.new(viewport.X, viewport.Y)
end

-- Camera Sway is off and the camera has eased back onto the room shot (the aim of a real click depends on it).
local function waitForCameraRest()
	local camera = workspace.CurrentCamera
	local rest = waitFor(function()
		local base = camera:GetAttribute("MenuBaseCFrame")
		return typeof(base) == "CFrame" and (camera.CFrame.LookVector - base.LookVector).Magnitude < 0.0005
	end, 5)
	assert(rest, "the camera never settled onto the room shot")
end

local function describePoint(label, point)
	print(("settings_board: %s -> user_mouse_input x=%.0f y=%.0f (viewport %.0f, %.0f)"):format(label, point.X, point.Y - INSET, point.X, point.Y))
end

if CASE == "A" then
	ensureScene("Settings")
	local parts = boardParts()
	local gui = parts.gui

	local SettingsBoard = require(clientScript:WaitForChild("SettingsBoard", 10))
	assert(type(SettingsBoard.mount) == "function", "SettingsBoard.mount missing")
	assert(type(SettingsBoard.setEnabled) == "function", "SettingsBoard.setEnabled missing")
	assert(type(SettingsBoard.unmount) == "function", "SettingsBoard.unmount missing")

	assert(gui:IsA("SurfaceGui"), GUI_NAME .. " should be a SurfaceGui, is " .. gui.ClassName)
	assert(gui.Enabled, GUI_NAME .. " should be Enabled in the Settings scene")
	assert(gui.Adornee == board, GUI_NAME .. ".Adornee should be the Settingsboard, is " .. tostring(gui.Adornee))
	assert(
		gui.Face == Enum.NormalId[board:GetAttribute("BoardFace")],
		GUI_NAME .. ".Face should follow the board's BoardFace attribute, is " .. gui.Face.Name
	)
	assert(gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud, GUI_NAME .. ".SizingMode should be PixelsPerStud")
	assert(gui.PixelsPerStud == 50, GUI_NAME .. ".PixelsPerStud should be 50, is " .. gui.PixelsPerStud)
	assert(gui.ClipsDescendants, GUI_NAME .. ".ClipsDescendants should be true")
	assert(
		near(gui.AbsoluteSize.X, board.Size.X * 50, 1) and near(gui.AbsoluteSize.Y, board.Size.Y * 50, 1),
		"the canvas should be the board face at 50 px per stud, is " .. tostring(gui.AbsoluteSize)
	)

	-- Text: "SETTINGS" header, uppercase text in the theme's fonts everywhere (title, body or label font), switches start ON.
	assert(parts.header.Text == "SETTINGS", "Header should read SETTINGS, reads " .. parts.header.Text)
	local themeFonts = {}
	for _, key in { "titleFont", "bodyFont", "labelFont" } do
		themeFonts[THEME[key].Family .. "/" .. THEME[key].Weight.Name] = true
	end
	for _, item in gui:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			assert(item.Text == string.upper(item.Text), item:GetFullName() .. " text should be uppercase: " .. item.Text)
			assert(
				themeFonts[item.FontFace.Family .. "/" .. item.FontFace.Weight.Name],
				item:GetFullName() .. " should use one of the theme's fonts, uses " .. item.FontFace.Family .. "/" .. item.FontFace.Weight.Name
			)
			assert(item.TextScaled, item:GetFullName() .. " should be TextScaled")
		end
		-- Scale only: no pixel positions or sizes (UIStroke thickness and UICorner radius are the allowed exceptions).
		if item:IsA("GuiObject") then
			local p, s = item.Position, item.Size
			assert(
				p.X.Offset == 0 and p.Y.Offset == 0 and s.X.Offset == 0 and s.Y.Offset == 0,
				item:GetFullName() .. " uses pixels: Position " .. tostring(p) .. " Size " .. tostring(s)
			)
		end
	end
	assert(parts.swayToggle.Text == "ON" and parts.effectsToggle.Text == "ON", "both switches should start ON")

	-- mount() creates or reuses: a second call hands back the same gui and leaves exactly one.
	local again = SettingsBoard.mount(board, playerGui)
	assert(again == gui, "mount() should reuse the existing " .. GUI_NAME)
	local copies = 0
	for _, child in playerGui:GetChildren() do
		if child.Name == GUI_NAME then
			copies += 1
		end
	end
	assert(copies == 1, "expected exactly one " .. GUI_NAME .. ", found " .. copies)

	-- Touch targets: a finger needs 40 px, and the board is only ~266 px tall on a phone in landscape (390 px high), so
	-- each ROW must be that big. Projection scales with the viewport height, so check against 40 * height / 390.
	local viewportHeight = workspace.CurrentCamera.ViewportSize.Y
	local minRowHeight = 40 * viewportHeight / 390
	for _, rowName in { "MusicRow", "SfxRow", "SwayRow", "EffectsRow" } do
		local row = gui:FindFirstChild(rowName)
		assert(row and row:IsA("Frame"), rowName .. " missing")
		local height = screenPointOf(gui, row, Vector2.new(0.5, 1)).Y - screenPointOf(gui, row, Vector2.new(0.5, 0)).Y
		assert(
			height >= minRowHeight,
			("%s is %.1f px high on screen, a finger needs at least %.1f px at this %d px high viewport (40 px at 390)"):format(
				rowName,
				height,
				minRowHeight,
				viewportHeight
			)
		)
		print(("settings_board A: %s is %.1f px high at a %d px high viewport (needs %.1f)"):format(rowName, height, viewportHeight, minRowHeight))
	end
	for _, rowName in { "MusicRow", "SfxRow" } do
		assert(gui[rowName].Active, rowName .. " should be Active: a press anywhere on it starts the slider's drag")
	end
	for _, rowName in { "SwayRow", "EffectsRow" } do
		local hit = gui[rowName]:FindFirstChild("RowHit")
		assert(hit and hit:IsA("TextButton"), rowName .. ".RowHit (TextButton) missing: the whole row should flip the switch")
		assert(hit.Size == UDim2.fromScale(1, 1), rowName .. ".RowHit should cover the whole row, is " .. tostring(hit.Size))
	end

	local originalMusic, originalSfx = music.Volume, sfx.Volume
	local ok, err = pcall(function()
		-- The sliders start at the groups' volumes ...
		assert(near(parts.musicSlider.Fill.Size.X.Scale, originalMusic), "Music slider should start at the Music volume")
		assert(near(parts.sfxSlider.Fill.Size.X.Scale, originalSfx), "SFX slider should start at the SFX volume")
		-- ... and VolumeSlider.setAlpha on the board's slider moves the SFX group (attach wired nothing else to it).
		VolumeSlider.setAlpha(parts.sfxSlider, sfx, 0.3)
		assert(near(sfx.Volume, 0.3), "SFX.Volume should be 0.3, got " .. sfx.Volume)
		assert(near(parts.sfxSlider.Fill.Size.X.Scale, 0.3), "SFX Fill should follow")
		assert(near(parts.sfxSlider.Knob.Position.X.Scale, 0.3), "SFX Knob should follow")
		assert(near(music.Volume, originalMusic), "the SFX slider must not touch Music")

		-- The switches follow MenuSettings, however it is changed.
		MenuSettings.set("CameraSway", false)
		assert(
			waitFor(function()
				return parts.swayToggle.Text == "OFF"
			end, 1),
			"the Camera Sway switch should read OFF after MenuSettings.set('CameraSway', false)"
		)
		assert(parts.effectsToggle.Text == "ON", "the Screen Effects switch should be untouched")
		MenuSettings.set("CameraSway", true)
		assert(
			waitFor(function()
				return parts.swayToggle.Text == "ON"
			end, 1),
			"the Camera Sway switch should read ON again"
		)
	end)
	VolumeSlider.setAlpha(parts.sfxSlider, sfx, originalSfx)
	VolumeSlider.setAlpha(parts.musicSlider, music, originalMusic)
	MenuSettings.set("CameraSway", true)
	assert(ok, err)
	assert(near(sfx.Volume, originalSfx) and near(music.Volume, originalMusic), "volumes were not restored")
elseif CASE == "B1" then
	ensureScene("Settings")
	local parts = boardParts()
	assert(MenuSettings.get("ScreenEffects") == true, "ScreenEffects should start on")
	assert(parts.effectsToggle.Text == "ON", "the Screen Effects switch should start ON")
	MenuSettings.set("CameraSway", false)
	waitForCameraRest()
	playerGui:SetAttribute("SettingsBoardTestClicks", 0)
	parts.effectsToggle.Activated:Connect(function()
		playerGui:SetAttribute("SettingsBoardTestClicks", (playerGui:GetAttribute("SettingsBoardTestClicks") or 0) + 1)
	end)
	describePoint("Screen Effects switch", screenPointOf(parts.gui, parts.effectsToggle, Vector2.new(0.5, 0.5)))
elseif CASE == "B2" then
	assert(playerGui:GetAttribute("SettingsBoardTestClicks") ~= nil, "run case B1 first, in this same playtest")
	local parts = boardParts()
	local ok, err = pcall(function()
		local clicks = playerGui:GetAttribute("SettingsBoardTestClicks")
		assert(clicks == 1, "expected exactly one real click on the Screen Effects switch, got " .. tostring(clicks))
		assert(parts.effectsToggle.Text == "OFF", "the switch should read OFF after the click, reads " .. parts.effectsToggle.Text)
		assert(MenuSettings.get("ScreenEffects") == false, "Screen Effects should be off after the click")
		assert(
			waitFor(effectsAbsent, 1),
			"MenuBlur / MenuColorCorrection should be gone as soon as Screen Effects goes off in the Settings scene"
		)
		assert(parts.swayToggle.Text == "OFF", "the Camera Sway switch should still read OFF (B1 turned it off)")

		-- BACK on the menu: the Vignette stays hidden and the effects stay gone.
		ensureScene("Menu")
		assert(vignette.Visible == false, "the Vignette should be hidden after BACK with Screen Effects off")
		assert(effectsAbsent(), "the effects should still be absent after BACK")
		assert(parts.effectsToggle.Text == "OFF", "the switch should still read OFF after BACK")

		-- Switched back on from outside the board: everything returns, the switch reads ON.
		MenuSettings.set("ScreenEffects", true)
		assert(waitFor(effectsPresent, 1), "MenuBlur / MenuColorCorrection should reappear when Screen Effects goes on")
		assert(waitFor(function()
			return vignette.Visible == true
		end, 1), "the Vignette should reappear when Screen Effects goes on")
		assert(
			waitFor(function()
				return parts.effectsToggle.Text == "ON"
			end, 1),
			"the switch should read ON once Screen Effects is on again"
		)
	end)
	MenuSettings.set("ScreenEffects", true)
	MenuSettings.set("CameraSway", true)
	assert(ok, err)
elseif CASE == "C" then
	ensureScene("Settings")
	local parts = boardParts()
	assert(parts.gui.Enabled, GUI_NAME .. " should be Enabled in the Settings scene")
	ensureScene("Menu")
	assert(parts.gui.Parent == playerGui, GUI_NAME .. " should stay mounted after BACK")
	assert(parts.gui.Enabled == false, GUI_NAME .. ".Enabled should be false after goTo Menu")
	assert(root.Visible and not back.Visible, "Menu should show Root and hide Back")
	-- Going back in reuses the same gui.
	ensureScene("Settings")
	assert(playerGui:FindFirstChild(GUI_NAME) == parts.gui, "re-entering Settings should reuse the same " .. GUI_NAME)
	assert(parts.gui.Enabled, GUI_NAME .. " should be Enabled again on re-entry")
	ensureScene("Menu")
	assert(parts.gui.Enabled == false, GUI_NAME .. " should be hidden again")
elseif CASE == "D1" then
	ensureScene("Settings")
	local parts = boardParts()
	playerGui:SetAttribute("SettingsBoardTestMusic", music.Volume) -- D2 restores it
	VolumeSlider.setAlpha(parts.musicSlider, music, 0.2)
	MenuSettings.set("CameraSway", false)
	waitForCameraRest()
	describePoint("Music slider left end (alpha 0.04)", screenPointOf(parts.gui, parts.musicSlider, Vector2.new(0.04, 0.5)))
	describePoint("Music slider middle (alpha 0.5)", screenPointOf(parts.gui, parts.musicSlider, Vector2.new(0.5, 0.5)))
	describePoint("Music slider right end (alpha 1.04)", screenPointOf(parts.gui, parts.musicSlider, Vector2.new(1.04, 0.5)))
elseif CASE == "D2" then
	local parts = boardParts()
	local volume = music.Volume
	local ok, err = pcall(function()
		if D2_STAGE == "press" then
			assert(volume <= 0.12, "pressing on the left end of the slider should set Music near 0, got " .. volume)
		elseif D2_STAGE == "middle" then
			assert(volume >= 0.4 and volume <= 0.6, "dragging to the middle should set Music near 0.5, got " .. volume)
		elseif D2_STAGE == "end" then
			assert(volume >= 0.9, "dragging to the right end should set Music to 0.9 or more, got " .. volume)
		else
			error("unknown D2_STAGE " .. tostring(D2_STAGE))
		end
		assert(near(parts.musicSlider.Fill.Size.X.Scale, volume), "the Fill should show the volume " .. volume)
		assert(near(parts.musicSlider.Knob.Position.X.Scale, volume), "the Knob should show the volume " .. volume)
		assert(near(sfx.Volume, 0.5), "the Music drag must not touch SFX, SFX is " .. sfx.Volume)
		-- The drag listens through a temporary Frame over the board; it must be gone once the button is up.
		assert(
			(D2_STAGE == "end") == (parts.gui:FindFirstChild("VolumeSliderDragCatcher") == nil),
			"the drag catcher should exist while the button is down and be gone after the release"
		)
	end)
	if D2_STAGE == "end" or not ok then
		VolumeSlider.setAlpha(parts.musicSlider, music, playerGui:GetAttribute("SettingsBoardTestMusic") or 0.5)
		MenuSettings.set("CameraSway", true)
	end
	assert(ok, err)
elseif CASE == "E1" then
	-- Regression for VolumeSlider's ScreenGui path, which the SurfaceGui fix must not break: a throwaway ScreenGui
	-- slider on a throwaway SoundGroup, with a real drag along it like D. Prints the points of the drag.
	for _, child in playerGui:GetChildren() do
		if child.Name == "SettingsBoardTestGui" then
			child:Destroy()
		end
	end
	local testGui = Instance.new("ScreenGui")
	testGui.Name = "SettingsBoardTestGui"
	testGui.IgnoreGuiInset = true
	testGui.ResetOnSpawn = false
	testGui.DisplayOrder = 1000
	testGui.Parent = playerGui
	local slider = Instance.new("Frame")
	slider.Name = "Slider"
	slider.Position = UDim2.fromScale(0.3, 0.8)
	slider.Size = UDim2.fromScale(0.4, 0.05)
	slider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	slider.BorderSizePixel = 0
	slider.Parent = testGui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BorderSizePixel = 0
	fill.Parent = slider
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromScale(0.04, 2)
	knob.BorderSizePixel = 0
	knob.Parent = slider
	local group = Instance.new("SoundGroup")
	group.Name = "SettingsBoardTestGroup"
	group.Volume = 0.2
	group.Parent = SoundService
	VolumeSlider.attach(slider, group)
	assert(near(group.Volume, 0.2), "attach should not change the group volume")
	for _, alpha in { 0.04, 0.5, 1.04 } do
		-- AbsolutePosition is in GUI space, which sits INSET above the viewport space describePoint takes.
		local point = slider.AbsolutePosition + Vector2.new(slider.AbsoluteSize.X * alpha, slider.AbsoluteSize.Y / 2)
		describePoint("ScreenGui slider at alpha " .. alpha, point + Vector2.new(0, INSET))
	end
elseif CASE == "E2" then
	-- Stages like D2, for the ScreenGui slider. "end" also removes the throwaway slider and group.
	local group = SoundService:FindFirstChild("SettingsBoardTestGroup")
	assert(group, "run case E1 first, in this same playtest")
	local volume = group.Volume
	local ok, err = pcall(function()
		if D2_STAGE == "press" then
			assert(volume <= 0.12, "pressing on the left end of the slider should set the volume near 0, got " .. volume)
		elseif D2_STAGE == "middle" then
			assert(volume >= 0.4 and volume <= 0.6, "dragging to the middle should set the volume near 0.5, got " .. volume)
		elseif D2_STAGE == "end" then
			assert(volume >= 0.9, "dragging to the right end should set the volume to 0.9 or more, got " .. volume)
		else
			error("unknown D2_STAGE " .. tostring(D2_STAGE))
		end
	end)
	if D2_STAGE == "end" or not ok then
		group:Destroy()
		local testGui = playerGui:FindFirstChild("SettingsBoardTestGui")
		if testGui then
			testGui:Destroy()
		end
	end
	assert(ok, err)
elseif CASE == "F1" then
	-- A drag that starts on the Music row's title, away from the track: the whole row is the touch target.
	ensureScene("Settings")
	local parts = boardParts()
	playerGui:SetAttribute("SettingsBoardTestMusic", music.Volume) -- D2 restores it
	VolumeSlider.setAlpha(parts.musicSlider, music, 0.6)
	MenuSettings.set("CameraSway", false)
	waitForCameraRest()
	local row = parts.musicSlider.Parent
	-- The title spans x 0.05-0.75 and y 0.06-0.52 of the row; the slider starts at x 0.05 and is 0.9 wide.
	describePoint("Music row title area, left (alpha 0.08)", screenPointOf(parts.gui, row, Vector2.new(0.12, 0.25)))
	describePoint("Music row title area, middle (alpha 0.5)", screenPointOf(parts.gui, row, Vector2.new(0.5, 0.25)))
	describePoint("Music row right end (alpha 1.04)", screenPointOf(parts.gui, row, Vector2.new(0.985, 0.25)))
elseif CASE == "G1" then
	ensureScene("Settings")
	local parts = boardParts()
	assert(MenuSettings.get("ScreenEffects") == true, "ScreenEffects should start on")
	MenuSettings.set("CameraSway", false)
	waitForCameraRest()
	local row = parts.effectsToggle.Parent
	local rowHit = row:FindFirstChild("RowHit")
	assert(rowHit and rowHit:IsA("TextButton"), "EffectsRow.RowHit (TextButton) missing")
	playerGui:SetAttribute("SettingsBoardTestRowClicks", 0)
	playerGui:SetAttribute("SettingsBoardTestToggleClicks", 0)
	rowHit.Activated:Connect(function()
		playerGui:SetAttribute("SettingsBoardTestRowClicks", (playerGui:GetAttribute("SettingsBoardTestRowClicks") or 0) + 1)
	end)
	parts.effectsToggle.Activated:Connect(function()
		playerGui:SetAttribute("SettingsBoardTestToggleClicks", (playerGui:GetAttribute("SettingsBoardTestToggleClicks") or 0) + 1)
	end)
	-- The title spans x 0.05-0.65 of the row, the ON / OFF button x 0.69-0.95.
	describePoint("Screen Effects row, title area", screenPointOf(parts.gui, row, Vector2.new(0.2, 0.5)))
elseif CASE == "G2" then
	assert(playerGui:GetAttribute("SettingsBoardTestRowClicks") ~= nil, "run case G1 first, in this same playtest")
	local parts = boardParts()
	local ok, err = pcall(function()
		local rowClicks = playerGui:GetAttribute("SettingsBoardTestRowClicks")
		local toggleClicks = playerGui:GetAttribute("SettingsBoardTestToggleClicks")
		assert(rowClicks == 1, "expected exactly one real click on the row's RowHit, got " .. tostring(rowClicks))
		assert(toggleClicks == 0, "the click on the title area must not reach the Toggle button, it got " .. tostring(toggleClicks))
		assert(MenuSettings.get("ScreenEffects") == false, "a click on the row should switch Screen Effects off")
		assert(parts.effectsToggle.Text == "OFF", "the button should read OFF after the row click, reads " .. parts.effectsToggle.Text)
	end)
	MenuSettings.set("ScreenEffects", true)
	MenuSettings.set("CameraSway", true)
	assert(ok, err)
else
	error("unknown CASE " .. tostring(CASE))
end

return "PASS"
