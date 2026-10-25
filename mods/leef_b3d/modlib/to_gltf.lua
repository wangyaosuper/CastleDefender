

--THIS FILE IS INACTIVE, VERY BROKEN


--appgurueu:
-- B3D to glTF converter
-- See https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
--! Highly experimental; expect bugs!

-- glTF constants
local write_int, write_uint, write_single = leef.binary.write_int, leef.binary.write_uint, leef.binary.write_single
local array_buffer = 34962 -- "Buffer containing vertex attributes, such as vertices, texcoords or colors."
local element_array_buffer = 34963 -- "Buffer used for element indices."
local component_type = {
    signed_byte = 5120,
    unsigned_byte = 5121,
    signed_short = 5122,
    unsigned_short = 5123,
    unsigned_int = 5125,
    float = 5126,
}

function write_gltf(self, file)
	modlib.json:write_file(self:to_gltf(), file)
end

-- Coordinate system conversions:
-- "Blitz 3D uses a left-handed system: X+ is to the right. Y+ is up. Z+ is forward."
-- "glTF uses a right-handed coordinate system. glTF defines +Y as up, +Z as forward, and -X as right;
-- the front of a glTF asset faces +Z."

local function translation_to_gltf(vec)
    return {-vec[1], vec[2], vec[3]} -- invert the X-axis
end

local function quaternion_to_gltf(quat)
    -- TODO (!) is this correct?
    return {-quat[1], quat[2], quat[3], quat[4]} -- invert the X-axis
end

-- Convert a color from table format to glTF RGBA list format
local function color_to_gltf(col)
    return {col.r, col.g, col.b, col.a}
end

-- Basic helpers for writing to the buffer, all parameterized in terms of `write_byte`

local function write_index(write_byte, index)
    write_uint(write_byte, index - 1 --[[1-based to 0-based]], 4)
end

local function write_float(write_byte, float)
    assert(-math.huge < float and float < math.huge)
    assert(-math.huge < fround(float) and fround(float) < math.huge, ("%.18g got %.18g"):format(float, fround(float)))
    write_single(write_byte, fround(float))
end

local function write_floats(write_byte, floats, expected_len)
    assert(#floats == expected_len)
    for i = 1, expected_len do
        write_float(write_byte, floats[i])
    end
end

local function write_vector(write_byte, vec)
    return write_floats(write_byte, vec, 3)
end

local function write_translation(write_byte, vec)
    return write_vector(write_byte, translation_to_gltf(vec))
end

local function write_quaternion(write_byte, quat)
    -- XYZW order is already correct, but we still need to convert left-handed to right-handed
    return write_floats(write_byte, quaternion_to_gltf(quat), 4)
end

function leef.b3d.to_gltf(self)
    -- Accessor helper: Stores arrays of raw data in a buffer, produces views & accessors.
    -- Everything is dumped in the same large buffer.
    local buffer_rope = {} -- buffer content (table of strings)
    local buffer_views = {} -- glTF buffer views
    local accessors = {} -- glTF accessors
    local offset = 0 -- current byte offset
    local function add_accessor(
        type, -- name of the composite type (e.g. SCALAR, VEC3, VEC4, MAT4, ...)
        comp_type, -- name of the component type (e.g. float, unsigned_int, ...)
        index, -- true / false / nil: whether this is an index (true) or vertex data (false) or neither (nil)
        func -- `function(write_byte) ... return count, min, max end` to be called to write to the buffer view;
             -- the count of elements written must be returned; min and max may be returned
    )
        -- Always add padding to obtain a multiple of 4
        -- TODO (?) don't add padding if it isn't required
        table.insert(buffer_rope, ("\0"):rep(offset % 4))
        offset = math.ceil(offset / 4) * 4
        local bytes_written = 0
        local count, min, max = func(function(byte)
            table.insert(buffer_rope, string_char(byte))
            bytes_written = bytes_written + 1
        end)
        assert(count)

        -- Add buffer view
        table.insert(buffer_views, {
            buffer = 0, -- 0-based - there only is one buffer
            byteOffset = offset,
            byteLength = bytes_written,
            target = ((index == true) and element_array_buffer) -- index data
                or ((index == false) and array_buffer) -- vertex data
                or nil, -- no target hint
        })
        table.insert(accessors, {
            bufferView = #buffer_views - 1, -- 0-based
            byteOffset = 0, -- view has correct offset
            componentType = assert(component_type[comp_type]),
            type = type,
            count = count,
            min = min,
            max = max,
        })

        offset = offset + bytes_written
        return #accessors - 1 -- 0-based index of the accessor
    end

    local textures = {} -- glTF textures
    local function add_texture(name)
        -- TODO (?) add an appropriate sampler
        table.insert(textures, {name = name})
        return #textures - 1 -- 0-based texture index
    end
    for _, tex in ipairs(self.textures) do
        -- Assert that all values we don't map properly yet are defaults
        -- TODO dig into Blitz3D sources to figure out the meaning of flags & blend
        -- TODO (...) deal with flag value of 65536:
        -- "The flags field value can conditional an additional flag value of '65536'.
        -- This is used to indicate that the texture uses secondary UV values, ala the TextureCoords command."
        assert(tex.flags == 1) -- TODO (?) see https://github.com/blitz-research/blitz3d/blob/master/gxruntime/gxcanvas.h#L59
        assert(tex.blend == 2)
        -- Assert that the texture isn't transformed
        assert(tex.rotation == 0)
        assert(tex.pos[1] == 0 and tex.pos[2] == 0)
        assert(tex.scale[1] == 1 and tex.scale[2] == 1)
        add_texture(tex.file)
    end

    -- Map brushes to materials (& textures)
    local materials = {}
    for i, brush in ipairs(self.brushes) do
        -- Assert defaults
        -- See https://github.com/blitz-research/blitz3d/blob/6beb288cb5962393684a59a4a44ac11524894939/blitz3d/brush.cpp#L164-L167:
        -- 0 = default/replace, 1 = alpha, 2 = multiply, 3 = add
        assert(brush.blend == 1) -- (alpha)
        -- TODO (...) figure out what these "effects" are and if/how to map them to glTF
        assert(brush.fx == 0)
        assert(#brush.texture_id <= 1) -- TODO (...) this supports only a single texture per brush for now
        local index
        if brush.texture_id[1] then
            index = brush.texture_id[1] -- 0-based
        else
            -- Implementations seem to implicitly assume textures for brushes
            index = add_texture(brush.name)
        end
        materials[i] = {
            name = brush.name,
            alphaMode = "BLEND",
            pbrMetallicRoughness = {
                baseColorFactor = color_to_gltf(brush.color),
                metallicFactor = brush.shininess, -- TODO (?) are these really equivalent?
                -- Add texture if there is none
                baseColorTexture = {
                    index = index,
                    -- `texCoord = 0` is the default already, no need to set it
                },
            },
        }
    end

    local meshes = {}
    local function add_mesh(mesh, weights, add_neutral_bone)
        local attributes = {}

        local vertices = mesh.vertices
        attributes.POSITION = add_accessor("VEC3", "float", false, function(write_byte)
            local inf = math.huge
            local min_pos, max_pos = {inf, inf, inf}, {-inf, -inf, -inf}
            for _, vertex in ipairs(mesh.vertices) do
                local pos = translation_to_gltf(vertex.pos)
                write_vector(write_byte, pos)
                min_pos = modlib.vector.combine(min_pos, pos, math.min)
                max_pos = modlib.vector.combine(max_pos, pos, math.max)
            end
            return #mesh.vertices, min_pos, max_pos -- vertex accessors MUST provide min & max
        end)

        local has_normals = vertices.flags % 2 == 1 -- lowest bit set?
        if has_normals then
            attributes.NORMAL = add_accessor("VEC3", "float", false, function(write_byte)
                for _, vertex in ipairs(mesh.vertices) do
                    -- Some B3D models don't seem to have their normals normalized.
                    -- TODO (?) raise a warning when handling this gracefully
                    write_translation(write_byte, modlib.vector.normalize(vertex.normal))
                end
                return #mesh.vertices
            end)
        end

        local has_colors = vertices.flags % 4 >= 2 -- second lowest bit set?
        if has_colors then
            attributes.COLOR_0 = add_accessor("VEC4", "float", false, function(write_byte)
                for _, vertex in ipairs(mesh.vertices) do
                    write_floats(write_byte, color_to_gltf(vertex.color), 4)
                end
                return #mesh.vertices
            end)
        end

        if vertices.tex_coord_sets >= 1 then
            assert(vertices.tex_coord_set_size == 2)
            for tex_coord_set = 1, vertices.tex_coord_sets do
                local tcs_id = tex_coord_set - 1 -- 0-based
                attributes[("TEXCOORD_%d"):format(tcs_id)] = add_accessor("VEC2", "float", false, function(write_byte)
                    for _, vertex in ipairs(mesh.vertices) do
                        write_floats(write_byte, vertex.tex_coords[tex_coord_set], 2)
                    end
                    return #mesh.vertices
                end)
            end
        end

        if next(weights) ~= nil then
            -- Count (& pack into list) joints influencing vertices, normalize weights
            local max_count = 0
            local joint_ids = {}
            local normalized_weights = {}
            -- Handle (supposedly) animated/dynamic vertices (can still be static by having zero weights)
            for vertex_id, joint_weights in pairs(weights) do
                local total_weight = 0
                local count = 0
                for _, weight in pairs(joint_weights) do
                    total_weight = total_weight + weight
                    count = count + 1
                end
                if total_weight > 0 then -- animated?
                    joint_ids[vertex_id] = {}
                    normalized_weights[vertex_id] = {}
                    for joint, weight in pairs(joint_weights) do
                        table.insert(joint_ids[vertex_id], joint)
                        table.insert(normalized_weights[vertex_id], weight / total_weight)
                    end
                    max_count = math.max(max_count, count)
                end
            end
            -- Now search for static vertices
            for vertex_id in ipairs(mesh.vertices) do
                if not joint_ids[vertex_id] then
                    -- Vertex isn't influenced by any bones => Add a dummy neutral bone to influence this vertex
                    -- See https://github.com/KhronosGroup/glTF/issues/2269
                    -- and https://github.com/KhronosGroup/glTF-Blender-IO/pull/1552/
                    joint_ids[vertex_id] = {add_neutral_bone()}
                    normalized_weights[vertex_id] = {1}
                    max_count = math.max(max_count, 1) -- it is (theoretically) possible that all vertices are static
                end
            end
            assert(max_count > 0) -- TODO (?) warning for max_count > 4
            for set_start = 1, max_count, 4 do -- Iterate sets of 4 bones
                local set_id = math.floor(set_start / 4) -- 0-based => floor rather than ceil
                -- Write the joint IDs
                attributes[("JOINTS_%d"):format(set_id)] = add_accessor("VEC4", "unsigned_short", false, function(write_byte)
                    for vertex_id in ipairs(mesh.vertices) do
                        for i = set_start, set_start + 3 do
                            local vrt_joint_ids, vrt_norm_weights = assert(joint_ids[vertex_id]), assert(normalized_weights[vertex_id])
                            assert(#vrt_joint_ids == #vrt_norm_weights)
                            local id = vrt_joint_ids[i] or 0
                            local weight = vrt_norm_weights[i] or 0
                            if weight == 0 then
                                id = 0 -- required by the glTF spec
                            end
                            write_uint(write_byte, id, 2)
                        end
                    end
                    return #mesh.vertices
                end)
                -- Write the corresponding weights
                attributes[("WEIGHTS_%d"):format(set_id)] = add_accessor("VEC4", "float", false, function(write_byte)
                    for vertex_id in ipairs(mesh.vertices) do
                        for i = set_start, set_start + 3 do
                            local weight = (normalized_weights[vertex_id] or {})[i] or 0
                            write_float(write_byte, weight)
                        end
                    end
                    return #mesh.vertices
                end)
            end
        end

        -- Write the indices per triangle set
        local primitives = {}
        for i, triangle_set in ipairs(mesh.triangle_sets) do
            local index_accessor = add_accessor("SCALAR", "unsigned_int", true, function(write_byte)
                for _, tri in ipairs(triangle_set.vertex_ids) do
                    -- Flip winding order due to the coordinate system transformation
                    -- TODO (!) is this correct?
                    for j = 3, 1, -1 do
                        write_index(write_byte, tri[j])
                    end
                end
                return 3 * #triangle_set.vertex_ids
            end)
            -- Each triangle set is equivalent to one glTF "primitive"
            local brush_id = triangle_set.brush_id or mesh.brush_id
            if brush_id == 0 then -- default brush
                brush_id = nil -- TODO (?) add default material if there are UVs
            else
                brush_id = brush_id - 1 -- 0-based
            end
            primitives[i] = {
                attributes = attributes,
                indices = index_accessor,
                material = brush_id,
                -- `mode = 4` (triangles) is the default already, no need to set it
            }
        end

        table.insert(meshes, {primitives = primitives})
        return #meshes - 1 -- 0-based
    end

    -- glTF lists
    local nodes = {}
    local skins = {}
    local samplers = {}
    local channels = {}
    local function add_node(
        node, -- b3d node to add
        bind_mat, -- bind matrix of the parent bone (may be `nil` if none)
        fps, -- fps of the parent bone (may be `nil` if none)
        anim -- shared animation of the parent mesh
    )
        table.insert(nodes, false) -- HACK first insert a placeholder to get a fixed ID
        local node_id = #nodes - 1 -- 0-indexed <=> before `table.insert`!

        -- Animation (speed)?
        fps = node.animation and node.animation.fps or fps

        -- Keyframes?
        if node.keys then
            -- Convert from a list of keyframes of three overrides to three lists of channels
            local targets = {
                translation = {output_type = "VEC3", b3d_field = "position", write_value = write_translation},
                scale = {output_type = "VEC3", b3d_field = "scale", write_value = write_vector},
                rotation = {output_type = "VEC4", b3d_field = "rotation", write_value = write_quaternion}
            }
            for _, keyframe in ipairs(node.keys) do
                local frame = keyframe.frame
                for _, target in pairs(targets) do
                    local value = keyframe[target.b3d_field]
                    if value then
                        table.insert(target, {frame = frame, value = value})
                    end
                end
            end
            for target, keyframes in pairs(targets) do
                if #keyframes > 0 then
                    -- Write input (timestamps)
                    local input = add_accessor("SCALAR", "float", nil, function(write_byte)
                        local min, max = math.huge, -math.huge
                        for _, keyframe in ipairs(keyframes) do
                            local sec = keyframe.frame / (fps or 60) -- convert frames to seconds; default FPS is 60
                            write_float(write_byte, sec)
                            min, max = math.min(min, sec), math.max(max, sec)
                        end
                        return #keyframes, {min}, {max} -- min and max are mandatory
                    end)

                    -- Write output (overrides)
                    local output = add_accessor(keyframes.output_type, "float", nil, function(write_byte)
                        for _, keyframe in ipairs(keyframes) do
                            keyframes.write_value(write_byte, keyframe.value)
                        end
                        return #keyframes
                    end)

                    table.insert(samplers, {
                        input = input,
                        output = output,
                        -- interpolation default is already linear, matching b3d
                    })

                    table.insert(channels, {
                        sampler = #samplers - 1, -- 0-based
                        target = {
                            node = node_id,
                            path = target,
                        }
                    })
                end
            end
        end

        if node.mesh then
            -- Initialize skeletal animation
            assert(not anim)
            anim = {
                weights = {},
                joints = {},
                inv_bind_mats = {},
            }
        end

        if node.bone then
            local joint_id = #anim.joints
            table.insert(anim.joints, node_id)

            -- "To compose the local transformation matrix, TRS properties MUST be converted to matrices and postmultiplied in
            -- the T * R * S order; first the scale is applied to the vertices, then the rotation, and then the translation."
            local translation = translation_to_gltf(node.position)
            local rotation = modlib.quaternion.normalize(quaternion_to_gltf(node.rotation))
            local scale = node.scale
            local loc_trans_mat = mat4.scale(scale)
                :compose(mat4.rotation(rotation))
                :compose(mat4.translation(translation))

            -- Compute a proper inverse bind matrix as the inverse of the product of the transformation matrices
            -- along the path from the root (the mesh) to the current node (the bone).
            -- See e.g. https://stackoverflow.com/questions/17127994/opengl-bone-animation-why-do-i-need-inverse-of-bind-pose-when-working-with-gp
            -- https://computergraphics.stackexchange.com/questions/7603/confusion-about-how-inverse-bind-pose-is-actually-calculated-and-used
            bind_mat = bind_mat and bind_mat:multiply(loc_trans_mat) or loc_trans_mat
            table.insert(anim.inv_bind_mats, bind_mat:inverse())

            -- Insert into reverse lookup `anim.weights[vertex_id][joint_id] = weight`
            -- such that writing the mesh can then write the weights per vertex
            for vertex_id, weight in pairs(node.bone) do
                if weight > 0 then
                    anim.weights[vertex_id] = anim.weights[vertex_id] or {}
                    anim.weights[vertex_id][joint_id] = weight
                end
            end
        end

        local children = {}
        for _, child in ipairs(node.children) do
            table.insert(children, add_node(child, bind_mat, fps, anim))
        end
        local mesh, skin_id, neutral_node_id
        if node.mesh then
            local neutral_joint_id
            -- Lazily adds a placeholder for the neutral joint, returns joint ID
            local function add_neutral_joint()
                if neutral_joint_id then
                    return neutral_joint_id
                end
                neutral_node_id = #nodes -- 0-based
                table.insert(nodes, {
                    name = "neutral_bone",
                    -- We need to flip the hierarchy: The neutral bone must be a parent of the mesh root;
                    -- if it were a sibling, there would be no common skeleton root (accepted by Blender but not by glTF validator);
                    -- if it were a child, transformations of the mesh root would affect it and it wouldn't be a neutral bone anymore.
                    children = {node_id},
                    -- translation, scale, rotation all default to identity
                })
                neutral_joint_id = #anim.joints -- 0-based
                table.insert(anim.joints, neutral_node_id)
                return neutral_joint_id -- 0-based
            end
            mesh = add_mesh(node.mesh, anim.weights, add_neutral_joint)
            if anim.joints and anim.joints[1] then
                if neutral_joint_id then
                    -- Duplicate the inverse bind matrix of the parent (which the neutral bone will be a child of)
                    table.insert(anim.inv_bind_mats, bind_mat or mat4.identity())
                end
                table.insert(skins, {
                    inverseBindMatrices = add_accessor("MAT4", "float", nil, function(write_byte)
                        for _, inv_bind_mat in ipairs(anim.inv_bind_mats) do
                            assert(#inv_bind_mat == 4)
                            -- glTF uses column-major order (we use row-major order)
                            for i = 1, 4 do
                                for j = 1, 4 do
                                    write_float(write_byte, inv_bind_mat[j][i])
                                end
                            end
                        end
                        return #anim.inv_bind_mats
                    end),
                    joints = anim.joints,
                    skeleton = neutral_node_id, -- make the neutral bone the skeleton root
                })
                skin_id = #skins - 1 -- 0-based
            end
        end
        -- Now replace the placeholder
        nodes[node_id + 1 --[[0-based to 1-based]]] = {
            name = node.name,
            mesh = mesh,
            skin = skin_id,
            children = children[1] and children, -- glTF does not allow empty lists
            translation = translation_to_gltf(node.position),
            scale = node.scale,
            rotation = quaternion_to_gltf(node.rotation),
        }
        -- If a neutral bone exists, return the neutral bone (which has the node as a child) instead of the node
        return neutral_node_id or node_id -- 0-based
    end

    local scene, scenes
    if self.node then
        scene, scenes = 0, {{nodes = {add_node(self.node)}}}
    end

    local buffer_string = table.concat(buffer_rope)
    return {
        asset = {
            generator = "modlib b3d:to_gltf",
            version = "2.0"
        },
        -- Textures
        textures = textures[1] and textures, -- glTF does not allow empty lists
        materials = materials[1] and materials,
        -- Accessors, buffer views & buffers
        accessors = accessors,
        bufferViews = buffer_views,
        buffers = {
            {
                byteLength = #buffer_string,
                uri = "data:application/octet-stream;base64,"
                    .. modlib.base64.encode(buffer_string) -- Note: Blender requires base64 padding
            },
        },
        -- Meshes & nodes
        meshes = meshes,
        nodes = nodes,
        -- A scene is not strictly needed but is useful for getting rid of validator warnings & having a proper root defined
        scene = scene,
        scenes = scenes,
        -- Animation
        skins = skins,
        -- B3D only contains (up to) a single animation
        animations = channels[1] and {
            {
                channels = channels,
                samplers = samplers,
            },
        },
    }
end