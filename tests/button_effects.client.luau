-- Run in the Client datamodel of a playtest while the main menu is still open (before Play is pressed).
-- Checks that MainMenuClient attached ButtonEffects to every menu button, then drives ButtonEffects.setState
-- directly (the module is required from its ModuleScript; setState finds PopScale/PopStroke on the button,
-- so this copy of the module acts on the same Instances the menu uses).
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local TOLERANCE = 0.01

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

local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
local root = menu:FindFirstChild("Root")
assert(root, "MainMenu.Root missing")

local buttons = {
	Play = root.Buttons.Play,
	Settings = root.Buttons.Settings,
	Credits = root.Buttons.Credits,
	SettingsClose = root.SettingsPanel.Close,
	CreditsClose = root.CreditsPanel.Close,
}

-- attach() ran on every button: PopScale/PopStroke exist and start idle.
for name, button in buttons do
	local popScale = button:FindFirstChild("PopScale")
	assert(popScale and popScale:IsA("UIScale"), "PopScale missing on " .. name)
	local popStroke = button:FindFirstChild("PopStroke")
	assert(popStroke and popStroke:IsA("UIStroke"), "PopStroke missing on " .. name)
	assert(popStroke.Color == Color3.new(1, 1, 1), name .. " PopStroke should be white")
	assert(popStroke.Thickness == 2, name .. " PopStroke.Thickness should be 2")
	assert(popStroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border, name .. " PopStroke should use Border mode")
	assert(math.abs(popScale.Scale - 1) <= TOLERANCE, name .. " PopScale should start at 1, got " .. popScale.Scale)
	assert(popStroke.Transparency == 1, name .. " PopStroke should start invisible, got " .. popStroke.Transparency)
end

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "MainMenuClient missing")
local effectsModule = clientScript:WaitForChild("ButtonEffects", 10)
assert(effectsModule and effectsModule:IsA("ModuleScript"), "ButtonEffects ModuleScript missing")
local ButtonEffects = require(effectsModule)
assert(type(ButtonEffects.attach) == "function", "ButtonEffects.attach missing")
assert(type(ButtonEffects.setState) == "function", "ButtonEffects.setState missing")

local play = buttons.Play
local popScale = play.PopScale
local popStroke = play.PopStroke

local function expectState(label, scale, transparency)
	assert(
		math.abs(popScale.Scale - scale) <= TOLERANCE,
		label .. ": PopScale.Scale should be " .. scale .. ", got " .. popScale.Scale
	)
	assert(
		math.abs(popStroke.Transparency - transparency) <= TOLERANCE,
		label .. ": PopStroke.Transparency should be " .. transparency .. ", got " .. popStroke.Transparency
	)
end

ButtonEffects.setState(play, "hover")
task.wait(0.3)
expectState("hover", 1.1, 0)

ButtonEffects.setState(play, "press")
task.wait(0.3)
expectState("press", 0.95, 0)

ButtonEffects.setState(play, "idle")
task.wait(0.3)
expectState("idle", 1, 1)

-- Rapid changes: the last state wins and nothing is left half-tweened.
ButtonEffects.setState(play, "hover")
task.wait(0.05)
ButtonEffects.setState(play, "idle")
task.wait(0.3)
expectState("hover then idle", 1, 1)

ButtonEffects.setState(play, "idle")
task.wait(0.05)
ButtonEffects.setState(play, "hover")
task.wait(0.3)
expectState("idle then hover", 1.1, 0)

ButtonEffects.setState(play, "idle")
task.wait(0.3)
expectState("final idle", 1, 1)

-- Invalid input is rejected, not silently ignored.
assert(not pcall(ButtonEffects.setState, play, "bogus"), "setState should reject an unknown state")

return "PASS"
