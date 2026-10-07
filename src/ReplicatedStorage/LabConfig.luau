-- LabConfig: the one place to edit Room 1's injection lab: how long things take, how much they hurt, the sound ids and the list
-- of Harddrives on the tablet. It also holds the limb table and the small helpers that read it. It lives in ReplicatedStorage
-- because both sides need it: the server (the rules, the timing and the effects) and every player's client (Bob's animation,
-- the tablet menu and the death screen).
--
-- Numbers (seconds unless it says otherwise):
--   RESPAWN_TIME       how long a player stays dead before respawning. The server copies it into Players.RespawnTime at startup,
--                      and the death screen fades its ringing out over the same time.
--   LIMB_DAMAGE        health taken from the player and from their copy when Explosive blows off an arm or a leg (health, not
--                      seconds). A head or torso hit is always fatal, whatever this says.
--   FUSE_SECONDS       Explosive's fuse: from the needle leaving the limb to the blast. Keep it above 0.
--   LOST_LIMB_SECONDS  how long a blown-off limb lies on the floor before it disappears.
--   FOLLOW_DISTANCE    how far (studs) Bob keeps from a player he follows with his eyes when they walk into the room.
--   Timings            how long each part of an injection takes. Keep every one above 0. The keys are fixed, change only the
--                      numbers. Bob is busy (and the tablet is read-only) for the sum of all five.
--                        Move       Bob's trip from where he is to the injection spot
--                        NeedleOut  the needle sliding into the limb
--                        Hold       the needle staying in (the hiss plays now)
--                        NeedleIn   the needle sliding back out
--                        Return     Bob's trip home
--
-- Sounds: the keys are fixed (the lab looks them up by name); change only the asset ids, each written as "rbxassetid://123456".
-- All of them play in the SFX SoundGroup (so the Sound Effects slider applies), except DeathRing, which has no group so it stays
-- audible while everything else is silenced on death.
--   DeathRing   the ear ringing on the death screen
--   FuseBeep    Explosive's fuse, speeding up until the blast
--   NeedleHiss  while the needle is held in the limb
--   BobMotor    loops while Bob is moving (louder the faster he goes)
--
-- HardDrives: what the tablet lists, in this order. name is the label on the tablet (keep it UPPERCASE and short). id must match
-- a function of the same name in ServerScriptService.HardDriveEffects and a picture under ReplicatedStorage.LabAssets.HardDrives,
-- so a new Harddrive needs both of those too, not only a line here.
--
-- The limb table (LIMB_KEYS and Limbs): you should not need to edit this. The six limb keys are the R6 names. A body may be R6
-- or R15, so Limbs says, per rig, which parts make up each limb (parts, by name in the body) and which joint holds it on (joint
-- = the part the joint sits in, then the joint's name; none for the torso). A limb is "lost" when its joint no longer exists, or
-- when none of its parts are left in the body. These helpers read the table; everything else asks them instead of looking at
-- the body itself:
--   LabConfig.rigOf(body)           "R6" or "R15", from the body's Humanoid
--   LabConfig.limbParts(body, key)  the limb's parts that are still in the body ({} for an unknown key or a missing limb)
--   LabConfig.limbJoint(body, key)  the joint holding the limb on, or nil (the torso has none, and a lost limb's is gone). It is a
--                                   Motor6D, or an AnimationConstraint: the R15 bodies Roblox builds from a HumanoidDescription use
--                                   those instead (same names)
--   LabConfig.isLost(body, key)     true when the limb is lost (an unknown key counts as lost). The torso is never lost while it is
--                                   in the body
--   LabConfig.limbCentre(body, key) the middle of the box around the limb's parts (a Vector3), or nil when it is lost
local LabConfig = {
	RESPAWN_TIME = 5,
	LIMB_DAMAGE = 20,
	FUSE_SECONDS = 3,
	LOST_LIMB_SECONDS = 10,
	FOLLOW_DISTANCE = 6,

	Timings = { Move = 2, NeedleOut = 0.4, Hold = 1, NeedleIn = 0.4, Return = 1.5 },

	Sounds = {
		DeathRing = "rbxassetid://9069161602",
		FuseBeep = "rbxassetid://118464872816736",
		NeedleHiss = "rbxassetid://8375254457",
		BobMotor = "rbxassetid://18627683806",
	},

	HardDrives = {
		{ id = "Explosive", name = "EXPLOSIVE" },
	},

	LIMB_KEYS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" },

	Limbs = {
		R6 = {
			Head = { parts = { "Head" }, joint = { "Torso", "Neck" } },
			Torso = { parts = { "Torso" } },
			LeftArm = { parts = { "Left Arm" }, joint = { "Torso", "Left Shoulder" } },
			RightArm = { parts = { "Right Arm" }, joint = { "Torso", "Right Shoulder" } },
			LeftLeg = { parts = { "Left Leg" }, joint = { "Torso", "Left Hip" } },
			RightLeg = { parts = { "Right Leg" }, joint = { "Torso", "Right Hip" } },
		},
		R15 = {
			Head = { parts = { "Head" }, joint = { "Head", "Neck" } },
			Torso = { parts = { "UpperTorso", "LowerTorso" } },
			LeftArm = {
				parts = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
				joint = { "LeftUpperArm", "LeftShoulder" },
			},
			RightArm = {
				parts = { "RightUpperArm", "RightLowerArm", "RightHand" },
				joint = { "RightUpperArm", "RightShoulder" },
			},
			LeftLeg = {
				parts = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
				joint = { "LeftUpperLeg", "LeftHip" },
			},
			RightLeg = {
				parts = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
				joint = { "RightUpperLeg", "RightHip" },
			},
		},
	},
}

function LabConfig.rigOf(body)
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
end

-- The table's entry for this body's rig and this key, or nil for an unknown key.
local function specOf(body, key)
	return LabConfig.Limbs[LabConfig.rigOf(body)][key]
end

function LabConfig.limbParts(body, key)
	local parts = {}
	local spec = specOf(body, key)
	if spec then
		for _, name in spec.parts do
			local part = body:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
	end
	return parts
end

function LabConfig.limbJoint(body, key)
	local spec = specOf(body, key)
	if not (spec and spec.joint) then
		return nil
	end
	local holder = body:FindFirstChild(spec.joint[1])
	local joint = holder and holder:FindFirstChild(spec.joint[2])
	return if joint and (joint:IsA("JointInstance") or joint:IsA("AnimationConstraint")) then joint else nil
end

function LabConfig.isLost(body, key)
	local spec = specOf(body, key)
	if not spec or #LabConfig.limbParts(body, key) == 0 then
		return true
	end
	return spec.joint ~= nil and LabConfig.limbJoint(body, key) == nil
end

function LabConfig.limbCentre(body, key)
	if LabConfig.isLost(body, key) then
		return nil
	end
	-- The box is aligned to the world axes: each part adds the extent of its own (turned) box.
	local low, high
	for _, part in LabConfig.limbParts(body, key) do
		local cf, size = part.CFrame, part.Size
		local half = (cf.RightVector:Abs() * size.X + cf.UpVector:Abs() * size.Y + cf.LookVector:Abs() * size.Z) / 2
		low = if low then low:Min(cf.Position - half) else cf.Position - half
		high = if high then high:Max(cf.Position + half) else cf.Position + half
	end
	return (low + high) / 2
end

return LabConfig
