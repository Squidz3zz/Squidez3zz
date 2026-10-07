-- Run in the Edit datamodel. Checks src/StarterPlayer/StarterPlayerScripts/LabClient/GooglyEyes.luau, the pure-maths pupil simulation
-- (the module is pushed into StarterPlayerScripts.LabClient first). It requires a clone, so a re-run after a push never gets a cached
-- old version.
--   G-A  the pupil never leaves its circle: 2000 steps of random acceleration (up to 400) and random dt (0 to 0.1), for three radii
--   G-B  with only gravity it settles at the bottom within 3 s, from any start
--   G-C  with only a pull toward +x it settles at the right-hand rim within 3 s
--   G-D  a spin of 20 still leaves the pupil moving faster than 15 after one step (tangent, not a push into the rim), for radii 0.5 and 1.
--        On a 0.2 rim a sub-step sweeps 0.4 radians and the rim bounces cost 28% in one frame (speed 14.4), so a spin that fast is
--        meant for a bigger eye.
--   G-E  a new eye rests at the bottom, and a zero, negative or NaN dt changes nothing
--   G-F  watching beats gravity: with gravity and a pull toward +x, after 3 s the pupil is more than half its radius toward +x,
--        for Bob's radius (0.1925) and 0.5
local GooglyEyes = require(game.StarterPlayer.StarterPlayerScripts.LabClient.GooglyEyes:Clone())
local GRAVITY = Vector2.new(0, -196.2)
local ZERO = Vector2.zero
local RADII = { 0.2, 0.5, 1 }
local rng = Random.new(7)

-- G-A
for _, radius in RADII do
	local eye = GooglyEyes.new(radius)
	for i = 1, 2000 do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local accel = Vector2.new(math.cos(angle), math.sin(angle)) * rng:NextNumber(0, 400)
		GooglyEyes.step(eye, GRAVITY, ZERO, accel, rng:NextNumber(0, 0.1))
		assert(eye.offset.Magnitude <= radius + 1e-6, "G-A: pupil left its circle at step " .. i .. " (radius " .. radius .. ", |offset| " .. eye.offset.Magnitude .. ")")
	end
end

-- G-B
for _, radius in RADII do
	for trial = 1, 20 do
		local eye = GooglyEyes.new(radius)
		local angle = rng:NextNumber(0, 2 * math.pi)
		eye.offset = Vector2.new(math.cos(angle), math.sin(angle)) * rng:NextNumber(0, radius)
		for _ = 1, 180 do
			GooglyEyes.step(eye, GRAVITY, ZERO, ZERO, 1 / 60)
		end
		local off = (eye.offset - Vector2.new(0, -radius)).Magnitude
		assert(off < 0.01, "G-B: radius " .. radius .. " trial " .. trial .. " ended " .. off .. " from the bottom")
	end
end

-- G-C
for _, radius in RADII do
	local eye = GooglyEyes.new(radius)
	for _ = 1, 180 do
		GooglyEyes.step(eye, ZERO, Vector2.new(1, 0), ZERO, 1 / 60)
	end
	assert(eye.offset.X > 0.9 * radius, "G-C: radius " .. radius .. " ended at x " .. eye.offset.X)
end

-- G-D
for _, radius in { 0.5, 1 } do
	local eye = GooglyEyes.new(radius)
	GooglyEyes.spin(eye, 20)
	GooglyEyes.step(eye, GRAVITY, ZERO, ZERO, 1 / 60)
	assert(eye.velocity.Magnitude > 15, "G-D: radius " .. radius .. " speed after one step " .. eye.velocity.Magnitude)
end

-- G-E
local eye = GooglyEyes.new(0.5)
assert(eye.radius == 0.5 and eye.offset == Vector2.new(0, -0.5) and eye.velocity == ZERO, "G-E: a new eye is not resting at the bottom")
for _, dt in { 0, -1, 0 / 0 } do
	GooglyEyes.step(eye, GRAVITY, Vector2.new(1, 0), Vector2.new(50, 50), dt)
	assert(eye.offset == Vector2.new(0, -0.5) and eye.velocity == ZERO, "G-E: dt " .. dt .. " moved the eye")
end

-- G-F
local watched = {}
for _, radius in { 0.1925, 0.5 } do
	local watcher = GooglyEyes.new(radius)
	for _ = 1, 180 do
		GooglyEyes.step(watcher, GRAVITY, Vector2.new(1, 0), ZERO, 1 / 60)
	end
	assert(watcher.offset.X > 0.5 * radius, ("G-F: radius %g ended at x %.4f, not past half the radius (%.4f)"):format(radius, watcher.offset.X, 0.5 * radius))
	table.insert(watched, ("%.2f of r %g"):format(watcher.offset.X / radius, radius))
end

return "PASS googly_eyes (G-A..G-F; G-F x/radius " .. table.concat(watched, ", ") .. ")"
