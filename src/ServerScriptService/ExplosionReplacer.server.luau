-- ExplosionReplacer: every Explosion in Workspace, whoever made it on the server (a script, a tool, a free model), shows as the
-- user's boom instead of Roblox's, and goes through the gore system. The moment one is added (the same frame, before it reaches
-- any player) Gore.roblox takes it: Roblox no longer snaps joints; the limbs near it tear, break or come off, the bodies it would
-- have killed die through gore (and ragdoll), and corpses near it are thrown (Gore says how). Then it is made invisible and
-- Booms.at plays the boom (no blood) at its Position. One its maker already made invisible stays invisible and gets no boom, but
-- still goes through Gore. Its BlastPressure push and its Hit event stay as its maker set them. Without Gore (still loading,
-- failed to load, or Gore.roblox failing, which warns once and puts DestroyJointRadiusPercent back) the Explosion works as
-- Roblox's own. An Explosion made by a LocalScript only exists on that player's screen and is not seen here. Room 1's Explosive
-- Harddrive makes no Explosion at all: it calls Booms.at itself.
local ServerScriptService = game:GetService("ServerScriptService")

local Booms = require(ServerScriptService:WaitForChild("Booms"))

local warned = false
local function warnOnce(message: string)
	if not warned then
		warned = true
		warn(message)
	end
end

-- Set once Gore has loaded (below); explosions before that get the boom only.
local Gore = nil

workspace.DescendantAdded:Connect(function(thing)
	if not thing:IsA("Explosion") then
		return
	end
	if Gore then
		local percent = thing.DestroyJointRadiusPercent
		local done, err = pcall(Gore.roblox, thing)
		if not done then
			thing.DestroyJointRadiusPercent = percent
			warnOnce("ExplosionReplacer: Gore.roblox failed, so this explosion works as Roblox's own: " .. tostring(err))
		end
	end
	if thing.Visible then
		thing.Visible = false
		Booms.at(thing.Position)
	end
end)

local goreModule = ServerScriptService:WaitForChild("Gore", 5)
local ok, result = pcall(require, goreModule)
if goreModule and ok then
	Gore = result
else
	warnOnce("ExplosionReplacer: Gore did not load, so explosions work as Roblox's own: " .. tostring(result))
end
