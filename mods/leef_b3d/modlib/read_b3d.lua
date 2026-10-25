--- parse .b3d files into a lua table.
--
-- This is apart of the [LEEF-b3d](https://github.com/Luanti-Extended-Engine-Features/LEEF-b3d) module
--
-- note: capitlization of name indicates a "chunk" defined by the blitz3d format (see [b3d_specification.txt](https://github.com/Luanti-Extended-Engine-Features/LEEF-b3d/blob/master/b3d_specification.txt))
--@module b3d_reader

local read_int, read_single = leef.binary.read_int, leef.binary.read_single
local function tbl_append(table, other_table)
	local length = #table
	for index, value in ipairs(other_table) do
		table[length + index] = value
	end
	return table
end
local function tbl_keys(table)
	local keys = {}
	for key, _ in pairs(table) do
		keys[#keys + 1] = key
	end
	return keys
end
--reads a model directly (based on name). Note that "node_only" abstracts chunks not necessary to finding the position/transform of a bone/node.

--- read b3d models by their name. This simplifies `read_from_stream`.
-- @function read_model
-- @param modelname string, the name of model you are trying to read.
-- @param node_only bool, specifies wether to ignore textures, meshes, or anything else. Use this if you're only trying to solve bone transforms.
-- @return @{BB3D}
function leef.b3d_reader.read_model(modelname, node_only)
	assert(modelname, "no modelname provided")
	-- @todo remove core dependancy on
	local path = assert(leef.paths.media_paths[modelname], "no model found by the name "..modelname.."'")
	local out
	local ignored
	if node_only then
		ignored = {"TEXS", "BRUS", "BONE", "MESH"}
	end
	local stream = io.open(path, "rb")
	if not stream then return end --if the file wasn't found we probably shouldnt just assert.
	out = leef.b3d_reader.read_from_stream(stream, ignored)
	assert(stream:read(1)==nil, "LEEF b3d_reader: unknown error, EOF not reached")
	stream:close()
	return out
end

--"ignore_chunks" is a list of chunks to ignore when reading- as for various applications it may be uncessary or otherwise redundant
--note that this does not increase runtime spead as chunks still must be read before we know what they are (currently)
--chunk types: "BB3D", "TEXS", "BRUS", "TRIS", "MESH", "BONE", "ANIM", "KEYS", "VRTS", "NODE"
--this specifies what chunks can be found inside eachother
--MESH subtypes: VRTS, TRIS
--BB3D subtypes: TEXS, NODE
--NODE subtypes: KEYS, ANIM, NODE, BONE, MESH

--node_paths is a table of nodes indexed by a table containing a hierarchal list of nodes to get to that node (including itself).
--this is ideal if you need to, say, solve for the transform of a node- instead of iterating 100s of times to get every parent node
--it's all provided for you. Note that it's from highest to lowest, where lowest of course is the current node, the last element.

--made originally by appgurueu
-- See `b3d_specification.txt` as well as https://github.com/blitz-research/blitz3d/blob/master/blitz3d/loader_b3d.cpp

--- an unordered list of chunks to be ignored.
--- "NODE" and "BB3D" are ommitted as they are not allowed.
-- @field 1 "TEXS" texture information
-- @field 2 "BRUS" brushes (materials)
-- @field 3 "MESH" (sub-chunks of "MESH" include "VERTS" & "TRIS")
-- @field 4 "TRIS" sets of triangles
-- @field 5 "VRTS" vertices
-- @field 6 "BONE" node vertex weights
-- @field 7 "ANIM" animation information
-- @field 8 "KEYS" keyframes
-- @table ignore_chunks

--- table which specifies a keyframe. This is apart of the node chunk
--@field position position relative to parent {x,y,z}
--@field rotation quaternion rotation {x,y,z,w}
--@field scale scale of the node {x,y,z}
--@table keyframe

--- node paths
-- a list of nodes indexed by a hieracrchy of nodes i.e. "path.to.node"
--@field (...) node
--@table node_paths

--- read directly from file
--@function read_from_stream
--@param stream the file object (from the io library) to read from. Make sure you open it as "rb" (read binary.)
--@param ignore_chunks a list in the format of @{ignore_chunks}
--@return @{BB3D}
function leef.b3d_reader.read_from_stream(stream, ignore_chunks)
	local left = 8
	local ignored = {}
	if ignore_chunks then
		for i, v in pairs(ignore_chunks) do
			ignored[v] = true
		end
		assert(not ignored.BB3D, "reader cannot not ignore entire model. (ignore_chunks contained BB3D)")
		assert(not ignored.NODE, "reader cannot not ignore entire model. (ignore_chunks contained NODE)")
	end
	local function byte()
		left = left - 1
		return assert(stream:read(1):byte())
	end

	local function int()
		return read_int(byte, 4)
	end

	local function id()
		return int() + 1
	end

	local function optional_id()
		local id = int()
		if id == -1 then
			return
		end
		return id + 1
	end

	local function string()
		local rope = {}
		while true do
			left = left - 1
			local char = assert(stream:read(1))
			if char == "\0" then
				return table.concat(rope)
			end
			table.insert(rope, char)
		end
	end

	local function float()
		return read_single(byte)
	end

	local function float_array(length)
		local list = {}
		for index = 1, length do
			list[index] = float()
		end
		return list
	end

	local function color()
		local ret = {}
		ret.r = float()
		ret.g = float()
		ret.b = float()
		ret.a = float()
		return ret
	end

	local function vector3()
		return float_array(3)
	end

	local function quaternion()
		local w = float()
		local x = float()
		local y = float()
		local z = float()
		return {x, y, z, w}
	end

	local function content()
		if left < 0 then
			error(("unexpected EOF at position %d"):format(stream:seek()))
		end
		return left ~= 0
	end

	local node_chunk_types = {

	}
	--- chunks
	--@section chunks

	local chunk
	local chunks = {
		TEXS = function()

			local textures = {}
			while content() do
				local tex = {}
				tex.file = string()
				tex.flags = int()
				tex.blend = int()
				tex.pos = float_array(2)
				tex.scale = float_array(2)
				tex.rotation = float()
				table.insert(textures, tex)
			end
			return textures
		end,
		BRUS = function()
			local brushes = {}
			local n_texs = int()
			assert(n_texs <= 8)
			while content() do
				local brush = {}
				brush.name = string()
				brush.color = color()
				brush.shininess = float()
				brush.blend = int()
				brush.fx = int()
				brush.texture_id = {}
				for index = 1, n_texs do
					brush.texture_id[index] = optional_id()
				end
				table.insert(brushes, brush)
			end
			return brushes
		end,
		VRTS = function()
			--- vertices
			--@field flags uknown
			--@field tex_coord_sets the number of texture coordinate sets
			--@field tex_coord_set_size unknown
			--@field ... a list of vertices, the integer index defines their vertex_ids { pos={x,y,z}, color={r, g, b, a}, tex_coords=... }
			--@table VRTS
			local vertices = {}
			vertices.flags = int()
			vertices.tex_coord_sets = int()
			vertices.tex_coord_set_size = int()
			assert(vertices.tex_coord_sets <= 8 and vertices.tex_coord_set_size <= 4)
			local has_normal = (vertices.flags % 2 == 1) or nil
			local has_color = (math.floor(vertices.flags / 2) % 2 == 1) or nil
			while content() do
				local vertex = {}
				vertex.pos = vector3()
				vertex.normal = has_normal and vector3()
				vertex.color = has_color and color()
				vertex.tex_coords = {}
				for tex_coord_set = 1, vertices.tex_coord_sets do
					local tex_coords = {}
					for tex_coord = 1, vertices.tex_coord_set_size do
						tex_coords[tex_coord] = float()
					end
					vertex.tex_coords[tex_coord_set] = tex_coords
				end
				table.insert(vertices, vertex)
			end
			return vertices
		end,
		TRIS = function()
			--- triangle/poly sets
			--@field brush_id
			--@field vertex_ids a list of three vertex IDs {i, j, k} which make it up
			--@table TRIS
			local tris = {}
			tris.brush_id = id()
			tris.vertex_ids = {}
			while content() do
				local i = id()
				local j = id()
				local k = id()
				table.insert(tris.vertex_ids, {i, j, k})
			end
			return tris
		end,
		MESH = function()
			--- the mesh chunk table
			-- @field brush_id (may not exist) brush from brush chunk to use
			-- @field vertices @{VRTS} vertices and indexed by their ID and additional info
			-- @field triangle_sets @{TRIS} a list of three vertices to be used in
			-- @table MESH
			local mesh = {}
			mesh.brush_id = optional_id()
			mesh.vertices = chunk{VRTS = true}
			mesh.triangle_sets = {}
			repeat
				local tris = chunk{TRIS = true}
				table.insert(mesh.triangle_sets, tris)
			until not content()
			return mesh
		end,
		BONE = function()
			--- bone table
			-- a list of vertex weights indexed by their vertex_id
			-- @table BONE
			local bone = {}
			while content() do
				local vertex_id = id()
				assert(not bone[vertex_id], "duplicate vertex weight")
				local weight = float()
				if weight > 0 then
					-- Many exporters include unneeded zero weights
					bone[vertex_id] = weight
				end
			end
			return bone
		end,
		KEYS = function()
			--- keyframes.
			-- a list of keyframes
			-- @field flags defines if position rotation and scale exists (further explanation needed)
			-- @field ... a list of @{keyframe}s
			-- @table KEYS
			local flags = int()
			local _flags = flags % 8
			local rotation, scale, position
			if _flags >= 4 then
				rotation = true
				_flags = _flags - 4
			end
			if _flags >= 2 then
				scale = true
				_flags = _flags - 2
			end
			position = _flags >= 1
			local bone = {
				flags = flags
			}
			--see keyframe documentation
			while content() do
				local frame = {}
				--minetest uses a zero indexed frame system, so for consistency, we offset it by 1
				frame.frame = int()-1
				if position then
					frame.position = vector3()
				end
				if scale then
					frame.scale = vector3()
				end
				if rotation then
					frame.rotation = quaternion()
				end
				table.insert(bone, frame)
			end
			return bone
		end,

		ANIM = function()
			--- defines the animation of a model
			--@field flags unused?
			--@field frames number of frames
			--@field fps framerate of the model
			--@table ANIM
			local ret = {}
			ret.flags = int() -- flags are unused
			ret.frames = int()
			ret.fps = float()
			return ret
		end,
		NODE = function()
			--- node
			-- a node chunk possibly containing the following chunks.
			-- there are three possible "types" of nodes. All bones will contain the following chunks:
			-- position, rotation, scale. Bones will have a
			-- bone field which will contain IDs from it's parent node's mesh chunk.
			-- @field name
			-- @field type string which is either "pivot", "bone" or "mesh"
			-- @field children a list of child {nodes, Transformations (position, rotation, scale) will be applied to the children.
			-- @field position position {x, y, z} of the bone
			-- @field rotation quaternion {x, y, z, w} rotation of the bone at rest
			-- @field scale {x, y, z} scale of the bone at rest
			-- @field mesh @{MESH} chunk. Found in **mesh** node
			-- @field bone @{BONE} chunk. Found in **bone** node
			-- @field keys @{KEYS} chunk. Found in **bone** node
			-- @field animation @{ANIM} chunk. Typically found in root node (uknown wether it can be elsewhere.)
			-- @field parent the parent node. (The node in which this node is in the children table)
			-- @table NODE
			local node = {}
			node.name = string()
			node.position = vector3()
			node.scale = vector3()
			if not ignored.KEYS then
				node.keys = {}
			end
			node.rotation = quaternion()
			node.children = {}
			local node_type
			--See https://github.com/blitz-research/blitz3d/blob/master/blitz3d/loader_b3d.cpp#L263
			--Order is not validated; double occurrences of mutually exclusive node def are
			--... they are what appgurueu????
			while content() do
				local elem, type = chunk()
				if type == "MESH" then
					assert(not node_type)
					node_type = "mesh"
					if not ignored[type] then
						node.mesh = elem
					end
				elseif type == "BONE" then
					assert(not node_type)
					node_type = "bone"
					if not ignored[type] then
						node.bone = elem
					end
				elseif type == "KEYS" then
					if not ignored[type] then
						tbl_append(node.keys, elem)
					end
				elseif type == "NODE" then
					elem.parent = node
					table.insert(node.children, elem)
				elseif type == "ANIM" then
					if not ignored[type] then
						node.animation = elem
					end
				else
					assert(not node_type, "Appgurueu decided to not put actual comments telling me what this means, so I'm not sure, but your .b3d file is fscked up lol. I dont even think this assert is needed.")
					node_type = "pivot"
				end
			end
			--added because ignored nodes may obfuscate the type of node- which could be necessary for finding bone "paths"
			node.type = node_type or "pivot"
			-- Ensure frames are sorted ascendingly
			table.sort(node.keys, function(a, b)
				assert(a.frame ~= b.frame, "duplicate frame")
				return a.frame < b.frame
			end)
			return node
		end,
		BB3D = function()
			--- b3d table structure outputted by the b3d reader.
			-- Note: in the b3d writer the node_paths field is ignored
			-- @field node_paths all of the nodes in the model @{b3d_nodes}
			-- @field node a table containing the root @{NODE} of the model.
			-- @field textures TEXS texture information. TEXS not currently documented as not currently useful for minetest purposes
			-- @field brushes BRUS material information. BRUS not currently documented as not currently useful for minetest purposes
			-- @field version `{major=float, minor=float}` this functionally means nothing, but it's version information.
			-- @table BB3D
			local version = int()
			local self = {
				version = {
					major = math.floor(version / 100),
					minor = version % 100,
				},
			}
			if not ignored.TEXS then self.textures = {} end
			if not ignored.BRUS then self.brushes = {} end
			assert(self.version.major <= 2, "unsupported version: " .. self.version.major)
			while content() do
				local field, type = chunk{TEXS = true, BRUS = true, NODE = true}
				if not ignored[type] then
					if type == "TEXS" then
						tbl_append(self.textures, field)
					elseif type == "BRUS" then
						tbl_append(self.brushes, field)
					else
						self.node = field
					end
				end
			end
			return self
		end
	}

	local function chunk_header()
		left = left - 4
		return stream:read(4), int()
	end

	function chunk(possible_chunks)
		local type, new_left = chunk_header()
		local parent_left
		left, parent_left = new_left, left
		if possible_chunks and not possible_chunks[type] then
			error("expected one of " .. table.concat(tbl_keys(possible_chunks), ", ") .. ", found " .. type .. ". This is likely exporter error.")
		end
		local res = assert(chunks[type])()
		assert(left == 0)
		left = parent_left - new_left
		return res, type
	end

	--due to the nature of how the b3d is read, paths have to be built by recursively iterating the table in post.
	--luckily most of the ground work is layed out for us already.

	--also, Fatal here: for the sake of my reputation (which is nonexistent), typically I wouldn't nest these functions
	--because I am not a physcopath and or a german named Lars, but for the sake of consistency I am doing it like this.
	--(Not that its *always* a bad idea, but unless you're baking in parameters it's sort of useless and potentially wasteful)
	local copy_path = leef.table and leef.table.shallow_copy or function(tbl)
		local new_table = {}
		for i, v in pairs(tbl) do
			new_table[i] = v
		end
		return new_table
	end
	local function make_paths(node, path, node_paths)
		local new_path = copy_path(path)
		table.insert(new_path, node)
		node_paths[new_path] = node --this will create a list of paths
		for i, next_node in pairs(node.children) do
			make_paths(next_node, new_path, node_paths)
		end
		node.path = new_path
	end

	local self = chunk{BB3D = true}
	-- see node_paths documentation
	self.node_paths = {}
	self.excluded_chunks = ignore_chunks and table.copy(ignore_chunks) or {}
	assert(self.node, "no root node - model improperly exported. If using blender, ensure all objects are selected before exporting.")
	make_paths(self.node, {}, self.node_paths)

	--b3d metatable unimplemented
	return setmetatable(self, leef._b3d_metatable or {})
end