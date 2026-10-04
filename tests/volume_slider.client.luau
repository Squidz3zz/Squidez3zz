-- Run in the Client datamodel of a FRESH playtest, while the menu is open (the Play press is not part of this test).
-- Drives VolumeSlider.setAlpha/attach on the live Instances: setAlpha acts only on the Instances it is given (this
-- test's module copy shares no state with the game's) and the test restores the original volume.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local TOLERANCE = 0.001

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

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or TOLERANCE)
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
assert(playerGui:GetAttribute("MenuOpen") == true, "MenuOpen should be true while the menu is open")
local root = menu:FindFirstChild("Root")
assert(root, "MainMenu.Root missing")

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "MainMenuClient missing")

-- Slider: setAlpha acts only on the Instances it is given (this test's module copy shares no state with the game's).
local sliderModule = clientScript:WaitForChild("VolumeSlider", 10)
assert(sliderModule and sliderModule:IsA("ModuleScript"), "VolumeSlider ModuleScript missing")
local VolumeSlider = require(sliderModule)
assert(type(VolumeSlider.attach) == "function", "VolumeSlider.attach missing")
assert(type(VolumeSlider.setAlpha) == "function", "VolumeSlider.setAlpha missing")

local slider = root.SettingsPanel.Slider
local music = SoundService:FindFirstChild("Music")
assert(music and music:IsA("SoundGroup"), "SoundService.Music (SoundGroup) missing")
local originalVolume = music.Volume

local function expectAlpha(label, alpha)
	assert(near(music.Volume, alpha), label .. ": Music.Volume should be " .. alpha .. ", got " .. music.Volume)
	assert(
		near(slider.Fill.Size.X.Scale, alpha),
		label .. ": Fill.Size.X.Scale should be " .. alpha .. ", got " .. slider.Fill.Size.X.Scale
	)
	assert(
		near(slider.Knob.Position.X.Scale, alpha),
		label .. ": Knob.Position.X.Scale should be " .. alpha .. ", got " .. slider.Knob.Position.X.Scale
	)
	-- Only the X scale follows alpha; the rest of the layout is untouched.
	assert(slider.Fill.Size.X.Offset == 0, label .. ": Fill.Size.X.Offset should stay 0")
	assert(slider.Fill.Size.Y == UDim.new(1, 0), label .. ": Fill.Size.Y should stay {1, 0}")
	assert(slider.Knob.Position.X.Offset == 0, label .. ": Knob.Position.X.Offset should stay 0")
	assert(slider.Knob.Position.Y == UDim.new(0.5, 0), label .. ": Knob.Position.Y should stay {0.5, 0}")
end

VolumeSlider.setAlpha(slider, music, 0.25)
expectAlpha("setAlpha 0.25", 0.25)

VolumeSlider.setAlpha(slider, music, 1.7)
expectAlpha("setAlpha 1.7 clamps to 1", 1)

VolumeSlider.setAlpha(slider, music, -3)
expectAlpha("setAlpha -3 clamps to 0", 0)

-- attach starts from the group's current volume (checked on a throwaway copy so the live slider is not touched).
local group = Instance.new("SoundGroup")
group.Volume = 0.8
local sliderCopy = slider:Clone()
VolumeSlider.attach(sliderCopy, group)
assert(near(sliderCopy.Fill.Size.X.Scale, 0.8), "attach: Fill should start at the group volume 0.8")
assert(near(sliderCopy.Knob.Position.X.Scale, 0.8), "attach: Knob should start at the group volume 0.8")
assert(near(group.Volume, 0.8), "attach should not change the group volume")
sliderCopy:Destroy()
group:Destroy()

VolumeSlider.setAlpha(slider, music, originalVolume)
expectAlpha("restore", originalVolume)

return "PASS"
