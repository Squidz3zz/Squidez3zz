-- GooglyEyes: the physics of one googly eye's pupil, as pure maths (Vector2 only, no Instances), so BobAnimator can call it every frame
-- for each eye and a test can run it on its own. The pupil sits at an offset from the eye's centre, inside a circle of radius
-- Eye.radius (the white's radius minus the pupil's). Every vector is in the eye's own plane: x = right, y = up, in studs.
--   new(radius)                      an eye resting at the bottom: offset (0, -radius), no velocity
--   step(eye, gravity, pull, accel, dt)
--       gravity  gravity projected into the plane (studs/s^2)
--       pull     unit-ish direction toward what the eye is watching, in the plane; (0, 0) when it watches nothing
--       accel    the eye's own acceleration, projected into the plane (the pupil lags behind it, so Bob's moves jolt the pupils)
--       dt       seconds; at most 1/20 is simulated, and zero, negative or NaN does nothing
--     Acceleration = gravity + pull * PULL - accel - velocity * DAMPING, integrated in sub-steps of at most 1/240 s. A pupil pushed past
--     the rim goes back onto it and its outward velocity is reflected, times RESTITUTION. So the pupil stays inside its circle whatever
--     dt or forces it is given (as long as they are finite numbers).
--   spin(eye, speed)                 adds speed (studs/s) along the rim's tangent at the current offset, counter-clockwise
-- The settings below are the feel: PULL is how hard a watched target tugs, DAMPING how fast the pupil loses speed (per second) and
-- RESTITUTION how much of its speed a pupil keeps when it bounces off the rim.
local PULL = 60
local DAMPING = 4
local RESTITUTION = 0.55

local SUBSTEP = 1 / 240
local MAX_DT = 1 / 20

export type Eye = { offset: Vector2, velocity: Vector2, radius: number }

local GooglyEyes = {}

function GooglyEyes.new(radius: number): Eye
	return { offset = Vector2.new(0, -radius), velocity = Vector2.zero, radius = radius }
end

function GooglyEyes.step(eye: Eye, gravity: Vector2, pull: Vector2, accel: Vector2, dt: number)
	if not (dt > 0) then
		return
	end
	dt = math.min(dt, MAX_DT)
	local count = math.max(1, math.ceil(dt / SUBSTEP - 1e-9)) -- the 1e-9 keeps a dt of exactly n sub-steps at n
	local h = dt / count
	local push = gravity + pull * PULL - accel
	local offset, velocity, radius = eye.offset, eye.velocity, eye.radius
	for _ = 1, count do
		velocity += (push - velocity * DAMPING) * h
		offset += velocity * h
		local distance = offset.Magnitude
		if distance > radius then
			local normal = offset / distance
			offset = normal * radius
			local outward = velocity:Dot(normal)
			if outward > 0 then
				velocity -= normal * (outward * (1 + RESTITUTION))
			end
		end
	end
	eye.offset, eye.velocity = offset, velocity
end

function GooglyEyes.spin(eye: Eye, speed: number)
	local offset = eye.offset
	local distance = offset.Magnitude
	-- at the exact centre there is no tangent, so spin along +x
	local tangent = if distance > 1e-6 then Vector2.new(-offset.Y, offset.X) / distance else Vector2.new(1, 0)
	eye.velocity += tangent * speed
end

return GooglyEyes
