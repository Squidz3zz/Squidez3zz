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
--   Flesh.stub(body, key)   for an arm or a leg being severed: its Death set (the bone stub, Stub1) is welded to the Torso where
--                           the limb rests (from the joint, a Motor6D's C0 * C1:Inverse(), or a dangling limb's socket). Call it
--                           before the joint goes.
-- Only at GoreConfig GORE_LEVEL 2. At 1 nothing is welded or hidden, and a severed limb leaves a plain dark-red block (GoreStump)
-- at the joint instead of the stub; at 0 nothing at all. A body that has lost its parts (a dead body emptied into its corpse)
-- is skipped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig", 5) or error("Gore: GoreConfig is missing"))
local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig", 5) or error("Gore: LabConfig is missing"))

local FOLDER = "GoreFlesh"
-- Level 1's stump: a slab across the top end of the limb (an R6 arm or leg is 2 studs long), flush with the joint.
local STUMP_SIZE = Vector3.new(1, 0.3, 1)
local STUMP_COLOR = Color3.fromRGB(95, 12, 12)

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
