-- Run in Edit datamodel. Verifies the static main-menu UI built by studio/build_main_menu_ui.luau: three ScreenGuis in
-- ReplicatedStorage. MainMenu (the heavy-factory layout: Scale-only Title / Buttons / CharacterView, the BACK button)
-- stays in the phone's safe area; the Vignette and the Fader live in their own full-screen ScreenGuis (ScreenInsets None)
-- so they reach the notch strips and rounded corners.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local TOLERANCE = 0.0005
-- The phone check (844x390) needs every menu button at least 40px tall.
local MIN_BUTTON_SIZE = 40
local PHONE_HEIGHT = 390

local menu = ReplicatedStorage:FindFirstChild("MainMenu")
assert(menu, "MainMenu missing")
assert(menu:IsA("ScreenGui"), "MainMenu must be a ScreenGui")
local vignetteGui = ReplicatedStorage:FindFirstChild("MainMenuVignette")
assert(vignetteGui, "MainMenuVignette missing")
assert(vignetteGui:IsA("ScreenGui"), "MainMenuVignette must be a ScreenGui")
local faderGui = ReplicatedStorage:FindFirstChild("MainMenuFader")
assert(faderGui, "MainMenuFader missing")
assert(faderGui:IsA("ScreenGui"), "MainMenuFader must be a ScreenGui")

-- Every path with its expected ClassName. A path is resolved inside the ScreenGui that owns its first part: Vignette
-- inside MainMenuVignette, Fader inside MainMenuFader, everything else inside MainMenu.
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

-- The ScreenGui that owns `path`.
local function ownerOf(path)
	local first = string.match(path, "^[^%.]+")
	if first == "Vignette" then
		return vignetteGui
	elseif first == "Fader" then
		return faderGui
	end
	return menu
end

local function find(path)
	local node = ownerOf(path)
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
	assert(node, "missing: " .. ownerOf(path).Name .. "." .. path)
	return node
end

local function near(a, b)
	return math.abs(a - b) <= TOLERANCE
end

local function expectUDim2(path, property, xs, xo, ys, yo)
	local value = get(path)[property]
	assert(
		near(value.X.Scale, xs) and value.X.Offset == xo and near(value.Y.Scale, ys) and value.Y.Offset == yo,
		("%s.%s.%s should be {%s, %s}, {%s, %s}, got %s"):format(ownerOf(path).Name, path, property, xs, xo, ys, yo, tostring(value))
	)
end

local function expectColor(path, property, expected)
	local value = get(path)[property]
	assert(
		value == expected,
		("%s.%s.%s should be %s, got %s"):format(ownerOf(path).Name, path, property, tostring(expected), tostring(value))
	)
end

for _, path in ABSENT do
	assert(find(path) == nil, "MainMenu." .. path .. " should be absent (the popups were replaced by 3D rooms)")
end

for _, entry in EXPECTED do
	local node = get(entry[1])
	assert(
		node.ClassName == entry[2],
		("%s.%s is %s, expected %s"):format(ownerOf(entry[1]).Name, entry[1], node.ClassName, entry[2])
	)
end

local PANEL = Color3.fromRGB(38, 36, 34)
local AMBER = Color3.fromRGB(255, 150, 30)
local VIGNETTE = Color3.fromRGB(12, 9, 6)

-- The three ScreenGuis. The Vignette (behind) and the Fader (on top) are full screen, notch strips included
-- (ScreenInsets None); MainMenu keeps the safe area so the buttons and BACK never sit under a notch.
local GUIS = {
	{ gui = vignetteGui, insets = Enum.ScreenInsets.None, order = 9 },
	{ gui = menu, insets = Enum.ScreenInsets.DeviceSafeInsets, order = 10 },
	{ gui = faderGui, insets = Enum.ScreenInsets.None, order = 11 },
}
for _, spec in GUIS do
	local gui = spec.gui
	assert(gui.ScreenInsets == spec.insets, ("%s.ScreenInsets must be %s, got %s"):format(gui.Name, tostring(spec.insets), tostring(gui.ScreenInsets)))
	assert(gui.IgnoreGuiInset == true, gui.Name .. ".IgnoreGuiInset must be true")
	assert(gui.DisplayOrder == spec.order, ("%s.DisplayOrder must be %d, got %d"):format(gui.Name, spec.order, gui.DisplayOrder))
	assert(gui.ResetOnSpawn == false, gui.Name .. ".ResetOnSpawn must be false")
	assert(gui.ZIndexBehavior == Enum.ZIndexBehavior.Sibling, gui.Name .. ".ZIndexBehavior must be Sibling")
end
assert(
	vignetteGui.DisplayOrder < menu.DisplayOrder and menu.DisplayOrder < faderGui.DisplayOrder,
	"DisplayOrder must run MainMenuVignette < MainMenu < MainMenuFader"
)

-- Each ScreenGui holds only what it is for: Vignette and Fader are no longer children of MainMenu, and MainMenu has
-- exactly Root and Back as GuiObject children.
assert(menu:FindFirstChild("Vignette") == nil, "Vignette must no longer be a child of MainMenu")
assert(menu:FindFirstChild("Fader") == nil, "Fader must no longer be a child of MainMenu")
local function guiObjectChildren(gui)
	local names = {}
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(names, child.Name)
		end
	end
	table.sort(names)
	return table.concat(names, ",")
end
assert(guiObjectChildren(menu) == "Back,Root", "MainMenu must have exactly Root and Back as GuiObject children, got " .. guiObjectChildren(menu))
assert(guiObjectChildren(vignetteGui) == "Vignette", "MainMenuVignette must hold only the Vignette, got " .. guiObjectChildren(vignetteGui))
assert(guiObjectChildren(faderGui) == "Fader", "MainMenuFader must hold only the Fader, got " .. guiObjectChildren(faderGui))

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

-- CharacterView: the avatar's slot on the right. The avatar is shown from the waist up, cut off at the bottom of the
-- screen, so the frame is anchored to the bottom edge; it is 1.3 times as wide as tall (room for the wave's swing) and
-- 0.48 of the screen wide, from 0.48 to 0.96, which keeps it clear of the Buttons (end at 0.30) and the Title (ends at 0.46).
local characterView = get("Root.CharacterView")
assert(characterView.AnchorPoint == Vector2.new(0, 1), "CharacterView.AnchorPoint must be (0, 1), got " .. tostring(characterView.AnchorPoint))
expectUDim2("Root.CharacterView", "Position", 0.48, 0, 1, 0)
expectUDim2("Root.CharacterView", "Size", 0.48, 0, 0.85, 0)
local aspect = get("Root.CharacterView.UIAspectRatioConstraint")
assert(near(aspect.AspectRatio, 1.3), "CharacterView aspect ratio must be 1.3, got " .. aspect.AspectRatio)
assert(characterView.BackgroundTransparency == 1, "CharacterView must be transparent")
local titleRight = get("Root.Title").Position.X.Scale + get("Root.Title").Size.X.Scale
assert(characterView.Position.X.Scale >= titleRight, "CharacterView must start to the right of the Title frame")
assert(characterView.Position.X.Scale + characterView.Size.X.Scale <= 1 + TOLERANCE, "CharacterView must stay inside the screen")

-- Vignette: full screen, never in the way of a click. Four edges, darkest at the outside. Its ScreenGui sits behind
-- the menu (DisplayOrder 9), so its ZIndex only orders it inside that ScreenGui.
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

-- Fader: over everything (its ScreenGui has the highest DisplayOrder), full screen, clear until a fade starts.
local fader = get("Fader")
assert(fader.BackgroundTransparency == 1, "Fader must start transparent")
assert(fader.BackgroundColor3 == Color3.new(0, 0, 0), "Fader must be black")
assert(fader.ZIndex == 100, "Fader.ZIndex must be 100")
expectUDim2("Fader", "Position", 0, 0, 0, 0)
expectUDim2("Fader", "Size", 1, 0, 1, 0)
-- Root (title, buttons, avatar) stays below BACK. The ordering against the Vignette and the Fader comes from
-- DisplayOrder (checked above) now that they are ScreenGuis of their own.
assert(get("Root").ZIndex == 55, "Root.ZIndex must be 55, got " .. get("Root").ZIndex)
assert(get("Root").ZIndex < get("Back").ZIndex, "Root.ZIndex must be below Back, got Root " .. get("Root").ZIndex)

-- The build script no longer touches StarterGui, so nothing is asserted about it (a ScreenGui of the developer's own
-- there is fine).
for _, gui in { vignetteGui, menu, faderGui } do
	assert(gui:FindFirstChildWhichIsA("ImageLabel", true) == nil, "placeholder ImageLabel must be removed from " .. gui.Name)
end

-- Sound groups
local music = SoundService:FindFirstChild("Music")
assert(music, "SoundService.Music missing")
assert(music:IsA("SoundGroup"), "SoundService.Music must be a SoundGroup")
local sfx = SoundService:FindFirstChild("SFX")
assert(sfx, "SoundService.SFX missing")
assert(sfx:IsA("SoundGroup"), "SoundService.SFX must be a SoundGroup")

-- Scale-only sizing: every GuiObject in the three ScreenGuis has zero Size and Position offsets
local checked = 0
for _, gui in { vignetteGui, menu, faderGui } do
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			checked += 1
			assert(d.Size.X.Offset == 0 and d.Size.Y.Offset == 0, d:GetFullName() .. " has a non-zero Size offset")
			assert(d.Position.X.Offset == 0 and d.Position.Y.Offset == 0, d:GetFullName() .. " has a non-zero Position offset")
		end
	end
end
assert(checked > 0, "no GuiObjects were checked")

return "PASS"
