-- Flesh: the flesh, bone, ribcage, skull and stubs the gore system puts on bodies (it sits inside Gore, which calls it on every
-- state change; Gore's comments say when). The pieces are ServerStorage.Gore.Pieces, made by studio/build_gore.luau from the
-- user's FleshChart: <Limb>.<Set> Models of parts, each with the attribute Offset (where it sits on its R6 part).
--   Flesh.dress(body, key)  the limb's R6 part is hidden (Transparency 1, with its decals and the face, so its clothing goes too,
--                           and any accessory worn on it) and the pieces of the set it should wear are welded on, in a Folder
--                           named GoreFlesh inside the part (so they go wherever the part goes: off with a severed limb, into the
--                           corpse on death). Whatever it wore before is replaced, but only once the new set is welded: a
--                           missing or bad set errors before the body changes, so the limb keeps its skin (or its old
--                           flesh). The set, read from the body's attributes:
--                             an arm, a leg or the head, once not Intact  Variant<GoreVariant_<Limb>> (Variant1 flesh only,
--                                                                         Variant2 flesh and bone, or the head's skull)
--                             a destroyed head                            Death (flesh and skull), without the Skull when
--                                                                         GoreSkull is "blasted"
--                             a torn torso                                Sealed (with TorsoFilling) until GoreTorsoOpen, then
--                                                                         Open (no filling, the Ribcage showing)
--                             a destroyed torso                           Death (open, with the Ribcage)
--                           With all six limbs torn or worse each simply keeps its own set: FullBody.Variant1's pieces are the
--                           same flesh as every Variant1, and swapping a Variant2 limb to it would hide its bone again.
--                           A limb under clothing (a Shirt: arms and torso; Pants: legs and torso; never the head) also gets
--                           3-5 GoreScrap parts in the same folder: thin dark-red rags of that clothing near the joint end (an
--                           arm's or leg's top 35%, the torso's top edge for the Shirt and bottom edge for the Pants), just
--                           outside the part, each showing a patch of the limb's own front region of the classic template,
--                           tinted red. No clothing, or an empty template, means no scraps. They are cosmetic and use their
--                           own Random, so they never shift Gore's seeded chance rolls. Scraps that fail are dropped (with a
--                           warning, once) and the flesh goes on without them. In Studio, the attribute TestFailScraps on this
--                           module makes them fail after the first one, for tests.
--   Flesh.stub(body, key)   for an arm or a leg being severed: its Death set (the bone stub, Stub1) is welded to the Torso where
--                           the limb rests (from the joint, a Motor6D's C0 * C1:Inverse(), or a dangling limb's socket). Call it
--                           before the joint goes.
-- Only at GoreConfig GORE_LEVEL 2. At 1 nothing is welded or hidden, and a severed limb leaves a plain dark-red block (GoreStump)
-- at the joint instead of the stub; at 0 nothing at all. A body that has lost its parts (a dead body emptied into its corpse)
-- is skipped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig", 5) or error("Gore: GoreConfig is missing"))
local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig", 5) or error("Gore: LabConfig is missing"))

local FOLDER = "GoreFlesh"
-- Level 1's stump: a slab across the top end of the limb (an R6 arm or leg is 2 studs long), flush with the joint.
local STUMP_SIZE = Vector3.new(1, 0.3, 1)
local STUMP_COLOR = Color3.fromRGB(95, 12, 12)

-- Scraps. The classic clothing template is 585x559 pixels and an R6 body wears it at 64 pixels a stud (an arm's 1x2 front is
-- 64x128), so a Texture at that scale shows the fabric at its real size. A Texture's window on its face starts OffsetStuds from
-- the image's top-left corner (checked in Studio). Each covering: the clothing class, the left edge and top of the band the
-- patch comes from (the top 35% of the limb's front region, or the torso front's top or bottom 45 pixels), its width, and which
-- end of the part the scraps sit at (1 top, -1 bottom), and the X sign of its outer side (0 for the torso). Region coordinates:
-- the standard classic Shirt/Pants template.
local SCRAP_COLOR = Color3.fromRGB(60, 10, 10)
local SCRAP_TINT = Color3.fromRGB(215, 130, 130) -- light enough that the fabric's pattern shows through the red (ruling R1)
local PIXELS_PER_STUD = 64
local TILE_U, TILE_V = 585 / PIXELS_PER_STUD, 559 / PIXELS_PER_STUD
local SCRAP_MAX = 0.7
local COVERS = {
	RightArm = { { "Shirt", 217, 355, 64, 1, 1 } },
	LeftArm = { { "Shirt", 308, 355, 64, 1, -1 } },
	RightLeg = { { "Pants", 217, 355, 64, 1, 1 } },
	LeftLeg = { { "Pants", 308, 355, 64, 1, -1 } },
	Torso = { { "Shirt", 231, 74, 128, 1, 0 }, { "Pants", 231, 157, 128, -1, 0 } },
}
local rng = Random.new()
local scrapsWarned = false

local Flesh = {}

-- ServerStorage.Gore.Pieces.<key>.<setName>, or an error (before anything on the body has changed).
local function setNamed(key: string, setName: string): Instance
	local gore = ServerStorage:FindFirstChild("Gore")
	local pieces = gore and gore:FindFirstChild("Pieces")
	local group = pieces and pieces:FindFirstChild(key)
	local set = group and group:FindFirstChild(setName)
	return set or error(("Gore: ServerStorage.Gore.Pieces.%s.%s is missing (run studio/build_gore.luau)"):format(key, setName))
end

-- The set the limb wears now (nil while Intact), and a piece it leaves out.
local function setOf(body: Model, key: string): (string?, string?)
	local state = body:GetAttribute("Gore_" .. key)
	if state == nil or state == "Intact" then
		return nil, nil
	elseif key == "Torso" then
		return if state == "Destroyed" then "Death" elseif body:GetAttribute("GoreTorsoOpen") == true then "Open" else "Sealed", nil
	elseif key == "Head" and state == "Destroyed" then
		return "Death", if body:GetAttribute("GoreSkull") == "blasted" then "Skull" else nil
	end
	return "Variant" .. (body:GetAttribute("GoreVariant_" .. key) or 1), nil
end

-- Welds a clone of every piece in `set` (but `skip`) to `to`, at to.CFrame * at * Offset, into `parent`.
local function weld(set: Instance, to: BasePart, at: CFrame, parent: Instance, skip: string?)
	for _, source in set:GetChildren() do
		if source.Name == skip or not source:IsA("BasePart") then
			continue
		end
		local piece = source:Clone()
		local place = at * (source:GetAttribute("Offset") :: CFrame)
		piece.CFrame = to.CFrame * place
		local joint = Instance.new("Weld")
		joint.Part0 = to
		joint.Part1 = piece
		joint.C0 = place
		joint.Parent = piece
		piece.Parent = parent
	end
end

local function hide(body: Model, part: BasePart)
	part.Transparency = 1
	for _, thing in part:GetChildren() do
		if thing:IsA("Decal") then -- the face too; a Texture is a Decal
			thing.Transparency = 1
		end
	end
	for _, accessory in body:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		local joint = handle and handle:FindFirstChildWhichIsA("JointInstance")
		if joint and (joint.Part0 == part or joint.Part1 == part) then
			handle.Transparency = 1
		end
	end
end

-- Where the limb rests, in the Torso's space, or nil when its joint is gone.
local function restOf(torso: BasePart, key: string): CFrame?
	local joint = torso:FindFirstChild(LabConfig.Limbs[key].joint or "")
	if joint and joint:IsA("Motor6D") then
		return joint.C0 * joint.C1:Inverse()
	elseif joint and joint:IsA("BallSocketConstraint") and joint.Attachment0 and joint.Attachment1 then
		return joint.Attachment0.CFrame * joint.Attachment1.CFrame:Inverse()
	end
	return nil
end

-- Welds 3-5 GoreScrap rags of the clothing covering `key` (if any) to `part`, into `parent`.
local function scraps(body: Model, key: string, part: BasePart, parent: Instance)
	local worn = {}
	for _, cover in COVERS[key] or {} do
		local clothing = body:FindFirstChildOfClass(cover[1])
		local template = clothing and (clothing :: any)[cover[1] .. "Template"]
		if template and template ~= "" then
			table.insert(worn, { template, cover })
		end
	end
	if #worn == 0 then
		return
	end
	local half = part.Size / 2
	for _ = 1, rng:NextInteger(3, 5) do
		local template, cover = table.unpack(worn[rng:NextInteger(1, #worn)])
		local _, x, y, width, edge, outer = table.unpack(cover)
		-- A wedge's triangles are its Left and Right faces, so it is thin along X; a block is thin along Z.
		local wedge = rng:NextNumber() < 0.5
		local a, b = rng:NextNumber(0.3, SCRAP_MAX), rng:NextNumber(0.3, SCRAP_MAX)
		local scrap = Instance.new(if wedge then "WedgePart" else "Part") :: BasePart
		scrap.Name = "GoreScrap"
		scrap.Size = if wedge then Vector3.new(0.05, a, b) else Vector3.new(a, b, 0.05)
		scrap.Color = SCRAP_COLOR
		scrap.Material = Enum.Material.Fabric
		scrap.Massless = true
		scrap.CanCollide = false
		scrap.CanQuery = false
		scrap.CanTouch = false
		scrap.CastShadow = false
		local offsetU = (x + rng:NextNumber() * (width - SCRAP_MAX * PIXELS_PER_STUD)) / PIXELS_PER_STUD
		for _, face in if wedge then { Enum.NormalId.Left, Enum.NormalId.Right } else { Enum.NormalId.Front, Enum.NormalId.Back } do
			local texture = Instance.new("Texture")
			texture.Face = face
			texture.Texture = template
			texture.Color3 = SCRAP_TINT
			texture.StudsPerTileU = TILE_U
			texture.StudsPerTileV = TILE_V
			texture.OffsetStudsU = offsetU
			texture.OffsetStudsV = y / PIXELS_PER_STUD
			texture.Parent = scrap
		end
		-- On the front, the back or (an arm or a leg) the outer side, never a side pressed against the torso or the other leg;
		-- near the joint end, 0.05-0.15 studs out, turned at random about the side's normal.
		local pick = rng:NextInteger(1, if outer == 0 then 2 else 3)
		local side = if pick == 1 then Vector3.zAxis elseif pick == 2 then -Vector3.zAxis else Vector3.xAxis * outer
		local across = if side.X ~= 0 then Vector3.zAxis else Vector3.xAxis
		local at = side * (math.abs(side:Dot(half)) + rng:NextNumber(0.05, 0.15))
			+ Vector3.yAxis * (edge * half.Y * rng:NextNumber(0.45, 0.85))
			+ across * (across:Dot(half) * rng:NextNumber(-0.6, 0.6))
		local place = CFrame.lookAt(at, at + side)
			* CFrame.Angles(0, 0, rng:NextNumber(0, 2 * math.pi))
			* CFrame.Angles(0, if wedge then math.pi / 2 else 0, 0) -- the thin axis along the normal
		scrap.CFrame = part.CFrame * place
		local joint = Instance.new("Weld")
		joint.Part0 = part
		joint.Part1 = scrap
		joint.C0 = place
		joint.Parent = scrap
		scrap.Parent = parent
		if RunService:IsStudio() and script:GetAttribute("TestFailScraps") then
			error("TestFailScraps is set")
		end
	end
end

function Flesh.dress(body: Model, key: string)
	local part = LabConfig.limbParts(body, key)[1]
	local setName, skip = setOf(body, key)
	if GoreConfig.get("GORE_LEVEL") < 2 or not (part and setName) then
		return
	end
	-- Built off the body first: missing or bad pieces fail here, and the limb keeps what it had (its skin, or its old flesh).
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	weld(setNamed(key, setName), part, CFrame.identity, folder, skip)
	-- Scraps are trim: if they fail, the flesh still goes on, without any of them.
	local ok, err = pcall(scraps, body, key, part, folder)
	if not ok then
		for _, child in folder:GetChildren() do
			if child.Name == "GoreScrap" then
				child:Destroy()
			end
		end
		if not scrapsWarned then
			scrapsWarned = true
			warn("Gore: torn cloth scraps failed, the flesh goes on without them: " .. tostring(err))
		end
	end
	local old = part:FindFirstChild(FOLDER)
	if old then
		old:Destroy()
	end
	hide(body, part)
	folder.Parent = part
end

function Flesh.stub(body: Model, key: string)
	local level = GoreConfig.get("GORE_LEVEL")
	local torso = body:FindFirstChild("Torso")
	local rest = torso and torso:IsA("BasePart") and restOf(torso, key)
	if level < 1 or not rest then
		return
	end
	if level >= 2 then
		weld(setNamed(key, "Death"), torso, rest, torso)
		return
	end
	local stump = Instance.new("Part")
	stump.Name = "GoreStump"
	stump.Size = STUMP_SIZE
	stump.Color = STUMP_COLOR
	stump.Material = Enum.Material.SmoothPlastic
	stump.CanCollide = false
	stump.Massless = true
	local place = rest * CFrame.new(0, 1 - STUMP_SIZE.Y / 2, 0)
	stump.CFrame = torso.CFrame * place
	local joint = Instance.new("Weld")
	joint.Part0 = torso
	joint.Part1 = stump
	joint.C0 = place
	joint.Parent = stump
	stump.Parent = torso
end

return Flesh
