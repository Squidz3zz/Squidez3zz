-- MenuTheme: the menu's colours and fonts, read from ReplicatedFirst.MenuAssets (THEME and Themes) and painted on the menu.
--   get()                                     the active theme: MenuAssets.theme(), or the built-in Factory look below if
--                                             MenuAssets is missing or broken. Never throws, always has every key (panelBorder
--                                             aside: Factory has none), so a caller can read any key without checking.
--   applyToMenu(menu, vignetteGui, theme)     paints the CLONED MainMenu and MainMenuVignette before they are parented: the
--                                             Title (colour, font and outline, never its words), every button (fill, letters,
--                                             font, hover shading, accent bar, thin border) and BACK, the four Vignette edges and, when the
--                                             theme asks for it, the hazard stripe at the top of the screen. Safe to repeat,
--                                             skips whatever is missing (a renamed Title, a deleted button) and never throws:
--                                             a failing piece is warned about and the rest is still painted. The Fader is not
--                                             handed in, so it is never themed.
--   merge(result)                             lays a MenuAssets.theme() result over a copy of FACTORY: a value of another kind
--                                             than Factory's is ignored, a key FACTORY does not have is kept (so a key added
--                                             only in MenuAssets is not dropped). get() is merge(MenuAssets.theme()).
--   FACTORY                                   the built-in Factory look. It must stay equal to MenuAssets.Themes.Factory
--                                             (tests/menu_theme.edit.luau checks that).
-- Because the theme paints over the template's colours and fonts when the menu opens, editing those in Studio has no effect
-- while a theme is active. The Studio template (studio/build_main_menu_ui.luau) stays the Factory baseline.
-- The ButtonEffects hover outline, SettingsBoard, CreditsRoom and MenuCamera (the colour grade) read get() themselves;
-- LoadingScreen reads MenuAssets itself (it runs before this module has replicated) and keeps its own Factory defaults.
-- SettingsBoard and CreditsRoom require this module, so without it those two rooms stay empty; the menu, Play and
-- MenuCamera (which reads it in pcall) never depend on it.
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local MenuTheme = {}

local OSWALD = Font.fromEnum(Enum.Font.Oswald)
local AMBER = Color3.fromRGB(255, 150, 30)
local STEEL = Color3.fromRGB(38, 36, 34)

MenuTheme.FACTORY = {
	titleFont = Font.new(OSWALD.Family, Enum.FontWeight.Bold),
	bodyFont = OSWALD,
	labelFont = Font.new(OSWALD.Family, Enum.FontWeight.Bold),
	titleText = Color3.fromRGB(255, 255, 255),
	titleStroke = AMBER,
	titleStrokeTransparency = 0,
	titleStrokeThickness = 2,
	panel = STEEL,
	accent = AMBER,
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(220, 208, 190),
	hoverStroke = AMBER,
	buttonHoverShade = true,
	gradeTint = Color3.fromRGB(255, 235, 210),
	gradeSaturation = -0.15,
	vignette = Color3.fromRGB(12, 9, 6),
	vignetteTransparency = 0.15,
	hazardStripe = false,
	hazardYellow = Color3.fromRGB(242, 193, 46),
	hazardDark = Color3.fromRGB(29, 37, 41),
	loadingBackdrop = Color3.fromRGB(16, 14, 12),
	spinner = AMBER,
	boardBackdrop = Color3.fromRGB(22, 20, 18),
	boardPanel = STEEL,
	boardAccent = AMBER,
	boardHeader = AMBER,
	sliderTrack = Color3.fromRGB(62, 58, 54),
	sliderKnob = Color3.fromRGB(235, 230, 224),
	switchOn = AMBER,
	switchOff = Color3.fromRGB(58, 55, 52),
	switchOnText = Color3.fromRGB(22, 20, 18),
	switchOffText = Color3.fromRGB(165, 160, 154),
	creditHighlight = AMBER,
	nameLabelBg = STEEL,
	nameLabelText = Color3.fromRGB(255, 255, 255),
	nameLabelBorder = AMBER,
}

-- The hazard stripe: a thin bar across the top of the screen, a row of square tiles (each one UIGradient with hard colour
-- steps along its diagonal, so the diagonals of neighbouring tiles line up into one repeating diagonal stripe). Everything is
-- Scale: the bar is STRIPE_HEIGHT of the screen's height, and a tile is STRIPE_TILE bar heights on each side (RelativeYY), so
-- the stripes look the same on every screen shape; the bar clips the tiles that run past the right edge.
local STRIPE_HEIGHT = 0.015
local STRIPE_TILE = 4
-- Enough tiles for a screen up to STRIPE_TILES * STRIPE_TILE * STRIPE_HEIGHT = 4.2 times as wide as it is high.
local STRIPE_TILES = 70
-- The gradient has 4 yellow / dark periods along its length; across one tile that is 2 diagonal stripes of each colour.
local STRIPE_PERIODS = 4
local STEP = 0.0001

local warned = false

local function warnOnce(message)
	if not warned then
		warned = true
		warn(message)
	end
end

local function copy(source)
	local result = {}
	for key, value in source do
		result[key] = value
	end
	return result
end

function MenuTheme.merge(result)
	local theme = copy(MenuTheme.FACTORY)
	if type(result) ~= "table" then
		return theme
	end
	for key, value in result do
		-- A value of the right kind replaces Factory's (panelBorder has none, and is a colour); a key FACTORY does not have is
		-- kept, since MenuAssets.theme() has already checked it.
		local want = if key == "panelBorder" then "Color3" else typeof(MenuTheme.FACTORY[key])
		if want == "nil" or typeof(value) == want then
			theme[key] = value
		end
	end
	return theme
end

function MenuTheme.get()
	local module = ReplicatedFirst:FindFirstChild("MenuAssets")
	local ok, result = false, nil
	if module then
		ok, result = pcall(function()
			return require(module).theme()
		end)
	end
	if not ok or type(result) ~= "table" then
		warnOnce("MenuTheme: could not read MenuAssets.theme() (" .. tostring(result) .. "); using the built-in Factory look")
		return copy(MenuTheme.FACTORY)
	end
	return MenuTheme.merge(result)
end

-- A theme value if it is of the right kind, else nil (so a theme with a key missing paints nothing there).
local function colorOf(theme, key)
	local value = theme[key]
	return if typeof(value) == "Color3" then value else nil
end

local function fontOf(theme, key)
	local value = theme[key]
	return if typeof(value) == "Font" then value else nil
end

local function numberOf(theme, key)
	local value = theme[key]
	return if type(value) == "number" then value else nil
end

local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

-- The Title: colour, font and outline. Its words are Studio's, never touched here.
local function paintTitle(menu, theme)
	local root = menu:FindFirstChild("Root")
	local title = root and root:FindFirstChild("Title")
	if not (title and title:IsA("TextLabel")) then
		return
	end
	title.TextColor3 = colorOf(theme, "titleText") or title.TextColor3
	title.FontFace = fontOf(theme, "titleFont") or title.FontFace
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = colorOf(theme, "titleStroke") or stroke.Color
		stroke.Transparency = numberOf(theme, "titleStrokeTransparency") or stroke.Transparency
		stroke.Thickness = numberOf(theme, "titleStrokeThickness") or stroke.Thickness
	end
end

-- Every TextButton in the menu (PLAY, SETTINGS, CREDITS, BACK and any button added later): fill, letters, font, hover
-- shading, the accent bar and the thin border. The border is the UIStroke "PanelBorder": added when the theme has a panelBorder, removed when not.
local function paintButtons(menu, theme)
	local panel = colorOf(theme, "panel")
	local text = colorOf(theme, "text")
	local bodyFont = fontOf(theme, "bodyFont")
	local accent = colorOf(theme, "accent")
	local borderColor = colorOf(theme, "panelBorder")
	-- Roblox's own hover darkening (AutoButtonColor): on for Factory (the template already has it), off for light panels.
	local hoverShade = theme.buttonHoverShade
	for _, button in menu:GetDescendants() do
		if button:IsA("TextButton") then
			if type(hoverShade) == "boolean" then
				button.AutoButtonColor = hoverShade
			end
			button.BackgroundColor3 = panel or button.BackgroundColor3
			button.TextColor3 = text or button.TextColor3
			button.FontFace = bodyFont or button.FontFace
			local bar = button:FindFirstChild("Accent")
			if bar and bar:IsA("GuiObject") then
				bar.BackgroundColor3 = accent or bar.BackgroundColor3
			end
			local border = button:FindFirstChild("PanelBorder")
			if borderColor then
				if not (border and border:IsA("UIStroke")) then
					border = create("UIStroke", { Name = "PanelBorder" }, button)
				end
				border.Color = borderColor
				border.Thickness = 1
				border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			elseif border then
				border:Destroy()
			end
		end
	end
end

-- The yellow / dark ColorSequence of one tile: STRIPE_PERIODS periods, each half yellow and half dark, with hard steps.
local function stripeColors(yellow, dark)
	local points = {}
	local length = 1 / STRIPE_PERIODS
	for period = 0, STRIPE_PERIODS - 1 do
		local start = period * length
		table.insert(points, ColorSequenceKeypoint.new(start, yellow))
		table.insert(points, ColorSequenceKeypoint.new(start + length / 2 - STEP, yellow))
		table.insert(points, ColorSequenceKeypoint.new(start + length / 2, dark))
		table.insert(points, ColorSequenceKeypoint.new(start + length - STEP, dark))
	end
	table.insert(points, ColorSequenceKeypoint.new(1, dark))
	return ColorSequence.new(points)
end

-- Builds the stripe bar (not parented). A CanvasGroup, so it clips its tiles and can be faded as one piece.
local function buildStripe(yellow, dark)
	local bar = create("CanvasGroup", {
		Name = "HazardStripe",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, STRIPE_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 2,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 0),
	}, bar)
	local colors = stripeColors(yellow, dark)
	for index = 1, STRIPE_TILES do
		local tile = create("Frame", {
			Name = "Tile",
			LayoutOrder = index,
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Size = UDim2.fromScale(STRIPE_TILE, STRIPE_TILE),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Active = false,
		}, bar)
		create("UIGradient", { Rotation = 45, Color = colors }, tile)
	end
	return bar
end

-- The four screen edges (colour and outer transparency; they still fade to invisible on the inside) and the stripe.
local function paintVignette(vignetteGui, theme)
	local vignette = vignetteGui and vignetteGui:FindFirstChild("Vignette")
	if not vignette then
		return
	end
	local color = colorOf(theme, "vignette")
	local outer = numberOf(theme, "vignetteTransparency")
	for _, edge in vignette:GetChildren() do
		local gradient = edge:IsA("Frame") and edge:FindFirstChildOfClass("UIGradient")
		if gradient then
			edge.BackgroundColor3 = color or edge.BackgroundColor3
			if outer then
				local keypoints = {}
				for _, keypoint in gradient.Transparency.Keypoints do
					local value = if keypoint.Time == 0 then math.clamp(outer, 0, 1) else keypoint.Value
					table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, value))
				end
				gradient.Transparency = NumberSequence.new(keypoints)
			end
		end
	end

	-- Rebuilt on every apply, so a repeat leaves exactly one (or none when the theme has no stripe).
	local old = vignette:FindFirstChild("HazardStripe")
	if old then
		old:Destroy()
	end
	local yellow, dark = colorOf(theme, "hazardYellow"), colorOf(theme, "hazardDark")
	if theme.hazardStripe == true and yellow and dark then
		buildStripe(yellow, dark).Parent = vignette
	end
end

-- Runs one piece of painting; a failure is warned about and does not stop the next piece.
local function guarded(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("MenuTheme: could not paint the " .. label .. ": " .. tostring(err))
	end
end

function MenuTheme.applyToMenu(menu, vignetteGui, theme)
	if type(theme) ~= "table" then
		return
	end
	if typeof(menu) == "Instance" then
		guarded("Title", paintTitle, menu, theme)
		guarded("buttons", paintButtons, menu, theme)
	end
	if typeof(vignetteGui) == "Instance" then
		guarded("Vignette", paintVignette, vignetteGui, theme)
	end
end

return MenuTheme
