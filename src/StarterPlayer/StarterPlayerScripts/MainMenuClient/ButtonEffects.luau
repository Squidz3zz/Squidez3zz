-- ButtonEffects: hover/press "pop" for the menu buttons.
-- attach(button, opts?) adds a UIScale (PopScale) and a UIStroke (PopStroke) to the button and wires the input events.
-- opts.onHover (optional) is called, with no arguments and in pcall, each time the button goes from idle to hover: the
-- mouse entering it, a controller selecting it or a finger landing on it. Not when it is hovered again while it already
-- is, not on a press, and not when the hover comes back after a press while the cursor is still over it. The menu uses it
-- for the hover sound (ButtonSounds.hover).
-- opts.strokeColor (optional, a Color3) is the colour of the hover outline: the menu passes the theme's hoverStroke. Without
-- it (or with anything that is not a Color3) the outline is the Factory amber, so an unthemed button looks as it always did.
-- setState(button, state) is the only place tweens happen: events call it, and so do the tests. It finds
-- PopScale/PopStroke on the button itself, so it works on any attached button, and does nothing (no error) on a button
-- that is not attached. The only thing it remembers is whether a button is idle (and its onHover), which is what turns
-- "hover" into a hover sound once and not on every event.
local TweenService = game:GetService("TweenService")

local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- The hover outline's colour when no theme colour is given (Factory amber, the same as MenuAssets.Themes.Factory.hoverStroke).
local FACTORY_STROKE = Color3.fromRGB(255, 150, 30)

local STATES = {
	idle = { scale = 1, strokeTransparency = 1 },
	hover = { scale = 1.1, strokeTransparency = 0 },
	press = { scale = 0.95, strokeTransparency = 0 },
}

local ButtonEffects = {}

-- Per button, weak so a destroyed button is not kept alive: its onHover callback, and whether it is out of idle
-- (hover or press) right now.
local hoverCallbacks = setmetatable({}, { __mode = "k" })
local engaged = setmetatable({}, { __mode = "k" })

function ButtonEffects.setState(button, state)
	local target = STATES[state]
	assert(target, "ButtonEffects.setState: unknown state " .. tostring(state))
	local popScale = button:FindFirstChild("PopScale")
	local popStroke = button:FindFirstChild("PopStroke")
	if not (popScale and popStroke) then
		-- Not attached (or its menu is gone): nothing to tween. A selection can still be lost while the menu is destroyed (a
		-- controller D-pad press during Play's fade selects a button, then root:Destroy() fires SelectionLost), so this is quiet.
		return
	end

	-- Playing a tween cancels any tween already running on the same property, so quick state changes never fight.
	TweenService:Create(popScale, TWEEN_INFO, { Scale = target.scale }):Play()
	TweenService:Create(popStroke, TWEEN_INFO, { Transparency = target.strokeTransparency }):Play()

	-- onHover fires on idle -> hover only. A press counts as out of idle too, so the hover that follows a press (the
	-- cursor is still over the button) is not a new hover.
	local wasIdle = not engaged[button]
	engaged[button] = if state == "idle" then nil else true
	local onHover = hoverCallbacks[button]
	if state == "hover" and wasIdle and onHover then
		local ok, err = pcall(onHover)
		if not ok then
			warn("ButtonEffects: onHover of " .. button:GetFullName() .. " failed: " .. tostring(err))
		end
	end
end

function ButtonEffects.attach(button, opts)
	if button:FindFirstChild("PopScale") then
		return
	end
	if opts and opts.onHover then
		hoverCallbacks[button] = opts.onHover
	end

	local popScale = Instance.new("UIScale")
	popScale.Name = "PopScale"
	popScale.Scale = STATES.idle.scale
	popScale.Parent = button

	local popStroke = Instance.new("UIStroke")
	popStroke.Name = "PopStroke"
	popStroke.Color = if opts and typeof(opts.strokeColor) == "Color3" then opts.strokeColor else FACTORY_STROKE
	popStroke.Thickness = 2
	popStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	popStroke.Transparency = STATES.idle.strokeTransparency
	popStroke.Parent = button

	local mouseOver = false

	button.MouseEnter:Connect(function()
		mouseOver = true
		ButtonEffects.setState(button, "hover")
	end)
	button.MouseLeave:Connect(function()
		mouseOver = false
		ButtonEffects.setState(button, "idle")
	end)
	button.SelectionGained:Connect(function()
		ButtonEffects.setState(button, "hover")
	end)
	button.SelectionLost:Connect(function()
		ButtonEffects.setState(button, "idle")
	end)
	button.MouseButton1Down:Connect(function()
		ButtonEffects.setState(button, "press")
	end)
	button.MouseButton1Up:Connect(function()
		ButtonEffects.setState(button, if mouseOver then "hover" else "idle")
	end)

	-- Touch has no cursor, so a finger down counts as hover and lifting it as idle.
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			ButtonEffects.setState(button, "hover")
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			ButtonEffects.setState(button, "idle")
		end
	end)
end

return ButtonEffects
