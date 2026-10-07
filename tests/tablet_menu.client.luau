-- Run in the Client datamodel during a playtest, one case at a time (set CASE below). Needs a spawned, claimed player: start a fresh
-- playtest, run tests/fire_play.client.luau (it presses Play), then the server step "claim" of tests/tablet_menu.server.luau, then the
-- cases below, running the server steps named in each arrow between the client steps (each is its own execute_luau call).
-- Cases that build their own menu (A, D, L) take a copy of the TabletMenu module, so they never touch the real menu LabClient made.
-- The real menu is PlayerGui.TabletMenu (a test copy's gui is renamed TabletMenuTest).
--   A   (T-A, T-B, T-C) a fresh menu: open, CONFIRM inactive until both picks are made and then reading "CONFIRM: EXPLOSIVE INTO LEFT
--       ARM"; confirm() sends Explosive into the left arm, closes the menu, and a reopened menu is read-only and shows Bob's state;
--       after the blast, with the menu left open, the left arm is lost, greyed out and cannot be picked
--       (server step first: "claim"; afterwards: case L, then the server step "release")
--   D   (T-D) a refusal: with the room released, confirm() with both picks answers "NOT YOUR ROOM" and Status shows it for 3 s
--       (server step first: "release"; afterwards: the server step "claim")
--   E1  (T-E) the real LabClient: equip the Tablet, activate it; the real menu opens
--       -> server step "inject_right_arm"
--   E3  (T-E) after the blast the right arm and the tablet are gone and the real menu is closed
--       -> (server step "claim" for the next case)
--   F1  (T-F) the real menu opens again, and DeathScreen's Black is above it
--       -> server step "kill"
--   F3  (T-F) the menu closed when the character died, and is still closed after the respawn
--   L   the layout: every TextButton in the open menu's Root is at least 40 px tall, nothing in it uses pixel sizes; leaves a menu
--       open (with picks) to be photographed
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local MOVE = LabConfig.Timings.Move
local INJECT = LabConfig.Timings.NeedleOut + LabConfig.Timings.Hold + LabConfig.Timings.NeedleIn
local RETURN = LabConfig.Timings.Return
local FUSE = LabConfig.FUSE_SECONDS

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local room = workspace:WaitForChild("Room1", 10)
assert(room, "Workspace.Room1 missing on the client")
local bob = room:WaitForChild("BobTheInjector")

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.1)
	end
	return predicate()
end

local function humanoidOf(character)
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- A copy of the TabletMenu module, initialised with the real template; returns it and its gui. The module is cloned so its state is
-- its own and the real menu is left alone. The copy's gui is renamed so the real PlayerGui.TabletMenu stays the only one with that name.
local function makeTestMenu()
	local labClient = player:WaitForChild("PlayerScripts"):WaitForChild("LabClient")
	local source = labClient:FindFirstChild("TabletMenu")
	assert(source and source:IsA("ModuleScript"), "LabClient.TabletMenu (ModuleScript) missing")
	local template = ReplicatedStorage:FindFirstChild("TabletMenu")
	assert(template and template:IsA("ScreenGui"), "ReplicatedStorage.TabletMenu (ScreenGui) missing")
	local remotes = ReplicatedStorage:FindFirstChild("LabRemotes")
	local remote = remotes and remotes:FindFirstChild("RequestInjection")
	assert(remote and remote:IsA("RemoteFunction"), "ReplicatedStorage.LabRemotes.RequestInjection missing")

	local before = {}
	for _, child in playerGui:GetChildren() do
		before[child] = true
	end
	local menu = require(source:Clone())
	menu.init({ template = template, playerGui = playerGui, config = LabConfig, room = room, remote = remote })
	local gui
	for _, child in playerGui:GetChildren() do
		if not before[child] and child.Name == "TabletMenu" then
			gui = child
		end
	end
	assert(gui, "init did not put a TabletMenu gui in PlayerGui")
	gui.Name = "TabletMenuTest"
	return menu, gui
end

local function realGui()
	local gui = playerGui:FindFirstChild("TabletMenu")
	assert(gui and gui:IsA("ScreenGui"), "the real PlayerGui.TabletMenu is missing (LabClient did not build it)")
	return gui
end

-- Equips the Tablet and activates it, as a click does.
local function equipAndActivate()
	local character = player.Character
	local humanoid = humanoidOf(character)
	assert(humanoid and humanoid.Health > 0, "no live character: run tests/fire_play.client.luau first")
	local tool = player:WaitForChild("Backpack"):FindFirstChild("Tablet") or character:FindFirstChild("Tablet")
	assert(tool, "no Tablet tool: run the server step 'claim' of tests/tablet_menu.server.luau first")
	humanoid:EquipTool(tool)
	assert(waitFor(function()
		return tool.Parent == character
	end, 3), "the Tablet did not reach the hand")
	task.wait(0.2)
	tool:Activate()
	return tool, character
end

if CASE == "A" then
	local menu, gui = makeTestMenu()
	local root = gui.Root
	local status, confirmButton = root.Header.Status, root.Confirm
	assert(not gui.Enabled and not menu.isOpen(), "a new menu should be closed")
	assert(menu.view().open == false, "view().open should be false")

	-- T-A
	menu.open()
	assert(menu.isOpen() and gui.Enabled, "open() should open the menu")
	local v = menu.view()
	assert(v.open and v.hardDrive == nil and v.limb == nil, "nothing should be picked yet")
	assert(v.confirmActive == false and v.readOnly == false, "CONFIRM should be inactive on a fresh menu, and Bob is on Standby")
	assert(status.Text == "STANDBY", "Status should read STANDBY, reads " .. status.Text)
	assert(confirmButton.Text == "PICK A HARDDRIVE AND A LIMB", "Confirm reads " .. confirmButton.Text)
	local nothing, why = menu.confirm()
	assert(nothing == false and why == "INCOMPLETE", "confirm() with no picks should answer (false, 'INCOMPLETE')")
	menu.pickHardDrive("Explosive")
	assert(menu.view().confirmActive == false, "a Harddrive alone should not activate CONFIRM")
	assert(menu.view().hardDrive == "Explosive", "the Harddrive should be picked")
	menu.pickLimb("LeftArm")
	v = menu.view()
	assert(v.confirmActive == true and v.limb == "LeftArm", "both picks should activate CONFIRM")
	assert(confirmButton.Text == "CONFIRM: EXPLOSIVE INTO LEFT ARM", "Confirm reads " .. confirmButton.Text)
	assert(root.Target.LeftArm.Text == "L ARM" and root.Target.RightArm.Text == "R ARM", "the arm buttons should read L ARM and R ARM")
	assert(root.Target.RightArm.AbsolutePosition.X < root.Target.LeftArm.AbsolutePosition.X, "R ARM must be on the screen's left (the body is seen from the front)")
	assert(root.Target.RightLeg.AbsolutePosition.X < root.Target.LeftLeg.AbsolutePosition.X, "R LEG must be on the screen's left")
	menu.pickHardDrive("Nope")
	menu.pickLimb("Tail")
	v = menu.view()
	assert(v.hardDrive == "Explosive" and v.limb == "LeftArm", "an unknown Harddrive or limb must be ignored")

	-- T-B
	local ok, reason = menu.confirm()
	assert(ok == true and reason == nil, "confirm() should succeed, answered " .. tostring(ok) .. ", " .. tostring(reason))
	assert(menu.isOpen() == false and not gui.Enabled, "the menu should close on a successful confirm")
	menu.open()
	v = menu.view()
	assert(v.readOnly == true and v.confirmActive == false, "a reopened menu should be read-only while Bob works")
	assert(status.Text == "MOVING" or status.Text == "INJECTING", "Status should show Bob's state, reads " .. status.Text)
	menu.pickLimb("RightLeg")
	assert(menu.view().limb == "LeftArm" or menu.view().limb == nil, "picks must be ignored while read-only")
	assert(menu.view().limb ~= "RightLeg", "pickLimb must be ignored while read-only")
	assert(waitFor(function()
		return bob:GetAttribute("State") == "Standby"
	end, MOVE + INJECT + RETURN + 2), "Bob never got back to Standby")
	assert(menu.view().readOnly == false and status.Text == "STANDBY", "the menu should leave read-only when Bob is on Standby")

	-- T-C: the blast comes FUSE seconds after the needle is out; the menu stays open and must notice the lost arm by itself.
	local subject = room:FindFirstChild("Subject")
	assert(subject, "no Room1.Subject")
	assert(waitFor(function()
		return LabConfig.isLost(subject, "LeftArm")
	end, FUSE + 3), "the copy's left arm was never blown off")
	task.wait(0.3)
	v = menu.view()
	assert(v.lost.LeftArm == true, "view().lost.LeftArm should be true after the blast")
	for _, key in { "Head", "Torso", "RightArm", "LeftLeg", "RightLeg" } do
		assert(v.lost[key] == false, key .. " should not be lost")
	end
	assert(v.limb == nil, "a pick that was lost should be cleared")
	assert(root.Target.LeftArm.Text == "LOST", "a lost limb should read LOST, reads " .. root.Target.LeftArm.Text)
	assert(confirmButton.Text == "PICK A HARDDRIVE AND A LIMB", "Confirm reads " .. confirmButton.Text)
	menu.pickLimb("LeftArm")
	assert(menu.view().limb == nil, "pickLimb must ignore a lost limb")
	menu.pickLimb("RightArm")
	assert(menu.view().limb == "RightArm" and menu.view().confirmActive == true, "another limb can still be picked")
	menu.close()
	assert(not menu.isOpen(), "close() should close the menu")
	return "PASS tablet_menu T-A T-B T-C"
elseif CASE == "D" then
	local menu, gui = makeTestMenu()
	local status = gui.Root.Header.Status
	assert(room:GetAttribute("Owner") == 0, "run the server step 'release' first: the room is still owned")
	menu.open()
	menu.pickHardDrive("Explosive")
	menu.pickLimb("RightArm")
	assert(menu.view().confirmActive, "CONFIRM should be active")
	local ok, reason = menu.confirm()
	assert(ok == false and reason == "NOT YOUR ROOM", ("expected (false, 'NOT YOUR ROOM'), got (%s, %s)"):format(tostring(ok), tostring(reason)))
	assert(status.Text == "NOT YOUR ROOM", "Status should show the refusal, reads " .. status.Text)
	assert(menu.view().status == "NOT YOUR ROOM", "view().status should show the refusal")
	assert(menu.isOpen(), "a refused confirm must leave the menu open")
	task.wait(1.5)
	assert(status.Text == "NOT YOUR ROOM", "the refusal should still show after 1.5 s")
	task.wait(2)
	assert(status.Text == "STANDBY", "the refusal should go after 3 s, Status reads " .. status.Text)
	menu.close()
	return "PASS tablet_menu T-D"
elseif CASE == "E1" then
	local gui = realGui()
	assert(not gui.Enabled, "the real menu should start closed")
	equipAndActivate()
	assert(waitFor(function()
		return gui.Enabled
	end, 2), "activating the Tablet should open the real menu")
	assert(gui.Root.Header.Status.Text == "STANDBY", "Status reads " .. gui.Root.Header.Status.Text)
	return "PASS tablet_menu T-E (1 of 2): the real menu opened; now run the server step inject_right_arm, then case E3"
elseif CASE == "E3" then
	local gui = realGui()
	local character = player.Character
	if bob:GetAttribute("State") ~= "Standby" then
		assert(gui.Enabled, "the real menu should still be open while Bob works")
	end
	assert(waitFor(function()
		return not character:FindFirstChild("Tablet")
	end, MOVE + INJECT + FUSE + 3), "the tablet never went away")
	assert(waitFor(function()
		return not gui.Enabled
	end, 1), "the real menu should be closed once the tablet is gone")
	local subject = room:FindFirstChild("Subject")
	assert(subject and LabConfig.isLost(subject, "RightArm"), "the copy's right arm should be blown off")
	assert(LabConfig.isLost(character, "RightArm"), "the player's right arm should be blown off")
	return "PASS tablet_menu T-E"
elseif CASE == "F1" then
	local gui = realGui()
	assert(not gui.Enabled, "the real menu should start closed")
	equipAndActivate()
	assert(waitFor(function()
		return gui.Enabled
	end, 2), "activating the Tablet should open the real menu")
	local death = playerGui:FindFirstChild("DeathScreen")
	assert(death and death:IsA("ScreenGui"), "PlayerGui.DeathScreen missing")
	assert(death:FindFirstChild("Black"), "DeathScreen.Black missing")
	assert(death.DisplayOrder > gui.DisplayOrder, ("DeathScreen (%d) must sit above the menu (%d)"):format(death.DisplayOrder, gui.DisplayOrder))
	return ("PASS tablet_menu T-F (1 of 2): menu open, DeathScreen order %d above the menu's %d; now run the server step kill, then case F3"):format(
		death.DisplayOrder,
		gui.DisplayOrder
	)
elseif CASE == "F3" then
	local gui = realGui()
	local humanoid = humanoidOf(player.Character)
	local note = "closed while dead"
	if humanoid and humanoid.Health <= 0 then
		assert(gui.Enabled == false, "the menu should be closed once the character has died")
		local dead = player.Character
		assert(waitFor(function()
			return player.Character ~= dead and humanoidOf(player.Character) and humanoidOf(player.Character).Health > 0
		end, LabConfig.RESPAWN_TIME + 8), "the player never respawned")
	else
		note = "already respawned when checked"
	end
	task.wait(0.5)
	assert(gui.Enabled == false, "the menu should be closed after the respawn")
	return "PASS tablet_menu T-F (" .. note .. ")"
elseif CASE == "L" then
	local menu, gui = makeTestMenu()
	menu.open()
	menu.pickHardDrive("Explosive")
	menu.pickLimb("RightArm")
	task.wait(0.3)
	local root = gui.Root
	local viewport = workspace.CurrentCamera.ViewportSize
	assert(viewport.X > 100 and viewport.Y > 100, "the viewport is " .. tostring(viewport))
	local area = gui.AbsoluteSize

	-- Every button is at least 40 px tall here, and (since the children of Root are all scale-sized) at 667 x 375 too: the same
	-- fractions of the panel the screen allows there (0.94 of its height, less a 58 px top bar, or 0.94 of its width / 1.85).
	local smallest, smallestName, lowestHere, count = math.huge, "", math.huge, 0
	local panelHere = math.min(0.94 * (375 - 58), 0.94 * 667 / 1.85)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Name ~= "EntryTemplate" and not d:FindFirstAncestor("EntryTemplate") then
			for _, u in { d.Size.X, d.Size.Y, d.Position.X, d.Position.Y } do
				assert(u.Offset == 0, d:GetFullName() .. " uses a pixel size or position (" .. tostring(u) .. "); the layout is scale only")
			end
		end
		if d:IsA("TextButton") and d.Visible and not d:FindFirstAncestor("EntryTemplate") then
			count += 1
			local high = d.AbsoluteSize.Y
			lowestHere = math.min(lowestHere, high)
			assert(high >= 40, ("%s is %.1f px tall here (viewport %dx%d), under 40"):format(d:GetFullName(), high, viewport.X, viewport.Y))
			local scaled = high / root.AbsoluteSize.Y * panelHere
			assert(scaled >= 40, ("%s would be %.1f px tall at 667x375, under 40"):format(d:GetFullName(), scaled))
			if scaled < smallest then
				smallest, smallestName = scaled, d.Name
			end
		end
	end
	assert(count >= 9, "expected at least 9 buttons (Close, an entry, six body parts and Confirm), found " .. count)
	assert(root.AbsoluteSize.X <= 760.5, "the panel is " .. root.AbsoluteSize.X .. " px wide, past 760")
	local rootEdge = root.AbsolutePosition + root.AbsoluteSize
	assert(root.AbsolutePosition.X >= 0 and root.AbsolutePosition.Y >= 0 and rootEdge.X <= area.X + 0.5 and rootEdge.Y <= area.Y + 0.5, "the panel leaves the screen area")
	return ("PASS tablet_menu layout: viewport %dx%d, gui area %dx%d, panel %dx%d, %d buttons, smallest %s %.1f px at 667x375 (min here %.1f); menu left open"):format(
		viewport.X,
		viewport.Y,
		area.X,
		area.Y,
		root.AbsoluteSize.X,
		root.AbsoluteSize.Y,
		count,
		smallestName,
		smallest,
		lowestHere
	)
end
error("unknown CASE " .. tostring(CASE))
