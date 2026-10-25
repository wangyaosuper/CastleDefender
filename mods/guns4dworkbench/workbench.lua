local gui = flow.widgets
local workbench_formspec = flow.make_gui(function(player, ctx)
    local buttons_hbox = gui.Hbox{gui.Spacer{}}
    for _, type in pairs({"Guns", "Mags", "Ammo"}) do
        table.insert(buttons_hbox, 1, gui.Button{
            label = type,
            on_event = function(player, ctx)
                ctx.category = string.lower(type)
                return true
            end,
        })
    end

    local category = ctx.category or "ammo"
    local dropdown_table = guns4dworkbench[string.format("registered_%s", category)]
    local itemname = dropdown_table[ctx.form.workbench_dropdown or 1]
    table.insert(buttons_hbox, gui.Button{
        label = "Craft",
        on_event = function(player, ctx)
            local success, reason = guns4dworkbench.player_craft_item(itemname, player)
            if not success then
                core.chat_send_player(player:get_player_name(), core.colorize("#FF0000", string.format("Unable to craft. Reason: %s", guns4dworkbench.crafting_reasons[reason])))
            end
            return true
        end,
        w = 2,
    })

    local craft_table = guns4dworkbench.get_craft_for(itemname)
    local dropdown_hbox = gui.Hbox{
        gui.Dropdown{
            name = "workbench_dropdown",
            items = dropdown_table,
            w = 5.5,
            index_event = true,
        },
        gui.Spacer{},
        gui.ItemImage{
            w = 2, h = 2,
            item_name = craft_table.output,
            tooltip = ItemStack(craft_table.output):get_short_description(),
        },
    }

    local materials_hbox = gui.Hbox{
        gui.Label{label = "Materials:", style = {font_size = "*1.5"}},
    }
    for _, item in pairs(craft_table.recipe) do
        table.insert(materials_hbox, gui.Stack{
            gui.ItemImage{
                w = 1.25, h = 1.25,
                item_name = item,
                tooltip = ItemStack(item):get_short_description(),
            },
        })
    end

    return gui.Vbox{
        gui.Label{label = "Guns4dWorkbench", align_h = "centre", style = {font = "bold", font_size = "*1.5"}},
        buttons_hbox, dropdown_hbox, materials_hbox,
        gui.List{
            inventory_location = "current_player",
            list_name = "main",
            w = 8,
            h = 4,
        },
    }
end)

core.register_node("guns4dworkbench:Workbench", {
    description = "Gunsmith Workbench",
    groups = {cracky = 3},
    paramtype2 = "facedir",
    drawtype = "mesh",
    mesh = "guns4dworkbench.obj",
    tiles = {"guns4dworkbench.png"},
    visual_scale = 2,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        workbench_formspec:show(clicker)
    end
})