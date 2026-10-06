-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet), with the main menu open and the
-- loading screen gone. Pick the case with CASE below, then run the whole file as an execute_luau call.
-- Every colour and font asserted here is read from MenuAssets.theme() (the active theme), so the same file checks SterileBright
-- and, with THEME = "Factory" set temporarily in Studio, the Factory look.
--   A   the real menu, the real settings board and the real credits label all match the theme:
--       Menu      Title (colour, font, stroke, and its words untouched), Play / Settings / Credits / Back (panel, text, font,
--                 accent bar, border), the four Vignette edges, the hazard stripe (there when hazardStripe is true, with the
--                 hazard colours), the PopStroke hover colour (before and after a hover), the Fader still black.
--       Loading   what the loading screen built (its TestHook "look" snapshot and the LoadingParts attribute): backdrop,
--                 vignette, title, spinner, tip, and the stripe.
--       Settings  the board: backdrop, frame, header, divider, rows and their borders, accent bars, slider track / fill /
--                 knob, the ON and OFF switch, and the fonts.
--       Credits   the hover highlight and the name label (background, text, border, font).
--   LF  loading screen fallback. In Edit first set the attribute LoadingTestNoTheme = true on ReplicatedFirst.LoadingScreen (a
--       Studio-only seam: the loader then behaves as if MenuAssets.theme() were missing), start a fresh playtest, run this,
--       stop the playtest and remove the attribute. The loading screen must have built the Factory look from its own defaults.
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function sameFont(a, b)
	return typeof(a) == "Font" and typeof(b) == "Font" and a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end

local function describe(value)
	if typeof(value) == "Font" then
		return value.Family .. "/" .. value.Weight.Name .. "/" .. value.Style.Name
	end
	return tostring(value)
end

local function expect(label, actual, expected)
	local equal
	if typeof(expected) == "Font" or typeof(actual) == "Font" then
		equal = sameFont(actual, expected)
	elseif type(expected) == "number" and type(actual) == "number" then
		equal = math.abs(actual - expected) < 0.0001
	else
		equal = actual == expected
	end
	assert(equal, ("%s should be %s, it is %s"):format(label, describe(expected), describe(actual)))
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")

local assetsScript = ReplicatedFirst:FindFirstChild("MenuAssets")
assert(assetsScript, "ReplicatedFirst.MenuAssets missing")
local MenuAssets = require(assetsScript)
assert(type(MenuAssets.theme) == "function", "MenuAssets.theme() missing")
local T = MenuAssets.theme()
print(("menu_theme: active theme '%s'"):format(tostring(MenuAssets.THEME)))

-- The menu opens by itself once the loading screen has handed over; real input and screenshots wait for it to be gone.
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 30)
assert(menu, "MainMenu missing in PlayerGui")
waitFor(function()
	return playerGui:FindFirstChild("LoadingScreen") == nil
end, 10)
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")
local vignetteGui = playerGui:WaitForChild("MainMenuVignette", 10)
local faderGui = playerGui:WaitForChild("MainMenuFader", 10)
assert(vignetteGui and faderGui, "MainMenuVignette / MainMenuFader missing")

local loadingScript = ReplicatedFirst:FindFirstChild("LoadingScreen")
local loadingHook = loadingScript and loadingScript:FindFirstChild("TestHook")
assert(loadingHook and loadingHook:IsA("BindableFunction"), "ReplicatedFirst.LoadingScreen.TestHook missing")

-- What the loading screen built, from the snapshot it takes of its own gui when it builds it.
local function checkLoading(expected)
	local look = loadingHook:Invoke("look")
	assert(type(look) == "table", "LoadingScreen.TestHook should answer Invoke('look') with a table")
	expect("loading backdrop", look.backdrop, expected.loadingBackdrop)
	expect("loading vignette colour", look.vignette, expected.vignette)
	expect("loading vignette outer transparency", look.vignetteTransparency, expected.vignetteTransparency)
	expect("loading title colour", look.titleColor, expected.titleText)
	expect("loading title font", look.titleFont, expected.titleFont)
	expect("loading title stroke", look.titleStroke, expected.titleStroke)
	expect("loading title stroke thickness", look.titleStrokeThickness, expected.titleStrokeThickness)
	expect("loading title stroke transparency", look.titleStrokeTransparency, expected.titleStrokeTransparency)
	expect("loading spinner", look.spinner, expected.spinner)
	expect("loading tip colour", look.tipColor, expected.textMuted)
	expect("loading tip font", look.tipFont, expected.bodyFont)
	expect("loading hazard stripe", look.hazardStripe, expected.hazardStripe)
	local parts = playerGui:GetAttribute("LoadingParts")
	assert(type(parts) == "string", "LoadingParts missing")
	local hasStripe = false
	for name in string.gmatch(parts, "[^,]+") do
		if name == "HazardStripe" then
			hasStripe = true
		end
	end
	assert(hasStripe == expected.hazardStripe, ("LoadingParts '%s' should %s HazardStripe"):format(parts, expected.hazardStripe and "list" or "not list"))
	if expected.hazardStripe then
		expect("loading stripe yellow", look.stripeYellow, expected.hazardYellow)
		expect("loading stripe dark", look.stripeDark, expected.hazardDark)
	end
end

if CASE == "LF" then
	assert(loadingScript:GetAttribute("LoadingTestNoTheme") == true, "case LF needs the attribute LoadingTestNoTheme = true on ReplicatedFirst.LoadingScreen (set it in Edit first)")
	-- Factory, from the loader's own defaults, whatever the active theme is.
	local factory = MenuAssets.Themes.Factory
	assert(type(factory) == "table", "MenuAssets.Themes.Factory missing")
	local expected = {}
	for key, value in factory do
		expected[key] = value
	end
	assert(T.loadingBackdrop ~= factory.loadingBackdrop, "the active theme must differ from Factory for this case to prove anything")
	checkLoading(expected)
	print("menu_theme LF: the loading screen built the Factory look from its own defaults")
	return "PASS"
end
assert(CASE == "A", "unknown CASE " .. tostring(CASE))

-- Menu ------------------------------------------------------------------------------------------------------------------
local root, back = menu.Root, menu.Back
local vignette, fader = vignetteGui.Vignette, faderGui.Fader
local template = ReplicatedStorage:FindFirstChild("MainMenu")
assert(template, "ReplicatedStorage.MainMenu missing")

local title = root.Title
expect("Title.TextColor3", title.TextColor3, T.titleText)
expect("Title.FontFace", title.FontFace, T.titleFont)
local titleStroke = title:FindFirstChildOfClass("UIStroke")
assert(titleStroke, "the Title has no UIStroke")
expect("Title stroke colour", titleStroke.Color, T.titleStroke)
expect("Title stroke thickness", titleStroke.Thickness, T.titleStrokeThickness)
expect("Title stroke transparency", titleStroke.Transparency, T.titleStrokeTransparency)
-- The words are Studio's: the theme never touches them.
assert(title.Text == template.Root.Title.Text, "the Title's words should be the template's: " .. title.Text .. " vs " .. template.Root.Title.Text)

local buttons = { Play = root.Buttons.Play, Settings = root.Buttons.Settings, Credits = root.Buttons.Credits, Back = back }
for name, button in buttons do
	expect(name .. ".BackgroundColor3", button.BackgroundColor3, T.panel)
	expect(name .. ".TextColor3", button.TextColor3, T.text)
	expect(name .. ".FontFace", button.FontFace, T.bodyFont)
	expect(name .. ".Accent", button.Accent.BackgroundColor3, T.accent)
	local border = button:FindFirstChild("PanelBorder")
	if T.panelBorder then
		assert(border and border:IsA("UIStroke"), name .. " should have the border UIStroke PanelBorder")
		expect(name .. " border colour", border.Color, T.panelBorder)
		expect(name .. " border thickness", border.Thickness, 1)
	else
		assert(border == nil, name .. " should have no PanelBorder in a theme without panelBorder")
	end
	-- The hover outline (PopStroke) takes the theme's colour, before and after a hover.
	local pop = button:FindFirstChild("PopStroke")
	assert(pop and pop:IsA("UIStroke"), name .. " has no PopStroke")
	expect(name .. " PopStroke colour", pop.Color, T.hoverStroke)
end

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "MainMenuClient missing")
local ButtonEffects = require(clientScript:WaitForChild("ButtonEffects", 10))
ButtonEffects.setState(buttons.Play, "hover")
task.wait(0.3)
expect("Play PopStroke colour while hovered", buttons.Play.PopStroke.Color, T.hoverStroke)
expect("Play PopStroke transparency while hovered", buttons.Play.PopStroke.Transparency, 0)
ButtonEffects.setState(buttons.Play, "idle")
task.wait(0.3)

local edges = 0
for _, edge in vignette:GetChildren() do
	if edge:IsA("Frame") and edge:FindFirstChildOfClass("UIGradient") then
		edges += 1
		expect(edge.Name .. " edge colour", edge.BackgroundColor3, T.vignette)
		local keypoints = edge.UIGradient.Transparency.Keypoints
		expect(edge.Name .. " edge outer transparency", keypoints[1].Value, T.vignetteTransparency)
		expect(edge.Name .. " edge inner transparency", keypoints[#keypoints].Value, 1)
	end
end
assert(edges == 4, "expected the four Vignette edges, found " .. edges)

local stripe = vignette:FindFirstChild("HazardStripe")
if T.hazardStripe then
	assert(stripe, "the Vignette should hold the HazardStripe when hazardStripe is true")
	assert(stripe.AbsoluteSize.Y > 0 and stripe.AbsoluteSize.X >= vignette.AbsoluteSize.X - 1, "the stripe should run across the top of the screen")
	assert(stripe.AbsolutePosition.Y <= 1, "the stripe should sit at the top of the screen")
	local yellow, dark = false, false
	for _, item in stripe:GetDescendants() do
		if item:IsA("UIGradient") then
			for _, keypoint in item.Color.Keypoints do
				yellow = yellow or keypoint.Value == T.hazardYellow
				dark = dark or keypoint.Value == T.hazardDark
			end
		end
	end
	assert(yellow and dark, "the stripe should use the hazard yellow and the hazard dark")
	-- It follows Screen Effects like the rest of the Vignette frame, and never sinks a click.
	assert(stripe.Active == false, "the stripe must not be Active")
else
	assert(stripe == nil, "no HazardStripe expected when hazardStripe is false")
end

assert(fader.BackgroundColor3 == Color3.new(0, 0, 0), "the Fader must stay black in every theme, it is " .. tostring(fader.BackgroundColor3))

-- Loading ---------------------------------------------------------------------------------------------------------------
checkLoading(T)
print("menu_theme: menu and loading screen match the theme")

-- Settings board --------------------------------------------------------------------------------------------------------
local hook = clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook missing")
local MenuSettings = require(clientScript:WaitForChild("MenuSettings", 10))

local function ensureScene(name)
	if playerGui:GetAttribute("MenuScene") ~= name then
		local started = waitFor(function()
			return hook:Invoke("goTo", name)
		end, 2)
		assert(started, "goTo(" .. name .. ") did not start a transition")
	end
	local settled = waitFor(function()
		return playerGui:GetAttribute("MenuScene") == name and fader.BackgroundTransparency == 1
	end, 4)
	assert(settled, "scene " .. name .. " did not settle")
	task.wait(0.2)
end

ensureScene("Settings")
local gui = playerGui:FindFirstChild("SettingsBoardGui")
assert(gui and gui.Enabled, "SettingsBoardGui should be on the board in the Settings scene")
expect("board Backdrop", gui.Backdrop.BackgroundColor3, T.boardBackdrop)
local frameStroke = gui.Border:FindFirstChildOfClass("UIStroke")
assert(frameStroke, "the board frame has no UIStroke")
expect("board frame stroke", frameStroke.Color, T.boardAccent)
expect("board Header colour", gui.Header.TextColor3, T.boardHeader)
expect("board Header font", gui.Header.FontFace, T.titleFont)
expect("board Divider", gui.Divider.BackgroundColor3, T.boardAccent)
for _, rowName in { "MusicRow", "SfxRow", "SwayRow", "EffectsRow" } do
	local row = gui[rowName]
	expect(rowName .. " panel", row.BackgroundColor3, T.boardPanel)
	expect(rowName .. " accent bar", row.Accent.BackgroundColor3, T.boardAccent)
	expect(rowName .. " title colour", row.Title.TextColor3, T.text)
	expect(rowName .. " title font", row.Title.FontFace, T.bodyFont)
	local border = row:FindFirstChild("PanelBorder")
	if T.panelBorder then
		assert(border and border:IsA("UIStroke"), rowName .. " should have the border UIStroke PanelBorder")
		expect(rowName .. " border colour", border.Color, T.panelBorder)
	else
		assert(border == nil, rowName .. " should have no PanelBorder")
	end
end
for _, rowName in { "MusicRow", "SfxRow" } do
	local slider = gui[rowName].Slider
	expect(rowName .. " track", slider.BackgroundColor3, T.sliderTrack)
	expect(rowName .. " fill", slider.Fill.BackgroundColor3, T.boardAccent)
	expect(rowName .. " knob", slider.Knob.BackgroundColor3, T.sliderKnob)
end
local sway = gui.SwayRow.Toggle
assert(sway.Text == "ON", "Camera Sway should start ON")
expect("ON switch fill", sway.BackgroundColor3, T.switchOn)
expect("ON switch text", sway.TextColor3, T.switchOnText)
expect("ON switch font", sway.FontFace, T.labelFont)
local swayStroke = sway:FindFirstChildOfClass("UIStroke")
assert(swayStroke, "the switch has no UIStroke")
expect("switch outline", swayStroke.Color, T.boardAccent)
local swayWas = MenuSettings.get("CameraSway")
local offOk, offErr = pcall(function()
	MenuSettings.set("CameraSway", false)
	assert(waitFor(function()
		return sway.Text == "OFF"
	end, 1), "the switch should read OFF")
	expect("OFF switch fill", sway.BackgroundColor3, T.switchOff)
	expect("OFF switch text", sway.TextColor3, T.switchOffText)
	expect("OFF switch font", sway.FontFace, T.labelFont)
end)
MenuSettings.set("CameraSway", swayWas)
assert(offOk, offErr)
print("menu_theme: settings board matches the theme")
ensureScene("Menu")

-- Credits label ---------------------------------------------------------------------------------------------------------
local room = workspace:WaitForChild("CreditsRoom", 10)
assert(room, "workspace.CreditsRoom missing")
ensureScene("Credits")
local folder = waitFor(function()
	local avatars = room:FindFirstChild("CreditAvatars")
	return avatars and avatars:FindFirstChild("Developer") and avatars
end, 25)
assert(folder, "the Developer avatar did not appear in the Credits room within 25s")
task.wait(0.5)
local camera = workspace.CurrentCamera
local developer = folder.Developer
local CreditsRoom = require(clientScript:WaitForChild("CreditsRoom", 10))
local head = developer:FindFirstChild("Head")
assert(head, "the Developer has no Head")
local point = camera:WorldToViewportPoint(head.Position)
-- No yield between hoverAt and the checks: the real tracker follows the mouse each frame.
local hit = CreditsRoom.hoverAt(room, camera, Vector2.new(point.X, point.Y))
assert(hit == "Developer", "hoverAt on the Developer's head returned " .. tostring(hit))
local highlight = developer:FindFirstChild("CreditHighlight")
assert(highlight and highlight:IsA("Highlight"), "no CreditHighlight on the hovered Developer")
expect("CreditHighlight outline", highlight.OutlineColor, T.creditHighlight)
local nameGui = developer:FindFirstChild("CreditName")
assert(nameGui, "no CreditName label on the hovered Developer")
local label = nameGui:FindFirstChildWhichIsA("TextLabel", true)
assert(label, "the CreditName has no TextLabel")
expect("name label background", label.BackgroundColor3, T.nameLabelBg)
expect("name label text", label.TextColor3, T.nameLabelText)
expect("name label font", label.FontFace, T.labelFont)
local labelStroke = label:FindFirstChildOfClass("UIStroke")
assert(labelStroke, "the name label has no UIStroke")
expect("name label border", labelStroke.Color, T.nameLabelBorder)
CreditsRoom.hoverAt(room, camera, Vector2.new(2, 2))
print("menu_theme: credits label matches the theme")
ensureScene("Menu")

return "PASS"
