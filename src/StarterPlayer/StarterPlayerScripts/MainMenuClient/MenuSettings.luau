-- MenuSettings: the two on/off switches of the main menu, Camera Sway and Screen Effects (both on by default).
-- The state lives in attributes on LocalPlayer, not in this module, so every copy of the module sees the same values
-- (a test that requires this module gets its own copy, and still drives the game's) and anyone can listen with changed().
-- Settings are not saved between sessions: every join starts with both on.
local Players = game:GetService("Players")

local PREFIX = "MenuSetting_"
local NAMES = {
	CameraSway = true,
	ScreenEffects = true,
}

local MenuSettings = {}

local function attributeName(name)
	assert(NAMES[name], "MenuSettings: unknown setting " .. tostring(name))
	return PREFIX .. name
end

local function localPlayer()
	local player = Players.LocalPlayer
	assert(player, "MenuSettings is client-only: Players.LocalPlayer is missing")
	return player
end

-- A setting nobody has touched yet counts as on.
function MenuSettings.get(name)
	return localPlayer():GetAttribute(attributeName(name)) ~= false
end

function MenuSettings.set(name, value)
	assert(type(value) == "boolean", "MenuSettings.set: value must be a boolean, got " .. typeof(value))
	localPlayer():SetAttribute(attributeName(name), value)
end

-- Fires when the stored value changes. A first set(name, true) on an untouched setting also fires it (nil -> true),
-- so listeners should read get(name) rather than assume the direction of the change.
function MenuSettings.changed(name)
	return localPlayer():GetAttributeChangedSignal(attributeName(name))
end

return MenuSettings
