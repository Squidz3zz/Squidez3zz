-- Run in the Client datamodel of a running playtest, after tests/fire_play.client.luau (so the player has a live character).
-- Fires ReplicatedStorage.GoreReset (what the Reset Character button does through GoreReset.client): the character dies, it
-- ragdolls into a corpse in Workspace.Corpses, and every limb on that corpse is still Intact at 100 (a reset is no hit).
-- Returns "PASS gore_reset". The player respawns as after any death.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LIMB_KEYS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

local function waitFor(check: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not check() do
		if os.clock() > deadline then
			return false
		end
		task.wait()
	end
	return true
end

local reset = ReplicatedStorage:WaitForChild("GoreReset", 10)
assert(reset and reset:IsA("RemoteEvent"), "ReplicatedStorage.GoreReset (RemoteEvent) is missing")
local character = Players.LocalPlayer.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
assert(humanoid and humanoid.Health > 0, "no live character: run tests/fire_play.client.luau first")
local torso = character:WaitForChild("Torso", 5)
assert(torso, "the character has no Torso (R6)")

reset:FireServer()
assert(waitFor(function()
	return humanoid.Health == 0
end, 5), "GoreReset did not kill the character (Health " .. humanoid.Health .. ")")
assert(waitFor(function()
	local parent = torso.Parent
	return parent ~= nil and parent.Parent == workspace:FindFirstChild("Corpses")
end, 5), "the reset left no corpse (no ragdoll)")
local corpse = torso.Parent :: Model
for _, key in LIMB_KEYS do
	local state, hp = corpse:GetAttribute("Gore_" .. key), corpse:GetAttribute("GoreHP_" .. key)
	assert(state == "Intact" and hp == 100, ("the reset left %s %s at %s, expected Intact at 100"):format(key, tostring(state), tostring(hp)))
end
return "PASS gore_reset"
