-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet).
-- Exercises MainMenuClient through its Studio-only TestHook (a BindableFunction under the script).
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.1)
	end
	return predicate()
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")

-- The menu is cloned in at join, as three ScreenGuis: MainMenu (Root, Back), MainMenuVignette (Vignette) and
-- MainMenuFader (Fader).
local GUI_NAMES = { "MainMenu", "MainMenuVignette", "MainMenuFader" }
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
local vignetteGui = waitFor(function()
	return playerGui:FindFirstChild("MainMenuVignette")
end, 10)
assert(vignetteGui, "MainMenuVignette missing in PlayerGui")
local faderGui = waitFor(function()
	return playerGui:FindFirstChild("MainMenuFader")
end, 10)
assert(faderGui, "MainMenuFader missing in PlayerGui")
for _, name in GUI_NAMES do
	local gui = playerGui:FindFirstChild(name)
	assert(gui and gui:IsA("ScreenGui") and gui.Parent == playerGui, name .. " should be a ScreenGui in PlayerGui while the menu is open")
end
-- The clones keep what the build gave them: the overlays are full screen, behind (9) and over (11) the menu (10).
assert(vignetteGui.ScreenInsets == Enum.ScreenInsets.None and vignetteGui.DisplayOrder == 9, "MainMenuVignette should be ScreenInsets None, DisplayOrder 9")
assert(menu.ScreenInsets == Enum.ScreenInsets.DeviceSafeInsets and menu.DisplayOrder == 10, "MainMenu should be DeviceSafeInsets, DisplayOrder 10")
assert(faderGui.ScreenInsets == Enum.ScreenInsets.None and faderGui.DisplayOrder == 11, "MainMenuFader should be ScreenInsets None, DisplayOrder 11")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

local root = menu:FindFirstChild("Root")
assert(root, "MainMenu.Root missing")
assert(root:FindFirstChild("SettingsPanel") == nil and root:FindFirstChild("CreditsPanel") == nil, "the popup panels should be gone")
local vignette = vignetteGui:FindFirstChild("Vignette")
local fader = faderGui:FindFirstChild("Fader")
local back = menu:FindFirstChild("Back")
assert(vignette and fader and back, "MainMenuVignette.Vignette / MainMenuFader.Fader / MainMenu.Back missing")
assert(menu:FindFirstChild("Vignette") == nil and menu:FindFirstChild("Fader") == nil, "Vignette and Fader should not be in MainMenu")
assert(root.Visible, "Root should be visible at join")
assert(not back.Visible, "Back should start hidden")

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
local hook = clientScript and clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")

-- Scene: the menu announces itself as the current scene.
assert(hook:Invoke("scene") == "Menu", "scene should be 'Menu' while the menu is open, got " .. tostring(hook:Invoke("scene")))
assert(playerGui:GetAttribute("MenuScene") == "Menu", "PlayerGui attribute MenuScene should be 'Menu'")

-- Vignette follows the Screen Effects setting, initially and through changes.
local settingsModule = clientScript:WaitForChild("MenuSettings", 10)
assert(settingsModule and settingsModule:IsA("ModuleScript"), "MainMenuClient.MenuSettings (ModuleScript) missing")
local MenuSettings = require(settingsModule)
assert(MenuSettings.get("ScreenEffects") == true, "ScreenEffects should start on")
assert(vignette.Visible == true, "Vignette should be visible while Screen Effects is on")
local vignetteOk, vignetteError = pcall(function()
	MenuSettings.set("ScreenEffects", false)
	assert(waitFor(function()
		return vignette.Visible == false
	end, 1), "Vignette should hide when Screen Effects goes off")
	MenuSettings.set("ScreenEffects", true)
	assert(waitFor(function()
		return vignette.Visible == true
	end, 1), "Vignette should show again when Screen Effects goes on")
end)
MenuSettings.set("ScreenEffects", true)
assert(vignetteOk, vignetteError)

-- A hidden button never gets its MouseLeave, so hiding Root must reset the buttons or they would come back popped.
local ButtonEffects = require(clientScript:WaitForChild("ButtonEffects", 10))
local settingsButton = root.Buttons.Settings
local popOk, popError = pcall(function()
	ButtonEffects.setState(settingsButton, "hover")
	task.wait(0.3)
	assert(math.abs(settingsButton.PopScale.Scale - 1.1) <= 0.01, "Settings should be popped before Root is hidden")
	root.Visible = false
	task.wait(0.4)
	assert(
		math.abs(settingsButton.PopScale.Scale - 1) <= 0.01,
		"hiding Root should reset the buttons to idle, PopScale is " .. settingsButton.PopScale.Scale
	)
end)
root.Visible = true
assert(popOk, popError)

-- Play: debounced (a second press while playing does nothing), then the menu closes once the character exists.
assert(hook:Invoke("play") == true, "first play() should start the Play flow")
assert(hook:Invoke("play") == false, "second play() should be debounced")

local character = waitFor(function()
	return player.Character
end, 10)
assert(character, "player.Character is nil 10s after play()")

-- All three ScreenGuis go, not just MainMenu.
local function leftOver()
	local names = {}
	for _, name in GUI_NAMES do
		if playerGui:FindFirstChild(name) then
			table.insert(names, name)
		end
	end
	return table.concat(names, ", ")
end
local gone = waitFor(function()
	return leftOver() == ""
end, 10)
assert(gone, "the menu's ScreenGuis were not all destroyed after Play, still in PlayerGui: " .. leftOver())
assert(playerGui:GetAttribute("MenuOpen") == false, "MenuOpen should be false after Play")
assert(
	playerGui:GetAttribute("MenuScene") == nil,
	"MenuScene should be cleared after Play, got " .. tostring(playerGui:GetAttribute("MenuScene"))
)

return "PASS"
