-- CharacterPreview: shows a copy of the player's avatar in the menu's ViewportFrame, idling and facing the
-- camera, and waves when it appears and again every WAVE_INTERVAL seconds for as long as the menu shows it. The camera
-- shows the avatar from the waist up.
-- show(viewport, source) returns the clone, or nil if the viewport was already destroyed.
-- clonePosed and playIdle are the two halves of "a still copy of an avatar that idles": show uses them for the menu, and
-- CreditsRoom uses them for the avatars standing in the Credits room (which do not wave).

-- Seconds between the starts of two waves. The wave clip is 2 to 3 s long, so the avatar idles in between.
local WAVE_INTERVAL = 6
local CAMERA_FOV = 30
-- The shot is a window on the avatar, not a margin around it: its bottom edge sits just under the waist (the bottom of
-- Torso, or of LowerTorso on R15) and its top edge is above the head, high enough for the hand the wave raises. The
-- three numbers are fractions of the upper-body height (torso bottom to head top). The menu's CharacterView is 1.3
-- times as wide as it is tall (see studio/build_main_menu_ui.luau); measured over a looping wave on R6 and R15 (default
-- and the real avatar), in a frame of that shape, the arms stay within 0.91 (R6) to 0.97 (R15) of the half-width, the
-- hand R6 raises within 0.91 of the half-height, and the head within 0.53 and 0.49 of them.
local WAIST_MARGIN = 0.05
local HAND_ROOM = 0.45
local WINDOW_SLACK = 1.06
-- Only one arm swings out, so the aim moves toward its side, along the avatar's right, by this fraction of the
-- upper-body height. R6 waves with its right arm and reaches 3.0 studs out on that side but only 2.3 on the other;
-- R15 swings its arms out about equally (3.1 and 3.2), so it gets none.
local AIM_SHIFT = { R6 = 0.12, R15 = 0 }

-- Fallbacks for models that carry no Animate script (the idle is read from Animate when there is one).
local ANIMATIONS = {
	R15 = { idle = "rbxassetid://507766666", wave = "rbxassetid://507770239" },
	R6 = { idle = "rbxassetid://180435571", wave = "rbxassetid://128777973" },
}

-- Loads and plays one animation and returns its track. A failure leaves the bind pose, warns, returns nil and never throws.
local function playAnimation(animator, animationId, looped, priority)
	local ok, result = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local track = animator:LoadAnimation(animation)
		track.Looped = looped
		track.Priority = priority
		track:Play()
		return track
	end)
	if not ok then
		warn("CharacterPreview: could not play " .. animationId .. ": " .. tostring(result))
		return nil
	end
	return result
end

-- Plays `track` (the wave the avatar already waved with) again every WAVE_INTERVAL seconds, until `clone` has left the
-- game (Play destroyed the menu, or the viewport went). Reusing the one track keeps tracks from piling up on the Animator.
-- Meant for a thread of its own: it waits. The clone is checked before each replay and the replay is guarded, so it ends
-- quietly once the menu is gone.
local function repeatWave(clone, track)
	while true do
		task.wait(WAVE_INTERVAL)
		if not clone:IsDescendantOf(game) then
			return
		end
		local ok, err = pcall(track.Play, track)
		if not ok then
			warn("CharacterPreview: could not replay the wave: " .. tostring(err))
			return
		end
	end
end

-- The idle the player's own Animate script would use, or nil if the model has none.
local function readIdleId(model)
	local animate = model:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	local animation = idle and idle:FindFirstChild("Animation1")
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return animation.AnimationId
	end
	return nil
end

-- The Humanoid's Animator (made if it has none) and the fallback animation ids for its rig.
local function animationTools(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator, ANIMATIONS[humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"]
end

-- The point the camera aims at (the middle of the window) and the window's height in studs. Measured on the model as it
-- stands (upright, at the origin). Falls back to the whole model, with a margin, if it lacks a torso or a head.
local function shotWindow(clone, rootPart, rigName)
	local torso = clone:FindFirstChild("LowerTorso") or clone:FindFirstChild("Torso")
	local head = clone:FindFirstChild("Head")
	if torso and torso:IsA("BasePart") and head and head:IsA("BasePart") then
		local bottom = torso.Position.Y - torso.Size.Y / 2
		local top = head.Position.Y + head.Size.Y / 2
		if top > bottom then
			local height = top - bottom
			local windowBottom = bottom - WAIST_MARGIN * height
			local windowTop = top + HAND_ROOM * height
			local aim = Vector3.new(rootPart.Position.X, (windowTop + windowBottom) / 2, rootPart.Position.Z)
				+ rootPart.CFrame.RightVector * (AIM_SHIFT[rigName] * height)
			return aim, windowTop - windowBottom
		end
	end
	local boxCFrame, boxSize = clone:GetBoundingBox()
	return boxCFrame.Position, boxSize.Y * 1.4
end

local CharacterPreview = {}

-- A copy of `source` that stands still: no Animate script (a LocalScript, it would run wherever the copy goes),
-- anchored root, the root as the pivot (so the pivot and the bounding box are oriented like the root, not like the Head).
-- Returns the copy, not yet parented, and the idle animation id its Animate script used (nil if it had none).
function CharacterPreview.clonePosed(source)
	local clone = source:Clone()
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart) then
		clone:Destroy()
		error("CharacterPreview: source has no Humanoid / HumanoidRootPart")
	end

	local idleId = readIdleId(clone)
	local animate = clone:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	rootPart.Anchored = true
	clone.PrimaryPart = rootPart
	return clone, idleId
end

-- Plays the idle on loop. Call it once the copy is parented to a WorldModel or to Workspace: an animation needs that.
-- A failure leaves the bind pose and never throws.
function CharacterPreview.playIdle(clone, idleId)
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator, fallback = animationTools(humanoid)
	playAnimation(animator, idleId or fallback.idle, true, Enum.AnimationPriority.Idle)
end

function CharacterPreview.show(viewport, source)
	-- Play may have destroyed the menu while the avatar was still on its way.
	if not viewport:IsDescendantOf(game) then
		return nil
	end

	local clone, idleId = CharacterPreview.clonePosed(source)
	local rootPart = clone.PrimaryPart
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport.WorldModel

	-- Measured after parenting: accessory welds only settle once the model is in the WorldModel.
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rigName = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	local aim, windowHeight = shotWindow(clone, rootPart, rigName)
	local distance = (windowHeight * WINDOW_SLACK / 2) / math.tan(math.rad(CAMERA_FOV / 2))
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = CAMERA_FOV
	camera.CFrame = CFrame.lookAt(aim + rootPart.CFrame.LookVector * distance, aim)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	CharacterPreview.playIdle(clone, idleId)
	local animator, fallback = animationTools(humanoid)
	local wave = playAnimation(animator, fallback.wave, false, Enum.AnimationPriority.Action)
	if wave then
		-- Its own thread: show never yields.
		task.spawn(repeatWave, clone, wave)
	end

	return clone
end

return CharacterPreview
