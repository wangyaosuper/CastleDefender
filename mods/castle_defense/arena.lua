-- castle_defense/arena.lua
--
-- Shared arena geometry.
--
-- The terrain generator, the monster AI and the wave spawner all have to agree
-- on where the valley is, so the numbers live here exactly once:
--
--   * the valley floor is a flared wedge -- it is closed at the apex (behind
--     the inner wall) and opens out towards the plain,
--   * the capture zone is the narrow part of that wedge behind the inner wall:
--     monsters reaching it have taken the keep and win the game,
--   * monsters enter from the plain in front of the outer wall.

local arena = {}

-- Valley ---------------------------------------------------------------------

arena.VALLEY_APEX_Z = -45                          -- the ranges meet here
arena.VALLEY_DEG    = 22                           -- opening angle, either side
arena.VALLEY_SLOPE  = math.tan(math.rad(arena.VALLEY_DEG))

arena.GROUND_Y = 0 -- top solid node of plateau and plain

-- Half width of the flat valley floor at depth `z` (zero at the apex).
function arena.foot_half(z)
	return (z - arena.VALLEY_APEX_Z) * arena.VALLEY_SLOPE
end

-- Walls, kept in sync with mapgen.lua.
arena.OUTER_WALL_Z   = 40
arena.INNER_WALL_Z   = 8
arena.WALL_THICKNESS = 5

-- Capture zone ---------------------------------------------------------------

-- A box that is clipped to the valley floor, which keeps narrowing towards the
-- apex, so the marked area stays on walkable ground.
arena.CAPTURE = {
	z_min = -34,      -- deepest point, near the apex
	z_max = -22,      -- towards the walls
	half_x = 6,       -- clamped to the valley floor at that depth
}

function arena.capture_half_x(z)
	local half = arena.foot_half(z) - 1
	if half > arena.CAPTURE.half_x then
		half = arena.CAPTURE.half_x
	end
	return half
end

function arena.in_capture(pos)
	if pos.z < arena.CAPTURE.z_min or pos.z > arena.CAPTURE.z_max then
		return false
	end
	local half = arena.capture_half_x(pos.z)
	return half > 0 and math.abs(pos.x) <= half
end

-- Point monsters aim for.  It floats a little above the floor so that fireballs
-- fly over the red carpet instead of cratering it on the way in.
function arena.capture_center()
	return {
		x = 0,
		y = arena.GROUND_Y + 3,
		z = math.floor((arena.CAPTURE.z_min + arena.CAPTURE.z_max) / 2),
	}
end

-- Spawning -------------------------------------------------------------------

-- The horde gathers on the flat ground just outside the outer wall.
arena.SPAWN = {z_min = 44, z_max = 52, half_x = 28, y = arena.GROUND_Y + 2}

function arena.random_spawn_pos()
	local z = math.random(arena.SPAWN.z_min, arena.SPAWN.z_max)
	local half = math.min(arena.SPAWN.half_x, arena.foot_half(z) - 3)
	return {x = math.random(-half, half), y = arena.SPAWN.y, z = z}
end

return arena
