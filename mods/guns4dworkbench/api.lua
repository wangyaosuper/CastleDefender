function guns4dworkbench.register_ammocraft(name, def)
    if not def.output then def.output = name end
    table.insert(guns4dworkbench.registered_ammo, name)
    guns4dworkbench.registered_crafts[name] = def

    table.sort(guns4dworkbench.registered_ammo, function (a, b)
        return string.upper(a) < string.upper(b)
    end)
end

function guns4dworkbench.register_magcraft(name, def)
    if not def.output then def.output = name end
    table.insert(guns4dworkbench.registered_mags, name)
    guns4dworkbench.registered_crafts[name] = def

    table.sort(guns4dworkbench.registered_mags, function (a, b)
        return string.upper(a) < string.upper(b)
    end)
end

function guns4dworkbench.register_guncraft(name, def)
    if not def.output then def.output = name end
    table.insert(guns4dworkbench.registered_guns, name)
    guns4dworkbench.registered_crafts[name] = def

    table.sort(guns4dworkbench.registered_guns, function (a, b)
        return string.upper(a) < string.upper(b)
    end)
end

function guns4dworkbench.get_craft_for(name)
    return guns4dworkbench.registered_crafts[name]
end

function guns4dworkbench.is_eligible_for_craft(output, inv, listname)
    listname = listname or "main"
    local craft_def = guns4dworkbench.get_craft_for(output)
    if not craft_def then
        return false
    end
    local count = 0
    for _, input in pairs(craft_def.recipe) do
        if inv:contains_item(listname, ItemStack(input)) then
            count = count + 1
        end
    end
    if count >= #craft_def.recipe then
        return true
    end
    return false
end

guns4dworkbench.crafting_reasons = {
    [1] = "Insufficient items or ineligible craft.",
    [2] = "No inventory space available.",
    [3] = "Successfully handled.",
    [4] = "Was overridden by something else.",
}

--> Function for any automation. (Hopefully)
function guns4dworkbench.craft_item(output, inv, listname, override)
    override = override or false
    local boolean, number, itemstack = false, 1, nil

    local eligible = guns4dworkbench.is_eligible_for_craft(output, inv, listname)
    if eligible then
        local craft_table = guns4dworkbench.get_craft_for(output)

        local output_stack = ItemStack(craft_table.output)
        if not inv:room_for_item(listname, output_stack) and not override then
            number = 2
            return boolean, number, itemstack
        end

        for _, input in pairs(craft_table.recipe) do
            inv:remove_item(listname, ItemStack(input))
        end

        number = 3
        if override then
            number = 4
        end

        boolean, itemstack = true, inv:add_item(listname, output_stack)
    end
    return boolean, number, itemstack
end

function guns4dworkbench.player_craft_item(output, player, listname)
    listname = listname or "main"
    local inv = player:get_inventory()

    local success, number, itemstack = guns4dworkbench.craft_item(output, inv, listname, true)
    if number == 4 and itemstack ~= nil then
        core.add_item(player:get_pos(), itemstack)
        number = 3
    end
    return success, number, itemstack
end