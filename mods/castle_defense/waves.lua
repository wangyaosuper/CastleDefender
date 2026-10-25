-- castle_defense/waves.lua
--
-- Wave scheduler, HUD and win/lose arbitration.
--
--   * monsters march in from the plain in waves of growing size,
--   * the player holds the walls; a monster left alone long enough chews a
--     breach and runs for the keep,
--   * the narrow end of the valley behind the inner wall is the capture zone:
--     one monster setting foot in there and the monsters win,
--   * surviving the last wave wins the game for the defenders.

local modpath = minetest.get_modpath("castle_defense")
local arena = dofile(modpath .. "/arena.lua")

local MONSTER = "castle_defense:land_guard"

local WAVE = {
	first_delay = 30,  -- seconds of peace before the first wave
	rest = 25,         -- seconds between two waves
	base_size = 3,     -- monsters in wave 1
	growth = 2,        -- extra monsters per wave
	max_size = 20,     -- never send more than this at once
	timeout = 150,     -- a wave that will not end by itself is cut short
	total = 10,        -- survive this many waves to win
}

local SCAN_INTERVAL = 0.5
local BANNER_TIME = 5

-- Everything in the arena lies within this distance of the middle of the plaza.
local SCAN_CENTER = {x = 0, y = 0, z = 10}
local SCAN_RADIUS = 110

local game = {
	phase = "prepare", -- prepare | fighting | rest | won | lost
	timer = 0,
	wave = 0,
	alive = 0,
}

local scan_timer = 0
local banner_until = 0
local banner_on = false

-- Status line ----------------------------------------------------------------

local function status_text()

	if game.phase == "won" then
		return "DEFENDERS WIN -- the keep held for " .. WAVE.total .. " waves"
	elseif game.phase == "lost" then
		return "MONSTERS WIN -- the horde broke into the keep"
	elseif game.phase == "prepare" then
		return "Prepare your defences -- wave 1 in "
				.. math.max(0, math.ceil(WAVE.first_delay - game.timer)) .. "s"
	elseif game.phase == "rest" then
		return "Wave " .. game.wave .. " cleared -- next wave in "
				.. math.max(0, math.ceil(WAVE.rest - game.timer)) .. "s"
	end

	return "Wave " .. game.wave .. "/" .. WAVE.total
			.. " -- monsters left: " .. game.alive
end

-- HUD ------------------------------------------------------------------------

local hud_ids = {}

local function set_hud(field, text, color)

	for name, ids in pairs(hud_ids) do

		local player = minetest.get_player_by_name(name)

		if player then
			player:hud_change(ids[field], "text", text)

			if color then
				player:hud_change(ids[field], "number", color)
			end
		end
	end
end

local function set_status()
	set_hud("status", status_text())
end

local function flash(text, color)
	banner_until = minetest.get_gametime() + BANNER_TIME
	banner_on = true
	set_hud("banner", text, color)
end

local function clear_banner()
	banner_on = false
	set_hud("banner", "")
end

local function install_hud(player)

	local name = player:get_player_name()

	if hud_ids[name] then return end

	hud_ids[name] = {
		status = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.5, y = 0},
			offset = {x = 0, y = 24},
			alignment = {x = 0, y = 1},
			number = 0xFFFFFF,
			text = ""
		}),
		banner = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.5, y = 0.32},
			offset = {x = 0, y = 0},
			alignment = {x = 0, y = 0},
			scale = {x = 200, y = 200},
			number = 0xFFCC44,
			text = ""
		})
	}

	set_status()
end

minetest.register_on_joinplayer(function(player)

	install_hud(player)

	minetest.chat_send_player(player:get_player_name(),
		"[CastleDefinder] Hold the walls. If a monster reaches the red zone "
		.. "deep in the keep, the monsters win.")
end)

minetest.register_on_leaveplayer(function(player)
	hud_ids[player:get_player_name()] = nil
end)

-- Game flow ------------------------------------------------------------------

local function broadcast(text)
	minetest.chat_send_all("[CastleDefinder] " .. text)
end

local function wave_size(wave)
	return math.min(WAVE.base_size + (wave - 1) * WAVE.growth, WAVE.max_size)
end

local function finish(phase, text, color)
	game.phase = phase
	flash(text, color)
	broadcast(text)
	set_status()
end

-- Counts the monsters still on the field and reports a breach of the keep.
local function scan()

	local alive, breached = 0, false

	for _, obj in ipairs(minetest.get_objects_inside_radius(SCAN_CENTER, SCAN_RADIUS)) do

		local ent = obj:get_luaentity()

		if ent and ent.name == MONSTER then

			alive = alive + 1

			local pos = obj:get_pos()

			if pos and arena.in_capture(pos) then
				breached = true
			end
		end
	end

	return alive, breached
end

local function clear_field()

	for _, obj in ipairs(minetest.get_objects_inside_radius(SCAN_CENTER, SCAN_RADIUS)) do

		local ent = obj:get_luaentity()

		if ent and ent.name == MONSTER then
			obj:remove()
		end
	end
end

local function start_wave()

	game.wave = game.wave + 1
	game.phase = "fighting"
	game.timer = 0

	local size = wave_size(game.wave)

	for _ = 1, size do
		mobs:add_mob(arena.random_spawn_pos(), {
			name = MONSTER,
			ignore_count = true
		})
	end

	game.alive = size

	flash("WAVE " .. game.wave .. " -- " .. size .. " MONSTERS INCOMING", 0xFF6644)
	broadcast("Wave " .. game.wave .. "/" .. WAVE.total .. ": " .. size .. " monsters.")
	set_status()
end

local function wave_cleared()

	if game.wave >= WAVE.total then
		finish("won", "DEFENDERS WIN -- the keep held for " .. WAVE.total .. " waves",
			0x66FF66)
		return
	end

	game.phase = "rest"
	game.timer = 0
	broadcast("Wave " .. game.wave .. " cleared.")
	set_status()
end

minetest.register_globalstep(function(dtime)

	if banner_on and minetest.get_gametime() > banner_until then
		clear_banner()
	end

	if game.phase == "won" or game.phase == "lost" then return end

	-- Nobody is on the walls yet: hold the siege until a defender joins, or the
	-- clock would run the whole game out before anyone gets to fight.
	if #minetest.get_connected_players() == 0 then return end

	game.timer = game.timer + dtime
	scan_timer = scan_timer + dtime

	if scan_timer >= SCAN_INTERVAL then

		scan_timer = 0

		local alive, breached = scan()
		game.alive = alive

		if breached then
			finish("lost", "MONSTERS WIN -- the horde broke into the keep", 0xFF5555)
			return
		end

		set_status()
	end

	if game.phase == "fighting" then

		if game.alive == 0 and game.timer > 5 then
			wave_cleared()
		elseif game.timer > WAVE.timeout then
			flash("THE HORDE REGROUPS", 0xFFAA44)
			start_wave()
		end

	elseif game.phase == "prepare" then

		if game.timer >= WAVE.first_delay then
			start_wave()
		end

	elseif game.phase == "rest" then

		if game.timer >= WAVE.rest then
			start_wave()
		end
	end
end)

-- The arena is one long siege, so give the host a way to run it again.
minetest.register_chatcommand("cd_restart", {
	description = "Restart the defence from wave 1",
	privs = {server = true},
	func = function()

		clear_field()

		game.phase = "prepare"
		game.wave = 0
		game.timer = 0
		game.alive = 0
		scan_timer = 0

		clear_banner()
		set_status()

		return true, "Defence restarted -- wave 1 in " .. WAVE.first_delay .. "s."
	end
})
