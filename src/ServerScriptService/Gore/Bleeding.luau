-- Bleeding: bleed damage (it sits inside Gore, which is how GoreServer reaches it as Gore.bleed). A living tracked body with
-- n >= 2 open limbs (Torn, Broken or Severed) loses GoreConfig BLEED_PER_OPEN_LIMB * n health per second, as gore damage
-- (Gore.hurt, which the big-hit watcher ignores), at GORE_LEVEL 1 and up; at level 0 nothing bleeds.
--   Bleeding.tick(dt)  takes dt seconds of bleeding from every such body. Dead bodies are skipped: a corpse (which has
--                      GoreDiedAt and a still Humanoid at 0 health) and the emptied character a death leaves behind (its parts
--                      went into the corpse) do not bleed.
-- Each body bleeds for itself. Gore.hurt is not carried across a link, and a linked pair always has the same open limbs (the
-- link copies every state), so the two lose the same health; hurting a partner from here as well would make both lose double.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig", 5) or error("Gore: GoreConfig is missing"))
local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig", 5) or error("Gore: LabConfig is missing"))
local Integrity = require(script.Parent:WaitForChild("Integrity", 5) or error("Gore: Integrity is missing"))

local OPEN = { Torn = true, Broken = true, Severed = true }

local Bleeding = {}

function Bleeding.tick(dt: number)
	if GoreConfig.get("GORE_LEVEL") < 1 then
		return
	end
	for _, body in CollectionService:GetTagged("GoreBody") do
		local humanoid = body:FindFirstChildOfClass("Humanoid")
		if not (humanoid and humanoid.Health > 0 and body:GetAttribute("GoreDiedAt") == nil and body:FindFirstChild("Torso")) then
			continue
		end
		local open = 0
		for _, key in LabConfig.LIMB_KEYS do
			if OPEN[body:GetAttribute("Gore_" .. key)] then
				open += 1
			end
		end
		if open >= 2 then
			Integrity.hurt(body, GoreConfig.get("BLEED_PER_OPEN_LIMB") * open * dt)
		end
	end
end

return Bleeding
