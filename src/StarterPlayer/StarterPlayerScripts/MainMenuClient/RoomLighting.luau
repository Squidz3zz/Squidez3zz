-- RoomLighting: makes the Settings and Credits rooms look dark and amber from the very first frame.
--
-- WHY THIS EXISTS
-- The two rooms are models about 200 studs under the map. Roblox works out shadows and bounced light progressively, in a
-- grid of cells around the camera, and it only does that near where the camera is. When the menu cuts into a room the
-- camera jumps about 265 studs, far outside the part Roblox has already worked out, so for the first few seconds it has no
-- idea the room is closed in and lights it like an open field: the sun, the sky's ambient light and the sky's reflections
-- all shine into it. A few seconds later the grid catches up and the room settles into its proper look. That is the "wrong
-- lighting that fixes itself" you could see on every visit.
--
-- WHAT IT CHANGES
-- While a room is showing, apply() turns off the four things that come from outdoors (the room does not need them, since it
-- is lit by its own lamps):
--   Lighting.Brightness                 -> 0       (the sun's strength)
--   Lighting.OutdoorAmbient             -> black   (the sky's fill light on things that are not under a roof)
--   Lighting.EnvironmentDiffuseScale    -> 0       (how much of the sky's soft light reaches surfaces)
--   Lighting.EnvironmentSpecularScale   -> 0       (how much of the sky shows up as reflections)
-- Nothing else is touched: Ambient, ClockTime, the Sky, the Atmosphere and the screen effects stay as they are.
-- restore() puts the four original values back.
--
-- HOW IT KEEPS THE ORIGINALS
-- Before apply() changes a value it saves it as an attribute on Lighting, named MenuRoomLighting_<Property> (for example
-- MenuRoomLighting_Brightness). restore() reads them back and deletes them. Using attributes (rather than a variable in this
-- file) means any other copy of this module, such as the one a test loads, can find and restore the same originals. If the
-- attributes are already there (apply() was called twice) they are left alone, so the saved originals are always the real
-- ones and never the zeros that apply() wrote.
--
-- GOOD TO KNOW
-- It is client-only: Lighting changes made by a LocalScript are seen by this player alone and never reach the server or
-- other players. It never touches gameplay: init calls restore() when the player leaves a room and again on Play, so the
-- game always starts with its normal lighting. apply() and restore() never yield, can be called any number of times, and
-- restore() does nothing if nothing was saved. If a property cannot be read or written (a LocalScript is not always
-- allowed to touch every Lighting property), that one property is skipped and a single warning is printed.
local Lighting = game:GetService("Lighting")

local ATTRIBUTE_PREFIX = "MenuRoomLighting_"

-- What each property is set to while a room is showing.
local PROFILE = {
	{ property = "Brightness", value = 0 },
	{ property = "OutdoorAmbient", value = Color3.new(0, 0, 0) },
	{ property = "EnvironmentDiffuseScale", value = 0 },
	{ property = "EnvironmentSpecularScale", value = 0 },
}

local RoomLighting = {}

-- One warning per copy of this module, however many times a visit repeats it.
local warned = false

local function warnOnce(action, properties)
	if warned or #properties == 0 then
		return
	end
	warned = true
	warn("RoomLighting: could not " .. action .. " " .. table.concat(properties, ", ") .. " from a LocalScript; skipped")
end

-- Saves the Lighting values (unless an earlier apply() already did), then sets the room profile. Never yields.
function RoomLighting.apply()
	local skipped = {}
	for _, entry in PROFILE do
		local attribute = ATTRIBUTE_PREFIX .. entry.property
		local ok = pcall(function()
			-- Read first, so a property that cannot be read is left exactly as it is, and save before writing, so a value is
			-- never changed without its original being kept.
			local current = Lighting[entry.property]
			-- An existing attribute is an earlier apply()'s original: keep it, never save the profile's own values over it.
			if Lighting:GetAttribute(attribute) == nil then
				Lighting:SetAttribute(attribute, current)
			end
			Lighting[entry.property] = entry.value
		end)
		if not ok then
			table.insert(skipped, entry.property)
		end
	end
	warnOnce("apply", skipped)
end

-- Writes the saved originals back and removes the attributes. Nothing saved means nothing happens. Never yields.
function RoomLighting.restore()
	local skipped = {}
	for _, entry in PROFILE do
		local attribute = ATTRIBUTE_PREFIX .. entry.property
		local saved = Lighting:GetAttribute(attribute)
		if saved ~= nil then
			local ok = pcall(function()
				Lighting[entry.property] = saved
			end)
			if not ok then
				table.insert(skipped, entry.property)
			end
			Lighting:SetAttribute(attribute, nil)
		end
	end
	warnOnce("restore", skipped)
end

return RoomLighting
