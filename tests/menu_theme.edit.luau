-- Run in the Edit datamodel via execute_luau (no playtest needed).
-- Unit tests for the menu theme, on clones, so the copy tested is the one in Studio now and changing THEME never touches the
-- real modules:
--   ReplicatedFirst.MenuAssets        THEME, Themes (Factory, SterileBright) and theme()
--   MainMenuClient.MenuTheme          get() and applyToMenu(menu, vignetteGui, theme)
-- Cases:
--   1  Factory is today's look: amber, the steel panel, the vignette, the loading backdrop and Oswald.
--   2  SterileBright holds the approved values, and every preset only uses known keys.
--   3  an unknown THEME (or none at all) falls back to Factory, with one warning.
--   4  a preset that misses keys falls back to Factory key by key, and a value of the wrong type is ignored.
--   5  theme() hands out a fresh table every time.
--   6  MenuTheme's built-in Factory fallback equals MenuAssets.Themes.Factory, and get() equals theme().
--   7  applyToMenu recolours clones of the real ScreenGuis (never the Title's words), is safe to repeat, skips what is missing,
--      sets the buttons' hover shading and builds the hazard stripe only when the theme asks for it.
--   8  with Themes.Factory missing, the chosen preset is taken as it is, with exactly one warning (not one per key).
local LogService = game:GetService("LogService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
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

local function same(a, b)
	if typeof(a) == "Font" or typeof(b) == "Font" then
		return sameFont(a, b)
	end
	return a == b
end

local function expect(label, actual, expected)
	assert(same(actual, expected), ("%s should be %s, it is %s"):format(label, describe(expected), describe(actual)))
end

-- Every key a theme has, with the type its value must have. panelBorder is the one that may be missing (Factory has no border).
local TYPES = {
	titleFont = "Font", bodyFont = "Font", labelFont = "Font",
	titleText = "Color3", titleStroke = "Color3", titleStrokeTransparency = "number", titleStrokeThickness = "number",
	panel = "Color3", accent = "Color3", text = "Color3", textMuted = "Color3",
	hoverStroke = "Color3", buttonHoverShade = "boolean", gradeTint = "Color3", gradeSaturation = "number",
	vignette = "Color3", vignetteTransparency = "number", hazardStripe = "boolean", hazardYellow = "Color3", hazardDark = "Color3",
	loadingBackdrop = "Color3", spinner = "Color3",
	boardBackdrop = "Color3", boardPanel = "Color3", boardAccent = "Color3", boardHeader = "Color3",
	sliderTrack = "Color3", sliderKnob = "Color3", switchOn = "Color3", switchOff = "Color3",
	switchOnText = "Color3", switchOffText = "Color3",
	creditHighlight = "Color3", nameLabelBg = "Color3", nameLabelText = "Color3", nameLabelBorder = "Color3",
}
local OPTIONAL = { panelBorder = "Color3" }

local assetsScript = ReplicatedFirst:FindFirstChild("MenuAssets")
assert(assetsScript and assetsScript:IsA("ModuleScript"), "ReplicatedFirst.MenuAssets (ModuleScript) missing")
local menuClientScript = StarterPlayer.StarterPlayerScripts:FindFirstChild("MainMenuClient")
assert(menuClientScript, "StarterPlayerScripts.MainMenuClient missing")
local themeScript = menuClientScript:FindFirstChild("MenuTheme")
assert(themeScript and themeScript:IsA("ModuleScript"), "MainMenuClient.MenuTheme (ModuleScript) missing")

-- A fresh copy of MenuAssets each time, so a test that edits THEME or Themes leaves nothing behind.
local function freshAssets()
	local assets = require(assetsScript:Clone())
	assert(type(assets.THEME) == "string", "MenuAssets.THEME (a string) missing")
	assert(type(assets.Themes) == "table", "MenuAssets.Themes (a table) missing")
	assert(type(assets.Themes.Factory) == "table", "MenuAssets.Themes.Factory missing")
	assert(type(assets.Themes.SterileBright) == "table", "MenuAssets.Themes.SterileBright missing")
	assert(type(assets.theme) == "function", "MenuAssets.theme() missing")
	return assets
end

-- Runs fn and returns its result plus the warnings it logged.
local function withWarnings(fn)
	local warnings = {}
	local connection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning then
			table.insert(warnings, message)
		end
	end)
	local ok, result = pcall(fn)
	task.wait(0.2)
	connection:Disconnect()
	assert(ok, result)
	return result, warnings
end

local function checkComplete(theme, label)
	for key, typeName in TYPES do
		assert(typeof(theme[key]) == typeName, ("%s.%s should be a %s, it is %s"):format(label, key, typeName, typeof(theme[key])))
	end
	for key, typeName in OPTIONAL do
		assert(theme[key] == nil or typeof(theme[key]) == typeName, ("%s.%s should be a %s or nil"):format(label, key, typeName))
	end
end

-- 1  Factory is today's look ------------------------------------------------------------------------------------------
do
	local assets = freshAssets()
	assets.THEME = "Factory"
	local theme = assets.theme()
	checkComplete(theme, "Factory")
	local amber = rgb(255, 150, 30)
	local oswald = Font.fromEnum(Enum.Font.Oswald)
	expect("Factory.accent", theme.accent, amber)
	expect("Factory.hoverStroke", theme.hoverStroke, amber)
	expect("Factory.titleStroke", theme.titleStroke, amber)
	expect("Factory.spinner", theme.spinner, amber)
	expect("Factory.boardAccent", theme.boardAccent, amber)
	expect("Factory.boardHeader", theme.boardHeader, amber)
	expect("Factory.switchOn", theme.switchOn, amber)
	expect("Factory.creditHighlight", theme.creditHighlight, amber)
	expect("Factory.nameLabelBorder", theme.nameLabelBorder, amber)
	expect("Factory.panel", theme.panel, rgb(38, 36, 34))
	expect("Factory.boardPanel", theme.boardPanel, rgb(38, 36, 34))
	expect("Factory.nameLabelBg", theme.nameLabelBg, rgb(38, 36, 34))
	expect("Factory.boardBackdrop", theme.boardBackdrop, rgb(22, 20, 18))
	expect("Factory.sliderTrack", theme.sliderTrack, rgb(62, 58, 54))
	expect("Factory.sliderKnob", theme.sliderKnob, rgb(235, 230, 224))
	expect("Factory.switchOff", theme.switchOff, rgb(58, 55, 52))
	expect("Factory.switchOffText", theme.switchOffText, rgb(165, 160, 154))
	expect("Factory.switchOnText", theme.switchOnText, rgb(22, 20, 18))
	expect("Factory.text", theme.text, Color3.new(1, 1, 1))
	expect("Factory.titleText", theme.titleText, Color3.new(1, 1, 1))
	expect("Factory.nameLabelText", theme.nameLabelText, Color3.new(1, 1, 1))
	expect("Factory.textMuted", theme.textMuted, rgb(220, 208, 190))
	expect("Factory.vignette", theme.vignette, rgb(12, 9, 6))
	expect("Factory.vignetteTransparency", theme.vignetteTransparency, 0.15)
	expect("Factory.loadingBackdrop", theme.loadingBackdrop, rgb(16, 14, 12))
	expect("Factory.titleStrokeThickness", theme.titleStrokeThickness, 2)
	expect("Factory.titleStrokeTransparency", theme.titleStrokeTransparency, 0)
	expect("Factory.hazardStripe", theme.hazardStripe, false)
	expect("Factory.buttonHoverShade", theme.buttonHoverShade, true)
	expect("Factory.gradeTint", theme.gradeTint, rgb(255, 235, 210))
	expect("Factory.gradeSaturation", theme.gradeSaturation, -0.15)
	assert(theme.panelBorder == nil, "Factory has no panel border")
	expect("Factory.titleFont", theme.titleFont, Font.new(oswald.Family, Enum.FontWeight.Bold))
	expect("Factory.labelFont", theme.labelFont, Font.new(oswald.Family, Enum.FontWeight.Bold))
	expect("Factory.bodyFont", theme.bodyFont, oswald)
	assert(string.find(theme.bodyFont.Family, "Oswald", 1, true), "Factory.bodyFont should be Oswald")
end

-- 2  SterileBright holds the approved values -------------------------------------------------------------------------
do
	local assets = freshAssets()
	assets.THEME = "SterileBright"
	local theme = assets.theme()
	checkComplete(theme, "SterileBright")
	local teal = rgb(19, 184, 166)
	expect("SterileBright.titleText", theme.titleText, rgb(52, 73, 90))
	expect("SterileBright.titleStroke", theme.titleStroke, rgb(255, 255, 255))
	assert(theme.titleStrokeThickness > 0 and theme.titleStrokeThickness <= 2, "the Sterile title stroke should be thin")
	expect("SterileBright.text", theme.text, rgb(75, 101, 119))
	expect("SterileBright.textMuted", theme.textMuted, rgb(110, 130, 145))
	expect("SterileBright.panel", theme.panel, rgb(255, 255, 255))
	expect("SterileBright.boardPanel", theme.boardPanel, rgb(255, 255, 255))
	expect("SterileBright.nameLabelBg", theme.nameLabelBg, rgb(255, 255, 255))
	expect("SterileBright.panelBorder", theme.panelBorder, rgb(185, 201, 205))
	for _, key in { "accent", "hoverStroke", "spinner", "boardAccent", "switchOn", "creditHighlight", "nameLabelBorder" } do
		expect("SterileBright." .. key, theme[key], teal)
	end
	expect("SterileBright.vignette", theme.vignette, rgb(205, 218, 222))
	assert(math.abs(theme.vignetteTransparency - 0.35) < 0.0001, "SterileBright.vignetteTransparency should be 0.35")
	expect("SterileBright.hazardStripe", theme.hazardStripe, true)
	expect("SterileBright.hazardYellow", theme.hazardYellow, rgb(242, 193, 46))
	expect("SterileBright.hazardDark", theme.hazardDark, rgb(29, 37, 41))
	expect("SterileBright.buttonHoverShade", theme.buttonHoverShade, false)
	expect("SterileBright.gradeTint", theme.gradeTint, rgb(240, 246, 252))
	assert(theme.gradeSaturation <= 0 and theme.gradeSaturation > -0.15, "the Sterile grade should be less grey than Factory's")
	expect("SterileBright.loadingBackdrop", theme.loadingBackdrop, rgb(233, 239, 241))
	expect("SterileBright.titleFont", theme.titleFont, Font.new("rbxasset://fonts/families/Michroma.json"))
	expect(
		"SterileBright.bodyFont",
		theme.bodyFont,
		Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.SemiBold)
	)
	expect("SterileBright.switchOff", theme.switchOff, rgb(225, 232, 234))
	expect("SterileBright.switchOffText", theme.switchOffText, rgb(75, 101, 119))
	expect("SterileBright.switchOnText", theme.switchOnText, rgb(255, 255, 255))

	-- A preset only uses keys the menu knows, so a typo such as "acent" cannot go unnoticed.
	for _, name in { "Factory", "SterileBright" } do
		for key in assets.Themes[name] do
			assert(TYPES[key] ~= nil or OPTIONAL[key] ~= nil, ("%s has an unknown key '%s'"):format(name, tostring(key)))
		end
	end
	-- And Factory, the base every other preset falls back to, defines all of them (panelBorder aside).
	for key in TYPES do
		assert(assets.Themes.Factory[key] ~= nil, "Factory is missing the key " .. key)
	end
end

-- 3  an unknown or missing THEME falls back to Factory, with one warning -------------------------------------------------
do
	local assets = freshAssets()
	assets.THEME = "Factory"
	local factory = assets.theme()
	assets.THEME = "NoSuchTheme"
	local theme, warnings = withWarnings(function()
		local first = assets.theme()
		assets.theme()
		assets.theme()
		return first
	end)
	for key in TYPES do
		expect("unknown theme: " .. key, theme[key], factory[key])
	end
	assert(theme.panelBorder == nil, "unknown theme: no panel border like Factory")
	local mentioning = 0
	for _, message in warnings do
		if string.find(message, "NoSuchTheme", 1, true) then
			mentioning += 1
		end
	end
	assert(mentioning == 1, "an unknown THEME should warn once, it warned " .. mentioning .. " times: " .. table.concat(warnings, " | "))

	for _, notAName in { false, 5, {} } do
		local other = freshAssets()
		other.THEME = notAName
		local fallback = withWarnings(function()
			return other.theme()
		end)
		expect("THEME = " .. tostring(notAName) .. ": accent", fallback.accent, factory.accent)
	end
end

-- 4  missing keys fall back one by one, and a wrong type is ignored ------------------------------------------------------
do
	local assets = freshAssets()
	assets.THEME = "Factory"
	local factory = assets.theme()
	local custom = rgb(1, 2, 3)
	assets.Themes.Partial = { accent = custom, panelBorder = rgb(4, 5, 6) }
	assets.THEME = "Partial"
	local theme = assets.theme()
	expect("Partial.accent", theme.accent, custom)
	expect("Partial.panelBorder", theme.panelBorder, rgb(4, 5, 6))
	for key in TYPES do
		if key ~= "accent" then
			expect("Partial." .. key .. " falls back to Factory", theme[key], factory[key])
		end
	end

	assets.Themes.Broken = { accent = "red", vignetteTransparency = "dark", hazardStripe = 1, bodyFont = Color3.new(), panelBorder = "grey", text = rgb(7, 8, 9) }
	assets.THEME = "Broken"
	local broken = withWarnings(function()
		return assets.theme()
	end)
	expect("Broken.accent (a string) falls back", broken.accent, factory.accent)
	expect("Broken.vignetteTransparency (a string) falls back", broken.vignetteTransparency, factory.vignetteTransparency)
	expect("Broken.hazardStripe (a number) falls back", broken.hazardStripe, factory.hazardStripe)
	expect("Broken.bodyFont (a Color3) falls back", broken.bodyFont, factory.bodyFont)
	assert(broken.panelBorder == nil, "Broken.panelBorder (a string) is ignored: no border")
	expect("Broken.text (a good value) is kept", broken.text, rgb(7, 8, 9))
end

-- 5  theme() hands out a fresh table every time --------------------------------------------------------------------------
do
	local assets = freshAssets()
	local first = assets.theme()
	first.accent = rgb(9, 9, 9)
	first.extra = true
	local second = assets.theme()
	assert(second.accent ~= rgb(9, 9, 9) and second.extra == nil, "editing a table from theme() must not change the next one")
end

-- 6  MenuTheme's built-in fallback is Factory, and get() is theme() ------------------------------------------------------
local MenuTheme = require(themeScript:Clone())
assert(type(MenuTheme.get) == "function", "MenuTheme.get missing")
assert(type(MenuTheme.applyToMenu) == "function", "MenuTheme.applyToMenu missing")
assert(type(MenuTheme.FACTORY) == "table", "MenuTheme.FACTORY (the built-in fallback) missing")
do
	local assets = freshAssets()
	for key in TYPES do
		expect("MenuTheme.FACTORY." .. key, MenuTheme.FACTORY[key], assets.Themes.Factory[key])
	end
	assert(MenuTheme.FACTORY.panelBorder == assets.Themes.Factory.panelBorder, "MenuTheme.FACTORY.panelBorder should match Factory")
	-- get() requires the real MenuAssets and is merge() of its theme(). Compare it with exactly that, from the same module (not
	-- a clone): a require cache that outlived an edit in this Studio session would otherwise make the two differ without
	-- anything being wrong.
	local live = MenuTheme.merge(require(assetsScript).theme())
	local viaMenuTheme = MenuTheme.get()
	for key in TYPES do
		expect("MenuTheme.get()." .. key, viaMenuTheme[key], live[key])
	end

	-- merge keeps a key MenuAssets has and FACTORY lacks (a new key added only there is not dropped), ignores a value of the
	-- wrong kind, and leaves everything else as Factory.
	assert(type(MenuTheme.merge) == "function", "MenuTheme.merge missing")
	local merged = MenuTheme.merge({ brandNewKey = 42, accent = "red", text = rgb(7, 8, 9), panelBorder = rgb(4, 5, 6) })
	assert(merged.brandNewKey == 42, "merge should keep a key FACTORY does not have")
	expect("merge: a wrong-typed accent is ignored", merged.accent, MenuTheme.FACTORY.accent)
	expect("merge: a good value is kept", merged.text, rgb(7, 8, 9))
	expect("merge: panelBorder is accepted", merged.panelBorder, rgb(4, 5, 6))
	expect("merge: untouched keys stay Factory", merged.panel, MenuTheme.FACTORY.panel)
	local fromNothing = MenuTheme.merge(nil)
	expect("merge(nil) is the Factory copy", fromNothing.accent, MenuTheme.FACTORY.accent)
	assert(fromNothing ~= MenuTheme.FACTORY, "merge must return a copy, not FACTORY itself")
end

-- 7  applyToMenu on clones of the real ScreenGuis --------------------------------------------------------------------
local menuTemplate = ReplicatedStorage:FindFirstChild("MainMenu")
local vignetteTemplate = ReplicatedStorage:FindFirstChild("MainMenuVignette")
assert(menuTemplate and vignetteTemplate, "ReplicatedStorage.MainMenu / MainMenuVignette missing")
local sterile = freshAssets()
sterile.THEME = "SterileBright"
local sterileTheme = sterile.theme()
local factoryAssets = freshAssets()
factoryAssets.THEME = "Factory"
local factoryTheme = factoryAssets.theme()

local function buttonsOf(menu)
	local list = {}
	for _, item in menu:GetDescendants() do
		if item:IsA("TextButton") then
			table.insert(list, item)
		end
	end
	assert(#list == 4, "the menu should have 4 buttons (Play, Settings, Credits, Back), found " .. #list)
	return list
end

local function countNamed(parent, name)
	local count = 0
	for _, item in parent:GetDescendants() do
		if item.Name == name then
			count += 1
		end
	end
	return count
end

do
	local menu, vignetteGui = menuTemplate:Clone(), vignetteTemplate:Clone()
	local originalText = menu.Root.Title.Text
	local before = {}
	for _, button in buttonsOf(menu) do
		before[button] = button.BackgroundColor3
	end
	MenuTheme.applyToMenu(menu, vignetteGui, sterileTheme)

	local title = menu.Root.Title
	expect("Title.TextColor3", title.TextColor3, sterileTheme.titleText)
	expect("Title.FontFace", title.FontFace, sterileTheme.titleFont)
	local stroke = title:FindFirstChildOfClass("UIStroke")
	assert(stroke, "the Title lost its UIStroke")
	expect("Title stroke colour", stroke.Color, sterileTheme.titleStroke)
	expect("Title stroke thickness", stroke.Thickness, sterileTheme.titleStrokeThickness)
	expect("Title stroke transparency", stroke.Transparency, sterileTheme.titleStrokeTransparency)
	assert(title.Text == originalText, "the theme must never change the Title's words, it changed them to " .. title.Text)

	for _, button in buttonsOf(menu) do
		expect(button.Name .. ".BackgroundColor3", button.BackgroundColor3, sterileTheme.panel)
		expect(button.Name .. ".TextColor3", button.TextColor3, sterileTheme.text)
		expect(button.Name .. ".FontFace", button.FontFace, sterileTheme.bodyFont)
		expect(button.Name .. ".Accent", button.Accent.BackgroundColor3, sterileTheme.accent)
		local border = button:FindFirstChild("PanelBorder")
		assert(border and border:IsA("UIStroke"), button.Name .. " should have a UIStroke named PanelBorder")
		expect(button.Name .. " border colour", border.Color, sterileTheme.panelBorder)
		assert(border.Thickness == 1 and border.ApplyStrokeMode == Enum.ApplyStrokeMode.Border, button.Name .. " border should be 1px, Border mode")
		assert(button.Text == string.upper(button.Text), button.Name .. " text should stay as it was")
		assert(button.AutoButtonColor == sterileTheme.buttonHoverShade and button.AutoButtonColor == false, button.Name .. ".AutoButtonColor should follow buttonHoverShade (false)")
	end

	local vignette = vignetteGui.Vignette
	local edges = 0
	for _, edge in vignette:GetChildren() do
		if edge:IsA("Frame") and edge:FindFirstChildOfClass("UIGradient") then
			edges += 1
			expect(edge.Name .. " edge colour", edge.BackgroundColor3, sterileTheme.vignette)
			local keypoints = edge.UIGradient.Transparency.Keypoints
			assert(math.abs(keypoints[1].Value - sterileTheme.vignetteTransparency) < 0.0001, edge.Name .. " outer transparency should be " .. sterileTheme.vignetteTransparency)
			assert(keypoints[#keypoints].Value == 1 and keypoints[#keypoints].Time == 1, edge.Name .. " should still fade to 1 on the inside")
		end
	end
	assert(edges == 4, "the four Vignette edges should be recoloured, found " .. edges)

	-- The hazard stripe: one, in the Vignette frame, Scale only, yellow and near-black.
	local stripe = vignette:FindFirstChild("HazardStripe")
	assert(stripe and stripe:IsA("GuiObject"), "Vignette.HazardStripe should exist when hazardStripe is true")
	assert(countNamed(vignetteGui, "HazardStripe") == 1, "exactly one HazardStripe")
	assert(stripe.Active == false, "the stripe must never sink a click")
	assert(stripe.Position.Y.Offset == 0 and stripe.Size.Y.Offset == 0 and stripe.Size.Y.Scale > 0 and stripe.Size.Y.Scale <= 0.04, "the stripe is thin and Scale only")
	assert(stripe.Position.Y.Scale == 0 and stripe.Size.X.Scale == 1, "the stripe runs across the top of the screen")
	local yellow, dark, other = 0, 0, 0
	for _, item in stripe:GetDescendants() do
		if item:IsA("GuiObject") then
			assert(
				item.Size.X.Offset == 0 and item.Size.Y.Offset == 0 and item.Position.X.Offset == 0 and item.Position.Y.Offset == 0,
				item:GetFullName() .. " uses pixels"
			)
		end
		if item:IsA("UIGradient") then
			for _, keypoint in item.Color.Keypoints do
				if keypoint.Value == sterileTheme.hazardYellow then
					yellow += 1
				elseif keypoint.Value == sterileTheme.hazardDark then
					dark += 1
				else
					other += 1
				end
			end
		end
	end
	assert(yellow > 0 and dark > 0 and other == 0, ("the stripe should use only the hazard yellow and dark (yellow %d, dark %d, other %d)"):format(yellow, dark, other))

	-- Applying twice changes nothing: still one stripe and one border per button.
	MenuTheme.applyToMenu(menu, vignetteGui, sterileTheme)
	assert(countNamed(vignetteGui, "HazardStripe") == 1, "a second apply must not add a second stripe")
	assert(countNamed(menu, "PanelBorder") == 4, "a second apply must not add a second border per button")

	-- The same clone themed Factory afterwards: no border, no stripe left behind, the Factory colours back.
	MenuTheme.applyToMenu(menu, vignetteGui, factoryTheme)
	assert(countNamed(vignetteGui, "HazardStripe") == 0, "a Factory apply should remove the stripe")
	assert(countNamed(menu, "PanelBorder") == 0, "a Factory apply should remove the borders")
	for _, button in buttonsOf(menu) do
		expect(button.Name .. " Factory colour", button.BackgroundColor3, before[button])
		assert(button.AutoButtonColor == true, button.Name .. ".AutoButtonColor should be back to true under Factory")
	end
	menu:Destroy()
	vignetteGui:Destroy()
end

-- Factory over the untouched template changes nothing it can see, and builds no stripe or border.
do
	local menu, vignetteGui = menuTemplate:Clone(), vignetteTemplate:Clone()
	MenuTheme.applyToMenu(menu, vignetteGui, factoryTheme)
	expect("Factory Title.TextColor3", menu.Root.Title.TextColor3, menuTemplate.Root.Title.TextColor3)
	expect("Factory Title.FontFace", menu.Root.Title.FontFace, menuTemplate.Root.Title.FontFace)
	expect("Factory Play.BackgroundColor3", menu.Root.Buttons.Play.BackgroundColor3, menuTemplate.Root.Buttons.Play.BackgroundColor3)
	expect("Factory Play.FontFace", menu.Root.Buttons.Play.FontFace, menuTemplate.Root.Buttons.Play.FontFace)
	expect("Factory Play Accent", menu.Root.Buttons.Play.Accent.BackgroundColor3, menuTemplate.Root.Buttons.Play.Accent.BackgroundColor3)
	expect("Factory Back.TextColor3", menu.Back.TextColor3, menuTemplate.Back.TextColor3)
	for _, button in buttonsOf(menu) do
		assert(button.AutoButtonColor == true, button.Name .. ".AutoButtonColor should stay true under Factory (the template's value)")
	end
	for _, edge in vignetteGui.Vignette:GetChildren() do
		if edge:IsA("Frame") then
			expect("Factory " .. edge.Name .. " edge", edge.BackgroundColor3, vignetteTemplate.Vignette[edge.Name].BackgroundColor3)
			local want = vignetteTemplate.Vignette[edge.Name].UIGradient.Transparency.Keypoints[1].Value
			assert(math.abs(edge.UIGradient.Transparency.Keypoints[1].Value - want) < 0.0001, "Factory " .. edge.Name .. " transparency should match the template")
		end
	end
	assert(countNamed(vignetteGui, "HazardStripe") == 0 and countNamed(menu, "PanelBorder") == 0, "Factory builds no stripe and no border")
	menu:Destroy()
	vignetteGui:Destroy()
end

-- Missing pieces are skipped, and the rest is still themed. A theme with no keys changes nothing.
do
	local menu, vignetteGui = menuTemplate:Clone(), vignetteTemplate:Clone()
	menu.Root.Title:Destroy()
	menu.Root.Buttons.Settings:Destroy()
	vignetteGui.Vignette.Left:Destroy()
	local ok, err = pcall(MenuTheme.applyToMenu, menu, vignetteGui, sterileTheme)
	assert(ok, "applyToMenu should skip what is missing, it threw: " .. tostring(err))
	expect("Play still themed", menu.Root.Buttons.Play.BackgroundColor3, sterileTheme.panel)
	expect("Back still themed", menu.Back.BackgroundColor3, sterileTheme.panel)
	expect("Top edge still themed", vignetteGui.Vignette.Top.BackgroundColor3, sterileTheme.vignette)

	local plain = menuTemplate:Clone()
	local plainVignette = vignetteTemplate:Clone()
	local okEmpty, errEmpty = pcall(MenuTheme.applyToMenu, plain, plainVignette, {})
	assert(okEmpty, "applyToMenu with an empty theme should do nothing, it threw: " .. tostring(errEmpty))
	expect("empty theme leaves the Title colour", plain.Root.Title.TextColor3, menuTemplate.Root.Title.TextColor3)
	expect("empty theme leaves the Play colour", plain.Root.Buttons.Play.BackgroundColor3, menuTemplate.Root.Buttons.Play.BackgroundColor3)
	assert(countNamed(plainVignette, "HazardStripe") == 0 and countNamed(plain, "PanelBorder") == 0, "an empty theme builds nothing")
	for _, gui in { menu, vignetteGui, plain, plainVignette } do
		gui:Destroy()
	end
end

-- 8  Themes.Factory renamed or deleted: the chosen preset is still used, with one warning ---------------------------------------
do
	local intact = freshAssets()
	intact.THEME = "SterileBright"
	local wanted = intact.theme()

	local assets = freshAssets()
	assets.Themes.Factory = nil
	assets.THEME = "SterileBright"
	local theme, warnings = withWarnings(function()
		local first = assets.theme()
		assets.theme()
		return first
	end)
	for key in TYPES do
		expect("no Factory: " .. key, theme[key], wanted[key])
	end
	expect("no Factory: panelBorder", theme.panelBorder, wanted.panelBorder)
	assert(#warnings == 1, "a missing Factory should warn exactly once (not once per key), it warned " .. #warnings .. " times: " .. table.concat(warnings, " | "))
	assert(string.find(warnings[1], "Factory", 1, true), "the warning should name Factory: " .. warnings[1])

	-- MenuTheme fills what a preset leaves out from its built-in Factory copy, so a half-written preset still has every key.
	local renamed = freshAssets()
	renamed.Themes.TheOldFactory = renamed.Themes.Factory
	renamed.Themes.Factory = nil
	renamed.Themes.Half = { accent = rgb(1, 2, 3) }
	renamed.THEME = "Half"
	local half = withWarnings(function()
		return renamed.theme()
	end)
	expect("no Factory, half preset: accent", half.accent, rgb(1, 2, 3))
	local merged = MenuTheme.merge(half)
	for key in TYPES do
		assert(merged[key] ~= nil, "no Factory, half preset: MenuTheme.merge should supply " .. key)
	end
end

-- The Fader is never themed: applyToMenu is only given the menu and the vignette gui.
do
	local fader = ReplicatedStorage:FindFirstChild("MainMenuFader")
	assert(fader and fader.Fader.BackgroundColor3 == Color3.new(0, 0, 0), "the Fader template must stay black")
end

return "PASS"
