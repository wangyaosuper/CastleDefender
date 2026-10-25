
--- allows the creation of a "proxy" for a real table or structure of tables which prevents modification but inheriting the values of the parent table.
--
-- constructor accepts a custom function for handling attempts to change the value of fields. Defaults to an error message.
--
-- This works with a given tree of tables.
--
-- @module proxy_table

leef.class.proxy_table = {}
local proxy_table = leef.class.proxy_table

--reference which indicates that a value is nil. This is so that proxies can store overwritten data.
local NIL_VALUE = {}


--these are just to keep references around, if a reference is broken or lost on either side dont keep it.
proxy_table.objects_by_proxy = {}
local objects_by_proxy = proxy_table.objects_by_proxy
setmetatable(objects_by_proxy, {
    __mode = "kv"
})

--- the proxy's overriden values and child tables
-- @field p.__LEEF_PROXY_OVERRIDES
local __LEEF_PROXY_OVERRIDES = "__LEEF_PROXY_OVERRIDES"
--- the proxy's parent table that it gets its values from
-- @field p.__LEEF_PROXY_PARENT
--local __LEEF_PROXY_PARENT = "__LEEF_PROXY_PARENT"
--- the proxy's index handling function
-- @field p.__LEEF_NEWINDEX_HANDLER
local __LEEF_NEWINDEX_HANDLER = "__LEEF_NEWINDEX_HANDLER"
local proxy_metatable = {
    __index = function(proxy, key)
        local overrides = rawget(proxy, __LEEF_PROXY_OVERRIDES)
        local override_value = overrides[key]
        local original_value = objects_by_proxy[proxy][key]
        local out_value = override_value or original_value
        local value_type = type(out_value)
        --if it's overriden...
        if override_value then
            if override_value==NIL_VALUE then return nil end
            return override_value
        end
        --if it's not overriden
        if (value_type == "table") then
            local new = proxy_table.new(out_value, rawget(proxy, __LEEF_NEWINDEX_HANDLER))
            rawset(overrides, key, new)
            return new
        else
            return original_value
        end
    end,
    __newindex = function(t,k,v)
        if rawget(t, __LEEF_NEWINDEX_HANDLER) then
            t:__LEEF_NEWINDEX_HANDLER(objects_by_proxy[t], k, v)
        else
            error("attempt to modify proxy table.. "..debug.getinfo(2).short_src..":"..debug.getinfo(2).currentline)
        end
    end
}

--- sets an override on the proxy's fields. You can use this in the `newindex_handling_func` param to allow proxy tables to be modified
-- @tparam proxy proxy the proxy table
-- @param key
-- @param value
function proxy_table.set_field_override(proxy,key,value)
    --if value==nil then value=NIL_VALUE end
    local value_type = type(value)
    if value==nil then
        rawget(proxy, __LEEF_PROXY_OVERRIDES)[key] = NIL_VALUE
    elseif value_type=="table" then
        rawget(proxy, __LEEF_PROXY_OVERRIDES)[key] = proxy_table.new(value, rawget(proxy, __LEEF_NEWINDEX_HANDLER))
    else
        rawget(proxy, __LEEF_PROXY_OVERRIDES)[key] = value
    end
end
function proxy_table.redact_field_override(t,k,v)
    rawget(t, __LEEF_PROXY_OVERRIDES)[k] = nil
end

--- create a new proxy table
-- @tparam table table to create immutable interface for
-- @tparam functions newindex_handling_func `function(proxy, original_object, key, value)` to call when the proxy table has an attempted set
-- @return Proxy table
-- @function new
function proxy_table.new(tbl, newindex_handling_func)
    assert(tbl~=proxy_table, "do not call leef.class.proxy_table functions as methods.")
    assert(tbl, "no table provided")
    --I'm leaving this here as a reminder: this will break everything because multiple proxies can exist for one table.
    --And daully the best way to identify the existence of a proxy in any given structure (from it's parent) is it's presence in the table.
    --and since __index only calls if something is NOT found in a table, this of course means that we simply should create it ourselves.
--> local proxy = proxies_by_object[tbl]
    local proxy = {}
    proxy.__LEEF_PROXY_PARENT = tbl
    proxy.__LEEF_NEWINDEX_HANDLER = newindex_handling_func
    proxy.__LEEF_PROXY_OVERRIDES = {}

    --if it already existed there's no need to update any of this
    --proxies_by_object[tbl] = proxy
    objects_by_proxy[proxy] = tbl
    setmetatable(proxy, proxy_metatable)
    return proxy
end

--- check if its a proxy table
-- @param value value it check if proxy
-- @treturn bool
-- @function is_proxy
function proxy_table.is_proxy(value)
    assert(value~=proxy_table, "do not call leef.class.proxy_table functions as methods.")
    if objects_by_proxy[value] then return true end
    return false
end

local function or_equals(a,b,c)
    return (a==b) or (a==c)
end
local old_ipairs = ipairs
local old_pairs = pairs
local function proxy_pairs_iterator(overrides,k,original,iterating_proxy,proxy)
    local outkey, _ = k, nil
    if iterating_proxy then
        local outval
        outkey, outval = next(overrides, outkey)
        if outval == NIL_VALUE then outkey, _, _ = proxy_pairs_iterator(overrides, outkey, original, true, proxy) end
        if not outkey then outkey, _, iterating_proxy = proxy_pairs_iterator(overrides, nil, original, false, proxy) end
    else
        outkey, _ = next(original, outkey)
        local temp_val = rawget(overrides,outkey)
        if not outkey then return nil,nil,false end
        if temp_val then outkey, _, _ = proxy_pairs_iterator(overrides, outkey, original, false, proxy) end
    end
    return outkey, outkey and proxy[outkey], iterating_proxy
end
--since next is modified we basically just return the normal pairs func to not kill perf
function pairs(...)
    local t = ...
    local original = objects_by_proxy[t]
    if original then
        local key, val, mode = nil,nil,true
        local overrides, proxy
        return function(t2,k)
            if not t2 then return end
            overrides = overrides or rawget(t2, __LEEF_PROXY_OVERRIDES)
            proxy = proxy or t2

            key, val, mode = proxy_pairs_iterator(overrides, k, original, mode, proxy)
            return key, val
        end, t, nil
    end
    return old_pairs(...)
end

local function iter(p, i)
    i = i + 1
    local t = objects_by_proxy[p]
    local v = t[i]
    if v then
      return i, v
    end
end
function ipairs(...)
    local p = ...
    if objects_by_proxy[p] then
        return iter, p, 0
    else
        return old_ipairs(...)
    end
end

--[[local old_ipairs = ipairs
function ipairs(t, ...)
    return old_ipairs(proxies[t] or t, ...)
end]]