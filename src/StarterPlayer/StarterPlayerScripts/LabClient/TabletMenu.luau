-- TabletMenu: the tablet's menu, where the owner of Room 1 picks a Harddrive and a limb and confirms. LabClient opens it when the
-- Tablet tool is activated and closes it when the tool goes (unequipped, destroyed) or the character dies.
--   init(opts)       clones opts.template (ReplicatedStorage.TabletMenu, built by studio/build_lab.luau) into opts.playerGui, one entry per
--                    LabConfig.HardDrives item. opts = { template, playerGui, config (LabConfig), room (Workspace.Room1), remote
--                    (LabRemotes.RequestInjection) }
--   open() / close() / isOpen()
--   pickHardDrive(id) / pickLimb(key)   ignored for an unknown id or key, for a lost limb and while the menu is read-only
--   confirm()        (false, "INCOMPLETE") and nothing else unless both are picked and the menu is not read-only (or an earlier confirm
--                    is still waiting for the server); else asks the server: (true) closes the menu, (false, reason) shows the reason in
--                    Status for REFUSAL_SECONDS and leaves the menu open
--   view()           what the menu shows, for tests: { open, hardDrive, limb, confirmActive, readOnly, lost = { [limbKey] = boolean },
--                    status }
-- Read-only while Bob's State is not "Standby": nothing can be picked, CONFIRM is greyed and Status shows his state. Lost limbs are
-- the copy's (LabConfig.isLost on Room1.Subject), kept up to date while the menu is open. The look is the template's Factory look; the
-- colours of a picked, lost or inactive button are the ones below. B on a controller closes the menu. The hover and click sounds are
-- the main menu's SoundService.MenuSfxHover and MenuSfxConfirm, looked up by name (silent if they are missing).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local REFUSAL_SECONDS = 3
local CLOSE_ACTION = "TabletMenuClose"

local AMBER = Color3.fromRGB(255, 150, 30)
local AMBER_DARK = Color3.fromRGB(140, 82, 16) -- the picked limb's fill
local STEEL = Color3.fromRGB(58, 55, 52)
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(16, 14, 12)
local LOST_FILL = Color3.fromRGB(28, 26, 24)
local GREYED = Color3.fromRGB(110, 104, 96)

local TabletMenu = {}

local gui: ScreenGui? = nil
local config, room, bob, remote
local status: TextLabel, confirmButton: TextButton
local entries: { [string]: TextButton } = {} -- Harddrive id -> its entry
local limbButtons: { [string]: TextButton } = {} -- limb key -> its button
local limbLabels: { [string]: string } = {} -- limb key -> what its button reads when it is not lost
local lost: { [string]: boolean } = {}
local hardDrive: string? = nil
local limb: string? = nil
local refusal: string? = nil
local refusalToken = 0 -- bumped by every refusal and by close(), so an old refusal's timer does not clear a newer one
local pending = false -- a confirm is waiting for the server
local subjectWatch: { RBXScriptConnection } = {}

local function need(parent: Instance, ...: string): any
	local node = parent
	for _, name in { ... } do
		local child = node:FindFirstChild(name)
		assert(child, "TabletMenu template: " .. node:GetFullName() .. " has no " .. name)
		node = child
	end
	return node
end

local function sfx(name: string)
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound.TimePosition = 0
		sound:Play()
	end
end

local function readOnly(): boolean
	return bob:GetAttribute("State") ~= "Standby"
end

local function confirmActive(): boolean
	return hardDrive ~= nil and limb ~= nil and not readOnly() and not pending
end

-- "LeftArm" -> "LEFT ARM"
local function limbWords(key: string): string
	return string.upper((key:gsub("(%l)(%u)", "%1 %2")))
end

local function hardDriveName(id: string): string
	for _, item in config.HardDrives do
		if item.id == id then
			return item.name
		end
	end
	return string.upper(id)
end

-- Reads which limbs of the copy are lost (none when there is no copy) and drops a pick that was lost.
local function readLost()
	local subject = room:FindFirstChild("Subject")
	for _, key in config.LIMB_KEYS do
		lost[key] = subject ~= nil and config.isLost(subject, key)
	end
	if limb and lost[limb] then
		limb = nil
	end
end

-- Paints everything from the state above.
local function render()
	readLost()
	for id, entry in entries do
		entry.Stroke.Enabled = id == hardDrive
	end
	for key, button in limbButtons do
		local isLost = lost[key]
		local picked = key == limb
		button.Text = if isLost then "LOST" else limbLabels[key]
		button.BackgroundColor3 = if isLost then LOST_FILL elseif picked then AMBER_DARK else STEEL
		button.TextColor3 = if isLost then GREYED else WHITE
		button.Stroke.Enabled = picked
	end
	local active = confirmActive()
	confirmButton.Text = if hardDrive and limb
		then ("CONFIRM: %s INTO %s"):format(hardDriveName(hardDrive), limbWords(limb))
		else "PICK A HARDDRIVE AND A LIMB"
	confirmButton.BackgroundColor3 = if active then AMBER else STEEL
	confirmButton.TextColor3 = if active then DARK else GREYED
	status.Text = refusal or string.upper(tostring(bob:GetAttribute("State") or ""))
end

local function showRefusal(reason: string)
	refusal = reason
	refusalToken += 1
	local mine = refusalToken
	task.delay(REFUSAL_SECONDS, function()
		if mine == refusalToken then
			refusal = nil
			render()
		end
	end)
	render()
end

-- Follows the copy: it comes and goes, and its joints go when a limb is blown off.
local function watchSubject()
	for _, connection in subjectWatch do
		connection:Disconnect()
	end
	table.clear(subjectWatch)
	local subject = room:FindFirstChild("Subject")
	if subject then
		local function later()
			task.defer(render) -- a removal is only done once the event has finished
		end
		table.insert(subjectWatch, subject.DescendantAdded:Connect(later))
		table.insert(subjectWatch, subject.DescendantRemoving:Connect(later))
	end
	render()
end

-- A Harddrive's brick, in the entry's ViewportFrame, with a camera of its own looking at it from the side and above. No brick, no
-- picture: the entry still works.
local function fillIcon(icon: ViewportFrame, id: string)
	local assets = ReplicatedStorage:FindFirstChild("LabAssets")
	local drives = assets and assets:FindFirstChild("HardDrives")
	local brick = drives and drives:FindFirstChild(id)
	if not (brick and brick:IsA("BasePart")) then
		return
	end
	local copy = brick:Clone()
	copy.Anchored = true
	copy.CFrame = CFrame.new()
	copy.Parent = icon
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(1.2, 0.8, 1).Unit * copy.Size.Magnitude * 1.9, Vector3.zero)
	camera.Parent = icon
	icon.CurrentCamera = camera
end

-- Hover and click sounds, and what the button does.
local function wire(button: TextButton, onClick: () -> ())
	button.MouseEnter:Connect(function()
		sfx("MenuSfxHover")
	end)
	button.SelectionGained:Connect(function()
		sfx("MenuSfxHover")
	end)
	button.Activated:Connect(onClick)
end

function TabletMenu.init(opts)
	assert(not gui, "TabletMenu.init was already called")
	config, room, remote = opts.config, opts.room, opts.remote
	bob = room:WaitForChild("BobTheInjector", 10)
	assert(bob, "Workspace.Room1.BobTheInjector did not appear")

	local built = opts.template:Clone()
	built.Enabled = false
	local root = need(built, "Root")
	status = need(root, "Header", "Status")
	confirmButton = need(root, "Confirm")
	local list = need(root, "Injections", "List")
	local entryTemplate = need(list, "EntryTemplate")
	local target = need(root, "Target")
	for _, key in config.LIMB_KEYS do
		limbButtons[key] = need(target, key)
		need(limbButtons[key], "Stroke")
		limbLabels[key] = limbButtons[key].Text
	end

	for index, item in config.HardDrives do
		local entry = entryTemplate:Clone()
		entry.Name = item.id
		entry.LayoutOrder = index
		entry.Visible = true
		need(entry, "Label").Text = item.name
		need(entry, "Stroke")
		fillIcon(need(entry, "Icon"), item.id)
		entry.Parent = list
		entries[item.id] = entry
		wire(entry, function()
			sfx("MenuSfxConfirm")
			TabletMenu.pickHardDrive(item.id)
		end)
	end
	for key, button in limbButtons do
		wire(button, function()
			sfx("MenuSfxConfirm")
			TabletMenu.pickLimb(key)
		end)
	end
	wire(need(root, "Header", "Close"), function()
		sfx("MenuSfxConfirm")
		TabletMenu.close()
	end)
	wire(confirmButton, function()
		if confirmActive() then
			sfx("MenuSfxConfirm")
		end
		TabletMenu.confirm()
	end)

	bob:GetAttributeChangedSignal("State"):Connect(render)
	room.ChildAdded:Connect(function(child)
		if child.Name == "Subject" then
			watchSubject()
		end
	end)
	room.ChildRemoved:Connect(function(child)
		if child.Name == "Subject" then
			watchSubject()
		end
	end)

	built.Parent = opts.playerGui
	gui = built
	watchSubject()
end

function TabletMenu.isOpen(): boolean
	return gui.Enabled
end

function TabletMenu.open()
	if gui.Enabled then
		return
	end
	render()
	gui.Enabled = true
	ContextActionService:BindAction(CLOSE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			TabletMenu.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonB)
	if UserInputService.GamepadEnabled then
		local first = config.HardDrives[1]
		GuiService.SelectedObject = (first and entries[first.id]) or limbButtons.Head
	end
end

function TabletMenu.close()
	if not gui.Enabled then
		return
	end
	gui.Enabled = false
	refusal = nil
	refusalToken += 1
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	render()
end

function TabletMenu.pickHardDrive(id: string)
	if readOnly() or not entries[id] then
		return
	end
	hardDrive = id
	render()
end

function TabletMenu.pickLimb(key: string)
	if readOnly() or not limbButtons[key] then
		return
	end
	readLost()
	if not lost[key] then
		limb = key
	end
	render()
end

function TabletMenu.confirm(): (boolean, string?)
	if not confirmActive() then
		return false, "INCOMPLETE"
	end
	pending = true
	render()
	local reached, accepted, reason = pcall(remote.InvokeServer, remote, hardDrive, limb)
	pending = false
	if reached and accepted then
		TabletMenu.close()
		return true
	end
	reason = if reached then reason or "REFUSED" else "NO ANSWER"
	if gui.Enabled then
		showRefusal(reason) -- (the menu may have been closed while the server was thinking)
	end
	return false, reason
end

function TabletMenu.view()
	return {
		open = gui.Enabled,
		hardDrive = hardDrive,
		limb = limb,
		confirmActive = confirmActive(),
		readOnly = readOnly(),
		lost = table.clone(lost),
		status = status.Text,
	}
end

return TabletMenu
