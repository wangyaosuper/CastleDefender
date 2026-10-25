cave_monsters = {}

cave_monsters.SPAWN_CHANCE = 0.75
cave_monsters.MAX_PER_CHUNK = 3
cave_monsters.MONSTER_HP_MIN = 18
cave_monsters.MONSTER_HP_MAX = 22
cave_monsters.MONSTER_DAMAGE = 6
cave_monsters.MONSTER_SPEED = 1.8
cave_monsters.AMBIENT_SPAWN_INTERVAL = 19
cave_monsters.AMBIENT_SPAWN_CHANCE = 900
cave_monsters.MAX_NEARBY = 5

local SPAWN_LIGHT_MAX = 7
local SPAWN_Y_MAX = -5
local CHASE_DISTANCE = 16
local ATTACK_DISTANCE = 1.4
local ATTACK_INTERVAL = 1.0

local function noise3d_integer(noise, pos)
	return math.abs(math.floor(noise:get_3d(pos) * 0x7fffffff))
end

local function is_day()
	local time = minetest.get_timeofday()
	return time > 0.22 and time < 0.78
end

local function get_node_light(pos)
	return minetest.get_node_light(pos) or 15
end

local function is_cave_floor(pos)
	local node = minetest.get_node(pos)
	if node.name == "air" or node.name == "ignore" then
		return false
	end
	local above = minetest.get_node({x=pos.x, y=pos.y+1, z=pos.z})
	local above2 = minetest.get_node({x=pos.x, y=pos.y+2, z=pos.z})
	if above.name ~= "air" or above2.name ~= "air" then
		return false
	end
	local def = minetest.registered_nodes[node.name]
	if not def then
		return false
	end
	if def.walkable == false then
		return false
	end
	local groups = def.groups or {}
	return groups.cracky or groups.stone or groups.crumbly or groups.cobble
		or node.name:find("stone") or node.name:find("cobble")
end

local function find_spawn_positions(minp, maxp)
	local positions = {}
	local step = 6
	for x = minp.x + 1, maxp.x - 1, step do
		for z = minp.z + 1, maxp.z - 1, step do
			local y_top = math.min(maxp.y, -8)
			local y_bot = math.max(minp.y, -31000)
			if y_top <= y_bot then
				break
			end
			for y = y_top, y_bot, -step do
				local floor = {x=x, y=y, z=z}
				if is_cave_floor(floor) then
					local feet = {x=floor.x, y=floor.y+1, z=floor.z}
					local light = get_node_light(feet)
					if light <= SPAWN_LIGHT_MAX then
						table.insert(positions, vector.new(feet))
						break
					end
				end
			end
		end
	end
	return positions
end

local function spawn_monster(pos)
	local obj = minetest.add_entity(pos, "cave_monsters:cave_stalker")
	if not obj then
		return nil
	end
	local hp = math.random(cave_monsters.MONSTER_HP_MIN, cave_monsters.MONSTER_HP_MAX)
	obj:set_hp(hp)
	return obj
end

local function random_sample(rand, list, count)
	local ret = {}
	local work = {}
	for i, v in ipairs(list) do
		work[i] = v
	end
	for n = 1, count do
		if #work == 0 then
			break
		end
		local idx = rand:next(1, #work)
		table.insert(ret, work[idx])
		table.remove(work, idx)
	end
	return ret
end

minetest.register_on_generated(function(minp, maxp, blockseed)
	if maxp.y > SPAWN_Y_MAX then
		return
	end
	local noise = minetest.get_perlin(77883, 4, 0.5, 1)
	local rand = PcgRandom(noise3d_integer(noise, {x=minp.x, y=minp.y, z=minp.z}))
	if rand:next(0, 1000) / 1000 > cave_monsters.SPAWN_CHANCE then
		return
	end
	local spawns = find_spawn_positions(minp, maxp)
	if #spawns == 0 then
		return
	end
	local count_max = cave_monsters.MAX_PER_CHUNK
	if maxp.y < -64 then
		count_max = count_max + 1
	end
	if maxp.y < -256 then
		count_max = count_max + 2
	end
	local n = rand:next(1, count_max)
	local chosen = random_sample(rand, spawns, n)
	for _, pos in ipairs(chosen) do
		spawn_monster(pos)
	end
end)

local cave_stalker_def = {
	hp_max = 20,
	physical = true,
	collide_with_objects = true,
	collisionbox = {-0.4, -1.0, -0.4, 0.4, 0.9, 0.4},
	selectionbox = {-0.4, -1.0, -0.4, 0.4, 0.9, 0.4},
	visual = "upright_sprite",
	visual_size = {x = 1.4, y = 1.8},
	textures = {
		"default_stone.png^[colorize:#10132a:190^default_mossycobble.png^[opacity:140",
		"default_stone.png^[colorize:#10132a:190",
	},
	spritediv = {x = 1, y = 1},
	initial_sprite_basepos = {x = 0, y = 0},
	makes_footstep_sound = true,
	stepheight = 0.6,
	jump = true,
	floats = 0,
	drops = {
		{name = "default:flint", chance = 20, min = 1, max = 1},
		{name = "default:coal_lump", chance = 2, min = 1, max = 3},
		{name = "default:cobble", chance = 1, min = 1, max = 2},
		{name = "default:apple", chance = 2, min = 1, max = 3},
		{name = "farming:bread", chance = 3, min = 1, max = 3},
	},
	armor_groups = {fleshy = 100, stone = 70, cracky = 50},
	attack = {
		full_punch_interval = ATTACK_INTERVAL,
		damage_groups = {fleshy = cave_monsters.MONSTER_DAMAGE},
	},

	get_staticdata = function(self)
		return minetest.serialize({
			hp = self.object:get_hp(),
		})
	end,

	on_activate = function(self, staticdata, dtime_s)
		self.object:set_armor_groups(self.armor_groups or {fleshy = 100})
		if staticdata and staticdata ~= "" then
			local data = minetest.deserialize(staticdata)
			if data and data.hp then
				self.object:set_hp(data.hp)
			end
		end
		self._monster_timer = 0
		self._attack_cooldown = 0
		self._wander_timer = 0
		self._jump_cd = 0
		self._wander_dir = nil
		self._state = "idle"
		self._target = nil
	end,

	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if not puncher or not puncher:is_player() then
			return
		end
		self._target = puncher
		self._state = "chase"
	end,

	on_death = function(self, killer)
		local pos = self.object:get_pos()
		if not pos then
			return
		end
		if self.drops then
			for _, drop in ipairs(self.drops) do
				if math.random(1, drop.chance) == 1 then
					local count = math.random(drop.min, drop.max)
					for i = 1, count do
						minetest.add_item({
							x = pos.x + (math.random() - 0.5) * 0.8,
							y = pos.y + 0.2,
							z = pos.z + (math.random() - 0.5) * 0.8,
						}, drop.name)
					end
				end
			end
		end
	end,

	on_step = function(self, dtime, moveresult)
		self._monster_timer = (self._monster_timer or 0) + dtime
		self._attack_cooldown = math.max(0, (self._attack_cooldown or 0) - dtime)
		self._jump_cd = math.max(0, (self._jump_cd or 0) - dtime)
		self._wander_timer = (self._wander_timer or 0) - dtime

		if self._monster_timer < 0.09 then
			return
		end
		local dt = self._monster_timer
		self._monster_timer = 0

		local pos = self.object:get_pos()
		if not pos then
			return
		end

		local hp = self.object:get_hp()
		if hp <= 0 then
			return
		end

		local players = minetest.get_connected_players()
		local nearest = nil
		local nearest_dist = CHASE_DISTANCE + 1

		for _, pl in ipairs(players) do
			local pp = pl:get_pos()
			if pp then
				local dist = vector.distance(pos, pp)
				if dist < nearest_dist then
					local light_at_pl = get_node_light({x=pp.x, y=pp.y+1, z=pp.z})
					if light_at_pl and light_at_pl <= SPAWN_LIGHT_MAX + 3 then
						nearest = pl
						nearest_dist = dist
					end
				end
			end
		end

		if nearest then
			self._target = nearest
			self._state = "chase"
		elseif self._state == "chase" and not nearest then
			self._state = "idle"
			self._target = nil
		end

		local yaw = self.object:get_yaw() or 0
		local velocity = self.object:get_velocity() or {x=0, y=0, z=0}
		local speed = cave_monsters.MONSTER_SPEED

		if self._state == "chase" and self._target then
			local tpos = self._target:get_pos()
			if not tpos or not self._target:get_player_name() then
				self._state = "idle"
				self._target = nil
			else
				local dx = tpos.x - pos.x
				local dz = tpos.z - pos.z
				local dist_h = math.sqrt(dx*dx + dz*dz)

				local desired_yaw = math.atan2(-dx, dz)
				local dyaw = ((desired_yaw - yaw + math.pi * 3) % (math.pi * 2)) - math.pi
				yaw = yaw + dyaw * math.min(1, dt * 5)

				if dist_h > ATTACK_DISTANCE then
					local move_x = -math.sin(yaw) * speed
					local move_z = math.cos(yaw) * speed
					self.object:set_velocity({x = move_x, y = velocity.y, z = move_z})
				else
					self.object:set_velocity({x = 0, y = velocity.y, z = 0})
					if self._attack_cooldown <= 0 then
						self._attack_cooldown = ATTACK_INTERVAL
						self._target:punch(self.object, 1.0, {
							full_punch_interval = ATTACK_INTERVAL,
							damage_groups = {fleshy = cave_monsters.MONSTER_DAMAGE},
						}, vector.direction(pos, tpos))
					end
				end

				if moveresult and moveresult.touching_ground and dist_h > 0.8 and self._jump_cd <= 0 then
					local ahead = {
						x = pos.x + -math.sin(yaw) * 0.8,
						y = pos.y,
						z = pos.z + math.cos(yaw) * 0.8,
					}
					local anode = minetest.get_node(ahead)
					if anode.name ~= "air" and anode.name ~= "ignore" then
						local def = minetest.registered_nodes[anode.name]
						if def and def.walkable ~= false then
							self.object:set_velocity({
								x = velocity.x,
								y = 5.8,
								z = velocity.z,
							})
							self._jump_cd = 0.45
						end
					end
				end
			end
		else
			if self._wander_timer <= 0 or not self._wander_dir then
				self._wander_dir = math.random() * math.pi * 2
				self._wander_timer = 1.5 + math.random() * 3.5
			end

			local dyaw = ((self._wander_dir - yaw + math.pi * 3) % (math.pi * 2)) - math.pi
			yaw = yaw + dyaw * math.min(1, dt * 2)
			local s = speed * 0.35
			self.object:set_velocity({
				x = -math.sin(yaw) * s,
				y = velocity.y,
				z = math.cos(yaw) * s,
			})

			if pos.y > 40 then
				local light = get_node_light({x=pos.x, y=pos.y+1, z=pos.z})
				if is_day() or (light and light > SPAWN_LIGHT_MAX + 4) then
					self.object:set_hp(0)
					return
				end
			end
		end

		self.object:set_yaw(yaw)
	end,
}

minetest.register_entity("cave_monsters:cave_stalker", cave_stalker_def)

minetest.register_abm({
	label = "Cave monsters ambient spawn",
	nodenames = {"group:stone", "group:cracky", "default:cobble", "default:mossycobble"},
	neighbors = {"air"},
	interval = cave_monsters.AMBIENT_SPAWN_INTERVAL,
	chance = cave_monsters.AMBIENT_SPAWN_CHANCE,
	catch_up = false,
	action = function(pos, node)
		if pos.y > SPAWN_Y_MAX then
			return
		end
		local feet = {x=pos.x, y=pos.y+1, z=pos.z}
		local head = {x=pos.x, y=pos.y+2, z=pos.z}
		if minetest.get_node(feet).name ~= "air" then
			return
		end
		if minetest.get_node(head).name ~= "air" then
			return
		end
		local light = get_node_light(feet)
		if not light or light > SPAWN_LIGHT_MAX then
			return
		end
		local objs = minetest.get_objects_inside_radius(pos, 18)
		local count = 0
		for _, o in ipairs(objs) do
			local lua = o:get_luaentity()
			if lua and lua.name and lua.name == "cave_monsters:cave_stalker" then
				count = count + 1
				if count >= cave_monsters.MAX_NEARBY then
					return
				end
			end
		end
		local player_near = false
		for _, p in ipairs(minetest.get_connected_players()) do
			local pp = p:get_pos()
			if pp then
				local d = vector.distance(pos, pp)
				if d >= 10 and d <= 48 then
					player_near = true
					break
				end
			end
		end
		if player_near then
			spawn_monster(feet)
		end
	end,
})

minetest.register_chatcommand("spawncavemonster", {
	description = "Spawn a cave stalker monster at your position",
	privs = {server = true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		local pos = player:get_pos()
		local obj = spawn_monster(pos)
		if obj then
			return true, "Cave stalker spawned at your position (HP " ..
				tostring(obj:get_hp()) .. ", dmg " .. cave_monsters.MONSTER_DAMAGE .. ")."
		else
			return false, "Failed to spawn cave stalker."
		end
	end,
})
