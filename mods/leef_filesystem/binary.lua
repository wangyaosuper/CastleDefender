--- read and write (little endian) binary.
-- This is apart of the [LEEF-filesystem](https://github.com/Luanti-Extended-Engine-Features/LEEF-filesystem) module.
--@module binary

local assert, math_huge, math_frexp, math_floor
	= assert, math.huge, math.frexp, math.floor

local negative_nan = 0/0
local positive_nan = negative_nan ^ 1

--- reading binary inputs.
-- read a binary inputs using a `read_byte` function.
-- @section reading
-- @see read_byte


--- expected function inputs.
-- functions will expect either a `read_byte` or `write_byte` function as inputs
-- @section input

--- `read_byte` is a param name which refers to a function which reads the next byte- returning a whole number between 0-255.
--
-- 	function byte()
--		left = left - 1
--		return assert(file_handle:read(1):byte())
--		--reads the next chracter, and converts it to a "numerical code" using string.byte()
-- 		--it's important that this function moves forward in the file stream (as :read(1) does)
-- 	end
-- @function read_byte
-- @return a bytecode (an int between 0 and 255.)

--- `write_byte` is similar to read_byte, however it is given an input and expected to write it to the file.
-- (example needed)
-- @function write_byte

--- functions
-- @section functions

--- read an IEEE 754 single precision (32-bit) floating point number
-- @function read_single
-- @param function @{read_byte}
-- @return number
function leef.binary.read_single(read_byte)
	-- First read the mantissa
	local mantissa = read_byte() / 0x100
	mantissa = (mantissa + read_byte()) / 0x100

	-- Second and first byte in big endian: last bit of exponent + 7 bits of mantissa, sign bit + 7 bits of exponent
	local exponent_byte = read_byte()
	local sign_byte = read_byte()
	local sign = 1
	if sign_byte >= 0x80 then
		sign = -1
		sign_byte = sign_byte - 0x80
	end
	local exponent = sign_byte * 2
	if exponent_byte >= 0x80 then
		exponent = exponent + 1
		exponent_byte = exponent_byte - 0x80
	end
	mantissa = (mantissa + exponent_byte) / 0x80
	if exponent == 0xFF then
		if mantissa == 0 then
			return sign * math_huge
		end
		-- Differentiating quiet and signalling nan is not possible in Lua, hence we don't have to do it
		return sign == 1 and positive_nan or negative_nan
	end
	assert(mantissa < 1)
	if exponent == 0 then
		-- subnormal value
		return sign * 2^-126 * mantissa
	end
	return sign * 2 ^ (exponent - 127) * (1 + mantissa)
end

--- read an IEEE 754 double-precision (64-bit) floating point number
-- @function read_double
-- @param function @{read_byte}
-- @return number
function leef.binary.read_double(read_byte)
	-- First read the mantissa
	local mantissa = 0
	for _ = 1, 6 do
		mantissa = (mantissa + read_byte()) / 0x100
	end
	-- Second and first byte in big endian: last 4 bits of exponent + 4 bits of mantissa; sign bit + 7 bits of exponent
	local exponent_byte = read_byte()
	local sign_byte = read_byte()
	local sign = 1
	if sign_byte >= 0x80 then
		sign = -1
		sign_byte = sign_byte - 0x80
	end
	local exponent = sign_byte * 0x10
	local mantissa_bits = exponent_byte % 0x10
	exponent = exponent + (exponent_byte - mantissa_bits) / 0x10
	mantissa = (mantissa + mantissa_bits) / 0x10
	if exponent == 0x7FF then
		if mantissa == 0 then
			return sign * math_huge
		end
		-- Differentiating quiet and signalling nan is not possible in Lua, hence we don't have to do it
		return sign == 1 and positive_nan or negative_nan
	end
	assert(mantissa < 1)
	if exponent == 0 then
		-- subnormal value
		return sign * 2^-1022 * mantissa
	end
	return sign * 2 ^ (exponent - 1023) * (1 + mantissa)
end

--- read an unsigned integer of any given length
-- @function read_uint
-- @param function @{read_byte}
-- @param int length in bytes of unsigned integer
-- @return unit number
function leef.binary.read_uint(read_byte, bytes)
	local factor = 1
	local uint = 0
	for _ = 1, bytes do
		uint = uint + read_byte() * factor
		factor = factor * 0x100
	end
	return uint
end

--- read a signed integer of any given length
-- @function read_uint
-- @param function @{read_byte}
-- @param int length in bytes of integer
-- @return int number
function leef.binary.read_int(read_byte, bytes)
	local uint = leef.binary.read_uint(read_byte, bytes)
	local max = 0x100 ^ bytes
	if uint >= max / 2 then
		return uint - max
	end
	return uint
end

--- writing binary
-- @function write_uint
-- @param write_byte @{write_byte}
-- @tparam int unit unit to write
-- @tparam int bytes number of bytes to right
function leef.binary.write_uint(write_byte, uint, bytes)
	for _ = 1, bytes do
		write_byte(uint % 0x100)
		uint = math_floor(uint / 0x100)
	end
	assert(uint == 0)
end

function leef.binary.write_int(write_byte, int, bytes)
	local max = 0x100 ^ bytes
	if int < 0 then
		assert(-int <= max / 2)
		int = max + int
	else
		assert(int < max / 2)
	end
	return leef.binary.write_uint(write_byte, int, bytes)
end

function leef.binary.write_single(write_byte, number)
	if number ~= number then -- nan: all ones
		for _ = 1, 4 do write_byte(0xFF) end
		return
	end

	local sign_byte, exponent_byte, mantissa_byte_1, mantissa_byte_2

	local sign_bit = 0
	if number < 0 then
		number = -number
		sign_bit = 0x80
	end

	if number == math_huge then -- inf: exponent = all 1, mantissa = all 0
		sign_byte, exponent_byte, mantissa_byte_1, mantissa_byte_2 = sign_bit + 0x7F, 0x80, 0, 0
	else -- real number
		local mantissa, exponent = math_frexp(number)
		if exponent <= -126 or number == 0 then -- must write a subnormal number
			mantissa = mantissa * 2 ^ (exponent + 126)
			exponent = 0
		else -- normal numbers are stored as 1.<mantissa>
			mantissa = mantissa * 2 - 1
			exponent = exponent - 1 + 127 -- mantissa << 1 <=> exponent--
			assert(exponent < 0xFF)
		end

		local exp_lowest_bit = exponent % 2

		sign_byte = sign_bit + (exponent - exp_lowest_bit) / 2

		mantissa = mantissa * 0x80
		exponent_byte = exp_lowest_bit * 0x80 + math_floor(mantissa)
		mantissa = mantissa % 1

		mantissa = mantissa * 0x100
		mantissa_byte_1 = math_floor(mantissa)
		mantissa = mantissa % 1

		mantissa = mantissa * 0x100
		mantissa_byte_2 = math_floor(mantissa)
		mantissa = mantissa % 1

		assert(mantissa == 0) -- no truncation allowed: round numbers properly using modlib.math.fround
	end

	write_byte(mantissa_byte_2)
	write_byte(mantissa_byte_1)
	write_byte(exponent_byte)
	write_byte(sign_byte)
end

function leef.binary.write_double(write_byte, number)
	if number ~= number then -- nan: all ones
		for _ = 1, 8 do write_byte(0xFF) end
		return
	end

	local sign_byte, exponent_byte, mantissa_bytes

	local sign_bit = 0
	if number < 0 then
		number = -number
		sign_bit = 0x80
	end

	if number == math_huge then -- inf: exponent = all 1, mantissa = all 0
		sign_byte, exponent_byte, mantissa_bytes = sign_bit + 0x7F, 0xF0, {0, 0, 0, 0, 0, 0}
	else -- real number
		local mantissa, exponent = math_frexp(number)
		if exponent <= -1022 or number == 0 then -- must write a subnormal number
			mantissa = mantissa * 2 ^ (exponent + 1022)
			exponent = 0
		else -- normal numbers are stored as 1.<mantissa>
			mantissa = mantissa * 2 - 1
			exponent = exponent - 1 + 1023 -- mantissa << 1 <=> exponent--
			assert(exponent < 0x7FF)
		end

		local exp_low_nibble = exponent % 0x10

		sign_byte = sign_bit + (exponent - exp_low_nibble) / 0x10

		mantissa = mantissa * 0x10
		exponent_byte = exp_low_nibble * 0x10 + math_floor(mantissa)
		mantissa = mantissa % 1

		mantissa_bytes = {}
		for i = 1, 6 do
			mantissa = mantissa * 0x100
			mantissa_bytes[i] = math_floor(mantissa)
			mantissa = mantissa % 1
		end
		assert(mantissa == 0)
	end

	for i = 6, 1, -1 do
		write_byte(mantissa_bytes[i])
	end
	write_byte(exponent_byte)
	write_byte(sign_byte)
end

function leef.binary.write_float(write_byte, number, double)
	(double and leef.binary.write_double or leef.binary.write_single)(write_byte, number)
end

--- misc binary helpers
-- @section misc

--- "returns nearest 32-bit single precision float representation of a number" (or something)
-- @function fround
-- @param number
-- @return nearest 32-bit single precision float representation of a number
function leef.binary.fround(number)
	if number == 0 or number ~= number then
		return number
	end
	local sign = 1
	if number < 0 then
		sign = -1
		number = -number
	end
	local _, exp = math.frexp(number)
	exp = exp - 1 -- we want 2^exponent >= number > 2^(exponent-1)
	local powexp = 2 ^ math.max(-126, math.min(exp, 127))
	local leading = exp <= -127 and 0 or 1 -- subnormal number?
	local mantissa = math.floor((number / powexp - leading) * 0x800000 + 0.5)
	if
		mantissa > 0x800000 -- doesn't fit in mantissa
		or (exp >= 127 and mantissa == 0x800000) -- fits if the exponent can be increased
	then
		return sign * inf
	end
	return sign * powexp * (leading + mantissa / 0x800000)
end
