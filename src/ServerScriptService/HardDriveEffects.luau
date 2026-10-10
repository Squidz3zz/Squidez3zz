-- HardDriveEffects: what each Harddrive does once Bob has injected it. One function per Harddrive id (the ids in
-- LabConfig.HardDrives), named exactly like the id. LabServer calls it in its own thread as the needle leaves the limb, with
-- the bodies to apply it to (the owner's copy and the owner's character, at once, so the two stay the same), the limb key and
-- stillLinked: a function that turns false when the room is released, the copy is replaced or either body dies. An effect that
-- takes time checks it as it goes and stops, with nothing done, once it is false. Health they take goes through Gore.hurt, so
-- the gore system's big-hit watcher does not count it as a hit.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
-- With a timeout, so a missing Booms fails this module's load (LabServer then refuses injections) instead of hanging LabServer.
local Booms = require(ServerScriptService:WaitForChild("Booms", 5))
-- The gore system. Without it the Explosive blows limbs off itself, as it did before Gore.
local goreLoaded, Gore = pcall(require, ServerScriptService:WaitForChild("Gore", 5))
if not goreLoaded then
	warn("HardDriveEffects: Gore did not load, so the Explosive blows limbs off without it: " .. tostring(Gore))
	Gore = nil
end
local GoreConfig = if Gore then require(ReplicatedStorage:WaitForChild("GoreConfig")) else nil

local FUSE_RED = Color3.fromRGB(255, 30, 20)
-- The fuse's blink (one glow and one beep) comes every BLINK_FIRST seconds at the start, speeding up to every BLINK_LAST.
local BLINK_FIRST = 0.6
local BLINK_LAST = 0.12
-- Losing these is always fatal; any other limb falls off.
local FATAL = { Head = true, Torso = true }
-- Without Gore, a blown-off arm or leg is flung by Roblox physics: off in a random direction, 20 to 60 degrees above level, at a
-- random speed in FLING_SPEED (studs per second), spinning at up to FLING_SPIN radians per second.
local FLING_SPEED = NumberRange.new(15, 30)
local FLING_SPIN = 15

local random = Random.new()
local goreWarned = false

local HardDriveEffects = {}

-- Gore[fnName](...), pcall'd: false when Gore is missing or the call failed (the first failure warns).
local function gore(fnName: string, ...: any): boolean
	if not Gore then
		return false
	end
	local ok, err = pcall(Gore[fnName], ...)
	if not ok and not goreWarned then
		goreWarned = true
		warn("HardDriveEffects: Gore." .. fnName .. " failed: " .. tostring(err))
	end
	return ok
end

local function hurt(body: Model, humanoid: Humanoid, amount: number)
	if not gore("hurt", body, amount) then
		humanoid.Health = math.max(0, humanoid.Health - amount)
	end
end

-- The Explosive without Gore (and at GoreConfig GORE_LEVEL 0): the arm or leg comes off and is flung; the server owns it from
-- then on (so the owner's own limb flies the same), and it goes after LabConfig.LOST_LIMB_SECONDS.
local function blowOff(body: Model, limbKey: string)
	local torso = body:FindFirstChild("Torso")
	-- Found by name: a Motor6D, or the socket a Broken limb hangs from.
	local joint = torso and torso:FindFirstChild(LabConfig.Limbs[limbKey].joint)
	if joint then
		joint:Destroy()
	end
	for _, part in LabConfig.limbParts(body, limbKey) do
		part.Anchored = false
		part.CanCollide = true
		part.Parent = workspace
		pcall(part.SetNetworkOwner, part, nil)
		local heading, climb = random:NextNumber(0, 2 * math.pi), math.rad(random:NextNumber(20, 60))
		local direction = Vector3.new(math.cos(heading) * math.cos(climb), math.sin(climb), math.sin(heading) * math.cos(climb))
		part.AssemblyLinearVelocity = direction * random:NextNumber(FLING_SPEED.Min, FLING_SPEED.Max)
		part.AssemblyAngularVelocity = random:NextUnitVector() * random:NextNumber(0, FLING_SPIN)
		Debris:AddItem(part, LabConfig.LOST_LIMB_SECONDS)
	end
end

local function sfxGroup(): SoundGroup
	local group = SoundService:FindFirstChild("SFX")
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = "SFX"
		group.Parent = SoundService
	end
	return group :: SoundGroup
end

-- Explosive: a fuse of FUSE_SECONDS (the limb glows red and beeps, faster and faster), then a blast at the limb: a blood boom
-- (Booms.at with blood, spraying away from the body) at each body's limb centre (taken before anything comes off; no Explosion
-- instance). An arm or a leg
-- costs the body LIMB_DAMAGE health; the head or the torso kills.
-- Through Gore (GORE_LEVEL 1 or 2) the blast is Gore.blastLimb(EXPLOSIVE_POWER) on the first body's (the copy's) injected limb
-- and nothing else: no radius, so the torso, the head and the other limbs are untouched; the injected arm or leg always
-- breaks (dangling, or ripped off by chance), and the copy's link to its owner gives the owner exactly the same (blasting both
-- bodies would hit the owner twice).
-- Without Gore, or at GORE_LEVEL 0, it is the blast from before Gore: each body's arm or leg is flung off and nothing else is hurt.
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

	local centres: { [Model]: Vector3 } = {}
	for _, body in fused do
		local centre = LabConfig.limbCentre(body, limbKey)
		centres[body] = centre
		local torso = body:FindFirstChild("Torso")
		if centre and torso then
			-- The blood sprays away from the body: from the torso out through an arm or a leg, the way the body faces for the
			-- head or the torso.
			local away = centre - torso.Position
			Booms.at(centre, true, if FATAL[limbKey] or away.Magnitude < 0.1 then torso.CFrame.LookVector else away.Unit)
		elseif centre then
			Booms.at(centre, true)
		end
	end
	local first = fused[1]
	local exploded = GoreConfig ~= nil
		and GoreConfig.get("GORE_LEVEL") ~= 0
		and first ~= nil
		and centres[first] ~= nil
		and gore("blastLimb", first, limbKey, GoreConfig.get("EXPLOSIVE_POWER"))
	for _, body in fused do
		local humanoid = body:FindFirstChildOfClass("Humanoid")
		if centres[body] and humanoid then
			if FATAL[limbKey] then
				hurt(body, humanoid, math.huge)
			else
				if not exploded then
					blowOff(body, limbKey)
				end
				hurt(body, humanoid, LabConfig.LIMB_DAMAGE)
			end
		end
	end
end

return HardDriveEffects
