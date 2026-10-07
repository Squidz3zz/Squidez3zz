-- Run in the Client datamodel during a playtest, after tests/fire_play.client.luau. Checks LabClient's claim prompt text for this player.
-- It checks whichever state the room is in, so run it twice in one playtest: once with the room free, once after
-- tests/lab_claim.server.luau case A (which leaves it claimed by you).
--   free         the prompt is enabled and says "Claim Room 1"
--   yours        the prompt is enabled and says "Release Room 1"
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
local state, expected
if owner == 0 then
	state, expected = "free", "Claim Room 1"
elseif owner == player.UserId then
	state, expected = "yours", "Release Room 1"
else
	error("Room 1 is owned by someone else (" .. tostring(owner) .. ")")
end

local function assertState()
	assert(
		waitFor(function()
			return prompt.Enabled == true and prompt.ActionText == expected
		end, 5),
		("room %s: the prompt should be enabled and say '%s', it is Enabled=%s '%s'"):format(
			state,
			expected,
			tostring(prompt.Enabled),
			prompt.ActionText
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

return "PASS lab_claim.client (" .. state .. ")"
