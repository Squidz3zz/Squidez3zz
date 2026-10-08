-- ExplosionReplacer: every Explosion in Workspace, whoever made it on the server (a script, a tool, a free model), shows as the
-- user's boom instead of Roblox's. The moment one is added (the same frame, before it reaches any player) it is made invisible and
-- Booms.at plays the boom (no blood) at its Position. One its maker already made invisible stays invisible and gets no boom. Its
-- physics (BlastPressure, BlastRadius, DestroyJointRadiusPercent, Hit) stay as its maker set them. An Explosion made by a
-- LocalScript only exists on that player's screen and is not seen here. Room 1's Explosive Harddrive makes no Explosion at all: it
-- calls Booms.at itself.
local ServerScriptService = game:GetService("ServerScriptService")

local Booms = require(ServerScriptService:WaitForChild("Booms"))

workspace.DescendantAdded:Connect(function(thing)
	if thing:IsA("Explosion") and thing.Visible then
		thing.Visible = false
		Booms.at(thing.Position)
	end
end)
