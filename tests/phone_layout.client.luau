-- Run in the Client datamodel of a playtest; the menu does not have to be open (it measures clones of the
-- ReplicatedStorage.MainMenu template, so hover pops and scene changes in the live menu cannot skew it).
-- Simulates screens by cloning Root and Back into a Frame of a temporary ScreenGui in PlayerGui. Both are all Scale,
-- so they reflow to the Frame. At each size it reads the rectangles of Title, Buttons and CharacterView and checks that
--   * they stay inside the screen and do not overlap each other,
--   * the Play / Settings / Credits buttons are at least MIN_BUTTON_SIZE px tall and wide, stay inside their
--     Buttons frame and do not overlap each other,
--   * the BACK button (hidden in the template, made Visible in the clone) is at least MIN_BUTTON_SIZE px tall and
--     wide and stays inside the screen,
--   * on the landscape phone, the Title starts below Roblox's topbar (where the menu and chat icons sit).
-- Asserted: phone landscape (844x390, an iPhone 14) and the current window. Portrait (390x844) is only reported
-- (printed), because Roblox phones play in landscape.
-- KEEP = true leaves the landscape simulation on screen for a screen_capture; run again with KEEP = false to clean up.
local KEEP = false

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MIN_BUTTON_SIZE = 40
local EPSILON = 0.5 -- px of rounding slack
-- Bottom of the topbar band on a phone in landscape, in px. GuiService.TopbarInset describes the real window (the
-- simulated frame has no topbar of its own), so the Title must clear whichever of the two is larger.
local PHONE_TOPBAR_BOTTOM = 58

local TEST_GUI_NAME = "PhoneLayoutTest"

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local template = ReplicatedStorage:FindFirstChild("MainMenu")
assert(template and template:FindFirstChild("Root"), "ReplicatedStorage.MainMenu.Root missing")
assert(template:FindFirstChild("Back"), "ReplicatedStorage.MainMenu.Back missing")

local function removeTestGuis()
	for _, child in playerGui:GetChildren() do
		if child.Name == TEST_GUI_NAME then
			child:Destroy()
		end
	end
end
removeTestGuis()

local function overlaps(a, b)
	return a.x < b.x + b.w - EPSILON and b.x < a.x + a.w - EPSILON and a.y < b.y + b.h - EPSILON and b.y < a.y + a.h - EPSILON
end

local function inside(inner, outer)
	return inner.x >= outer.x - EPSILON
		and inner.y >= outer.y - EPSILON
		and inner.x + inner.w <= outer.x + outer.w + EPSILON
		and inner.y + inner.h <= outer.y + outer.h + EPSILON
end

local function describe(rect)
	return ("(%.0f,%.0f %.0fx%.0f)"):format(rect.x, rect.y, rect.w, rect.h)
end

-- Builds the simulated screen, measures it and returns { problems = {string}, details = string }.
-- checkTopbar: also require the Title to start below the topbar.
local function measure(label, size, keep, checkTopbar)
	local gui = Instance.new("ScreenGui")
	gui.Name = TEST_GUI_NAME
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Size = size
	screen.BackgroundColor3 = Color3.fromRGB(30, 60, 90)
	screen.BorderSizePixel = 0
	screen.Parent = gui
	local root = template.Root:Clone()
	root.Parent = screen
	-- BACK starts hidden (only the room scenes show it); show it so it gets a layout to measure.
	local back = template.Back:Clone()
	back.Visible = true
	back.Parent = screen
	gui.Parent = playerGui

	-- Layout (UIListLayout, aspect ratios) settles over the next frames.
	local characterView = root:WaitForChild("CharacterView")
	local deadline = os.clock() + 3
	repeat
		task.wait()
	until (screen.AbsoluteSize.X > 0 and characterView.AbsoluteSize.X > 0) or os.clock() > deadline
	task.wait(0.1)

	local problems = {}
	local details = {}
	local screenRect = { x = 0, y = 0, w = screen.AbsoluteSize.X, h = screen.AbsoluteSize.Y }

	local function rectOf(element)
		local position = element.AbsolutePosition - screen.AbsolutePosition
		return { x = position.X, y = position.Y, w = element.AbsoluteSize.X, h = element.AbsoluteSize.Y }
	end

	local names = { "Title", "Buttons", "CharacterView" }
	local rects = {}
	for _, name in names do
		local element = root:FindFirstChild(name)
		if not element then
			table.insert(problems, name .. " missing")
		else
			rects[name] = rectOf(element)
			table.insert(details, name .. " " .. describe(rects[name]))
			if rects[name].w <= 0 or rects[name].h <= 0 then
				table.insert(problems, name .. " has no size")
			elseif not inside(rects[name], screenRect) then
				table.insert(problems, name .. " " .. describe(rects[name]) .. " is outside the screen " .. describe(screenRect))
			end
		end
	end
	for i = 1, #names do
		for j = i + 1, #names do
			local a, b = rects[names[i]], rects[names[j]]
			if a and b and overlaps(a, b) then
				table.insert(problems, names[i] .. " " .. describe(a) .. " overlaps " .. names[j] .. " " .. describe(b))
			end
		end
	end

	if checkTopbar and rects.Title then
		local minTop = math.max(GuiService.TopbarInset.Height, PHONE_TOPBAR_BOTTOM)
		table.insert(details, ("Title top %.0f (topbar band ends at %.0f)"):format(rects.Title.y, minTop))
		if rects.Title.y < minTop - EPSILON then
			table.insert(problems, ("Title top %.0f is inside the topbar band, which ends at %.0f"):format(rects.Title.y, minTop))
		end
	end

	local buttonNames = { "Play", "Settings", "Credits" }
	local buttonRects = {}
	for _, name in buttonNames do
		local button = root.Buttons:FindFirstChild(name)
		if not button then
			table.insert(problems, "button " .. name .. " missing")
		else
			local rect = rectOf(button)
			buttonRects[name] = rect
			table.insert(details, name .. " " .. describe(rect))
			if rect.h < MIN_BUTTON_SIZE or rect.w < MIN_BUTTON_SIZE then
				table.insert(problems, ("button %s is %.0fx%.0f px, under the %d px tap target"):format(name, rect.w, rect.h, MIN_BUTTON_SIZE))
			end
			if rects.Buttons and not inside(rect, rects.Buttons) then
				table.insert(problems, "button " .. name .. " " .. describe(rect) .. " spills out of Buttons")
			end
		end
	end
	for i = 1, #buttonNames do
		for j = i + 1, #buttonNames do
			local a, b = buttonRects[buttonNames[i]], buttonRects[buttonNames[j]]
			if a and b and overlaps(a, b) then
				table.insert(problems, "button " .. buttonNames[i] .. " overlaps button " .. buttonNames[j])
			end
		end
	end

	local backRect = rectOf(back)
	table.insert(details, "Back " .. describe(backRect))
	if backRect.h < MIN_BUTTON_SIZE or backRect.w < MIN_BUTTON_SIZE then
		table.insert(problems, ("Back is %.0fx%.0f px, under the %d px tap target"):format(backRect.w, backRect.h, MIN_BUTTON_SIZE))
	end
	if not inside(backRect, screenRect) then
		table.insert(problems, "Back " .. describe(backRect) .. " is outside the screen " .. describe(screenRect))
	end

	if not keep then
		gui:Destroy()
	end
	return {
		problems = problems,
		details = ("%s screen %s: %s"):format(label, describe(screenRect), table.concat(details, "; ")),
	}
end

local landscape = measure("landscape 844x390", UDim2.fromOffset(844, 390), KEEP, true)
local window = measure("current window", UDim2.fromScale(1, 1), false, false)
local portrait = measure("portrait 390x844", UDim2.fromOffset(390, 844), false, false)

print("phone_layout: " .. landscape.details)
print("phone_layout: " .. window.details)
print("phone_layout: " .. portrait.details)
print(
	"phone_layout: portrait 390x844 (informational): "
		.. if #portrait.problems == 0 then "no problems" else table.concat(portrait.problems, " | ")
)

assert(#landscape.problems == 0, "landscape 844x390: " .. table.concat(landscape.problems, " | "))
assert(#window.problems == 0, "current window: " .. table.concat(window.problems, " | "))

if not KEEP then
	assert(playerGui:FindFirstChild(TEST_GUI_NAME) == nil, "temporary test ScreenGui was not destroyed")
end
return "PASS"
