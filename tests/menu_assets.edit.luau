-- Run in the Edit datamodel via execute_luau (no playtest needed).
-- Unit checks for ReplicatedFirst.MenuAssets.soundId, the one small function that turns a typed sound id into the text a Sound's
-- SoundId needs. ButtonSounds, MenuAudio and LoadingScreen all read MenuAssets.Sounds through it, so a beginner who types an id
-- as a plain number (123456) or as a quoted number ("123456") gets the same sound as one who types "rbxassetid://123456".
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local moduleScript = ReplicatedFirst:FindFirstChild("MenuAssets")
assert(moduleScript and moduleScript:IsA("ModuleScript"), "ReplicatedFirst.MenuAssets (ModuleScript) missing")
-- A clone, so a MenuAssets edited since the last require is the one that is tested.
local MenuAssets = require(moduleScript:Clone())
assert(type(MenuAssets.soundId) == "function", "MenuAssets.soundId (a function) missing")
local soundId = MenuAssets.soundId

-- { typed value, what it becomes (nil: no usable id) }
local cases = {
	{ 123, "rbxassetid://123" },
	{ "123", "rbxassetid://123" },
	{ " 123 ", "rbxassetid://123" },
	{ "rbxassetid://123", "rbxassetid://123" },
	{ 113223325628963, "rbxassetid://113223325628963" },
	{ "113223325628963", "rbxassetid://113223325628963" },
	{ "http://www.roblox.com/asset/?id=123", "http://www.roblox.com/asset/?id=123" },
	{ "", nil },
	{ "   ", nil },
	{ 0, nil },
	{ -5, nil },
	{ 1.5, nil },
	{ math.huge, nil },
	{ 0 / 0, nil },
	{ true, nil },
	{ {}, nil },
}
for index, case in cases do
	local typed, expected = case[1], case[2]
	local actual = soundId(typed)
	assert(
		actual == expected,
		("soundId(%s) [case %d] should be %s, it is %s"):format(tostring(typed), index, tostring(expected), tostring(actual))
	)
end
assert(soundId(nil) == nil, "soundId(nil) should be nil")

-- The shipped ids are already in the final form, and stay that way.
assert(type(MenuAssets.Sounds) == "table", "MenuAssets.Sounds missing")
local count = 0
for key, value in MenuAssets.Sounds do
	count += 1
	assert(soundId(value) == value, ("the shipped id for %s (%s) should come back unchanged, it gives %s"):format(key, tostring(value), tostring(soundId(value))))
end
assert(count == 6, "MenuAssets.Sounds should hold the six keys, it holds " .. count)

return "PASS"
