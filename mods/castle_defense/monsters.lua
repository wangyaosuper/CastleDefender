-- castle_defense/monsters.lua
--
-- The horde that storms the keep.
--
-- The monsters are land guards, but unlike the stock mob they spit fireballs:
-- a fireball that hits a player burns him, and one that hits a brick blows the
-- brick out of the wall, so a horde left alone chews its own breach.
--
-- The stock mob states already know how to walk to a target and how to spit a
-- fireball at it, so the custom AI here is small:
--
--   * a player within sight takes priority -- fireballs go at him,
--   * otherwise the monster keeps its eyes on the capture zone and marches,
--   * while a wall is in the way it stops and hammers that wall instead.

local modpath = minetest.get_modpath("castle_defense")
local arena = dofile(modpath .. "/arena.lua")

local MONSTER = "castle_defense:land_guard"
local FIREBALL = "castle_defense:fireball"

local FIREBALL_DAMAGE = 8  -- damage a fireball does to a player
local BREACH_RADIUS   = 2  -- how much wall one fireball takes with it
local WALL_NODE       = "default:brick"
local PLAYER_RANGE    = 24 -- how far a monster looks for a player to burn

-- Fireball -------------------------------------------------------------------

mobs:register_arrow(FIREBALL, {
	visual = "sprite",
	visual_size = {x = 1, y = 1},
	textures = {"mobs_fireball.png"},
	collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3},
	velocity = 9,
	tail = 1,
	tail_texture = "mobs_fireball.png",
	tail_size = 10,
	glow = 5,
	expire = 0.1,
	lifetime = 6,

	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1, fleshy = 100})
	end,

	hit_player = function(self, player)
		player:punch(self.object, 1.0,
			{full_punch_interval = 1.0, damage_groups = {fleshy = FIREBALL_DAMAGE}}, nil)
	end,

	hit_mob = function(self, mob)
		mob:punch(self.object, 1.0,
			{full_punch_interval = 1.0, damage_groups = {fleshy = FIREBALL_DAMAGE}}, nil)
	end,

	-- Whatever else it lands on goes up in smoke.  The blast is asked to carve
	-- nodes only (entity_radius = 0): the horde crowds the foot of the wall, so
	-- a blast that hurt bystanders would have the monsters shelling each other.
	hit_object = function(self)
		mobs:boom(self, self.object:get_pos(), BREACH_RADIUS, 0)
	end,

	hit_node = function(self, pos)
		mobs:boom(self, pos, BREACH_RADIUS, 0)
	end
})

-- Monster --------------------------------------------------------------------

-- Nearest player the monster can actually see.
local function visible_player(self, pos)
	local best, best_dist

	for _, obj in ipairs(minetest.get_objects_inside_radius(pos, PLAYER_RANGE)) do
		if obj:is_player() then
			local ppos = obj:get_pos()
			ppos.y = ppos.y + 1 -- aim at the chest, not at the feet
			local dist = vector.distance(pos, ppos)

			if (not best_dist or dist < best_dist)
					and self:line_of_sight(pos, ppos) then
				best, best_dist = obj, dist
			end
		end
	end

	return best
end

-- Is there brickwork right in front of the monster's face?
local function facing_wall(self, pos)
	local yaw = self.object:get_yaw() or 0
	local ahead = {
		x = pos.x - math.sin(yaw) * 1.5,
		y = pos.y,
		z = pos.z + math.cos(yaw) * 1.5
	}

	return minetest.get_node(ahead).name == WALL_NODE
end

mobs:register_mob(MONSTER, {
	description = "Fire Land Guard",
	type = "monster",
	passive = false,

	-- walk first, then spit fire; while a wall blocks the way the monster is
	-- pushed into the shooting half of the cycle by do_custom below
	attack_type = "dogshoot",
	dogshoot_switch = 2,
	dogshoot_count_max = 3,  -- seconds of spitting fire
	dogshoot_count2_max = 8, -- seconds of marching
	arrow = FIREBALL,
	shoot_interval = 1.4,
	shoot_offset = 1.0,

	-- fireballs do the work at range, this is the last resort up close
	reach = 2,
	damage = 8,
	punch_interval = 1.5,
	friendly_fire = false,

	hp_min = 30,
	hp_max = 45,
	armor = 90, -- damage taken in percent
	collisionbox = {-0.4, -1.0, -0.4, 0.4, 1.6, 0.4},
	visual = "mesh",
	mesh = "mobs_dungeon_master.b3d",
	glow = 1,
	textures = {
		{"mobs_land_guard.png"},
		{"mobs_land_guard2.png"},
		{"mobs_land_guard3.png"}
	},
	makes_footstep_sound = true,
	sounds = {random = "mobs_dungeonmaster", shoot_attack = "mobs_fireball"},

	walk_velocity = 1.6,
	run_velocity = 3.2,
	jump_height = 1,
	fear_height = 0, -- never stop for a drop: the keep is the goal
	floats = 0,
	view_range = 80, -- spans the whole arena, so the goal is never "too far"
	water_damage = 0,
	lava_damage = 2,
	light_damage = 0,

	drops = {
		{name = "mobs:leather", chance = 2, min = 0, max = 2},
		{name = "default:steel_ingot", chance = 3, min = 0, max = 1},
		{name = "default:apple", chance = 3, min = 0, max = 1}
	},

	animation = {
		stand_start = 0, stand_end = 19,
		walk_start = 20, walk_end = 35,
		run_start = 20, run_end = 35, run_speed = 40,
		punch_start = 36, punch_end = 48,
		shoot_start = 36, shoot_end = 48,
		speed_normal = 15, speed_run = 20
	},

	-- the arrow spawns inside the monster's own collision box, which would make
	-- it hit its owner on the first step: shove it clear of the shooter
	arrow_override = function(ent, self)
		local pos = self.object:get_pos()
		local yaw = self.object:get_yaw() or 0

		ent.object:set_pos({
			x = pos.x - math.sin(yaw),
			y = pos.y,
			z = pos.z + math.cos(yaw)
		})
	end,

	do_custom = function(self, dtime)
		local pos = self.object:get_pos()
		if not pos then return end

		-- a player on the walls is the most interesting target around
		local player = visible_player(self, pos)

		if player then
			local name = player:get_player_name()

			if self.cd_player ~= name then
				self.cd_player = name
				self:do_attack(player, true)
			end

			return
		end

		self.cd_player = nil

		-- nothing to shoot at for now: march on the capture zone
		self.cd_retarget = (self.cd_retarget or 0) - dtime

		if self.cd_retarget <= 0 or not self.attack or not self.attack:get_pos() then
			self.cd_retarget = 4
			self:go_to(arena.capture_center())
		end

		-- brick in the face: stop and burn a hole through it
		if facing_wall(self, pos) then
			self.dogshoot_switch = 1
			self.dogshoot_count = 0
		end
	end
})
