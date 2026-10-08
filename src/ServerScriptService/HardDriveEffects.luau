-- HardDriveEffects: what each Harddrive does once Bob has injected it. One function per Harddrive id (the ids in
-- LabConfig.HardDrives), named exactly like the id. LabServer calls it in its own thread as the needle leaves the limb, with
-- the bodies to apply it to (the owner's copy and the owner's character, at once, so the two stay the same), the limb key and
-- stillLinked: a function that turns false when the room is released, the copy is replaced or either body dies. An effect that
-- takes time checks it as it goes and stops, with nothing done, once it is false.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
-- With a timeout, so a missing Booms fails this module's load (LabServer then refuses injections) instead of hanging LabServer.
local Booms = require(ServerScriptService:WaitForChild("Booms", 5))

local FUSE_RED = Color3.fromRGB(255, 30, 20)
-- The fuse's blink (one glow and one beep) comes every BLINK_FIRST seconds at the start, speeding up to every BLINK_LAST.
local BLINK_FIRST = 0.6
local BLINK_LAST = 0.12
-- Losing these is always fatal; any other limb falls off.
local FATAL = { Head = true, Torso = true }

local HardDriveEffects = {}

local function sfxGroup(): SoundGroup
	local group = SoundService:FindFirstChild("SFX")
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = "SFX"
		group.Parent = SoundService
	end
	return group :: SoundGroup
end

-- Explosive: a fuse of FUSE_SECONDS (the limb glows red and beeps, faster and faster), then a blast at the limb: Booms.at the
-- limb's centre (taken before it comes off; no Explosion instance). An arm or a leg falls off and the body loses LIMB_DAMAGE
-- health; the head or the torso kills. The blast itself hurts nothing else.
function HardDriveEffects.Explosive(bodies: { Model }, limbKey: string, stillLinked: () -> boolean)
	local fused: { Model } = {}
	local glows: { Highlight } = {}
	local beeps: { Sound } = {}
	for _, body in bodies do
		local humanoid = body:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not LabConfig.isLost(body, limbKey) then
			table.insert(fused, body)
			local parts = LabConfig.limbParts(body, limbKey)
			for _, part in parts do
				local glow = Instance.new("Highlight")
				glow.Name = "FuseGlow"
				glow.FillColor = FUSE_RED
				glow.OutlineColor = FUSE_RED
				glow.DepthMode = Enum.HighlightDepthMode.Occluded
				glow.Parent = part
				table.insert(glows, glow)
			end
			local beep = Instance.new("Sound")
			beep.Name = "FuseBeep"
			beep.SoundId = LabConfig.Sounds.FuseBeep
			beep.SoundGroup = sfxGroup()
			beep.Parent = parts[1]
			table.insert(beeps, beep)
		end
	end

	local start = os.clock()
	local lit = false
	while stillLinked() do
		local elapsed = os.clock() - start
		if elapsed >= LabConfig.FUSE_SECONDS then
			break
		end
		lit = not lit
		for _, glow in glows do
			glow.FillTransparency = if lit then 0.1 else 0.8
		end
		if lit then
			for _, beep in beeps do
				beep:Play()
			end
		end
		local blink = BLINK_FIRST + (BLINK_LAST - BLINK_FIRST) * elapsed / LabConfig.FUSE_SECONDS
		task.wait(math.min(blink / 2, LabConfig.FUSE_SECONDS - elapsed))
	end
	for _, glow in glows do
		glow:Destroy()
	end
	for _, beep in beeps do
		beep:Destroy()
	end
	if not stillLinked() then
		return
	end

	for _, body in fused do
		local centre = LabConfig.limbCentre(body, limbKey)
		local humanoid = body:FindFirstChildOfClass("Humanoid")
		if centre and humanoid then
			Booms.at(centre)
			if FATAL[limbKey] then
				humanoid.Health = 0
			else
				local parts = LabConfig.limbParts(body, limbKey)
				local joint = LabConfig.limbJoint(body, limbKey)
				if joint then
					joint:Destroy()
				end
				for _, part in parts do
					part.Anchored = false
					part.CanCollide = true
					part.Parent = workspace
					Debris:AddItem(part, LabConfig.LOST_LIMB_SECONDS)
				end
				humanoid.Health -= LabConfig.LIMB_DAMAGE
			end
		end
	end
end

return HardDriveEffects
