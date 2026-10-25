Guns4d.node_properties = {}
--{["default:gravel"] = {rha=2, random_deviation=1, behavior="normal"}, . . . }
--behavior types:
--normal, bullets hit and penetrate
--breaks, bullets break it but still applies RHA/randomness values (etc)
--ignore, bullets pass through

--unimplemented

--liquid, bullets hit and penetrate, but effects are different
--damage, bullets hit and penetrate, but replace with "replace = _"

--mmRHA of wood .05 (mostly arbitrary)
--{choppy = 2, oddly_breakable_by_hand = 2, flammable = 2, wood = 1}

--this is really the best way I could think of to do this
--in a perfect world you could perfectly balance each node, but a aproximation will have to do
--luckily its still an option, if you are literally out of your fucking mind.
minetest.register_on_mods_loaded(function()
    for i, v in pairs(minetest.registered_nodes) do
        local groups = v.groups
        local RHA = 1
        local random_deviation = 1
        local behavior_type = "normal"
        if groups.oddly_breakable_by_hand then
            RHA = RHA / groups.oddly_breakable_by_hand
        end
        if groups.choppy then
            RHA = RHA/(10*groups.choppy)
        end
        if groups.flora or groups.grass then
            RHA = 0
            random_deviation = 0
            behavior_type = "ignore"
        end
        if groups.leaves then
            --RHA = .0001
            --random_deviation = .005
            behavior_type = "ignore"
        end
        if groups.stone then
            RHA = 1/groups.stone
            random_deviation = .5
        end
        if groups.cracky then
            RHA = RHA*(.5/groups.cracky)
            random_deviation = random_deviation*(.5/groups.cracky)
        end
        if groups.crumbly then
            RHA = RHA/groups.crumbly
        end
        if groups.soil then
            RHA = RHA*(groups.soil*2)
        end
        if groups.sand then
            RHA = RHA*(groups.sand*2)
        end
        if groups.liquid then
            --behavior type here
            --RHA = .5
            --random_deviation = .1
            behavior_type = "ignore"
        end
        if groups.glass then
            RHA = RHA / (groups.glass * 200)
            random_deviation = 0.2
            behavior_type = "breaks"
        end
        --"rolled homogenous armor"
        if behavior_type=="ignore" then
            RHA=0
            random_deviation=0
        end
        Guns4d.node_properties[i] = {mmRHA=RHA*1000, random_deviation=random_deviation, behavior=behavior_type}
    end

    -- Override for basic_houses window nodes: ensure guns can easily break ALL windows
    -- basic_houses.glass list from basic_houses/init.lua:
    --   xpanes:pane_flat, default:glass, default:obsidian_glass, xpanes:bar_flat
    -- Also includes MineClone2 variants and colored panes.
    local fragile_window_overrides = {
        -- Very low mmRHA so even weak pistols/shotguns break them easily at any range.
        -- Sharp penetration of weakest ammo: .45 ACP = 4mm, 12G = 2mm per pellet.
        -- We use 0.05 mmRHA = 0.00005 effective after 1000 multiplier, effectively instant break.
        mmRHA = 0.05,
        random_deviation = 0.01,
        behavior = "breaks"
    }
    local bar_window_overrides = {
        -- Iron bars slightly tougher but still breakable by any gun
        mmRHA = 0.3,
        random_deviation = 0.05,
        behavior = "breaks"
    }
    local obsidian_glass_overrides = {
        -- Obsidian glass tougher than normal but still breakable
        mmRHA = 0.8,
        random_deviation = 0.1,
        behavior = "breaks"
    }

    local function set_override(name, overrides)
        if Guns4d.node_properties[name] then
            Guns4d.node_properties[name].mmRHA = overrides.mmRHA
            Guns4d.node_properties[name].random_deviation = overrides.random_deviation
            Guns4d.node_properties[name].behavior = overrides.behavior
        end
    end

    -- 1) Flat glass panes (most common window in basic_houses)
    set_override("xpanes:pane_flat", fragile_window_overrides)

    -- 2) Colored glass panes (MineClone2 support)
    local pane_colors = {"red", "green", "blue", "light_blue", "black", "white",
                         "yellow", "brown", "orange", "pink", "grey", "silver",
                         "magenta", "purple", "cyan", "lime"}
    for _, c in ipairs(pane_colors) do
        set_override("xpanes:pane_" .. c .. "_flat", fragile_window_overrides)
    end

    -- 3) Solid glass blocks
    set_override("default:glass", fragile_window_overrides)
    set_override("mcl_core:glass", fragile_window_overrides)
    for _, c in ipairs(pane_colors) do
        set_override("mcl_core:glass_" .. c, fragile_window_overrides)
    end

    -- 4) Obsidian glass (tougher, but still should break)
    set_override("default:obsidian_glass", obsidian_glass_overrides)

    -- 5) Iron bars / bar panes (used as "windows" too in basic_houses)
    set_override("xpanes:bar_flat", bar_window_overrides)
    set_override("xpanes:bar", bar_window_overrides)
    set_override("default:iron_bars", bar_window_overrides)
end)
function Guns4d.override_node_propertoes(node, table)
    --TODO: check if node is valid
    assert(type(table.mmRHA)=="number", "no mmRHA value provided in override")
    assert(type(table.behavior)=="string", "no behavior type provided in override")
    assert(type(table.random_deviation)=="number", "no random_deviation value provided in override")
    Guns4d.node_properties[node] = table
end