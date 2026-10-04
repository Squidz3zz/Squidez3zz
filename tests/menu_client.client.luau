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

-- The menu is cloned in at join.
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

local root = menu:FindFirstChild("Root")
assert(root, "MainMenu.Root missing")
local settings = root:FindFirstChild("SettingsPanel")
local credits = root:FindFirstChild("CreditsPanel")
assert(settings and credits, "SettingsPanel / CreditsPanel missing")
assert(not settings.Visible and not credits.Visible, "panels should start hidden")

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
local hook = clientScript and clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")

-- Panels: opening one hides the other, closePanels hides both.
hook:Invoke("openPanel", "Settings")
assert(settings.Visible, "openPanel('Settings') should show SettingsPanel")
assert(not credits.Visible, "openPanel('Settings') should hide CreditsPanel")

hook:Invoke("openPanel", "Credits")
assert(credits.Visible, "openPanel('Credits') should show CreditsPanel")
assert(not settings.Visible, "openPanel('Credits') should hide SettingsPanel")

hook:Invoke("openPanel", "Settings")
assert(settings.Visible and not credits.Visible, "reopening Settings should hide CreditsPanel again")

hook:Invoke("closePanels")
assert(not settings.Visible and not credits.Visible, "closePanels() should hide both panels")

-- Play: debounced (a second press while playing does nothing), then the menu closes once the character exists.
hook:Invoke("openPanel", "Settings") -- play() must close any open panel
assert(hook:Invoke("play") == true, "first play() should start the Play flow")
assert(not settings.Visible, "play() should close the open panel")
assert(hook:Invoke("play") == false, "second play() should be debounced")

local character = waitFor(function()
	return player.Character
end, 10)
assert(character, "player.Character is nil 10s after play()")

local gone = waitFor(function()
	return playerGui:FindFirstChild("MainMenu") == nil
end, 10)
assert(gone, "MainMenu was not destroyed after Play")
assert(playerGui:GetAttribute("MenuOpen") == false, "MenuOpen should be false after Play")

return "PASS"
