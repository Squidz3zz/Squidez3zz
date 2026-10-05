-- Run in Edit datamodel. Verifies the static main-menu UI tree built by studio/build_main_menu_ui.luau
-- (the heavy-factory layout: Scale-only Title / Buttons / CharacterView, the Vignette, the BACK button, the Fader).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local TOLERANCE = 0.0005
-- The phone check (844x390) needs every menu button at least 40px tall.
local MIN_BUTTON_SIZE = 40
local PHONE_HEIGHT = 390

local menu = ReplicatedStorage:FindFirstChild("MainMenu")
assert(menu, "MainMenu missing")
assert(menu:IsA("ScreenGui"), "MainMenu must be a ScreenGui")

-- Every path (relative to MainMenu) with its expected ClassName.
local EXPECTED = {
	{ "Root", "Frame" },
	{ "Root.Title", "TextLabel" },
	{ "Root.Title.UIStroke", "UIStroke" },
	{ "Root.Buttons", "Frame" },
	{ "Root.Buttons.UIListLayout", "UIListLayout" },
	{ "Root.Buttons.Play", "TextButton" },
	{ "Root.Buttons.Play.Accent", "Frame" },
	{ "Root.Buttons.Settings", "TextButton" },
	{ "Root.Buttons.Settings.Accent", "Frame" },
	{ "Root.Buttons.Credits", "TextButton" },
	{ "Root.Buttons.Credits.Accent", "Frame" },
	{ "Root.CharacterView", "ViewportFrame" },
	{ "Root.CharacterView.UIAspectRatioConstraint", "UIAspectRatioConstraint" },
	{ "Root.CharacterView.WorldModel", "WorldModel" },
	{ "Vignette", "Frame" },
	{ "Vignette.Top", "Frame" },
	{ "Vignette.Top.UIGradient", "UIGradient" },
	{ "Vignette.Bottom", "Frame" },
	{ "Vignette.Bottom.UIGradient", "UIGradient" },
	{ "Vignette.Left", "Frame" },
	{ "Vignette.Left.UIGradient", "UIGradient" },
	{ "Vignette.Right", "Frame" },
	{ "Vignette.Right.UIGradient", "UIGradient" },
	{ "Back", "TextButton" },
	{ "Back.Accent", "Frame" },
	{ "Fader", "Frame" },
}

-- Things that must be gone: the v1 popups.
local ABSENT = { "Root.SettingsPanel", "Root.CreditsPanel", "SettingsPanel", "CreditsPanel" }

local function find(path)
	local node = menu
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part)
		if not node then
			return nil
		end
	end
	return node
end

local function get(path)
	local node = find(path)
	assert(node, "missing: MainMenu." .. path)
	return node
end

local function near(a, b)
	return math.abs(a - b) <= TOLERANCE
end

local function expectUDim2(path, property, xs, xo, ys, yo)
	local value = get(path)[property]
	assert(
		near(value.X.Scale, xs) and value.X.Offset == xo and near(value.Y.Scale, ys) and value.Y.Offset == yo,
		("MainMenu.%s.%s should be {%s, %s}, {%s, %s}, got %s"):format(path, property, xs, xo, ys, yo, tostring(value))
	)
end

local function expectColor(path, property, expected)
	local value = get(path)[property]
	assert(value == expected, ("MainMenu.%s.%s should be %s, got %s"):format(path, property, tostring(expected), tostring(value)))
end

for _, path in ABSENT do
	assert(find(path) == nil, "MainMenu." .. path .. " should be absent (the popups were replaced by 3D rooms)")
end

for _, entry in EXPECTED do
	local node = get(entry[1])
	assert(node.ClassName == entry[2], ("MainMenu.%s is %s, expected %s"):format(entry[1], node.ClassName, entry[2]))
end

local PANEL = Color3.fromRGB(38, 36, 34)
local AMBER = Color3.fromRGB(255, 150, 30)
local VIGNETTE = Color3.fromRGB(12, 9, 6)

-- ScreenGui settings
assert(menu.ResetOnSpawn == false, "MainMenu.ResetOnSpawn must be false")
assert(menu.IgnoreGuiInset == true, "MainMenu.IgnoreGuiInset must be true")
assert(menu.ZIndexBehavior == Enum.ZIndexBehavior.Sibling, "MainMenu.ZIndexBehavior must be Sibling")
assert(menu.DisplayOrder == 10, "MainMenu.DisplayOrder must be 10")

-- Title: sits above the buttons, sharing their left edge. Oswald Bold with an amber outline.
local title = get("Root.Title")
assert(title.AnchorPoint == Vector2.new(0, 1), "Title.AnchorPoint must be (0, 1)")
expectUDim2("Root.Title", "Position", 0.06, 0, 0.27, 0)
expectUDim2("Root.Title", "Size", 0.40, 0, 0.10, 0)
assert(title.FontFace.Family:find("Oswald", 1, true), "Title must use Oswald, got " .. title.FontFace.Family)
assert(title.FontFace.Weight == Enum.FontWeight.Bold, "Title must be Bold, got " .. tostring(title.FontFace.Weight))
assert(title.Text == title.Text:upper(), "Title text must be uppercase")
expectColor("Root.Title.UIStroke", "Color", AMBER)

-- Buttons frame: middle-left, vertically centred on 0.56.
local buttons = get("Root.Buttons")
assert(buttons.AnchorPoint == Vector2.new(0, 0.5), "Buttons.AnchorPoint must be (0, 0.5)")
expectUDim2("Root.Buttons", "Position", 0.06, 0, 0.56, 0)
-- Tuned from the spec's 0.42 / 0.19 / 0.215 so the phone check holds: with those the buttons were 31px tall at 390px.
expectUDim2("Root.Buttons", "Size", 0.24, 0, 0.50, 0)
local list = get("Root.Buttons.UIListLayout")
assert(list.FillDirection == Enum.FillDirection.Vertical, "Buttons layout must be vertical")
assert(list.SortOrder == Enum.SortOrder.LayoutOrder, "Buttons layout must sort by LayoutOrder")
assert(list.Padding.Offset == 0, "UIListLayout.Padding must be Scale only")

-- On-screen gap between adjacent buttons: UIListLayout padding scales with the Buttons frame, not the screen.
local gap = list.Padding.Scale * buttons.Size.Y.Scale
assert(gap >= 0.08 and gap <= 0.10, ("the gap between buttons is %.4f of the screen height, it must be 0.08 to 0.10"):format(gap))

local buttonHeight = get("Root.Buttons.Play").Size.Y.Scale * buttons.Size.Y.Scale
assert(
	buttonHeight * PHONE_HEIGHT >= MIN_BUTTON_SIZE,
	("a button is %.1f px tall on a %d px screen, it must be at least %d"):format(buttonHeight * PHONE_HEIGHT, PHONE_HEIGHT, MIN_BUTTON_SIZE)
)
local stack = 3 * get("Root.Buttons.Play").Size.Y.Scale + 2 * list.Padding.Scale
assert(stack <= 1 + TOLERANCE, ("three buttons and two gaps fill %.4f of the Buttons frame, they must fit in 1"):format(stack))

local layoutOrder = { Play = 1, Settings = 2, Credits = 3 }
local labels = { Play = "PLAY", Settings = "SETTINGS", Credits = "CREDITS" }
for name, order in layoutOrder do
	local path = "Root.Buttons." .. name
	local button = get(path)
	assert(button.LayoutOrder == order, name .. ".LayoutOrder must be " .. order)
	expectUDim2(path, "Size", 1, 0, get("Root.Buttons.Play").Size.Y.Scale, 0)
	expectColor(path, "BackgroundColor3", PANEL)
	assert(button.BackgroundTransparency == 0, name .. " must be opaque")
	assert(button.FontFace.Family:find("Oswald", 1, true), name .. " must use Oswald, got " .. button.FontFace.Family)
	assert(button.Text == labels[name], name .. " label must be " .. labels[name] .. ", got " .. button.Text)
	assert(button.TextColor3 == Color3.new(1, 1, 1), name .. " text must be white")
	expectUDim2(path .. ".Accent", "Size", 0.03, 0, 1, 0)
	expectUDim2(path .. ".Accent", "Position", 0, 0, 0, 0)
	expectColor(path .. ".Accent", "BackgroundColor3", AMBER)
end

-- CharacterView: the avatar's slot on the right.
expectUDim2("Root.CharacterView", "Position", 0.56, 0, 0.10, 0)
expectUDim2("Root.CharacterView", "Size", 0.40, 0, 0.85, 0)
assert(get("Root.CharacterView").BackgroundTransparency == 1, "CharacterView must be transparent")

-- Vignette: full screen, under the Fader, never in the way of a click. Four edges, darkest at the outside.
local vignette = get("Vignette")
assert(vignette.ZIndex == 50, "Vignette.ZIndex must be 50")
assert(vignette.BackgroundTransparency == 1, "Vignette must be transparent")
assert(vignette.Active == false, "Vignette.Active must be false so it never sinks clicks")
expectUDim2("Vignette", "Position", 0, 0, 0, 0)
expectUDim2("Vignette", "Size", 1, 0, 1, 0)
-- Gradient Rotation 0 runs left to right, 90 top to bottom; each edge's gradient must start at its OUTER side.
local EDGES = {
	Top = { size = { 1, 0.18 }, rotation = 90 },
	Bottom = { size = { 1, 0.18 }, rotation = 270 },
	Left = { size = { 0.18, 1 }, rotation = 0 },
	Right = { size = { 0.18, 1 }, rotation = 180 },
}
for name, spec in EDGES do
	local path = "Vignette." .. name
	local edge = get(path)
	expectUDim2(path, "Size", spec.size[1], 0, spec.size[2], 0)
	expectColor(path, "BackgroundColor3", VIGNETTE)
	assert(edge.BackgroundTransparency == 0, name .. " edge must be opaque, the gradient fades it")
	assert(edge.Active == false, name .. " edge must not be Active")
	local gradient = get(path .. ".UIGradient")
	assert(near(gradient.Rotation % 360, spec.rotation), ("%s gradient Rotation should be %d, got %s"):format(name, spec.rotation, gradient.Rotation))
	local keypoints = gradient.Transparency.Keypoints
	assert(#keypoints == 2, name .. " gradient must have 2 keypoints")
	assert(keypoints[1].Time == 0 and near(keypoints[1].Value, 0.15), name .. " gradient must start at Transparency 0.15 (outer edge)")
	assert(keypoints[2].Time == 1 and near(keypoints[2].Value, 1), name .. " gradient must end at Transparency 1 (inner edge)")
end
-- Outer edges sit on the screen border.
assert(get("Vignette.Top").Position == UDim2.fromScale(0, 0) and get("Vignette.Top").AnchorPoint == Vector2.new(0, 0), "Top edge must hug the top")
assert(get("Vignette.Bottom").Position == UDim2.fromScale(0, 1) and get("Vignette.Bottom").AnchorPoint == Vector2.new(0, 1), "Bottom edge must hug the bottom")
assert(get("Vignette.Left").Position == UDim2.fromScale(0, 0) and get("Vignette.Left").AnchorPoint == Vector2.new(0, 0), "Left edge must hug the left")
assert(get("Vignette.Right").Position == UDim2.fromScale(1, 0) and get("Vignette.Right").AnchorPoint == Vector2.new(1, 0), "Right edge must hug the right")

-- BACK: bottom-left, factory skin, hidden until a room scene shows it.
local back = get("Back")
assert(back.Visible == false, "Back must start hidden")
assert(back.ZIndex == 60, "Back.ZIndex must be 60")
assert(back.AnchorPoint == Vector2.new(0, 1), "Back.AnchorPoint must be (0, 1)")
expectUDim2("Back", "Position", 0.03, 0, 0.95, 0)
-- Tuned from the spec's 0.09 so the BACK button is 40px tall on the phone check (0.09 of 390px is 35px).
expectUDim2("Back", "Size", 0.12, 0, 0.11, 0)
assert(back.Size.Y.Scale * PHONE_HEIGHT >= MIN_BUTTON_SIZE, "Back must be at least 40px tall at 390px")
expectColor("Back", "BackgroundColor3", PANEL)
assert(back.Text == "BACK", "Back label must be BACK, got " .. back.Text)
assert(back.FontFace.Family:find("Oswald", 1, true), "Back must use Oswald")
assert(back.TextColor3 == Color3.new(1, 1, 1), "Back text must be white")
expectUDim2("Back.Accent", "Size", 0.03, 0, 1, 0)
expectColor("Back.Accent", "BackgroundColor3", AMBER)

-- Fader: over everything.
assert(get("Fader").BackgroundTransparency == 1, "Fader must start transparent")
assert(get("Fader").ZIndex == 100, "Fader.ZIndex must be 100")
-- Root (title, buttons, avatar) sits above the Vignette so the dark edges never dim it, and below BACK.
assert(
	get("Root").ZIndex > get("Vignette").ZIndex and get("Root").ZIndex < get("Back").ZIndex,
	"Root.ZIndex must be above the Vignette and below Back, got Root " .. get("Root").ZIndex
)
assert(get("Vignette").ZIndex < get("Back").ZIndex and get("Back").ZIndex < get("Fader").ZIndex, "ZIndex order must be Vignette < Back < Fader")

-- The build script no longer touches StarterGui, so nothing is asserted about it (a ScreenGui of the developer's own
-- there is fine).
assert(menu:FindFirstChildWhichIsA("ImageLabel", true) == nil, "placeholder ImageLabel must be removed")

-- Sound groups
local music = SoundService:FindFirstChild("Music")
assert(music, "SoundService.Music missing")
assert(music:IsA("SoundGroup"), "SoundService.Music must be a SoundGroup")
local sfx = SoundService:FindFirstChild("SFX")
assert(sfx, "SoundService.SFX missing")
assert(sfx:IsA("SoundGroup"), "SoundService.SFX must be a SoundGroup")

-- Scale-only sizing: every GuiObject under MainMenu has zero Size offsets
local checked = 0
for _, d in menu:GetDescendants() do
	if d:IsA("GuiObject") then
		checked += 1
		assert(d.Size.X.Offset == 0 and d.Size.Y.Offset == 0, d:GetFullName() .. " has a non-zero Size offset")
		assert(d.Position.X.Offset == 0 and d.Position.Y.Offset == 0, d:GetFullName() .. " has a non-zero Position offset")
	end
end
assert(checked > 0, "no GuiObjects were checked")

return "PASS"
