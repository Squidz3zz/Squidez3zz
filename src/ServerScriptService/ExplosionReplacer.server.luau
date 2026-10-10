-- ExplosionReplacer: every Explosion in Workspace, whoever made it on the server (a script, a tool, a free model), shows as the
-- user's boom instead of Roblox's, and goes through the gore system. The moment one is added (the same frame, before it reaches
-- any player) it is made invisible and Booms.at plays the boom (no blood) at its Position. One its maker already made invisible
-- stays invisible and gets no boom. Either way Gore.roblox then takes it: Roblox no longer snaps joints; the limbs near it tear,
-- break or come off, the bodies it would have killed die through gore (and ragdoll), and corpses near it are thrown (Gore says
-- how). Its BlastPressure push and its Hit event stay as its maker set them. Without Gore (or if Gore.roblox fails, which
-- warns once) the Explosion works as Roblox's own. An Explosion made by a LocalScript only exists on that player's screen and
-- is not seen here. Room 1's Explosive Harddrive makes no Explosion at all: it calls Booms.at itself.
local ServerScriptService = game:GetService("ServerScriptService")

local Booms = require(ServerScriptService:WaitForChild("Booms"))

local warned = false
local function warnOnce(message: string)
	if not warned then
		warned = true
		warn(message)
	end
end

local goreModule = ServerScriptService:WaitForChild("Gore", 5)
local ok, Gore = pcall(require, goreModule)
if not (goreModule and ok) then
	warnOnce("ExplosionReplacer: Gore did not load, so explosions work as Roblox's own: " .. tostring(Gore))
	Gore = nil
end

workspace.DescendantAdded:Connect(function(thing)
	if not thing:IsA("Explosion") then
		return
	end
	if thing.Visible then
		thing.Visible = false
		Booms.at(thing.Position)
	end
	if Gore then
		local done, err = pcall(Gore.roblox, thing)
		if not done then
			warnOnce("ExplosionReplacer: Gore.roblox failed: " .. tostring(err))
		end
	end
end)
