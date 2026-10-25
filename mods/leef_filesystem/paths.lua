--- used to find mod media and modpath information
--
-- This is apart of the [LEEF-filesystem](https://github.com/Luanti-Extended-Engine-Features/LEEF-filesystem) module.
-- @module paths

local media_foldernames = {"textures", "sounds", "media", "models", "locale"}
local media_extensions = {
	-- Textures
	"png", "jpg", "bmp", "tga", "pcx", "ppm", "psd", "wal", "rgb";
	-- Sounds
	"ogg";
	-- Models
	"x", "b3d", "md2", "obj", "gltf";
	-- Translations
	"tr";
}
local function split_extension(filename)
	return filename:match"^(.*)%.(.*)$"
end
--make it a set.
for i, v in pairs(media_extensions) do
    media_extensions[v] = true
end

local function get_resource(modname, resource)
	if not resource then
		resource = modname
		modname = minetest.get_current_modname()
	end
	return table.concat({minetest.get_modpath(modname), resource}, "/")
end

local function collect_media(modname)
	local media = {}
	local function traverse(folderpath)
		-- Traverse files (collect media)
		local filenames = minetest.get_dir_list(folderpath, false)
		for _, filename in pairs(filenames) do
			local _, ext = split_extension(filename)
			if media_extensions[ext] then
				media[filename] = table.concat({folderpath, filename}, "/")
			end
		end
		-- Traverse subfolders
		local foldernames = minetest.get_dir_list(folderpath, true)
		for _, foldername in pairs(foldernames) do
			if not foldername:match"^[_%.]" then -- ignore hidden subfolders / subfolders starting with `_`
				traverse(table.concat({folderpath, foldername}, "/"))
			end
		end
	end
	for _, foldername in ipairs(media_foldernames) do -- order matters!
		traverse(get_resource(modname, foldername))
	end
	return media
end

-- TODO clean this up eventually
local paths = {}
local mods = {}
local overridden_paths = {}
local mods_with_overriden_media = {}
for _, mod in ipairs(leef.utils.get_mod_load_order()) do
	local mod_media = collect_media(mod.name)
	for medianame, path in pairs(mod_media) do
		if paths[medianame] then
			overridden_paths[medianame] = overridden_paths[medianame] or {}
			table.insert(overridden_paths[medianame], paths[medianame])
			mods_with_overriden_media[medianame] = mods_with_overriden_media[medianame] or {}
			table.insert(mods_with_overriden_media[medianame], mods[medianame])
		end
		paths[medianame] = path
		mods[medianame] = mod.name
	end
end
--- paths of loaded media.
-- a list of filepaths of loaded media, i.e:
--	{
--		["model.b3d"] = "C:/path/minetest/mods/mod2/models/model.b3d"
--		["img.png"] = "C:/path/minetest/mods/mod2/textures/img.png"
--	}
-- NOTE: "loaded" meaning the final mediapath- what the client loads.
-- @table media_paths
leef.paths.media_paths = paths

---modname by media.
-- a list of mods by indexed by the name of loaded media
--	{
--		["model.b3d"] = "mod2"
--	}
-- NOTE: "loaded" meaning the final mediapath (what the client ultimately loads)
-- @table modname_by_media
leef.paths.modname_by_media = mods

--- overriden media paths.
-- a list of media paths that were overriden by conflicting model names- the unloaded media, i.e:
--	{
--		["model.b3d"] = {
--			"C:/path/minetest/mods/mod1/models/model.b3d"
--		}
--	}
-- @table overriden_media_paths
leef.paths.overriden_media_paths = overridden_paths

--- mods with overriden media (indexed by media).
-- a list of mods that have overriden media, by media names
--	{
--		["model.b3d"] = {
--			"mod1",
--		}
--	}
-- @table overriden_media_paths
leef.paths.mods_with_overriden_media = mods_with_overriden_media