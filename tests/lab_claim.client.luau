-- Run in the Client datamodel during a playtest, after tests/fire_play.client.luau. Checks LabClient's claim prompt text for this player.
-- It checks whichever state the room is in, so run it twice in one playtest: once with the room free, once after
-- tests/lab_claim.server.luau case A (which leaves it claimed by you).
--   free         the prompt is enabled, says "Claim Room 1" and needs no hold (HoldDuration 0)
--   yours        the prompt is enabled, says "Release Room 1" and needs a 1 s hold (HoldDuration 1)
-- Either way it then pretends another player owns the room (Owner is set on this client only, nothing reaches the server): the
-- prompt must be disabled; and then puts the real value back and checks the first state again.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local room = workspace:WaitForChild("Room1", 10)
assert(room, "Workspace.Room1 missing on the client")
local prompt = room:WaitForChild("ClaimButton"):WaitForChild("Button"):WaitForChild("ClaimPrompt")

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.1)
	end
	return predicate()
end

local owner = room:GetAttribute("Owner")
local state, expected, hold
if owner == 0 then
	state, expected, hold = "free", "Claim Room 1", 0
elseif owner == player.UserId then
	state, expected, hold = "yours", "Release Room 1", 1
else
	error("Room 1 is owned by someone else (" .. tostring(owner) .. ")")
end

local function assertState()
	assert(
		waitFor(function()
			return prompt.Enabled == true and prompt.ActionText == expected and prompt.HoldDuration == hold
		end, 5),
		("room %s: the prompt should be enabled, say '%s' and hold %s s, it is Enabled=%s '%s' %s s"):format(
			state,
			expected,
			hold,
			tostring(prompt.Enabled),
			prompt.ActionText,
			prompt.HoldDuration
		)
	)
end
assertState()

room:SetAttribute("Owner", 987654321)
local disabled = waitFor(function()
	return prompt.Enabled == false
end, 2)
room:SetAttribute("Owner", owner)
assert(disabled, "the prompt should be disabled while someone else owns the room")
assertState()

return "PASS lab_claim.client (" .. state .. ", HoldDuration " .. prompt.HoldDuration .. ")"
