-- Run in Edit datamodel. Verifies the static main-menu UI tree built by studio/build_main_menu_ui.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local menu = ReplicatedStorage:FindFirstChild("MainMenu")
assert(menu, "MainMenu missing")
assert(menu:IsA("ScreenGui"), "MainMenu must be a ScreenGui")

-- Every path (relative to MainMenu) with its expected ClassName.
local EXPECTED = {
	{ "Root", "Frame" },
	{ "Root.Title", "TextLabel" },
	{ "Root.Buttons", "Frame" },
	{ "Root.Buttons.UIListLayout", "UIListLayout" },
	{ "Root.Buttons.Play", "TextButton" },
	{ "Root.Buttons.Play.UICorner", "UICorner" },
	{ "Root.Buttons.Settings", "TextButton" },
	{ "Root.Buttons.Settings.UICorner", "UICorner" },
	{ "Root.Buttons.Credits", "TextButton" },
	{ "Root.Buttons.Credits.UICorner", "UICorner" },
	{ "Root.CharacterView", "ViewportFrame" },
	{ "Root.CharacterView.UIAspectRatioConstraint", "UIAspectRatioConstraint" },
	{ "Root.CharacterView.WorldModel", "WorldModel" },
	{ "Root.SettingsPanel", "Frame" },
	{ "Root.SettingsPanel.Header", "TextLabel" },
	{ "Root.SettingsPanel.MusicLabel", "TextLabel" },
	{ "Root.SettingsPanel.Slider", "Frame" },
	{ "Root.SettingsPanel.Slider.Fill", "Frame" },
	{ "Root.SettingsPanel.Slider.Knob", "Frame" },
	{ "Root.SettingsPanel.Close", "TextButton" },
	{ "Root.CreditsPanel", "Frame" },
	{ "Root.CreditsPanel.Header", "TextLabel" },
	{ "Root.CreditsPanel.Body", "TextLabel" },
	{ "Root.CreditsPanel.Close", "TextButton" },
	{ "Fader", "Frame" },
}

local function get(path)
	local node = menu
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part)
		assert(node, "missing: MainMenu." .. path)
	end
	return node
end

for _, entry in EXPECTED do
	local node = get(entry[1])
	assert(node.ClassName == entry[2], ("MainMenu.%s is %s, expected %s"):format(entry[1], node.ClassName, entry[2]))
end

-- ScreenGui settings
assert(menu.ResetOnSpawn == false, "MainMenu.ResetOnSpawn must be false")
assert(menu.IgnoreGuiInset == true, "MainMenu.IgnoreGuiInset must be true")
assert(menu.ZIndexBehavior == Enum.ZIndexBehavior.Sibling, "MainMenu.ZIndexBehavior must be Sibling")
assert(menu.DisplayOrder == 10, "MainMenu.DisplayOrder must be 10")

-- Initial visibility / fader
assert(get("Root.SettingsPanel").Visible == false, "SettingsPanel must start hidden")
assert(get("Root.CreditsPanel").Visible == false, "CreditsPanel must start hidden")
assert(get("Fader").BackgroundTransparency == 1, "Fader must start transparent")
assert(get("Fader").ZIndex == 100, "Fader.ZIndex must be 100")

-- Content and ordering
assert(get("Root.Title").Text == "GAME TITLE", "Title text must be GAME TITLE")
assert(get("Root.Buttons.UIListLayout").FillDirection == Enum.FillDirection.Vertical, "Buttons layout must be vertical")
assert(get("Root.Buttons.Play").LayoutOrder == 1, "Play.LayoutOrder must be 1")
assert(get("Root.Buttons.Settings").LayoutOrder == 2, "Settings.LayoutOrder must be 2")
assert(get("Root.Buttons.Credits").LayoutOrder == 3, "Credits.LayoutOrder must be 3")
assert(get("Root.CharacterView").BackgroundTransparency == 1, "CharacterView must be transparent")

-- One consistent style: every text object uses the Title's font
local titleFont = get("Root.Title").Font
for _, d in menu:GetDescendants() do
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		assert(d.Font == titleFont, d:GetFullName() .. " font is " .. d.Font.Name .. ", expected " .. titleFont.Name)
	end
end

-- Placeholder + moved-from-StarterGui cleanup
assert(menu:FindFirstChildWhichIsA("ImageLabel", true) == nil, "placeholder ImageLabel must be removed")
assert(StarterGui:FindFirstChild("ScreenGui") == nil, "StarterGui.ScreenGui must be moved out")

-- Music group
local music = SoundService:FindFirstChild("Music")
assert(music, "SoundService.Music missing")
assert(music:IsA("SoundGroup"), "SoundService.Music must be a SoundGroup")

-- Scale-only sizing: every GuiObject under MainMenu has zero Size offsets
local checked = 0
for _, d in menu:GetDescendants() do
	if d:IsA("GuiObject") then
		checked += 1
		assert(d.Size.X.Offset == 0 and d.Size.Y.Offset == 0, d:GetFullName() .. " has a non-zero Size offset")
	end
end
assert(checked > 0, "no GuiObjects were checked")

return "PASS"
