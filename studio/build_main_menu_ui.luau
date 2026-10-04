-- One-shot build script: run in the Edit datamodel via execute_luau.
-- Moves StarterGui.ScreenGui to ReplicatedStorage.MainMenu and builds the static main-menu tree.
-- After it runs, Studio is the source of truth for the UI; this script refuses to run a second time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

if ReplicatedStorage:FindFirstChild("MainMenu") then
	error("MainMenu already exists")
end

-- Style: dark panels, white text, rounded corners. All sizes/positions use Scale only
-- (UICorner radius is the one exception allowed by design).
local PANEL_COLOR = Color3.fromRGB(25, 25, 35)
local PANEL_TRANSPARENCY = 0.15
local TRACK_COLOR = Color3.fromRGB(60, 60, 80)
local ACCENT_COLOR = Color3.fromRGB(90, 160, 255)
local WHITE = Color3.new(1, 1, 1)
local CORNER = UDim.new(0.15, 0)
local PILL = UDim.new(0.5, 0)

-- Adopt the user's existing placeholder UI where there is one, otherwise build fresh.
local gui = StarterGui:FindFirstChild("ScreenGui") or Instance.new("ScreenGui")
local root = gui:FindFirstChild("Frame") or Instance.new("Frame")
local title = root:FindFirstChildWhichIsA("TextLabel")
local placeholderButtons = {}
for _, child in root:GetChildren() do
	if child:IsA("ImageLabel") then
		child:Destroy()
	elseif child:IsA("TextButton") then
		table.insert(placeholderButtons, child)
	end
end
-- Top-to-bottom order of the user's placeholder buttons becomes Play / Settings / Credits.
table.sort(placeholderButtons, function(a, b)
	return a.Position.Y.Scale < b.Position.Y.Scale
end)

-- One font for the whole menu: the Title's existing font (new text objects default to Legacy).
local FONT = if title then title.Font else Enum.Font.SourceSans

local function apply(inst, props, parent)
	for key, value in props do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function make(className, props, parent)
	return apply(Instance.new(className), props, parent)
end

-- inst may be an existing TextLabel to adopt; pass nil to create one.
local function label(inst, props, parent)
	inst = inst or Instance.new("TextLabel")
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0
	inst.Font = FONT
	inst.TextColor3 = WHITE
	inst.TextScaled = true
	return apply(inst, props, parent)
end

-- inst may be an existing TextButton to adopt; pass nil to create one.
local function button(inst, props, parent)
	inst = inst or Instance.new("TextButton")
	inst.BackgroundColor3 = PANEL_COLOR
	inst.BackgroundTransparency = PANEL_TRANSPARENCY
	inst.BorderSizePixel = 0
	inst.Font = FONT
	inst.TextColor3 = WHITE
	inst.TextScaled = true
	apply(inst, props, parent)
	make("UICorner", { CornerRadius = CORNER }, inst)
	return inst
end

apply(gui, {
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
})

apply(root, {
	Name = "Root",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, gui)

-- Title
label(title, {
	Name = "Title",
	Text = "GAME TITLE",
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromScale(0.05, 0.08),
	Size = UDim2.fromScale(0.45, 0.12),
}, root)

-- Menu buttons
local buttons = make("Frame", {
	Name = "Buttons",
	Position = UDim2.fromScale(0.05, 0.26),
	Size = UDim2.fromScale(0.28, 0.42),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, root)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.05, 0),
}, buttons)
for index, name in { "Play", "Settings", "Credits" } do
	button(placeholderButtons[index], {
		Name = name,
		Text = name,
		LayoutOrder = index,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 0.28),
	}, buttons)
end

-- Character preview (a script fills the WorldModel and camera later)
local characterView = make("ViewportFrame", {
	Name = "CharacterView",
	Position = UDim2.fromScale(0.57, 0.18),
	Size = UDim2.fromScale(0.38, 0.72),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, root)
make("UIAspectRatioConstraint", { AspectRatio = 0.95 }, characterView)
make("WorldModel", {}, characterView)

-- Settings / Credits panels share geometry, header and close button.
local function makePanel(name, headerText)
	local panel = make("Frame", {
		Name = name,
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
	}, root)
	make("UICorner", { CornerRadius = CORNER }, panel)
	label(nil, {
		Name = "Header",
		Text = headerText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.05),
		Size = UDim2.fromScale(0.8, 0.18),
	}, panel)
	button(nil, {
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.03),
		Size = UDim2.fromScale(0.1, 0.16),
	}, panel)
	return panel
end

local settingsPanel = makePanel("SettingsPanel", "Settings")
label(nil, {
	Name = "MusicLabel",
	Text = "Music Volume",
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromScale(0.1, 0.35),
	Size = UDim2.fromScale(0.8, 0.14),
}, settingsPanel)

local slider = make("Frame", {
	Name = "Slider",
	Position = UDim2.fromScale(0.1, 0.62),
	Size = UDim2.fromScale(0.8, 0.08),
	BackgroundColor3 = TRACK_COLOR,
	BorderSizePixel = 0,
}, settingsPanel)
make("UICorner", { CornerRadius = PILL }, slider)
local fill = make("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0.5, 1),
	BackgroundColor3 = ACCENT_COLOR,
	BorderSizePixel = 0,
}, slider)
make("UICorner", { CornerRadius = PILL }, fill)
local knob = make("Frame", {
	Name = "Knob",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.07, 2),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
}, slider)
make("UICorner", { CornerRadius = PILL }, knob)
make("UIAspectRatioConstraint", { AspectRatio = 1 }, knob)

local creditsPanel = makePanel("CreditsPanel", "Credits")
label(nil, {
	Name = "Body",
	Text = "Made by YOUR NAME",
	Position = UDim2.fromScale(0.1, 0.35),
	Size = UDim2.fromScale(0.8, 0.3),
}, creditsPanel)

-- Full-screen fade overlay, above everything
make("Frame", {
	Name = "Fader",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 100,
}, gui)

-- Everything built: publish. Rename + move last so a mid-build error never leaves a half-made MainMenu.
make("SoundGroup", { Name = "Music", Volume = 0.5 }, SoundService)
apply(gui, { Name = "MainMenu" }, ReplicatedStorage)

return "built MainMenu"
