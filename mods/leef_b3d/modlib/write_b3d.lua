--- writes b3d models in the same format as outputted by the b3d reader modul
--
-- This is apart of the [LEEF-b3d](https://github.com/Luanti-Extended-Engine-Features/LEEF-b3d) module
--
--@module b3d_writer


--Writer
local write_int, write_single = leef.binary.write_int, leef.binary.write_single
local string_char = string.char

local function write_rope(self)
	local rope = {}

	local written_len = 0
	local function write(str)
		written_len = written_len + #str
		table.insert(rope, str)
	end

	local function byte(val)
		write(string_char(val))
	end

	local function int(val)
		write_int(byte, val, 4)
	end

	local function id(val)
		int(val - 1)
	end

	local function optional_id(val)
		int(val and (val - 1) or -1)
	end

	local function string(val)
		write(val)
		write"\0"
	end

	local function float(val)
		write_single(byte, leef.binary.fround(val))
	end

	local function float_array(arr, len)
		assert(#arr == len)
		for i = 1, len do
			float(arr[i])
		end
	end

	local function color(val)
		float(val.r)
		float(val.g)
		float(val.b)
		float(val.a)
	end

	local function vector3(val)
		float_array(val, 3)
	end

	local function quaternion(quat)
		float(quat[4])
		float(quat[1])
		float(quat[2])
		float(quat[3])
	end

	local function chunk(name, write_func)
		write(name)

		-- Insert placeholder for the 4-bit len
		table.insert(rope, false)
		written_len = written_len + 4
		local len_idx = #rope -- save index of placeholder

		local prev_written_len = written_len
		write_func()

		-- Write the length of this chunk
		local chunk_len = written_len - prev_written_len
		local len_binary = {}
		write_int(function(byte)
			table.insert(len_binary, string_char(byte))
		end, chunk_len, 4)
		rope[len_idx] = table.concat(len_binary)
	end

	local function NODE(node)
		chunk("NODE", function()
			assert(node.scale, "a node is missing a name")
			string(node.name)
			assert(node.scale, "a node is missing position")
			vector3(node.position)
			assert(node.scale, "a node is missing scale")
			vector3(node.scale)
			assert(node.scale, "a node is missing rotation")
			quaternion(node.rotation)
			local mesh = node.mesh
			if mesh then
				chunk("MESH", function()
					optional_id(mesh.brush_id)
					local vertices = mesh.vertices
					chunk("VRTS", function()
						int(vertices.flags)
						int(vertices.tex_coord_sets)
						int(vertices.tex_coord_set_size)
						for _, vertex in ipairs(vertices) do
							vector3(vertex.pos)
							if vertex.normal then vector3(vertex.normal) end
							if vertex.color then color(vertex.color) end
							for tex_coord_set = 1, vertices.tex_coord_sets do
								local tex_coords = vertex.tex_coords[tex_coord_set]
								for tex_coord = 1, vertices.tex_coord_set_size do
									float(tex_coords[tex_coord])
								end
							end
						end
					end)
					for _, triangle_set in ipairs(mesh.triangle_sets) do
						chunk("TRIS", function()
							id(triangle_set.brush_id)
							for _, tri in ipairs(triangle_set.vertex_ids) do
								id(tri[1])
								id(tri[2])
								id(tri[3])
							end
						end)
					end
				end)
			end
			if node.bone then
				chunk("BONE", function()
					for vertex_id, weight in pairs(node.bone) do
						id(vertex_id)
						float(weight)
					end
				end)
			end
			if node.keys then
				local keys_by_flags = {}
				for _, key in ipairs(node.keys) do
					local flags = 0
					flags = flags
						+ (key.position and 1 or 0)
						+ (key.scale and 2 or 0)
						+ (key.rotation and 4 or 0)
					keys_by_flags[flags] = keys_by_flags[flags] or {}
					table.insert(keys_by_flags[flags], key)
				end
				for flags, keys in pairs(keys_by_flags) do
					chunk("KEYS", function()
						int(flags)
						for _, frame in ipairs(keys) do
							int(frame.frame)
							if frame.position then vector3(frame.position) end
							if frame.scale then vector3(frame.scale) end
							if frame.rotation then quaternion(frame.rotation) end
						end
					end)
				end
			end
			local anim = node.animation
			if anim then
				chunk("ANIM", function()
					int(anim.flags)
					int(anim.frames)
					float(anim.fps)
				end)
			end
			for _, child in ipairs(node.children) do
				NODE(child)
			end
		end)
	end

	chunk("BB3D", function()
		int(self.version.major * 100 + self.version.minor)
		if self.textures[1] then
			chunk("TEXS", function()
				for _, tex in ipairs(self.textures) do
					string(tex.file)
					int(tex.flags)
					int(tex.blend)
					float_array(tex.pos, 2)
					float_array(tex.scale, 2)
					float(tex.rotation)
				end
			end)
		end
		if self.brushes[1] then
			local max_n_texs = 0
			for _, brush in ipairs(self.brushes) do
				for n in pairs(brush.texture_id) do
					if n > max_n_texs then
						max_n_texs = n
					end
				end
			end
			chunk("BRUS", function()
				int(max_n_texs)
				for _, brush in ipairs(self.brushes) do
					string(brush.name)
					color(brush.color)
					float(brush.shininess)
					int(brush.blend)
					int(brush.fx)
					for index = 1, max_n_texs do
						optional_id(brush.texture_id[index])
					end
				end
			end)
		end
		if self.node then
			NODE(self.node)
		end
	end)
	return rope
end

--- output a string of binary in the blitz 3d format
-- @function write_string
-- @param self @{b3d_reader.BB3D|BB3D}
-- @return string containing the binary file
function leef.b3d_writer.write_string(self)
	return table.concat(write_rope(self))
end

--- output in the blitz3d format file reference
-- @function write_model_to_file
-- @param self @{b3d_reader.BB3D|BB3D}
-- @param stream io file object to write to
function leef.b3d_writer.write_model_to_file(self, stream)
	for _, str in ipairs(write_rope(self)) do
		stream:write(str)
	end
end