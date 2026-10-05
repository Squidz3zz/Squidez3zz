-- VolumeSlider: a draggable music volume slider.
-- attach(slider, group) wires mouse/touch dragging on `slider` (a Frame holding Fill and Knob Frames) to group.Volume.
-- setAlpha(slider, group, alpha) is the only place the volume and the visuals change: dragging calls it, and so do
-- the tests. It acts only on the Instances it is given and keeps no state of its own.
--
-- It works in a ScreenGui and in a SurfaceGui (the settings board). The two report the pointer differently: events
-- on a GUI element carry positions in that GUI's own space (screen pixels in a ScreenGui, canvas pixels in a
-- SurfaceGui), which is also what AbsolutePosition is in. UserInputService events always carry screen pixels, so
-- they only line up with a ScreenGui. In a SurfaceGui a drag therefore listens to a transparent Frame laid over the
-- whole canvas for its duration: it gets every move over the board in canvas pixels, like the element does.
local UserInputService = game:GetService("UserInputService")

-- Above everything else in the SurfaceGui, whatever ZIndexBehavior it uses.
local CATCHER_Z_INDEX = 100000

local VolumeSlider = {}

function VolumeSlider.setAlpha(slider, group, alpha)
	alpha = math.clamp(alpha, 0, 1)
	group.Volume = alpha

	local fill = slider.Fill
	local knob = slider.Knob
	-- Only the X scale follows alpha; the rest of the layout stays as designed.
	fill.Size = UDim2.new(UDim.new(alpha, fill.Size.X.Offset), fill.Size.Y)
	knob.Position = UDim2.new(UDim.new(alpha, knob.Position.X.Offset), knob.Position.Y)
end

-- `input` comes from an event of the slider's own GUI (or of a Frame in the same GUI), so its Position is in the
-- same space as the slider's AbsolutePosition.
local function alphaAt(slider, input)
	return (input.Position.X - slider.AbsolutePosition.X) / slider.AbsoluteSize.X
end

function VolumeSlider.attach(slider, group)
	VolumeSlider.setAlpha(slider, group, group.Volume)

	local dragging = false

	local function startDrag(input)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		-- The slider and its knob both report the press, so a drag already running ignores the second report.
		if dragging or not (isMouse or isTouch) then
			return
		end
		dragging = true
		VolumeSlider.setAlpha(slider, group, alphaAt(slider, input))

		local changedConnection, endedConnection
		local catcher = nil
		local surfaceGui = slider:FindFirstAncestorWhichIsA("SurfaceGui")

		-- A mouse drag follows the cursor; a touch drag follows the finger that started it. A SurfaceGui hands out its
		-- own InputObjects, so there a touch is matched by type: the board has one finger down at a time.
		local function samePointer(other)
			return other == input or (surfaceGui ~= nil and other.UserInputType == Enum.UserInputType.Touch)
		end
		local function follows(changed)
			if isMouse then
				return changed.UserInputType == Enum.UserInputType.MouseMovement
			end
			return samePointer(changed)
		end

		if surfaceGui then
			catcher = Instance.new("Frame")
			catcher.Name = "VolumeSliderDragCatcher"
			catcher.Size = UDim2.fromScale(1, 1)
			catcher.BackgroundTransparency = 1
			catcher.BorderSizePixel = 0
			catcher.Active = true
			catcher.ZIndex = CATCHER_Z_INDEX
			catcher.Parent = surfaceGui
			changedConnection = catcher.InputChanged:Connect(function(changed)
				if follows(changed) then
					VolumeSlider.setAlpha(slider, group, alphaAt(slider, changed))
				end
			end)
		else
			changedConnection = UserInputService.InputChanged:Connect(function(changed)
				if follows(changed) then
					VolumeSlider.setAlpha(slider, group, alphaAt(slider, changed))
				end
			end)
		end
		endedConnection = UserInputService.InputEnded:Connect(function(ended)
			local releases = if isMouse then ended.UserInputType == Enum.UserInputType.MouseButton1 else samePointer(ended)
			if releases then
				changedConnection:Disconnect()
				endedConnection:Disconnect()
				if catcher then
					catcher:Destroy()
				end
				dragging = false
			end
		end)
	end

	slider.InputBegan:Connect(startDrag)
	slider.Knob.InputBegan:Connect(startDrag)
end

return VolumeSlider
