# guns4dworkbench API

There are three components that are registered: Ammo, Mags, and Guns.

- Ammo: Bullets for the gun.
- Mags (Magazines): Where the bullets are stored.
- Guns: The gun itself.

## Registration Functions

There are three registration functions for each of the three components stated above.

- `guns4dworkbench.register_ammocraft(name, def)`
- `guns4dworkbench.register_magcraft(name, def)`
- `guns4dworkbench.register_guncraft(name, def)`

The registration works like the `shapeless` type in `core.register_craft`. See [Minetest Modding Book](https://rubenwardy.com/minetest_modding_book/en/items/nodes_items_crafting.html#crafting) for a clearer explanation on this.

If no output is stated, the name registered will be used as the output.

Example:

```lua
guns4dworkbench.register_ammocraft("guns4d_pack_1:45A", {
    output = "guns4d_pack_1:45A 10",
    recipe = {
        "default:copper_ingot",
        "tnt:gunpowder",
    }
})

guns4dworkbench.register_magcraft("guns4d_pack_1:awm_magazine", {
    recipe = {
        "default:steel_ingot 10",
    },
})

guns4dworkbench.register_guncraft("guns4d_pack_1:awm", {
    recipe = {
        "default:steel_ingot 30",
    },
})
```

## Global Tables

- `guns4dworkbench.registered_ammo`
  - Map of all the registered ammos.
- `guns4dworkbench.registered_mags`
  - Map of all the registered magazines.
- `guns4dworkbench.registered_guns`
  - Map of all the registered guns.
- `guns4dworkbench.registered_crafts`
  - Map of all the registered crafts, indexed by name.

## Crafting Functions

- `guns4dworkbench.get_craft_for(name)`
  - Returns `nil` if not found.
  - Returns the `def` found in the registration functions.
- `guns4dworkbench.is_eligible_for_craft(output, inv, listname)`
  - Checks to see if the inventory, `inv`, inside of list, `listname`, meets the needs for the output, `output`.
  - Returns boolean `true` for success and returns boolean `false` for failure.
  - If `listname` is `nil`, it will default to `"main"`.
    - Automatically assumes that the `inv` is a player inventory.

Example:

```lua
guns4dworkbench.is_eligible_for_craft("guns4d_pack_1:45A", player:get_inventory())
```

- `guns4dworkbench.craft_item(output, inv, listname, override)`
  - Crafts the item stated in `output`.
  - `inv` is an `InvRef`.
  - `listname` is a type of list in `InvRef`.
  - `override` is a boolean.
  - Returns `boolean, number, ItemStack`.
    - Boolean:
      - `True` -> Success.
      - `False` -> Failure.
    - Number:
      - `1` -> Insufficient items or ineligible craft.
      - `2` -> No inventory space available.
      - `3` -> Successfully handled.
      - `4` -> Was overridden by something else.
    - Itemstack:
      - Returns `nil` or `ItemStack` depending on whether `override` is true and if there is space in the inventory.
  - This function is used for autonomy. For players, use `guns4dworkbench.player_craft_item()`
- `guns4dworkbench.player_craft_item(output, player, listname)`
  - Mirror function to `guns4dworkbench.craft_item()` above.
  - The main difference is that if there is no more space in the player's inventory, the output will drop onto the player's position.
  - `listname` will default to `"main"` unless otherwise stated.
