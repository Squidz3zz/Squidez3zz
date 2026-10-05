-- One-shot build script: run in the Edit datamodel via execute_luau.
-- Builds the static main-menu tree from scratch as ReplicatedStorage.MainMenu (the heavy-factory look: Title and
-- Buttons middle-left, the avatar slot on the right, a dark Vignette, a BACK button for the room scenes), and creates
-- SoundService.Music and SoundService.SFX unless they are already there. It never adopts, moves or edits anything in
-- StarterGui, so a ScreenGui of your own stays untouched.
-- After it runs, Studio is the source of truth for the UI. The script refuses to run while ReplicatedStorage.MainMenu
-- exists, so as a recovery baseline it only works once the live MainMenu has been deleted (or moved out, e.g. to
-- ServerStorage.MainMenuBackupV1).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

if ReplicatedStorage:FindFirstChild("MainMenu") then
	error("MainMenu already exists")
end

-- Factory palette. All sizes/positions use Scale only (UIStroke thickness is the one exception allowed by design).
local PANEL_COLOR = Color3.fromRGB(38, 36, 34)
local AMBER = Color3.fromRGB(255, 150, 30)
local VIGNETTE_COLOR = Color3.fromRGB(12, 9, 6)
local WHITE = Color3.new(1, 1, 1)

-- One font for the whole menu: Oswald, with uppercase labels (new text objects default to Legacy fonts).
local FONT = Font.fromEnum(Enum.Font.Oswald)
local FONT_BOLD = Font.new(FONT.Family, Enum.FontWeight.Bold)

-- How deep each vignette edge is, as a fraction of the screen side it runs along the other way.
local VIGNETTE_DEPTH = 0.18

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

local function label(props, parent)
	local inst = Instance.new("TextLabel")
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0
	inst.FontFace = FONT
	inst.TextColor3 = WHITE
	inst.TextScaled = true
	return apply(inst, props, parent)
end

-- A factory button: dark steel with a thin amber bar down its left edge. Used by the menu buttons and BACK.
local function button(props, parent)
	local inst = Instance.new("TextButton")
	inst.BackgroundColor3 = PANEL_COLOR
	inst.BackgroundTransparency = 0
	inst.BorderSizePixel = 0
	inst.FontFace = FONT
	inst.TextColor3 = WHITE
	inst.TextScaled = true
	apply(inst, props, parent)
	make("Frame", {
		Name = "Accent",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.03, 1),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
	}, inst)
	return inst
end

local gui = make("ScreenGui", {
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
})

local root = make("Frame", {
	Name = "Root",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, gui)

-- Title: sits just above the buttons and shares their left edge.
-- Its top edge is at 0.20 of the height, which keeps it below Roblox's topbar (menu / chat icons) on phones in
-- landscape (about 58pt at 844x390).
local title = label({
	Name = "Title",
	Text = "GAME TITLE",
	FontFace = FONT_BOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0.06, 0.30),
	Size = UDim2.fromScale(0.40, 0.10),
}, root)
make("UIStroke", { Color = AMBER, Thickness = 2 }, title)

-- Menu buttons: middle-left, vertically centred on 0.56.
-- UIListLayout padding scales with this frame, not the screen: the gap on screen is 0.1775 x 0.50 = 0.089 of the
-- height (the spec wants 0.08 to 0.10) and a button is 0.215 x 0.50 = 0.1075 of the height, i.e. 42px at 390px.
-- (The spec's first values, 0.42 / 0.19 / 0.215, gave 31px buttons on the phone, under the 40px tap target.)
local buttons = make("Frame", {
	Name = "Buttons",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.06, 0.56),
	Size = UDim2.fromScale(0.24, 0.50),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, root)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.1775, 0),
}, buttons)
for index, name in { "Play", "Settings", "Credits" } do
	button({
		Name = name,
		Text = string.upper(name),
		LayoutOrder = index,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 0.215),
	}, buttons)
end

-- Character preview (a script fills the WorldModel and camera later)
local characterView = make("ViewportFrame", {
	Name = "CharacterView",
	Position = UDim2.fromScale(0.56, 0.10),
	Size = UDim2.fromScale(0.40, 0.85),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, root)
make("UIAspectRatioConstraint", { AspectRatio = 0.95 }, characterView)
make("WorldModel", {}, characterView)

-- Vignette: dark edges on all four sides, above Root and below BACK and the Fader. It is only ever seen, never
-- clicked: Active stays false on every frame so a press goes straight through to the buttons underneath.
-- Each edge fades with a UIGradient from Transparency 0.15 at the screen border to 1 on the inside. Gradient
-- Rotation 0 runs left to right and 90 top to bottom, so the rotation is picked per edge to start at its outer side.
local vignette = make("Frame", {
	Name = "Vignette",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 50,
}, gui)
local function edge(name, anchor, position, size, rotation)
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundColor3 = VIGNETTE_COLOR,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Active = false,
	}, vignette)
	make("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
end
edge("Top", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, VIGNETTE_DEPTH), 90)
edge("Bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, VIGNETTE_DEPTH), 270)
edge("Left", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(VIGNETTE_DEPTH, 1), 0)
edge("Right", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(VIGNETTE_DEPTH, 1), 180)

-- BACK: bottom-left, in the same skin. Hidden in the menu; the Settings and Credits rooms show it.
-- Its height is 0.11 of the screen (0.09 would be 35px at 390px, under the 40px tap target).
button({
	Name = "Back",
	Text = "BACK",
	Visible = false,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0.03, 0.95),
	Size = UDim2.fromScale(0.12, 0.11),
	ZIndex = 60,
}, gui)

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
if not SoundService:FindFirstChild("Music") then
	make("SoundGroup", { Name = "Music", Volume = 0.5 }, SoundService)
end
if not SoundService:FindFirstChild("SFX") then
	make("SoundGroup", { Name = "SFX", Volume = 0.5 }, SoundService)
end
apply(gui, { Name = "MainMenu" }, ReplicatedStorage)

return "built MainMenu"
