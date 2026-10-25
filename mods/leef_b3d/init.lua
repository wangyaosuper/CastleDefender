
--[[
   this library provides two modules:
   b3d
   b3d_nodes

   b3d_nodes is for reading and interperetting b3d objects from the b3d module.
   the b3d module is a heavily modified version of Modlib's b3d reader, and as such
   has it's own respective directory for licensing purposes.
]]

leef = leef or {}
leef.b3d_reader = {}
leef.b3d_writer = {}
leef.loaded_modules.b3d = true

local modpath = minetest.get_modpath("leef_b3d")
--placed in a seperate directory for the license
dofile(modpath.."/modlib/read_b3d.lua")
dofile(modpath.."/modlib/write_b3d.lua")
--dofile(modpath.."/modlib/to_gltf.lua")

--prevent accidental access of unavailable features:
if leef.math then
   leef.b3d_nodes = dofile(modpath.."/nodes.lua")
else
   leef.b3d_nodes = {}
   setmetatable(leef.b3d_nodes, {
      __index = function(_, k)
         if k ~= "loaded" then
            error("LEEF-Math not present, b3d_nodes not loaded.")
         else
            return false
         end
      end
   })
end
--dofile(modpath.."/read_b3d_bone.lua"