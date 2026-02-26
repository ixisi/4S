ANIM_LIB = {}; SCRIPT_FUNCS = {}; src= {}
local EASING_FUNCS = {
    linear      = function(t) return t end,

    quad_in     = function(t) return t * t end,
    quad_out    = function(t) return t * (2 - t) end,
    quad_inout  = function(t)
        if t < 0.5 then return 2 * t * t else return -1 + (4 - 2 * t) * t end
    end,

    sine_inout  = function(t) return 0.5 * (1 - math.cos(math.pi * t)) end,

    back_out    = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
    end,

    elastic_out = function(t)
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
    end,

    bounce_out  = function(t)
        local n1 = 7.5625
        local d1 = 2.75
        if t < 1 / d1 then
            return n1 * t * t
        elseif t < 2 / d1 then
            t = t - 1.5 / d1
            return n1 * t * t + 0.75
        elseif t < 2.5 / d1 then
            t = t - 2.25 / d1
            return n1 * t * t + 0.9375
        else
            t = t - 2.625 / d1
            return n1 * t * t + 0.984375
        end
    end
}
local ffi = require("ffi")

ffi.cdef[[
    typedef struct { long x; long y; } POINT;
    bool GetCursorPos(POINT* lp);
]]
local mouse= ffi.new("POINT")
function parse_time(str)
    if not str then return 0 end
    local val = tonumber(string.match(str, "[%d%.]+")) or 0
    local unit = string.match(str, "%a+") or "ms"

    if unit == "s" then
        return val * 1000
    elseif unit == "mi" then
        return val * 60000
    elseif unit == "hr" then
        return val * 3600000
    else
        return val
    end
end


function parse_value(src, current_val, input_str)
    if type(input_str) == "string" and input_str:sub(1, 1) == "(" then
        return evaluate_math(src, input_str)
    end

    if type(input_str) ~= "string" then return tonumber(input_str) or current_val end

    local op, val_str = string.match(input_str, "^([%+%-%*/]+)(.+)")

    if op and val_str then
        local resolved_val = resolve_path(src, val_str:match("^%s*(.-)%s*$"))
        
        local num_val = tonumber(resolved_val) or 0
        
        if op == "++" then
            return current_val + num_val
        elseif op == "--" then
            return current_val - num_val
        elseif op == "**" then
            return current_val * num_val
        end
    end
    return tonumber(resolve_path(src, input_str)) or current_val
end



function compile_line(cmd, args)
    
    local function process_args(src, raw_args)

        local skip_commands = { 
            ["gvar"]= true, ["var"]=true, ["label"]=true, ["jump"]=true, ["call"]=true, 
            ["change"]=true, ["attach"]=true, ["pin"]=true, ["source"]=true, 
            ["if"]=true, ["run"]=true, ["collision"]=true, 
            ["array.push"]=true, ["array.clear"]=true, ["foreach"]=true,
            ["array.pop"]=true, ["array.remove"]=true,
            ["media"]=true, ["media_time"]=true, ["filter"]=true,
            ["transition"]=true, ["sound"]=true,["log"]=true,
            ["return"]=true,["switch"]=true,["onpress"]=true
        }
        if skip_commands[cmd] then return raw_args end

        local runtime_args = {}
        for i, raw_arg in ipairs(raw_args) do
            if type(raw_arg) == "string" then
                local interpolated = raw_arg:gsub("([%a_][%w_%.]*)(:?)", function(word, colon)
                    if colon == ":" then return word .. colon end 
                    
                    if src.active_scope and src.active_scope[word] ~= nil then 
                        return tostring(src.active_scope[word]) .. colon 
                    end
                    if src.vars and src.vars[word] ~= nil then 
                        return tostring(src.vars[word]) .. colon 
                    end
                    return word .. colon
                end)
                runtime_args[i] = interpolated
            else
                runtime_args[i] = raw_arg
            end
        end
        return runtime_args
    end

    if ANIM_LIB[cmd] then
        local preset_func = ANIM_LIB[cmd]
        return function(src, override_state)
            local runtime_args = process_args(src, args)
            return preset_func(src, override_state or src.state, runtime_args)
        end
    end

    if cmd:sub(1, 1) == "@" then
        local func_name, args_block = cmd:match("@(%w+)(%b())")
        if not func_name then func_name = cmd:sub(2) end
        local func = SCRIPT_FUNCS[func_name]
        return function(src)
            if not func then return true end
            local runtime_args = process_args(src, args)
            local resolved_args = {}
            if args_block then
                local clean = args_block:sub(2, -2)
                local interp_clean = process_args(src, {clean})[1]
                for arg in string.gmatch(interp_clean, "([^,]+)") do
                    table.insert(resolved_args, resolve_path(src, arg:match("^%s*(.-)%s*$")))
                end
            end
            for _, arg in ipairs(runtime_args) do
                table.insert(resolved_args, resolve_path(src, arg))
            end
            func(src, unpack(resolved_args))
            return true
        end
    end

    return function(src)
        local items = src.active_sources or { src.scene_item }
        local runtime_args = process_args(src, args)
        
        for _, item in ipairs(items) do
            if item then
                local func = item
                local func_found = true
                for part in string.gmatch(cmd, "[^%.]+") do
                    if type(func) == "table" then func = func[part]
                    else func_found = false; break end
                end

                if func_found then 

                    local final_args = {}
                    for _, raw_arg in ipairs(runtime_args) do

                        if cmd == "text" then
                            table.insert(final_args, resolve_path(src, raw_arg))
                            
                        elseif raw_arg:find(":") then
                            local kv_table = {}
                            local current_state = {}
                            pcall(function() current_state = func() end)
                            if type(current_state) ~= "table" then current_state = {} end

                            for _, pair in ipairs(safe_split(raw_arg)) do
                                local k, v = string.match(pair, "%s*([^:]+)%s*:%s*(.+)%s*")
                                if k and v then
                                    local resolved_v = resolve_path(src, v)
                                    local base = current_state[k] or 0
                                    kv_table[k] = parse_value(src, base, resolved_v)
                                end
                            end
                            for k, v in pairs(current_state) do
                                if kv_table[k] == nil then kv_table[k] = v end
                            end
                            table.insert(final_args, kv_table)

                        elseif raw_arg:match("^[%+%-%*]") then
                            local current_val = 0
                            local status, result = pcall(function() return func() end)
                            if status and type(result) == "number" then current_val = result end
                            
                            local new_val = parse_value(src, current_val, raw_arg)
                            table.insert(final_args, new_val)
                            
                        else
                            table.insert(final_args, resolve_path(src, raw_arg))
                        end
                    end
                    if type(func) == "function" then
                        pcall(func, unpack(final_args))
                    end
                end
            end
        end
        return true
    end
end


function split(str, sep)
    local result = {}
    local start = 1

    while true do
        if not str then break end
        local first, last = string.find(str, sep, start, true)
        if not first then
            local last_part = str:sub(start):match("^%s*(.-)%s*$")
            if last_part ~= "" then table.insert(result, last_part) end
            break
        end

        local part = str:sub(start, first - 1):match("^%s*(.-)%s*$")
        if part ~= "" then table.insert(result, part) end
        start = last + 1
    end
    return result
end


function safe_split(str)
    if not str then return {} end
    local chunks = {}
    local depth = 0
    local start = 1

    for i = 1, #str do
        local c = str:sub(i, i)
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
        elseif c == "," and depth == 0 then
            table.insert(chunks, str:sub(start, i - 1))
            start = i + 1
        end
    end
    table.insert(chunks, str:sub(start))
    return chunks
end

function lerp(a, b, t) return a + (b - a) * t end




ANIM_LIB["easing"] = function(src, state, args)
    src.current_easing = args[1] or "linear"
    return true
end
-- !wait | duration_or_var
ANIM_LIB["wait"] = function(src, state, args)
    local duration = parse_time(args[1])
    if not state.init then
        state.start_time = os.clock()
        state.init = true
    end

    if (os.clock() - state.start_time) * 1000 >= duration then
        return true
    else
        return false
    end
end
ANIM_LIB["transition"] = function(src, state, args)
    local scene_name = resolve_path(src, args[1]) or args[1]
    local trans_type = resolve_path(src, args[2]) or args[2] or "Fade"
    local raw_time   = resolve_path(src, args[3]) or args[3] or "300ms"
    
    local duration_ms = parse_time(raw_time)

    local scene_source = obslua.obs_get_source_by_name(scene_name)
    if not scene_source then return true end

    local transition = obslua.obs_get_source_by_name(trans_type)
    
    if transition then
        obslua.obs_transition_set_duration(transition, duration_ms)
        obslua.obs_frontend_set_current_scene(scene_source)
        obslua.obs_source_release(transition)
    else
        obslua.obs_frontend_set_current_scene(scene_source)
    end

    obslua.obs_source_release(scene_source)
    return true
end

ANIM_LIB["switch"] = function(src, state, args)
    local scene_name = resolve_path(src, args[1]) or args[1]

    local scene_source = obs.obs_get_source_by_name(scene_name)
    if not scene_source then return true end

    obs.obs_frontend_set_current_scene(scene_source)
    obs.obs_source_release(scene_source)
    
    return true
end


ANIM_LIB["array.push"] = function(src, state, args)
    local arr_name = args[1]
    local raw_val = args[2]
    
    if not src.vars then src.vars = {} end
    if type(src.vars[arr_name]) ~= "table" then src.vars[arr_name] = {} end
    
    local resolved_val = resolve_path(src, raw_val) or raw_val
    table.insert(src.vars[arr_name], resolved_val)
    return true
end
ANIM_LIB["array.pop"] = function(src, state, args)
    local array_name = args[1]
    local save_var = args[2]
    local target_array = nil
    if src.active_task and src.active_task.variables and type(src.active_task.variables[array_name]) == "table" then
        target_array = src.active_task.variables[array_name]
    elseif src.active_scope and type(src.active_scope[array_name]) == "table" then
        target_array = src.active_scope[array_name]
    elseif src.vars and type(src.vars[array_name]) == "table" then
        target_array = src.vars[array_name]
    end
    if target_array and #target_array > 0 then
        local popped_val = table.remove(target_array)
        
        if save_var then
            if not src.active_scope then src.active_scope = {} end
            if src.active_task and src.active_task.variables then
                src.active_task.variables[save_var] = popped_val
            else
                src.active_scope[save_var] = popped_val
            end
        end
    end
    return true
end

ANIM_LIB["array.remove"] = function(src, state, args)
    local array_name = args[1]
    local value_to_remove = resolve_path(src, args[2]) or args[2] 

    local target_array = nil
    if src.active_task and src.active_task.variables and type(src.active_task.variables[array_name]) == "table" then
        target_array = src.active_task.variables[array_name]
    elseif src.active_scope and type(src.active_scope[array_name]) == "table" then
        target_array = src.active_scope[array_name]
    elseif src.vars and type(src.vars[array_name]) == "table" then
        target_array = src.vars[array_name]
    end

    if target_array then

        for i = #target_array, 1, -1 do
            if target_array[i] == value_to_remove then
                table.remove(target_array, i)
                break
            end
        end
    end
    return true
end
ANIM_LIB["array.clear"] = function(src, state, args)
    local arr_name = args[1]
    if src.vars then src.vars[arr_name] = {} end
    return true
end

ANIM_LIB["foreach"] = function(src, state, args)
    local arr_name = args[1]
    local iter_name = args[2]
    local target_label = args[3]

    local arr = resolve_path(src, arr_name)
    if type(arr) ~= "table" then return true end


    for index, val in ipairs(arr) do
        if src.labels and src.labels[target_label] then
            local snapshot = {}
            for k, v in pairs(src.active_scope or {}) do snapshot[k] = v end
            
            snapshot[iter_name] = val
            snapshot["_index"] = index 

            local interrupt_thread = {
                type = "THREAD", queue = src.queue, labels = src.labels,
                current_idx = src.labels[target_label], state = {},
                active_source = src.scene_item, active_sources = src.active_sources,
                variables = snapshot, call_stack = {}
            }
            if not src.async_tasks then src.async_tasks = {} end
            table.insert(src.async_tasks, interrupt_thread)
        end
    end
    return true
end

ANIM_LIB["onpress"] = function(src, state, args)
    local hotkey_name = args[1]
    local target_label = args[2]
    local target_label2 = args[3]
    local snapshot = {}
    for k, v in pairs(src.active_scope or {}) do snapshot[k] = v end
    
    local locked_source = src.scene_item
    local locked_sources = {}
    if src.active_sources then 
        for i, v in ipairs(src.active_sources) do locked_sources[i] = v end
    end
    obs.register.hotkey(hotkey_name, "4IM3 Trigger: " .. hotkey_name, function(pressed)
        if pressed and src.labels and src.labels[target_label] then
            local interrupt_thread = {
                type = "THREAD", queue = src.queue, labels = src.labels,
                current_idx = src.labels[target_label], state = {},
                active_source = locked_source, active_sources = locked_sources,
                variables = snapshot, call_stack = {}
            }
            if not src.async_tasks then src.async_tasks = {} end
            table.insert(src.async_tasks, interrupt_thread)
        elseif not pressed and src.labels and src.labels[target_label2] then
            local interrupt_thread = {
                type = "THREAD", queue = src.queue, labels = src.labels,
                current_idx = src.labels[target_label2], state = {},
                active_source = locked_source, active_sources = locked_sources,
                variables = snapshot, call_stack = {}
            }
            if not src.async_tasks then src.async_tasks = {} end
            table.insert(src.async_tasks, interrupt_thread)
        end
    end)
    
    return true
end
ANIM_LIB["media_time"] = function(src, state, args)
    local target_name = resolve_path(src, args[1]) or args[1]
    local var_name = args[2]

    local source = obs.obs_get_source_by_name(target_name)
    if not source then return true end

    local time_ms = obs.obs_source_media_get_time(source)
    obs.obs_source_release(source)
    if not src.active_scope then src.active_scope = {} end
    if src.active_task and src.active_task.variables then
        src.active_task.variables[var_name] = time_ms
    else
        src.active_scope[var_name] = time_ms
    end

    return true
end

ANIM_LIB["filter"] = function(src, state, args)

    if #args < 5 or args[5] == nil or args[5] == "" then
        local target_name = resolve_path(src, args[1]) or args[1]
        local filter_name = resolve_path(src, args[2]) or args[2]
        local prop_name   = resolve_path(src, args[3]) or args[3]
        local target_val  = tonumber(resolve_path(src, args[4]) or args[4]) or 0

        local source = obs.obs_get_source_by_name(target_name)
        if source then
            local filter = obs.obs_source_get_filter_by_name(source, filter_name)
            if filter then
                local settings = obs.obs_source_get_settings(filter)
                obs.obs_data_set_double(settings, prop_name, target_val)
                obs.obs_source_update(filter, settings)
                
                obs.obs_data_release(settings)
                obs.obs_source_release(filter)
            end
            obs.obs_source_release(source)
        end
        return true 
    end

    if not state.initialized then
        state.target_name = resolve_path(src, args[1]) or args[1]
        state.filter_name = resolve_path(src, args[2]) or args[2]
        state.prop_name   = resolve_path(src, args[3]) or args[3]
        state.target_val  = tonumber(resolve_path(src, args[4]) or args[4]) or 0
        
        local raw_time = resolve_path(src, args[5]) or args[5]
        state.duration = parse_time(raw_time)
        if state.duration <= 0 then state.duration = 0.001 end
        
        state.elapsed = 0

        local source = obs.obs_get_source_by_name(state.target_name)
        if source then
            local filter = obs.obs_source_get_filter_by_name(source, state.filter_name)
            if filter then
                local settings = obs.obs_source_get_settings(filter)
                state.start_val = obs.obs_data_get_double(settings, state.prop_name)
                obs.obs_data_release(settings)
                obs.obs_source_release(filter)
            else
                state.start_val = 0
            end
            obs.obs_source_release(source)
        else
            state.start_val = 0
        end
        state.initialized = true
    end

    local dt = (src.vars and src.vars["tick"]) or 0.016
    state.elapsed = state.elapsed + dt
    local progress = math.min(state.elapsed / state.duration, 1.0)
    
    local current_val = state.start_val + ((state.target_val - state.start_val) * progress)

    local source = obs.obs_get_source_by_name(state.target_name)
    if source then
        local filter = obs.obs_source_get_filter_by_name(source, state.filter_name)
        if filter then
            local settings = obs.obs_source_get_settings(filter)
            obs.obs_data_set_double(settings, state.prop_name, current_val)
            obs.obs_source_update(filter, settings)
            obs.obs_data_release(settings)
            obs.obs_source_release(filter)
        end
        obs.obs_source_release(source)
    end


    if progress >= 1.0 then return true end
    return false 
end

ANIM_LIB["move"] = function(src, state, args)
    local targets = src.active_sources or { src.scene_item }
    if #targets == 0 then return true end

    if not state.init then
        state.configs = {} 
        state.hasFinished = false

        state.duration = parse_time(args[2]) or 0
        if type(state.duration) ~= "number" then state.duration = 0 end
        state.start_time = os.clock()

        local move_args = args[1]

        for i, item in ipairs(targets) do
            if item.transform then item.transform(nil) end 
            local config = { item = item, starts = {}, targets = {} }
            
            for _, pair in ipairs(safe_split(move_args)) do
                local k, v = string.match(pair, "([^:]+):(.+)")
                if k and v then
                    k = k:match("^%s*(.-)%s*$")
                    v = v:match("^%s*(.-)%s*$")

                    local current_val = 0
                    if k == "x" then current_val = item.pos().x
                    elseif k == "y" then current_val = item.pos().y
                    elseif k == "rot" or k == "rotation" then current_val = item.rot()
                    elseif k:match("scale") then current_val = item.scale()[k:match("scale%.(%w+)")] or 1
                    elseif item[k] then current_val = item[k]() or 0
                    end

                    config.starts[k] = current_val
                    local resolved_v = resolve_path(src, v)
                    config.targets[k] = parse_value(src, current_val, resolved_v)
                end
            end
            table.insert(state.configs, config)
        end
        state.init = true
    end

    local now = os.clock()
    local predict_buffer = 0.016
    local elapsed = (now - state.start_time + predict_buffer) * 1000
    local t = (state.duration > 0) and (elapsed / state.duration) or 1
    if t > 1 then t = 1 end

    if not state.hasFinished then

        local ease_name = args[3] or src.current_easing or "linear"
        local ease_func = EASING_FUNCS[ease_name] or EASING_FUNCS.linear
        local eased_t = ease_func(t)

        for _, config in ipairs(state.configs) do
            local item = config.item
            for k, target in pairs(config.targets) do
                local start = config.starts[k]
                local val = start + (target - start) * eased_t

                if k == "x" then item.pos({ x = val })
                elseif k == "y" then item.pos({ y = val })
                elseif k == "rot" then item.rot(val)
                elseif k == "scale.x" then item.scale({ x = val })
                elseif k == "scale.y" then item.scale({ y = val })
                elseif item[k] then item[k](val)
                end
            end
        end
    end
    if t >= 1 or state.hasFinished then
        state.hasFinished = true
        for _, item in ipairs(targets) do
            if item._queue and #item._queue > 0 then return false end
        end
        return true
    else
        return false
    end
end
-- !source | obj1 | obj2 | obj3 ...
ANIM_LIB["source"] = function(src, state, args)
    if #args == 0 or (args[1] == "" and #args == 1) then
        src.active_sources = nil
        if src.original_item then src.scene_item = src.original_item end
        return true
    end
    local new_sources = {}
    for _, input in ipairs(args) do
        local resolved = resolve_path(src, input)
        
        if type(resolved) == "table" and resolved.pos then
            table.insert(new_sources, resolved)
        elseif type(resolved) == "string" then
            local fetched = obs.front.source(resolved)
            if fetched then
                table.insert(new_sources, fetched)
            else
                obslua.script_log(obslua.LOG_WARNING, "[4IM3-SCRIPT ERROR] Source not found: " .. tostring(resolved))
            end
        end
    end

    if #new_sources > 0 then
        src.active_sources = new_sources
        src.scene_item = new_sources[1] 
    end
    
    return true
end


-- !loop | (No args: restarts from beginning)
ANIM_LIB["loop"] = function(src, state, args)
    return "RESET"
end




-- !label | name
ANIM_LIB["label"] = function(src, state, args)
    return true
end

-- !if | property | operator | value | jump_to_label
-- !if | prop.key | operator | value_or_var | jump_label
-- !if | val1 | op | val2 | label_OR_@function
ANIM_LIB["if"] = function(src, state, args)
    local v1 = resolve_path(src, args[1])
    local op = args[2]
    local v2 = resolve_path(src, args[3])
    local target = args[4]
    local mode = args[5] 

    local n1, n2 = tonumber(v1), tonumber(v2)
    if n1 and n2 then v1, v2 = n1, n2 else v1, v2 = tostring(v1), tostring(v2) end

    local condition = false
    if op == "==" then
        condition = v1 == v2
    elseif op == "!=" then
        condition = v1 ~= v2
    elseif n1 and n2 then
        if op == ">=" then
            condition = v1 >= v2
        elseif op == "<=" then
            condition = v1 <= v2
        elseif op == ">" then
            condition = v1 > v2
        elseif op == "<" then
            condition = v1 < v2
        end
    end

    if condition then

        if src.labels and src.labels[target] then
            if mode and string.lower(mode) == "ret" then
                return "CALL", target
            else
                return "JUMP", target
            end
        end

        if type(target) == "string" and target:match("@") then
            resolve_path(src, target)
            return true
        end

        return "JUMP", target
    end

    return true
end

ANIM_LIB["media"] = function(src, state, args)
    local target_name = resolve_path(src, args[1]) or args[1]
    local action = resolve_path(src, args[2]) or args[2]
    local value = resolve_path(src, args[3]) or args[3]

    local source = obslua.obs_get_source_by_name(target_name)
    if not source then return true end
    if action == "play" then
        obslua.obs_source_media_play_pause(source, false)
    elseif action == "pause" then
        obslua.obs_source_media_play_pause(source, true)
    elseif action == "restart" then
        obslua.obs_source_media_restart(source)
    elseif action == "stop" then
        obslua.obs_source_media_stop(source)
    elseif action == "seek" then
        local time_ms = parse_time(value)
        if type(time_ms) == "number" then
            obslua.obs_source_media_set_time(source, time_ms)
        end 
    end
    obslua.obs_source_release(source)
    return true
end

ANIM_LIB["var"] = function(src, state, args)
    local var_name = args[1]
    local raw_val = args[2]
    

    if not src.active_scope then src.active_scope = {} end

    local current_val = 0
    if src.active_task and src.active_task.variables and src.active_task.variables[var_name] ~= nil then
        current_val = tonumber(src.active_task.variables[var_name]) or 0
    elseif src.active_scope[var_name] ~= nil then
        current_val = tonumber(src.active_scope[var_name]) or 0
    end
    local resolved_val = resolve_path(src, raw_val) or raw_val
    if type(raw_val) == "string" then
        if raw_val:sub(1,2) == "++" then
            resolved_val = current_val + (tonumber(resolve_path(src, raw_val:sub(3))) or 0)
        elseif raw_val:sub(1,2) == "--" then
            resolved_val = current_val - (tonumber(resolve_path(src, raw_val:sub(3))) or 0)
        end
    end

    if src.active_task and src.active_task.variables then
        src.active_task.variables[var_name] = resolved_val
    else
        src.active_scope[var_name] = resolved_val
    end
    
    return true
end

ANIM_LIB["gvar"] = function(src, state, args)
    local var_name = args[1]
    local raw_val = args[2]
    
    if not src.vars then src.vars = {} end
    local current_val = tonumber(src.vars[var_name]) or 0

    local resolved_val = resolve_path(src, raw_val) or raw_val
    if type(raw_val) == "string" then
        if raw_val:sub(1,2) == "++" then
            resolved_val = current_val + (tonumber(resolve_path(src, raw_val:sub(3))) or 0)
        elseif raw_val:sub(1,2) == "--" then
            resolved_val = current_val - (tonumber(resolve_path(src, raw_val:sub(3))) or 0)
        end
    end

    src.vars[var_name] = resolved_val
    return true
end
-- !jump | LABEL_NAME
ANIM_LIB["jump"] = function(src, state, args)
    return "JUMP", args[1]
end

SCRIPT_FUNCS["call"] = function(src, args)
    local target_label = args[1]
    local label_idx = src.labels[target_label]
    
    if label_idx then
        if args[2] then
            for _, pair in ipairs(safe_split(args[2])) do
                local k, v = string.match(pair, "([^:]+):(.+)")
                if k and v then
                    k = k:match("^%s*(.-)%s*$")
                    v = resolve_path(src, v:match("^%s*(.-)%s*$"))
                    src.active_scope[k] = tonumber(v) or v
                end
            end
        end
        
        table.insert(src.call_stack, src.current_idx)
        src.current_idx = label_idx
    end
    return true
end

-- !attach | target_source | label_name
ANIM_LIB["attach"] = function(src, state, args)
    local target_item = SCRIPT_FUNCS.source(src, args[1])
    local target_label = args[2]
    
    if target_item and src.labels[target_label] then

        local snapshot = {}
        for k, v in pairs(src.active_scope) do snapshot[k] = v end

        local new_thread = {
            type = "THREAD",
            queue = src.queue, 
            labels = src.labels,
            current_idx = src.labels[target_label],
            state = {}, 
            active_source = target_item, 
            active_sources = {target_item}, 
            variables = snapshot, 
            call_stack = {} 
        }
        table.insert(src.async_tasks, new_thread)
    end
    return true
end

ANIM_LIB["change"] = function(src, state, args)
    if not src.watchers then src.watchers = {} end
    
    local var, op, val, label
    if #args == 2 then
        var = args[1]; label = args[2]
    else
        var = args[1]; op = args[2]; val = args[3]; label = args[4]
    end

    for _, w in ipairs(src.watchers) do
        if w.var == var and w.label == label then
            w.op = op; w.val = val
            return true 
        end
    end
    
    table.insert(src.watchers, {
        var = var, op = op, val = val, label = label,
        last_val = "UNINITIALIZED_STATE"
    })
    return true
end

ANIM_LIB["return"] = function(src, state, args) return "RETURN" end


SCRIPT_FUNCS["delete"] = function(src)
    if src.scene_item and src.scene_item.remove then
        local target_item = src.scene_item

        target_item.remove() 
        

        if src.collision_pairs then
            for i = #src.collision_pairs, 1, -1 do
                local pair = src.collision_pairs[i]
                if pair.o1 == target_item or pair.o2 == target_item then
                    table.remove(src.collision_pairs, i)
                end
            end
        end
        
        if src.pinned_sources then
            for pin_id, pin_data in pairs(src.pinned_sources) do
                if pin_data.child == target_item or pin_data.parent == target_item then
                    src.pinned_sources[pin_id] = nil
                end
            end
        end
    end
    return 0
end

ANIM_LIB["delete"] = function(src, state, args)
    SCRIPT_FUNCS["delete"](src)
    return true
end

-- !collision | obj1 | obj2 | label
ANIM_LIB["collision"] = function(src, state, args)
    if not src.collision_pairs then src.collision_pairs = {} end
    local o1 = resolve_path(src, args[1])
    local o2 = resolve_path(src, args[2])
    local lbl = args[3]
    if o1 and o2 and lbl then
        for _, pair in ipairs(src.collision_pairs) do
            if (pair.o1 == o1 and pair.o2 == o2 and pair.label == lbl) or (pair.o1 == o2 and pair.o2 == o1 and pair.label == lbl) then
                return true 
            end
        end
        table.insert(src.collision_pairs, {o1=o1, o2=o2, label=lbl})
    end
    return true
end

-- !log | property_or_var_or_msg
ANIM_LIB["log"] = function(src, state, args)
    local path = args[1]
    local value = resolve_path(src, path)

    local output = (value ~= nil) and tostring(value) or path

    obslua.script_log(obslua.LOG_INFO, "[4IM3-SCRIPT] " .. tostring(output))
    return true
end

-- !rainbow | speed | duration
ANIM_LIB["rainbow"] = function(src, state, args)
    if not src.scene_item then return true end

    local speed = tonumber(args[1]) or 0.01
    local duration = parse_time(args[2] or "0ms") 

    if not state.init then
        state.hue = 0
        state.start_time = os.clock()
        src.scene_item.style.grad.enable()
        state.init = true
    end

    -- Update Hue
    state.hue = state.hue + (speed * 0.1)
    if state.hue > 1 then state.hue = 0 end

    -- Hue to RGB Helper
    local function h_to_rgb(h)
        local r, g, b
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local q = 1 - f
        local t = f
        i = i % 6
        if i == 0 then
            r, g, b = 1, t, 0
        elseif i == 1 then
            r, g, b = q, 1, 0
        elseif i == 2 then
            r, g, b = 0, 1, t
        elseif i == 3 then
            r, g, b = 0, q, 1
        elseif i == 4 then
            r, g, b = t, 0, 1
        elseif i == 5 then
            r, g, b = 1, 0, q
        end
        return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
    end

    local r, g, b = h_to_rgb(state.hue)
    src.scene_item.style.grad.color(r, g, b)

    -- Check Duration
    if duration > 0 then
        return (os.clock() - state.start_time) * 1000 >= duration
    end
    return false
end

-- !shake | intensity | duration
ANIM_LIB["shake"] = function(src, state, args)
    if not src.scene_item then return true end

    local intensity = tonumber(args[1]) or 10
    local duration = parse_time(args[2] or "500ms")

    if not state.init then
        -- Capture original position so we don't drift away
        local pos = src.scene_item.pos()
        state.base_x = pos.x
        state.base_y = pos.y
        state.start_time = os.clock()
        state.init = true
    end

    local dx = math.random(-intensity, intensity)
    local dy = math.random(-intensity, intensity)

    src.scene_item.pos({
        x = state.base_x + dx,
        y = state.base_y + dy
    })

    local elapsed = (os.clock() - state.start_time) * 1000
    if duration > 0 and elapsed >= duration then
        -- Restore original position on finish
        src.scene_item.pos({ x = state.base_x, y = state.base_y })
        return true
    end
    return false
end

-- !glitch | intensity | duration
ANIM_LIB["glitch"] = function(src, state, args)
    if not src.scene_item then return true end

    local intensity = tonumber(args[1]) or 20
    local duration = parse_time(args[2] or "1s")

    if not state.init then
        local pos = src.scene_item.pos()
        state.base_x, state.base_y = pos.x, pos.y
        state.start_time = os.clock()
        state.init = true
    end

    -- 20% chance to glitch this frame
    if math.random() > 0.8 then
        local dx = math.random(-intensity, intensity)
        local dy = math.random(-intensity, intensity)
        local ds = 1 + (math.random(-10, 10) / 100)

        src.scene_item.pos({ x = state.base_x + dx, y = state.base_y + dy })
        src.scene_item.scale({ x = ds, y = 1 }) -- Stretch width only for "digital" feel
    else
        -- Snap back to normal
        src.scene_item.pos({ x = state.base_x, y = state.base_y })
        src.scene_item.scale({ x = 1, y = 1 })
    end

    local elapsed = (os.clock() - state.start_time) * 1000
    if duration > 0 and elapsed >= duration then
        src.scene_item.pos({ x = state.base_x, y = state.base_y })
        src.scene_item.scale({ x = 1, y = 1 })
        return true
    end
    return false
end

-- !breathing | speed | duration
ANIM_LIB["breathing"] = function(src, state, args)
    if not src.scene_item then return true end

    local speed = tonumber(args[1]) or 0.05
    local duration = parse_time(args[2] or "0ms")

    if not state.init then
        state.timer = 0
        state.start_time = os.clock()
        state.init = true
    end

    state.timer = state.timer + speed
    local wave = math.sin(state.timer)

    local s = 1 + (wave * 0.025 + 0.025)
    src.scene_item.scale({ x = s, y = s })

    -- Opacity: 50% to 90%
    local op = 70 + (wave * 20)
    src.scene_item.opacity(op / 100) 

    if duration > 0 then
        return (os.clock() - state.start_time) * 1000 >= duration
    end
    return false
end

-- !dvd | speed | duration
ANIM_LIB["dvd"] = function(src, state, args)
    if not src.scene_item then return true end

    local speed = tonumber(args[1]) or 5
    local duration = parse_time(args[2] or "0ms")

    if not state.init then
        local pos = src.scene_item.pos()
        local bounds = src.vars.screen or { width = 1920, height = 1080 }

        state.x, state.y = pos.x, pos.y
        state.vx, state.vy = speed, speed
        state.w = src.scene_item.width()
        state.h = src.scene_item.height()
        state.sw, state.sh = bounds.width, bounds.height

        state.start_time = os.clock()
        state.init = true
    end

    local next_x = state.x + state.vx
    local next_y = state.y + state.vy

    -- Bounce X
    if next_x <= 0 then
        next_x = 0; state.vx = math.abs(state.vx)
    elseif next_x >= (state.sw - state.w) then
        next_x = state.sw - state.w; state.vx = -math.abs(state.vx)
    end

    -- Bounce Y
    if next_y <= 0 then
        next_y = 0; state.vy = math.abs(state.vy)
    elseif next_y >= (state.sh - state.h) then
        next_y = state.sh - state.h; state.vy = -math.abs(state.vy)
    end

    state.x, state.y = next_x, next_y
    src.scene_item.pos({ x = next_x, y = next_y })

    if duration > 0 then
        return (os.clock() - state.start_time) * 1000 >= duration
    end
    return false
end

-- !sway | speed | duration
ANIM_LIB["sway"] = function(src, state, args)
    if not src.scene_item then return true end

    local speed = tonumber(args[1]) or 0.05
    local duration = parse_time(args[2] or "0ms")

    if not state.init then
        state.timer = 0
        state.start_time = os.clock()
        state.init = true
    end

    state.timer = state.timer + speed
    local tilt = math.sin(state.timer) * 15 -- 15 degrees max

    src.scene_item.rot(tilt)

    if duration > 0 then
        return (os.clock() - state.start_time) * 1000 >= duration
    end
    return false
end


ANIM_LIB["run"] = function(src, state, args)
    local target_label = args[1]

    local snapshot = {}
    if src.active_scope then
        for k, v in pairs(src.active_scope) do 
            snapshot[k] = v 
        end
    end

    local interrupt_thread = {
        type = "THREAD", queue = src.queue, labels = src.labels,
        current_idx = src.labels[target_label], state = {},
        active_source = src.scene_item, active_sources = src.active_sources,
        variables = snapshot, call_stack = {}
    }
    
    if not src.async_tasks then src.async_tasks = {} end
    table.insert(src.async_tasks, interrupt_thread)
    
    return true
end

-- !stop
ANIM_LIB["stop"] = function(src, state, args)
    local target = resolve_path(src, args[1]) or args[1]
    
    if target == "all" then
        src.async_tasks = {}
        return true
    end

    if not src.async_tasks then return true end
    
    local target_map = {}
    local current_targets = src.active_sources or { src.scene_item }
    for _, item in ipairs(current_targets) do
        if item then target_map[tostring(item)] = true end
    end
    
    for i = #src.async_tasks, 1, -1 do
        local task = src.async_tasks[i]
        local task_targets = task.active_sources or { task.active_source }
        
        local kill_thread = false
        for _, task_item in ipairs(task_targets) do
            if task_item and target_map[tostring(task_item)] then
                kill_thread = true
                break
            end
        end
        
        if kill_thread then
            table.remove(src.async_tasks, i)
        end
    end
    
    return true
end
ANIM_LIB["then"] = function(src, state, args)
    local cmd = args[1]
    local cmd_args = {}; for i=2, #args do table.insert(cmd_args, args[i]) end
    local exe = compile_line(cmd, cmd_args)
    if exe then exe(src, state) end
    return true
end

-- !camera_shake | intensity | duration
ANIM_LIB["camera_shake"] = function(src, state, args)
    local intensity = tonumber(args[1]) or 10
    local duration = parse_time(args[2] or "200ms")
    if not state.init then
        state.init = true; state.start_time = os.clock()
        -- Save original pos of camera source
        if src.active_sources and src.active_sources[1] then
            state.cam = src.active_sources[1]
            state.ox = state.cam.pos().x; state.oy = state.cam.pos().y
        elseif src.scene_item then
            state.cam = src.scene_item
            state.ox = state.cam.pos().x; state.oy = state.cam.pos().y
        end
    end
    if state.cam then
        local dx = math.random(-intensity, intensity)
        local dy = math.random(-intensity, intensity)
        state.cam.pos({x=state.ox + dx, y=state.oy + dy})
    end
    if (os.clock() - state.start_time) * 1000 >= duration then
        if state.cam then state.cam.pos({x=state.ox, y=state.oy}) end
        return true
    end
    return false
end

ANIM_LIB["path"] = function(src, state, args)
    local targets = src.active_sources or { src.scene_item }
    if #targets == 0 then return true end

    if not state.init then
        state.configs = {}
        state.duration = parse_time(args[3]) or 1000
        state.start_time = os.clock()
        state.easing = args[4] or "quad_out"

        for _, item in ipairs(targets) do
            local start_pos = item.pos()
            
            -- Parse P1 (Control Point)
            local p1 = { x = start_pos.x, y = start_pos.y }
            for _, pair in ipairs(safe_split(args[1])) do
                local k, v = string.match(pair, "([^:]+):(.+)")
                if k and v then
                    k = k:match("^%s*(.-)%s*$")
                    v = v:match("^%s*(.-)%s*$")
                    if k == "x" then p1.x = tonumber(resolve_path(src, v)) or p1.x end
                    if k == "y" then p1.y = tonumber(resolve_path(src, v)) or p1.y end
                end
            end

            -- Parse P2 (Target Point)
            local p2 = { x = start_pos.x, y = start_pos.y }
            for _, pair in ipairs(safe_split(args[2])) do
                local k, v = string.match(pair, "([^:]+):(.+)")
                if k and v then
                    k = k:match("^%s*(.-)%s*$")
                    v = v:match("^%s*(.-)%s*$")
                    if k == "x" then p2.x = tonumber(resolve_path(src, v)) or p2.x end
                    if k == "y" then p2.y = tonumber(resolve_path(src, v)) or p2.y end
                end
            end
            
            table.insert(state.configs, { item = item, p0 = start_pos, p1 = p1, p2 = p2 })
        end
        state.init = true
    end

    local elapsed = (os.clock() - state.start_time) * 1000
    local t = math.min(elapsed / state.duration, 1)
    
    local ease_func = EASING_FUNCS[state.easing] or EASING_FUNCS.linear
    local eased_t = ease_func(t)

    for _, config in ipairs(state.configs) do
        local inv_t = 1 - eased_t
        local x = (inv_t^2 * config.p0.x) + (2 * inv_t * eased_t * config.p1.x) + (eased_t^2 * config.p2.x)
        local y = (inv_t^2 * config.p0.y) + (2 * inv_t * eased_t * config.p1.y) + (eased_t^2 * config.p2.y)
        config.item.pos({ x = x, y = y })
    end
    return t >= 1
end

-- !pin | parent_source | offsets (x:50, y:10)
-- To unpin, use !pin|none
ANIM_LIB["pin"] = function(src, state, args)
    local targets = src.active_sources or { src.scene_item }
    if #targets == 0 then return true end

    if not src.pinned_sources then src.pinned_sources = {} end
    
    local parent_arg = args[1]
    local offset_arg = args[2]

    if not parent_arg or parent_arg == "none" then
        for _, item in ipairs(targets) do
            src.pinned_sources[tostring(item)] = nil
        end
        return true
    end

    local parent_item = nil
    local resolved_parent = resolve_path(src, parent_arg)
    

    if type(resolved_parent) == "table" and resolved_parent.pos then
        parent_item = resolved_parent
    else
        parent_item = SCRIPT_FUNCS.source(src, resolved_parent)
    end
    
    if not parent_item then return true end


    local ox, oy = 0, 0
    if offset_arg then
        for _, pair in ipairs(safe_split(offset_arg)) do
            local k, v = string.match(pair, "([^:]+):(.+)")
            if k and v then
                k = k:match("^%s*(.-)%s*$")
                v = v:match("^%s*(.-)%s*$")
                if k == "x" then ox = tonumber(resolve_path(src, v)) or 0 end
                if k == "y" then oy = tonumber(resolve_path(src, v)) or 0 end
            end
        end
    end


    for _, item in ipairs(targets) do
        src.pinned_sources[tostring(item)] = {
            child = item,
            parent = parent_item,
            ox = ox,
            oy = oy
        }
    end
    
    return true
end

-- !spiral | center_x, center_y | start_radius | rotations | duration | easing
ANIM_LIB["spiral"] = function(src, state, args)
    local targets = src.active_sources or { src.scene_item }
    if #targets == 0 then return true end

    if not state.init then
        state.configs = {}
        state.duration = parse_time(args[4]) or 1000
        state.start_time = os.clock()
        state.easing = args[5] or "quad_out"
        
        -- Parse Center Point
        local cp_raw = safe_split(args[1])
        state.cx = tonumber(resolve_path(src, cp_raw[1]:match("x:(.+)"))) or 960
        state.cy = tonumber(resolve_path(src, cp_raw[2]:match("y:(.+)"))) or 540
        
        state.start_r = tonumber(resolve_path(src, args[2])) or 500
        state.rotations = tonumber(resolve_path(src, args[3])) or 2
        state.init = true
    end

    local elapsed = (os.clock() - state.start_time) * 1000
    local t = math.min(elapsed / state.duration, 1)
    
    local ease_func = EASING_FUNCS[state.easing] or EASING_FUNCS.linear
    local eased_t = ease_func(t)

    -- Archimedean Spiral Logic
    -- Current Radius shrinks from start_r to 0
    local current_r = state.start_r * (1 - eased_t)
    -- Current Angle goes from 0 to (rotations * 2 * PI)
    local angle = eased_t * (state.rotations * 2 * math.pi)

    for _, item in ipairs(targets) do
        local x = state.cx + math.cos(angle) * current_r
        local y = state.cy + math.sin(angle) * current_r
        item.pos({ x = x, y = y })
    end

    return t >= 1
end


-- !fade | target_opacity | duration | easing
ANIM_LIB["fade"] = function(src, state, args)
    local targets = src.active_sources or { src.scene_item }
    if #targets == 0 then return true end

    if not state.init then
        state.configs = {}
        state.duration = parse_time(args[2]) or 1000
        state.start_time = os.clock()
        state.easing = args[3] or "linear"

        for _, item in ipairs(targets) do
            -- Use the wrapper's opacity() function as a getter
            local current_opacity = item.opacity() or 1
            local target_opacity = parse_value(src, current_opacity, args[1])
            
            table.insert(state.configs, {
                item = item,
                start = current_opacity,
                target = target_opacity
            })
        end
        state.init = true
    end

    local elapsed = (os.clock() - state.start_time) * 1000
    local t = math.min(elapsed / state.duration, 1)
    
    local ease_func = EASING_FUNCS[state.easing] or EASING_FUNCS.linear
    local eased_t = ease_func(t)

    for _, config in ipairs(state.configs) do
        local val = config.start + (config.target - config.start) * eased_t
        config.item.opacity(val)
    end

    return t >= 1
end

ANIM_LIB["sound"] = function(src, state, args)
    local target_name = resolve_path(src, args[1]) or args[1]
    local action      = resolve_path(src, args[2]) or args[2]

    local source = obs.obs_get_source_by_name(target_name)
    if not source then return true end


    if action == "play" then
        obs.obs_source_media_restart(source)
        obs.obs_source_release(source)
        return true
    elseif action == "pause" then
        obs.obs_source_media_play_pause(source, true)
        obs.obs_source_release(source)
        return true
    elseif action == "stop" then
        obs.obs_source_media_stop(source)
        obs.obs_source_release(source)
        return true
    end

    local target_val = tonumber(resolve_path(src, args[3]) or args[3]) or 0
    local raw_time   = resolve_path(src, args[4]) or args[4]
    if raw_time == nil or raw_time == "" then
        if action == "volume" then
            obs.obs_source_set_volume(source, target_val)
        end
        obs.obs_source_release(source)
        return true
    end

    if not state.initialized then
        state.duration = parse_time(raw_time)
        if state.duration <= 0 then state.duration = 0.001 end
        state.elapsed = 0
        state.target_val = target_val
        
        if action == "volume" then
            state.start_val = obs.obs_source_get_volume(source)
        else
            state.start_val = 0
        end
        state.initialized = true
    end

    local dt = (src.vars and src.vars["tick"]) or 0.016
    state.elapsed = state.elapsed + dt
    local progress = math.min(state.elapsed / state.duration, 1.0)
    
    local current_val = state.start_val + ((state.target_val - state.start_val) * progress)

    if action == "volume" then
        obs.obs_source_set_volume(source, current_val)
    end

    obs.obs_source_release(source)
    if progress >= 1.0 then return true end
    return false 
end

SCRIPT_FUNCS = {
    alert = function(src, msg)
        obslua.script_log(obslua.LOG_WARNING, "[4IM3-SCRIPT] " .. tostring(msg))
        return 0
    end,
    dist = function(src, x1, y1, x2, y2)
        local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
        local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
        return math.sqrt(dx * dx + dy * dy)
    end,
    mouse= function()
        ffi.C.GetCursorPos(mouse)
        return {x=mouse.x, y= mouse.y}
    end,
    source = function(src, name)
        if not name then return nil end
        if type(name) == "table" and name.data then return name end
        -- Use the front.source wrapper which handles scene finding automatically
        local asource = obs.front.source(name)
        if not asource or not asource.data then
            obslua.script_log(obslua.LOG_WARNING, "[4IM3-SCRIPT] Source not found: " .. tostring(name))
            return nil
        end
        table.insert(obs._unload, asource)

        return asource
    end,

    clone = function(src, auto_delete)
        if not src.scene_item then return nil end
        local original_source = src.scene_item.get_source()
        if not original_source then return nil end
        
        -- 1. Create a Unique Name (Name + Time + Random to prevent conflicts)
        local unique_name = obslua.obs_source_get_name(original_source) .. "_clone_" .. tostring(os.clock() * 1000) .. math.random(100,999)
        
        -- 2. Get Current Scene Wrapper
        local scene = obs.scene:get_scene()
        if not scene then return nil end

        local new_source = obslua.obs_source_duplicate(original_source, unique_name, false)
        if not new_source then scene.free(); return nil end

        obslua.obs_scene_add(scene.data, new_source)
        
        local wrapped = scene.get(unique_name)
        
        obslua.obs_source_release(new_source) 
        scene.free()
        if wrapped and wrapped.data then
            wrapped.transform(src.scene_item.transform())
        else
             obslua.script_log(obslua.LOG_WARNING, "[4IM3-SCRIPT] Failed to clone source: " .. tostring(unique_name))
             return nil
        end
        table.insert(obs._unload, function()
            if auto_delete then
                wrapped.remove()
            else
                return wrapped.free()
            end
        end)
        obslua.obs_sceneitem_select(wrapped.data, false)
        return wrapped
    end,


    delete_source = function(src)
        if src.scene_item and src.scene_item.remove then
            src.scene_item.remove()
        end
        return 0
    end
}
-- include math to the 'SCRIPT_FUNCS'
for key, fn in pairs(math) do
    if type(fn) == "function" then
        SCRIPT_FUNCS[key] = function(sr, ...)
            return fn(...)
        end
    end
end




function evaluate_math(src, expr)
    if not expr then return 0 end

    -- 1. Check for @Function calls (e.g. @copy_self)
    local direct_func, direct_args = expr:match("^%s*@([%w_]+)(%b())%s*$")
    
    if not direct_func then
        local s_func, s_args = expr:match("^%s*(source)(%b())%s*$")
        if s_func then direct_func = s_func; direct_args = s_args end
    end

    if direct_func then
        local func = SCRIPT_FUNCS[direct_func]
        if func then
            local clean_args = direct_args:sub(2, -2)
            local resolved_args = {}
            for arg in string.gmatch(clean_args, "([^,]+)") do
                arg = arg:match("^%s*(.-)%s*$")
                arg = arg:gsub("\"", ""):gsub("'", "")
                table.insert(resolved_args, resolve_path(src, arg))
            end
            return func(src, unpack(resolved_args))
        else
            obslua.script_log(obslua.LOG_WARNING, "[4IM3] Function not found: @" .. tostring(direct_func))
        end
    end

    -- 2. Process Inline Math
    local working_expr = expr:match("^%((.*)%)$") or expr

    -- A. Replace inline @functions
    working_expr = working_expr:gsub("@([%w_]+)(%b())", function(func_name, args_block)
        local func = SCRIPT_FUNCS[func_name]
        if not func then return 0 end

        local clean_args = args_block:sub(2, -2)
        local resolved_args = {}
        for arg in string.gmatch(clean_args, "([^,]+)") do
            arg = arg:match("^%s*(.-)%s*$")
            table.insert(resolved_args, resolve_path(src, arg))
        end

        local result = func(src, unpack(resolved_args))
        if type(result) ~= "number" then return 0 end
        return result
    end)

    working_expr = working_expr:gsub("([%a_][%w_%.]*)", function(var_name)

        if var_name == "math" or var_name:match("^math%.") then 
            return var_name 
        end
        
        if var_name == "floor" or var_name == "ceil" or var_name == "sin" or var_name == "cos" or var_name == "abs" then 
            return var_name 
        end

        if tonumber(var_name) then return var_name end

        local val = resolve_path(src, var_name)
        return tonumber(val) or 0
    end)

    -- 3. Execute
    local func = load("return " .. working_expr)
    if func then
        local success, result = pcall(func)
        if success then return result end
    end

    return 0
end

function resolve_path(src, path)
    if path == nil then return nil end

    if type(path) == "string" and (path:match("^%b()$") or path:match("@") or path:match("^%s*source%s*%(")) then
        return evaluate_math(src, path)
    end

    if type(path) ~= "string" then return path end

    local parts = split(path, ".")
    local root_key = parts[1]
    local current_val = nil

    if src.active_task and src.active_task.variables and src.active_task.variables[root_key] ~= nil then
        current_val = src.active_task.variables[root_key]

    elseif src.active_scope and src.active_scope[root_key] ~= nil then
        current_val = src.active_scope[root_key]

    elseif src.vars and src.vars[root_key] ~= nil then
        current_val = src.vars[root_key]

    elseif src.scene_item and type(src.scene_item[root_key]) == "function" then
        current_val = src.scene_item[root_key]()
    else
        return tonumber(path) or path
    end

    for i = 2, #parts do
        if type(current_val) == "table" then
            current_val = current_val[parts[i]]

            if type(current_val) == "function" then

                local success, result = pcall(current_val)
                if success then current_val = result else return nil end
            end
        else
            return nil
        end
    end

    return current_val
end
-- [[ MAIN ]]
function defaults(settings)
    settings.str("output", "text", true)
    settings.str("code", "", true)
    settings.str("input", "", true)
end
function setup(settings)
    src= {
        settings = settings,
        current_idx = 1,
        state = {},
        async_tasks = {},
        queue = {},
        labels = {},
        scene_item = nil,
    }
    obs.script:ui(function(ui)
        local opt = ui.options("output", "")
        opt.add.str("< OUTPUT: TEXT >", "text").add.str(
            "< OUTPUT: INPUT >", "input"
        ).add.str("< OUTPUT: FILE >", "file")
        local text = ui.input("text", "", obs.enum.text.textarea)
        local input = ui.input("input", "")
        local file = ui.path("file", "")
        file.hide(); input.hide(); text.hide()
        local run = ui.button("run_code", "Execute", function()
            run_code(src, src.settings)
        end)
        local function init_show(value)
            if value == "text" then
                text.show(); input.hide(); file.hide()
            elseif value == "input" then
                text.hide(); input.show(); file.hide()
            elseif value == "file" then
                text.hide(); input.hide(); file.show()
            end
        end
        opt.onchange(function(value)
            init_show(value)
            return true
        end)
        init_show(src.settings.str("output"))
        return ui
    end)


end
-- [[ RUN CODE ]]
function run_code(src, settings)
    local raw_code = ""
    local output_type = settings.str("output")
    if output_type == "text" then
        raw_code = settings.str("text")
    elseif output_type == "input" then
        raw_code = settings.str("input")
    elseif output_type == "file" then
        local file_path = settings.str("file")
        local file = io.open(file_path, "r")
        if file then
            raw_code = file:read("*all"); file:close()
        end
    end
    -- Clean comments
    local clean_lines = {}
    for line in raw_code:gmatch("([^\r\n]*)\r?\n?") do
        local result_line = line
        local search_start = 1
        while true do
            local s, e = string.find(result_line, "%-%-", search_start)
            if not s then break end
            local char_before = (s > 1) and string.sub(result_line, s - 1, s - 1) or ""
            if char_before == "|" or char_before == ":" or char_before == "," then
                search_start = e + 1
            else
                result_line = string.sub(result_line, 1, s - 1)
                break
            end
        end
        table.insert(clean_lines, result_line)
    end
    local code = table.concat(clean_lines, "\n")
    src.queue = {}
    src.hotkeys = {}
    src.labels = {}
    src.async_tasks = {}
    src.current_idx = 1
    src.collision_pairs = {}
    src.watchers = {}
    src.active_sources = {}
    src.state = {}
    src.pinned_sources= {}
    src.scene_item = nil
    src.isInitialized = true
    src.vars = src.vars or { screen = obs.scene:size() , pi = math.pi, huge = math.huge}
    src.call_stack = {}
    local compiled_queue, compiled_labels = compile_block_text(src, code)
    src.queue = compiled_queue
    src.labels = compiled_labels
end

function smart_split(str)
    local chunks = {}
    local depth = 0
    local start = 1
    local len = #str
    
    for i = 1, len do
        local c = str:sub(i, i)
        if c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
        elseif depth == 0 then

            if str:sub(i, i+2) == "|+|" then
                local chunk = str:sub(start, i-1):match("^%s*(.-)%s*$")
                if chunk and chunk ~= "" then table.insert(chunks, chunk) end
                start = i + 3
                i = i + 2 
            end
        end
    end
    local last = str:sub(start):match("^%s*(.-)%s*$")
    if last and last ~= "" then table.insert(chunks, last) end
    return chunks
end


function compile_block_text(src, raw_code)
    local function resolve_includes(raw_text)
        return raw_text:gsub("!include%|([^|]+)%|%+%|", function(filepath)
            filepath = filepath:match("^%s*(.-)%s*$")
            local f = io.open(filepath, "r")
            if f then
                local content = f:read("*all")
                f:close()
                return resolve_includes(content) 
            end
            return "" 
        end)
    end
    raw_code = resolve_includes(raw_code)
    local queue = {}
    local labels = {}
    
    local steps = smart_split(raw_code)
    
    for _, step in ipairs(steps) do
        local clean_step = step:match("^%s*(.-)%s*$")
        
        local watch_vars_str, rest = clean_step:match("^%[%[(.-)%]%]%s*(.*)")
        local interrupt_label = nil
        
        if watch_vars_str then
            -- Check if there's a [Label] right after the [[vars]]
            local label_match, rest_after_label = rest:match("^%[(.-)%]%s*(.*)")
            if label_match then
                interrupt_label = label_match:match("^%s*(.-)%s*$")
                clean_step = rest_after_label
            else
                clean_step = rest
            end
        end
        
        local exe_func = nil

        if clean_step:match("^!run%s*%{") then
            local first_brace = clean_step:find("{")
            local last_brace = clean_step:match("^.*()%}")
            
            if first_brace and last_brace then
                local inner_code = clean_step:sub(first_brace + 1, last_brace - 1)
                local sub_queue, sub_labels = compile_block_text(src, inner_code)
                
                exe_func = function(ctx)
                    local snapshot = {}
                    local target_vars = ctx.active_scope or {}
                    for k, v in pairs(target_vars) do snapshot[k] = v end
                    
                    local new_thread = {
                        type = "THREAD", queue = sub_queue, labels = sub_labels,
                        current_idx = 1, state = {}, active_source = ctx.scene_item,
                        active_sources = ctx.active_sources, variables = snapshot, call_stack = {} 
                    }
                    if not ctx.async_tasks then ctx.async_tasks = {} end
                    table.insert(ctx.async_tasks, new_thread)
                    return true
                end
            end

        elseif clean_step:sub(1, 1) == "!" then
            local parts = split(clean_step:sub(2), "|")
            local cmd = parts[1]
            table.remove(parts, 1)

            if cmd == "label" and parts[1] then
                local label_name = parts[1]:match("^%s*(.-)%s*$")
                labels[label_name] = #queue + 1
            end

            exe_func = compile_line(cmd, parts)
        end

        if exe_func then
            if watch_vars_str then
                local watch_vars = {}
                for v in watch_vars_str:gmatch("([^,]+)") do
                    table.insert(watch_vars, v:match("^%s*(.-)%s*$"))
                end
                
                local original_exe = exe_func
                exe_func = function(ctx, state)
                    state = state or ctx.state 
                    
                    if not state._w_init then
                        state._w_vals = {}
                        for _, v in ipairs(watch_vars) do
                            state._w_vals[v] = tostring(resolve_path(ctx, v))
                        end
                        state._w_init = true
                    end
                    
                    -- Frame-by-Frame Check
                    for _, v in ipairs(watch_vars) do
                        if tostring(resolve_path(ctx, v)) ~= state._w_vals[v] then
                            -- State changed! Wipe the memory.
                            for k in pairs(state) do state[k] = nil end 
                            
                            if interrupt_label then
                                return "JUMP", interrupt_label
                            else
                                return true
                            end
                        end
                    end
                    
                    local res, target = original_exe(ctx, state)
                    
                    if res ~= false then
                        state._w_init = nil
                        state._w_vals = nil
                    end
                    return res, target
                end
            end
            
            table.insert(queue, exe_func)
        end
    end
    
    return queue, labels
end


function script_tick(fps)
    if not src.isInitialized or not src.queue then return end
    if not src.vars then src.vars = {} end
    src.vars["tick"]=fps or 0.016

    if src.pinned_sources then
        for pin_id, pin_data in pairs(src.pinned_sources) do
            if pin_data.child and pin_data.parent then
                local p_status, p_pos = pcall(function() return pin_data.parent.pos() end)
                local c_status, c_pos = pcall(function() return pin_data.child.pos() end)
                
                if p_status and p_pos and c_status and c_pos then
                    -- Both exist, snap child to parent + offset
                    pcall(function()
                        pin_data.child.pos({
                            x = p_pos.x + pin_data.ox,
                            y = p_pos.y + pin_data.oy
                        })
                    end)
                else
                    src.pinned_sources[pin_id] = nil
                end
            end
        end
    end
    if src.watchers then
        for _, w in ipairs(src.watchers) do
            local current_val = resolve_path(src, w.var)
            local current_str = tostring(current_val)
            
            -- Only evaluate if the value has actually changed since the last frame
            if current_str ~= w.last_val then
                w.last_val = current_str
                
                local condition_met = false
                
                if w.op and w.val then
                    local check_val = resolve_path(src, w.val)
                    local v1, v2 = tonumber(current_val), tonumber(check_val)
                    
                    if v1 and v2 then
                        if w.op == "==" then condition_met = (v1 == v2)
                        elseif w.op == ">" then condition_met = (v1 > v2)
                        elseif w.op == "<" then condition_met = (v1 < v2)
                        elseif w.op == ">=" then condition_met = (v1 >= v2)
                        elseif w.op == "<=" then condition_met = (v1 <= v2)
                        elseif w.op == "!=" or w.op == "~=" then condition_met = (v1 ~= v2) end
                    else
                        -- String Math (Text comparison)
                        if w.op == "==" then condition_met = (current_str == tostring(check_val))
                        elseif w.op == "!=" or w.op == "~=" then condition_met = (current_str ~= tostring(check_val)) end
                    end
                else
                    -- No condition provided, so ANY change is a valid trigger
                    condition_met = true 
                end
                
                if condition_met then
                    -- Spawn the interrupt thread!
                    if src.labels[w.label] then
                        local snapshot = {}
                        for k, v in pairs(src.active_scope or {}) do snapshot[k] = v end
                        local interrupt_thread = {
                            type = "THREAD", queue = src.queue, labels = src.labels,
                            current_idx = src.labels[w.label], state = {},
                            active_source = src.scene_item, active_sources = src.active_sources,
                            variables = snapshot, call_stack = {}
                        }
                        table.insert(src.async_tasks, interrupt_thread)
                    end
                end
            end
        end
    end
    if src.collision_pairs then
        if not src.cooldowns then src.cooldowns = {} end
        for i, pair in ipairs(src.collision_pairs) do
            local o1, o2 = pair.o1, pair.o2
            if o1 and o2 and o1.pos and o2.pos then
                local p1x, p1y = o1.pos().x, o1.pos().y
                local p2x, p2y = o2.pos().x, o2.pos().y
                local w1, h1 = o1.width(), o1.height()
                local w2, h2 = o2.width(), o2.height()
                local collision = not ( (p1x + w1 < p2x) or (p1x > p2x + w2) or (p1y + h1 < p2y) or (p1y > p2y + h2) )
                
                if collision then
                    if not src.cooldowns[i] then
                        src.cooldowns[i] = true
                        -- Trigger CALL to label
                        if not src.call_stack then src.call_stack = {} end
                        table.insert(src.call_stack, src.current_idx) -- Return to current
                        local jmp = src.labels[pair.label]
                        if jmp then src.current_idx = jmp end
                        src.state = {}
                    end
                else
                    src.cooldowns[i] = false
                end
            end
        end
    end
    if src.async_tasks then
        for i = #src.async_tasks, 1, -1 do
            local task = src.async_tasks[i]
            
            -- THREAD (Nested Queue)
            if task.type == "THREAD" then
                local ops = 0
                while task.queue[task.current_idx] do
                    if ops >= 10 then break end
                    
                    local func = task.queue[task.current_idx]
                    local global_item = src.scene_item 
                    local global_sources = src.active_sources
                    local global_scope = src.active_scope


                    src.scene_item = task.active_source 
                    src.active_sources = task.active_sources 
                    src.active_scope = task.variables 
                    
                    local result, target = func(src, task.state)
                    
                    task.active_source = src.scene_item
                    task.active_sources = src.active_sources
                    
                    src.scene_item = global_item 
                    src.active_sources = global_sources
                    src.active_scope = global_scope
                    
                    if result == false then break 
                    elseif result == "CALL" then
                        if not task.call_stack then task.call_stack = {} end
                        table.insert(task.call_stack, task.current_idx + 1)
                        local jmp = task.labels[target]
                        if jmp then task.current_idx = jmp else task.current_idx = task.current_idx + 1 end
                        task.state = {}
                    elseif result == "RETURN" then
                        if task.call_stack and #task.call_stack > 0 then
                            task.current_idx = table.remove(task.call_stack)
                        else
                            task.current_idx = #task.queue + 1 
                        end
                        task.state = {}
                    elseif result == "JUMP" then
                        local jmp = task.labels[target]
                        if jmp then task.current_idx = jmp else task.current_idx = task.current_idx + 1 end
                        task.state = {} 
                    else
                        task.current_idx = task.current_idx + 1
                        task.state = {}
                    end
                    ops = ops + 1

                end
                if task.current_idx > #task.queue then table.remove(src.async_tasks, i) end

            else
                if not task.exe then task.exe = compile_line(task.cmd, task.args) end
                if task.exe then
                    local is_finished = task.exe(src, task.state)
                    if is_finished then table.remove(src.async_tasks, i) end
                end
            end
        end
    end
    local brake = 0
    while src.queue[src.current_idx] do
        if brake > 100 then break end
        local execute_func = src.queue[src.current_idx]
        if not execute_func then src.current_idx = src.current_idx + 1; src.state = {}; return end
        
        local result, target = execute_func(src)
        if result == false then return end
        brake = brake + 1

        if result == "CALL" then
            if not src.call_stack then src.call_stack = {} end
            table.insert(src.call_stack, src.current_idx + 1)
            local jmp = src.labels[target]; if jmp then src.current_idx = jmp else src.current_idx = src.current_idx + 1 end
            src.state = {}
        elseif result == "RETURN" then
            if src.call_stack and #src.call_stack > 0 then src.current_idx = table.remove(src.call_stack)
            else src.current_idx = src.current_idx + 1 end; src.state = {}
        elseif result == "RESET" then src.current_idx = 1; src.state = {}; src.async_tasks = {}; src.call_stack = {}
        elseif result == "JUMP" then
            local jmp = src.labels[target]; if jmp then src.current_idx = jmp else src.current_idx = src.current_idx + 1 end; src.state = {}
        elseif result == true then src.current_idx = src.current_idx + 1; src.state = {} end
    end
end








-- [[ OBS CUSTOM API BEGIN ]]
    -- [[ OBS CUSTOM CALLBACKS ]]
        function script_load(settings)
            obs.utils.script_shutdown = false
            settings = obs.PairStack(settings, nil, nil, true)
            obs.utils.settings = settings

            if setup and type(setup) == "function" then
                setup(settings)
            end

            for _, filter in pairs(obs.utils.filters) do
                obslua.obs_register_source(filter)
            end
        end

        function script_save(settings)
            if obs.utils.script_shutdown then return end

            -- [[ OBS REGISTER HOTKEY SAVE DATA]]
            for name, iter in pairs(obs.register.hotkey_id_list) do
                local new_data = obslua.obs_hotkey_save(iter.id)
                if new_data then
                    obs.utils.settings.arr(name, new_data)
                    obslua.obs_data_array_release(new_data)
                end
            end
            -- [[ OBS REGISTER HOTKEY SAVE DATA END]]

            if type(onSaving) == "function" then
                return onSaving(obs.PairStack(settings, nil, nil, true))
            end
        end

        function script_unload()
            obs.utils.script_shutdown = true

            -- if obs.utils.scheduled then
            --     for _, clb in pairs(obs.utils.scheduled) do
            --         obslua.timer_remove(clb)
            --     end
            --     obs.utils.scheduled = {}
            -- end

            -- for _, iter in pairs(obs.mem.freeup) do
            --     if iter and iter.data then
            --         iter.free()
            --     end
            -- end
            if obs._unload and type(obs._unload) == "table" then
                for _, iter in pairs(obs._unload) do
                    if type(iter) == "table" and iter.data and iter.free then
                        iter.free()
                    elseif type(iter) == "function" then
                        pcall(function() iter() end)
                    end
                end
            end
            if unset and type(unset) == "function" then
                return unset()
            end
        end

        function script_defaults(settings)
            if type(defaults) == "function" then
                return defaults(obs.PairStack(settings, nil, nil, true))
            end
        end

        function script_properties()
            if obs.utils.ui and type(obs.utils.ui) == "function" then
                return obs.utils.ui()
            end
        end

    -- [[ OBS CUSTOM CALLBACKS END ]]

    obs = {
        utils = {
            scheduled = {},
            script_shutdown = false,
            OBS_SCENEITEM_TYPE = 1,
            OBS_SRC_TYPE = 2,
            OBS_OBJ_TYPE = 3,
            OBS_ARR_TYPE = 4,
            OBS_SCENE_TYPE = 5,
            OBS_SCENEITEM_LIST_TYPE = 6,
            OBS_SRC_LIST_TYPE = 7,
            OBS_UN_IN_TYPE = -1,
            OBS_SRC_WEAK_TYPE = 8,
            table = {},
            expect_wrapper = {},
            properties = {
                list = {}, options = {},
            },
            filters = {},
            _queue = {}
        },
        time = {},
        scene = {},
        client = {},
        mem = { freeup = {} },
        script = {},
        enum = {
            path = {
                read = obslua.OBS_PATH_FILE, write = obslua.OBS_PATH_FILE_SAVE, folder = obslua.OBS_PATH_DIRECTORY
            },
            button = {
                default = obslua.OBS_BUTTON_DEFAULT, url = obslua.OBS_BUTTON_URL,
            },
            list = {
                string = obslua.OBS_EDITABLE_LIST_TYPE_STRINGS,
                url = obslua.OBS_EDITABLE_LIST_TYPE_FILES_AND_URLS,
                file = obslua.OBS_EDITABLE_LIST_TYPE_FILES
            },
            text = {
                error = obslua.OBS_TEXT_INFO_ERROR,
                default = obslua.OBS_TEXT_INFO,
                warn = obslua.OBS_TEXT_INFO_WARNING,
                input = obslua.OBS_TEXT_DEFAULT,
                password = obslua.OBS_TEXT_PASSWORD,
                textarea = obslua.OBS_TEXT_MULTILINE,
            },
            group = {
                normal = obslua.OBS_GROUP_NORMAL, checked = obslua.OBS_GROUP_CHECKABLE,
            },
            options = {
                string = obslua.OBS_COMBO_FORMAT_STRING,
                int = obslua.OBS_COMBO_FORMAT_INT,
                float = obslua.OBS_COMBO_FORMAT_FLOAT,
                bool = obslua.OBS_COMBO_FORMAT_BOOL,
                edit = obslua.OBS_COMBO_TYPE_EDITABLE,
                default = obslua.OBS_COMBO_TYPE_LIST,
                radio = obslua.OBS_COMBO_TYPE_RADIO,
            },
            number = {
                int = obslua.OBS_COMBO_FORMAT_INT,
                float = obslua.OBS_COMBO_FORMAT_FLOAT,
                slider = 1000,
                input = 2000
            },
            bound = {
                none = obslua.OBS_BOUNDS_NONE,
                scale_inner = obslua.OBS_BOUNDS_SCALE_INNER,
                scale_outer = obslua.OBS_BOUNDS_SCALE_OUTER,
                stretch = obslua.OBS_BOUNDS_STRETCH,
                scale_width = obslua.OBS_BOUNDS_SCALE_WIDTH,
                scale_height = obslua.OBS_BOUNDS_SCALE_HEIGHT,
                max = obslua.OBS_BOUNDS_MAX_ONLY,
            }
        },
        register = {
            hotkey_id_list = {}, event_id_list = {}
        },
        front = {},
        shared = {},
        _unload= {}
    };
    bit = require('bit')
    os = require('os')
    -- dkjson= require('dkjson')
    math.randomseed(os.time())
    -- schedule an event
    -- [[  MEMORY MANAGE API ]]
        local ffi = require("ffi")

        ffi.cdef[[
            typedef struct { float x; float y; } vec2;
            
            // Define the native C functions we want to access
            void obs_sceneitem_get_pos(void *item, vec2 *pos);
            void obs_sceneitem_set_pos(void *item, const vec2 *pos);
            
            void obs_sceneitem_get_scale(void *item, vec2 *scale);
            void obs_sceneitem_set_scale(void *item, const vec2 *scale);
            
            void obs_sceneitem_set_rot(void *item, float rot);
            
            // We treat the userdata pointers as void* for FFI compatibility
        ]]
        function obs.shared.api(named_api)
            local arr_data_t = nil
            local function init_obs_data_t()
                for _, scene_name in pairs(obs.scene:names()) do
                    local a_scene = obs.scene:get_scene(scene_name)
                    if a_scene and a_scene.source then
                        local s_data_t = obs.PairStack(
                            obslua.obs_source_get_settings(a_scene.source)
                        )
                        if not s_data_t or s_data_t.data == nil then
                            a_scene.free()
                        else
                            if arr_data_t and arr_data_t.data then
                                -- replace data to the current
                                s_data_t.arr(named_api, arr_data_t.data)
                            else
                                -- register data to the current

                                arr_data_t = s_data_t.arr(named_api)
                                if not arr_data_t or arr_data_t.data == nil then
                                    arr_data_t = obs.ArrayStack()
                                    s_data_t.arr(named_api, arr_data_t.data)
                                    arr_data_t.free()
                                    arr_data_t = nil
                                end
                            end
                            s_data_t.free()
                            a_scene.free()
                        end
                    end
                end
                if not arr_data_t or arr_data_t.data == nil then
                    arr_data_t = obs.ArrayStack()
                end
            end
            init_obs_data_t()
            function arr_data_t.save()
                init_obs_data_t()
            end

            function arr_data_t.del()
                local del_count = 0
                for _, scene_name in pairs(obs.scene:names()) do
                    local a_scene = obs.scene:get_scene(scene_name)
                    if a_scene and a_scene.source then
                        local s_data_t = obs.PairStack(
                            obslua.obs_source_get_settings(a_scene.source)
                        )
                        if not s_data_t or s_data_t.data == nil then
                            a_scene.free()
                        else
                            s_data_t.del(named_api)
                            del_count = del_count + 1
                            s_data_t.free()
                        end
                        a_scene.free()
                    end
                end
                return del_count
            end

            -- obs.utils.table.append(obj_data_t, arr_data_t)
            return arr_data_t
        end

        function obs.expect(callback)
            return function(...)
                local args = { ... }
                local data = nil
                local caller = ""
                for i, v in ipairs(args) do
                    if caller ~= "" then
                        caller = caller .. ","
                    end
                    caller = caller .. "args[" .. tostring(i) .. "]"
                end
                caller = "return function(callback,args) return callback(" .. caller .. ") end";
                local run = loadstring(caller)
                local success, result = pcall(function()
                    data = run()(callback, args)
                end)
                local free_count = 0
                if not success then
                    for _, iter in pairs(obs.utils.expect_wrapper) do
                        if iter and type(iter.free) == "function" then
                            local s, r = pcall(function()
                                iter.free()
                            end)
                            if s then
                                free_count = free_count + 1
                            end
                        end
                    end
                    obslua.script_log(obslua.LOG_ERROR, "[ErrorWrapper ERROR] => " .. tostring(result))
                end
                return data
            end
        end

        function obs.ArrayStack(stack, name, fallback, unsafe)
            if fallback == nil then
                fallback = true
            end
            local self = nil
            self = {
                index = 0,
                get = function(index)
                    if type(index) ~= "number" or index < 0 or index > self.size() then
                        return nil
                    end
                    return obs.PairStack(obslua.obs_data_array_item(self.data, index), nil, true)
                end,
                next = obs.expect(function(__index)
                    if type(self.index) ~= "number" or self.index < 0 or self.index > self.size() then
                        return assert(false, "[ArrayStack] Invalid data provided or corrupted data for (" .. tostring(name) ..
                            ")")
                    end
                    return coroutine.wrap(function()
                        if self.size() <= 0 then
                            return nil
                        end
                        local i = 0
                        if __index == nil or type(__index) ~= "number" or __index < 0 or __index > self.size() then
                            __index = 0
                        end
                        for i = __index, self.size() - 1 do
                            coroutine.yield(i, obs.PairStack(
                                obslua.obs_data_array_item(self.data, i), nil, false
                            ))
                        end
                    end)
                    -- local temp = self.index;self.index = self.index + 1
                    -- return obs.PairStack(obslua.obs_data_array_item(self.data, temp), nil, true)
                end),
                find = function(key, value)
                    local index = 0
                    for itm in self.next() do
                        if itm and type(itm) == "table" and itm.data then
                            if itm.get_str(key) == value or itm.get_int(key) == value
                                or itm.get_bul(key) == value or itm.get_dbl(key) == value then
                                return itm, index
                            end
                            index = index + 1
                            itm.free()
                        end
                    end
                    return nil, nil
                end,

                free = function()
                    if self.data == nil or unsafe then
                        return false
                    end
                    obslua.obs_data_array_release(self.data)
                    self.data = nil
                    return true
                end,
                insert = obs.expect(function(value)
                    if type(value) ~= "userdata" and type(value) == "table" and value["data"] and type(value["data"]) == "userdata" then
                        value = value.data
                    end
                    if value == nil or type(value) ~= "userdata" then
                        obslua.script_log("FAILED TO INSERT OBJECT INTO [ArrayStack]")
                        return false
                    end
                    obslua.obs_data_array_push_back(self.data, value)
                    return self
                end),
                size = obs.expect(function()
                    if self.data == nil then
                        return 0
                    end
                    return obslua.obs_data_array_count(self.data);
                end),
                rm = obs.expect(function(idx)
                    if type(idx) ~= "number" or idx < 0 or self.size() <= 0 or idx > self.size() then
                        obslua.script_log("FAILED TO RM DATA FROM [ArrayStack] (INVALID INDEX)")
                        return false
                    end
                    obslua.obs_data_array_erase(self.data, idx)
                    return self
                end)
            }
            if stack and name then
                self.data = obslua.obs_data_get_array(stack, name)
            elseif not stack and fallback then
                self.data = obslua.obs_data_array_create()
            else
                self.data = stack
            end
            return self
        end

        function obs.time.schedule(timeout)
            local scheduler_callback = nil
            local function interval()
                if interval then
                    obslua.timer_remove(interval)
                    interval = nil
                else
                    return
                end

                -- Safety check
                if obs.utils.script_shutdown or type(scheduler_callback) ~= "function" then
                    return
                end
                return scheduler_callback(scheduler_callback)
            end
            local interval_list = {}
            local self = nil; self = {
                after = function(callback)
                    if obs.utils.script_shutdown or not interval then return end
                    if type(callback) == "function" or type(timeout) ~= "number" or timeout < 0 then
                        scheduler_callback = callback
                    else
                        obslua.script_log(obslua.LOG_ERROR, "[Scheduler] invalid callback/timeout " .. type(callback))
                        return false
                    end
                    obslua.timer_add(interval, timeout)
                    table.insert(interval_list, interval) -- Track timer
                    return self
                end,
                clear = function()
                    if interval ~= nil then
                        obslua.timer_remove(interval)
                        interval = nil
                    end
                end,
                update = function(timeout_t)
                    if type(timeout_t) ~= "number" or timeout_t < 0 then
                        obslua.script_log(obslua.LOG_ERROR, "[Scheduler] invalid timeout value")
                        return false
                    end
                    if type(interval) ~= "function" then
                        obslua.script_log(obslua.LOG_ERROR, "[Scheduler] invalid callback function")
                        return false
                    end
                    obslua.timer_remove(interval)
                    timeout = timeout_t
                    obslua.timer_add(interval, timeout)
                    return self
                end
            }
            return self
        end

        function obs.time.tick(fn, interval)
            local tm = nil
            local wrapper = function()
                if obs.utils.script_shutdown then return end
                return fn(tm, os.clock())
            end
            if not interval or type(interval) ~= "number" or interval == 0 or (interval <= 0 and not interval > 0) then
                interval = 0.001
            end
            tm = {
                clear = function()
                    return obslua.timer_remove(wrapper)
                end
            }
            obslua.timer_add(wrapper, interval)
            return tm
        end

        function obs.wrap(self)
            if not self or self == nil then
                self = { type = obs.utils.OBS_UN_IN_TYPE, data = nil, item = nil }
            end
            if not self.data then self.data = self.item end
            if not self.item then self.item = self.data end

            -- Debugging name helper
            for k, v in pairs(obs.utils) do
                if v == self.type then
                    self.type_name = tostring(k)
                end
            end

            function self.get_source()
                if not self.data then return nil end
                if self.type == obs.utils.OBS_SRC_TYPE then
                    return self.data
                elseif self.type == obs.utils.OBS_SCENEITEM_TYPE then
                    return obslua.obs_sceneitem_get_source(self.data)
                else
                    return self.data
                end
            end

            function self.free()
                if self.released or not self.data then return end
                if self.unsafe then
                    self.data = nil; self.released = true
                    return
                end
                -- 4. Actual Release Logic
                if self.type == obs.utils.OBS_SCENE_TYPE then
                    obslua.obs_scene_release(self.data)
                elseif self.type == obs.utils.OBS_SRC_WEAK_TYPE then
                    obslua.obs_weak_source_release(self.data)
                elseif self.type == obs.utils.OBS_SRC_TYPE then
                    obslua.obs_source_release(self.data)
                elseif self.type == obs.utils.OBS_ARR_TYPE then
                    obslua.obs_data_array_release(self.data)
                elseif self.type == obs.utils.OBS_OBJ_TYPE then
                    obslua.obs_data_release(self.data)
                elseif self.type == obs.utils.OBS_SCENEITEM_TYPE then
                    obslua.obs_sceneitem_release(self.data)
                elseif self.type == obs.utils.OBS_SCENEITEM_LIST_TYPE then
                    -- NOTE: OBS Lua usually returns a table for enum_items, not a C-list.
                    -- If 'sceneitem_list_release' doesn't exist in your API version, remove this line.
                    if obslua.sceneitem_list_release then
                        obslua.sceneitem_list_release(self.data)
                    end
                elseif self.type == obs.utils.OBS_SRC_LIST_TYPE then
                    if obslua.source_list_release then
                        obslua.source_list_release(self.data)
                    else
                        obslua.obs_source_list_release(self.data)
                    end
                end

                self.data = nil; self.item = nil; self.released = true
            end
            return self
        end

        function obs.PairStack(stack, name, fallback, unsafe)
            if fallback == nil then fallback = true end
            local self = nil; self = {
                free = function()
                    if self.data == nil or unsafe or obs.utils.script_shutdown then
                        return false
                    end
                    obslua.obs_data_release(self.data)
                    self.data = nil
                    return true
                end,
                json = function(p)
                    if not p then
                        return obslua.obs_data_get_json(self.data)
                    else
                        return obslua.obs_data_get_json_pretty(self.data)
                    end
                end,
                -- ... (rest of PairStack methods are fine) ...
                str = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_str(name) end
                    if self.data and name then
                        if def then
                            obslua.obs_data_set_default_string(self.data, name, value)
                        else
                            obslua.obs_data_set_string(self.data, name, value)
                        end
                    end
                    return self
                end),
                int = obs.expect(function(name, value, def)
                    value = tonumber(value)
                    if name and value == nil then return self.get_int(name) end
                    if self.data and name then
                        if def then
                            obslua.obs_data_set_default_int(self.data, name, value)
                        else
                            obslua.obs_data_set_int(self.data, name, value)
                        end
                    end
                    return self
                end),
                dbl = obs.expect(function(name, value, def)
                    value= tonumber(value)
                    if name and value == nil then return self.get_dbl(name) end
                    if self.data and name then
                        if def then
                            obslua.obs_data_set_default_double(self.data, name, value)
                        else
                            obslua.obs_data_set_double(self.data, name, value)
                        end
                    end
                    return self
                end),
                bul = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_bul(name) end
                    if self.data and name then
                        if def then
                            obslua.obs_data_set_default_bool(self.data, name, value)
                        else
                            obslua.obs_data_set_bool(self.data, name, value)
                        end
                    end
                    return self
                end),
                arr = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_arr(name) end
                    -- Unwrap wrapper if passed
                    if type(value) ~= "userdata" and type(value) == "table" and value["data"] then value = value.data end
                    if self.data and name and value then
                        if def then
                            obslua.obs_data_set_default_array(self.data, name, value)
                        else
                            obslua.obs_data_set_array(self.data, name, value)
                        end
                    end
                    return self
                end),
                obj = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_obj(name) end
                    if type(value) ~= "userdata" and type(value) == "table" and value["data"] then value = value.data end
                    if self.data and name and value then
                        if def then
                            obslua.obs_data_set_default_obj(self.data, name, value)
                        else
                            obslua.obs_data_set_obj(self.data, name, value)
                        end
                    end
                    return self
                end),

                -- Getters (Simplified for brevity, logic unchanged)
                get_str = obs.expect(function(name, def)
                    return def and obslua.obs_data_get_default_string(self.data, name) or
                        obslua.obs_data_get_string(self.data, name)
                end),
                get_int = obs.expect(function(name, def)
                    return def and obslua.obs_data_get_default_int(self.data, name) or
                        obslua.obs_data_get_int(self.data, name)
                end),
                get_dbl = obs.expect(function(name, def)
                    return def and obslua.obs_data_get_default_double(self.data, name) or
                        obslua.obs_data_get_double(self.data, name)
                end),
                get_bul = obs.expect(function(name, def)
                    return def and obslua.obs_data_get_default_bool(self.data, name) or
                        obslua.obs_data_get_bool(self.data, name)
                end),
                get_obj = obs.expect(function(name, def)
                    local res = def and obslua.obs_data_get_default_obj(self.data, name) or
                        obslua.obs_data_get_obj(self.data, name)
                    return obs.PairStack(res, nil, false) -- Return safe wrapper
                end),
                get_arr = obs.expect(function(name, def)
                    local res = def and obslua.obs_data_get_default_array(self.data, name) or
                        obslua.obs_data_get_array(self.data, name)
                    return obs.ArrayStack(res, nil, false)
                end),
                del = obs.expect(function(name)
                    obslua.obs_data_erase(self.data, name)
                    return true
                end),
            }

            if stack and name then
                self.data = obslua.obs_data_get_obj(stack, name)
            elseif not stack and fallback then
                self.data = obslua.obs_data_create()
            else
                if type(stack) == "string" then
                    self.data = obslua.obs_data_create_from_json(stack)
                    if not self.data then
                        self.data = obslua.obs_data_create()
                    end
                elseif type(stack) == "userdata" then
                    self.data = stack
                else
                    self.data = obslua.obs_data_create()
                end
            end
            return self
        end

    -- [[ MEMORY MANAGE API END ]]

    -- [[ OBS REGISTER CUSTOM API]]
        function obs.register.hotkey(unique_id, title, callback)
            local script_path_value = script_path()
            unique_id = tostring(script_path_value) .. "_" .. tostring(unique_id)
            local hotkey_id = obslua.obs_hotkey_register_frontend(
                unique_id, title, callback
            )
            -- load from data
            local hotkey_load_data = obs.utils.settings.get_arr(unique_id);
            if hotkey_load_data and hotkey_load_data.data ~= nil then
                obslua.obs_hotkey_load(hotkey_id, hotkey_load_data.data)
                hotkey_load_data.free()
            end
            obs.register.hotkey_id_list[unique_id] = {
                id = hotkey_id,
                title = title,
                callback = callback,
                remove = function(rss)
                    if rss == nil then
                        rss = false
                    end
                    -- obs.utils.settings.del(unique_id)
                    if rss then
                        if obs.register.hotkey_id_list[unique_id] and type(obs.register.hotkey_id_list[unique_id].callback) == "function" then
                            obslua.obs_hotkey_unregister(
                                obs.register.hotkey_id_list[unique_id].callback
                            )
                        end
                    end
                    obs.register.hotkey_id_list[unique_id] = nil
                end
            }
            return obs.register.hotkey_id_list[unique_id]
        end

        function obs.register.get_hotkey(unique_id)
            unique_id = tostring(script_path()) .. "_" .. tostring(unique_id)
            if obs.register.hotkey_id_list[unique_id] then
                return obs.register.hotkey_id_list[unique_id]
            end
            return nil
        end

        function obs.register.event(unique_id, callback)
            if not callback and unique_id and type(unique_id) == "function" then
                callback = unique_id
                unique_id = tostring(script_path()) .. "_" .. obs.utils.get_unique_id(3) .. "_event"
            else
                unique_id = tostring(script_path()) .. "_" .. tostring(unique_id) .. "_event"
            end
            if type(callback) ~= "function" then
                obslua.script_log(obslua.LOG_ERROR, "[OBS REGISTER EVENT] Invalid callback provided")
                return nil
            end
            local event_id = obslua.obs_frontend_add_event_callback(callback)
            obs.register.event_id_list[unique_id] = {
                id = event_id,
                callback = callback,
                unique_id = unique_id,
                remove = function(rss)
                    if rss == nil then
                        rss = false
                    end
                    if rss then obslua.obs_frontend_remove_event_callback(callback) end
                    obs.register.event_id_list[unique_id] = nil
                end
            };
        end

        function obs.register.get_event(unique_id)
            unique_id = tostring(script_path()) .. "_" .. tostring(unique_id) .. "_event"
            if obs.register.event_id_list[unique_id] then
                return obs.register.event_id_list[unique_id]
            end
            return nil
        end

    -- [[ OBS REGISTER CUSTOM API END]]


    -- [[ OBS FILTER CUSTOM API]]
        function obs.script.filter(filter)
            local self; self = {
                id = filter and filter.id or obs.utils.get_unique_id(3),
                type = filter and filter.type or obslua.OBS_SOURCE_TYPE_FILTER,
                output_flags = filter and filter.output_flags or bit.bor(obslua.OBS_SOURCE_VIDEO),

                get_height = function(src)
                    return src and src.height or 0
                end,

                get_width = function(src)
                    return src and src.width or 0
                end,

                update = function(_, settings)
                    if not _ or not _.isAlive or (obs.utils and obs.utils.script_shutdown) then return end

                    if filter and type(filter) == "table" and
                        filter["update"] and type(filter["update"]) == "function" then
                        return filter.update(_, obs.PairStack(settings, nil, nil, true))
                    end
                end,

                create = function(settings, source)
                    if filter and type(filter) == "table" and filter["create"] and type(filter["create"]) == "function" then
                        local src = filter.create(obs.PairStack(settings, nil, nil, true))
                        if src ~= nil and type(src) == "table" then
                            self.src = src
                            src.filter = source
                            src.is_custom = true
                            src.isAlive = true -- Ensure isAlive is set for custom sources too

                            if filter["setup"] and type(filter["setup"]) == "function" then
                                filter.setup(src)
                            end
                            return src
                        end
                    end

                    local src = {
                        filter = source,
                        source = nil,
                        params = nil,
                        height = 0,
                        width = 0,
                        isAlive = true, -- explicit alive flag
                        settings = obs.PairStack(settings, nil, nil, true),
                        aliveScheduledEvents = {},
                    }

                    -- 3. Initial sizing (Safe check)
                    if source ~= nil then
                        local target = obslua.obs_filter_get_parent(source)
                        if target ~= nil then
                            src.source = target
                            src.width = obslua.obs_source_get_base_width(target)
                            src.height = obslua.obs_source_get_base_height(target)
                        end
                    end
                    shader = [[
                                uniform float4x4 ViewProj;
                                uniform texture2d image;
                                uniform int width;
                                uniform int height;

                                sampler_state textureSampler {
                                    Filter    = Linear;
                                    AddressU  = Border;
                                    AddressV  = Border;
                                    BorderColor = 00000000;
                                };
                                struct VertData
                                {
                                    float4 pos : POSITION;
                                    float2 uv  : TEXCOORD0;
                                };
                                float4 ps_get(VertData v_in) : TARGET
                                {
                                    return image.Sample(textureSampler, v_in.uv.xy);
                                }
                                VertData VSDefault(VertData v_in)
                                {
                                    VertData vert_out;
                                    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
                                    vert_out.uv  = v_in.uv;
                                    return vert_out;
                                }
                                technique Draw
                                {
                                    pass
                                    {
                                        vertex_shader = VSDefault(v_in);
                                        pixel_shader  = ps_get(v_in);
                                    }
                                }
                            ]]
                    obslua.obs_enter_graphics()
                    src.shader = obslua.gs_effect_create(shader, nil, nil)
                    obslua.obs_leave_graphics()
                    if src.shader ~= nil then
                        src.params = {
                            width = obslua.gs_effect_get_param_by_name(src.shader, "width"),
                            height = obslua.gs_effect_get_param_by_name(src.shader, "height"),
                            image = obslua.gs_effect_get_param_by_name(src.shader, "image"),
                        }
                    else
                        return self.destroy()
                    end

                    if filter and filter["setup"] and type(filter["setup"]) == "function" then
                        filter.setup(src, src.settings)
                    end

                    self.src = src

                    -- 4. Asynchronous Source Assignment (SAFER)

                    obs.time.schedule(380).after(function()
                        -- CRITICAL: Check shutdown before touching C-pointers
                        if not src or not src.isAlive or (obs.utils and obs.utils.script_shutdown) then
                            return
                        end

                        -- Verify filter still exists in OBS
                        if src.filter then
                            src.source = obslua.obs_filter_get_parent(src.filter)

                            if filter and filter["finally"] and type(filter["finally"]) == "function" then
                                filter.finally(src)
                            end
                        end
                        src.isInitialized = true
                    end)

                    return src
                end,

                destroy = function(src)
                    if not src then return end
                    src.isAlive = false -- Mark dead immediately
                    if src and type(src) == "table" and src.shader then
                        obslua.obs_enter_graphics()
                        obslua.gs_effect_destroy(src.shader)
                        obslua.obs_leave_graphics()
                    end
                    if filter and type(filter) == "table" and filter["destroy"] and type(filter["destroy"]) == "function" then
                        filter.destroy(src)
                    end
                    -- Clear references to prevent dangling pointer crashes
                    src.source = nil
                    src.filter = nil
                    src.params = nil
                end,

                video_tick = function(src, fps)
                    -- 1. CRITICAL SAFETY CHECK
                    if not src or not src.isAlive or (obs.utils and obs.utils.script_shutdown) then
                        return
                    end

                    -- 2. Fallback: Try to get parent if missing (Common in startup)
                    if src.source == nil and src.filter then
                        src.source = obslua.obs_filter_get_parent(src.filter)
                    end

                    -- 3. Update Dimensions (Preventing the Crash)
                    -- Only attempt this if we have a valid source pointer
                    if src.source and src.filter then
                        src.width = obslua.obs_source_get_base_width(src.source)
                        src.height = obslua.obs_source_get_base_height(src.source)
                    else
                        src.width = 0; src.height = 0
                    end

                    -- 4. Execute User Tick
                    local __tick = (filter["video_tick"] or filter["tick"]) or function() end
                    __tick(src, fps)
                end,

                video_render = function(src)
                    -- 1. CRITICAL SAFETY CHECK
                    if not src or not src.isAlive or (obs.utils and obs.utils.script_shutdown) then
                        return
                    end
                    if filter and type(filter) == "table" and filter["video_render"] and type(filter["video_render"]) == "function" then
                        local result = filter.video_render(src)
                        if src.is_custom then
                            return result
                        end
                    end

                    -- 2. Validate Source/Filter before rendering
                    if src.source == nil and src.filter then
                        src.source = obslua.obs_filter_get_parent(src.filter)
                    end
                    if src.source and src.filter then
                        src.width = obslua.obs_source_get_base_width(src.source)
                        src.height = obslua.obs_source_get_base_height(src.source)
                    end

                    -- 3. Standard Filter Process
                    if src.filter then
                        local width = src.width; local height = src.height
                        if not obslua.obs_source_process_filter_begin(
                                src.filter, obslua.GS_RGBA, obslua.OBS_NO_DIRECT_RENDERING
                            ) then
                            obslua.obs_source_skip_video_filter(src.filter)
                            return nil
                        end
                        if not src.params then
                            obslua.obs_source_process_filter_end(src.filter, src.shader, width, height)
                            return nil
                        end
                        if type(width) == "number" then
                            obslua.gs_effect_set_int(src.params.width, width)
                        end
                        if type(height) == "number" then
                            obslua.gs_effect_set_int(src.params.height, height)
                        end
                        obslua.gs_blend_state_push()
                        obslua.gs_blend_function(
                            obslua.GS_BLEND_ONE, obslua.GS_BLEND_INVSRCALPHA
                        )
                        if width and height then
                            obslua.obs_source_process_filter_end(src.filter, src.shader, width, height)
                        end
                        obslua.gs_blend_state_pop()
                    end
                    return true
                end,

                get_name = function()
                    return filter and filter.name or "Custom Filter"
                end,

                get_defaults = function(settings)
                    local defaults = nil
                    if filter and type(filter) == "table" then
                        if filter["get_defaults"] and type(filter["get_defaults"]) == "function" then
                            defaults = filter.get_defaults
                        elseif filter["defaults"] and type(filter["defaults"]) == "function" then
                            defaults = filter.defaults
                        end
                    end
                    if defaults and type(defaults) == "function" then
                        return defaults(obs.PairStack(settings, nil, nil, true))
                    end
                end,

                get_properties = function(src)
                    local properties = nil
                    if filter and type(filter) == "table" then
                        if filter["get_properties"] and type(filter["get_properties"]) == "function" then
                            properties = filter.get_properties
                        elseif filter["properties"] and type(filter["properties"]) == "function" then
                            properties = filter.properties
                        end
                    end
                    if properties and type(properties) == "function" then
                        return properties(src)
                    end
                    return nil
                end
            }

            table.insert(obs.utils.filters, self)

            if not filter or type(filter) ~= "table" then
                filter = {}
            end

            filter.get_name = self.get_name
            if not filter.id then filter.id = self.id end
            filter.get_width = self.get_width
            filter.get_height = self.get_height
            filter.type = self.type
            filter.output_flags = self.output_flags

            return filter
        end
    -- [[ OBS FILTER CUSTOM API END]]

    -- [[ OBS SCENE API CUSTOM ]]
        function obs.scene:get_scene(scene_name)
            local scene; local source_scene;
            if not scene_name or not type(scene_name) == "string" then
                source_scene = obslua.obs_frontend_get_current_scene()
                if not source_scene then
                    return nil
                end
                scene = obslua.obs_scene_from_source(source_scene)
            else
                source_scene = obslua.obs_get_source_by_name(scene_name)
                if not source_scene then
                    return nil
                end
                scene = obslua.obs_scene_from_source(source_scene)
            end
            local obj_scene_t; obj_scene_t = {
                group_names = function()
                    local scene_items_list = obs.wrap({
                        data = obslua.obs_scene_enum_items(scene),
                        type = obs.utils.OBS_SCENEITEM_LIST_TYPE
                    })
                    if scene_items_list == nil or scene_items_list.data == nil then
                        return nil
                    end
                    local list = {}
                    for _, item in ipairs(scene_items_list.data) do
                        local source = obslua.obs_sceneitem_get_source(item)
                        if source ~= nil then
                            local sourceName = obslua.obs_source_get_name(source)
                            if obslua.obs_sceneitem_is_group(item) then
                                table.insert(list, sourceName)
                            end
                        end
                    end
                    scene_items_list.free()
                    return list
                end,
                source_names = function(source_id_type)
                    local scene_nodes_name_list = {}
                    local scene_items_list = obs.wrap({
                        data = obslua.obs_scene_enum_items(scene),
                        type = obs.utils.OBS_SCENEITEM_LIST_TYPE
                    })
                    for _, item in ipairs(scene_items_list.data) do
                        local source = obslua.obs_sceneitem_get_source(item)
                        if source ~= nil then
                            local sourceName = obslua.obs_source_get_name(source)
                            if source_id_type == nil or type(source_id_type) ~= "string" or source_id_type == "" then
                                table.insert(scene_nodes_name_list, sourceName)
                            else
                                local sourceId = obslua.obs_source_get_id(source)
                                if sourceId == source_id_type then
                                    table.insert(scene_nodes_name_list, sourceName)
                                end
                            end
                            source = nil
                        end
                    end
                    scene_items_list.free()
                    return scene_nodes_name_list
                end,
                get = function(source_name)
                    if not scene then
                        return nil
                    end
                    local c = 1
                    local scene_item; local scene_items_list = obs.wrap({
                        data = obslua.obs_scene_enum_items(scene),
                        type = obs.utils.OBS_SCENEITEM_LIST_TYPE
                    })
                    if scene_items_list == nil or scene_items_list.data == nil then
                        return nil
                    end
                    for _, item in ipairs(scene_items_list.data) do
                        c = c + 1
                        local src = obslua.obs_sceneitem_get_source(item)
                        local src_name = obslua.obs_source_get_name(src)
                        if src ~= nil and src_name == source_name then
                            obslua.obs_sceneitem_addref(item)
                            scene_item = obs.wrap({
                                data = item,
                                type = obs.utils.OBS_SCENEITEM_TYPE,
                                name = source_name
                            })
                            break
                        end
                    end
                    scene_items_list.free()
                    if scene_item == nil or scene_item.data == nil then
                        return nil
                    end
                    local obj_source_t;

                    obj_source_t = {
                        free = scene_item.free,
                        item = scene_item.data,
                        data = scene_item.data,

                        _busy = false,
                        _queue = {},
                        _timer = nil,
                        _frame_time = 0.016,
                        _last_run = os.clock(),

                        _cached_info = obslua.obs_transform_info(),
                        _cached_crop = obslua.obs_sceneitem_crop(),
                        _cached_pos = obslua.vec2(),
                        _cached_scale = obslua.vec2(),
                        _virtual = { initialized = false, pos = { x = 0, y = 0 }, scale = { x = 1, y = 1 }, rot = 0, bounds = { x = 0, y = 0 }, alignment = 0, bounds_type = 0 },

                        _sync_shadow = function()
                            if obj_source_t._virtual.initialized then return end
                            obslua.obs_sceneitem_get_info2(obj_source_t.data, obj_source_t._cached_info)
                            obj_source_t._virtual.pos = { x = obj_source_t._cached_info.pos.x, y = obj_source_t._cached_info.pos.y }
                            obj_source_t._virtual.scale = { x = obj_source_t._cached_info.scale.x, y = obj_source_t._cached_info.scale.y }
                            obj_source_t._virtual.rot = obj_source_t._cached_info.rot
                            obj_source_t._virtual.bounds = { x = obj_source_t._cached_info.bounds.x, y = obj_source_t._cached_info.bounds.y }
                            obj_source_t._virtual.alignment = obj_source_t._cached_info.alignment
                            obj_source_t._virtual.bounds_type = obj_source_t._cached_info.bounds_type
                            obj_source_t._virtual.initialized = true
                            -- Initialize cached structs
                            obslua.obs_sceneitem_get_info2(obj_source_t.data, obj_source_t._cached_info)
                            obslua.obs_sceneitem_get_crop(obj_source_t.data, obj_source_t._cached_crop)
                            obslua.obs_sceneitem_get_pos(obj_source_t.data, obj_source_t._cached_pos)
                            obslua.obs_sceneitem_get_scale(obj_source_t.data, obj_source_t._cached_scale)
                        end,


                        _safe_run = function(func)
                            return pcall(function()
                                return func()
                            end)
                        end,


                        pos = function(val)
                            obj_source_t._sync_shadow()
                            if val == nil or not (type(val) == "table") or (val.x == nil and val.y == nil) then
                                return { x = obj_source_t._virtual.pos.x, y = obj_source_t._virtual.pos.y }
                            end
                            return obj_source_t._safe_run(function()
                                return obj_source_t.transform({
                                    pos = val
                                })
                            end)
                        end,

                        scale = function(val)
                            obj_source_t._sync_shadow()                      
                            if val == nil or not (type(val) == "table") then
                                return { x = obj_source_t._virtual.scale.x, y = obj_source_t._virtual.scale.y }
                            end
                            return obj_source_t._safe_run(function()
                                return obj_source_t.transform({
                                    scale = val
                                })
                            end)
                        end,

                        rot = function(val)
                            obj_source_t._sync_shadow()
                            if val == nil then return obj_source_t._virtual.rot end
                            return obj_source_t._safe_run(function()
                                return obj_source_t.transform({
                                    rot = val
                                })
                            end)
                        end,

                        align = function(val)
                            obj_source_t._sync_shadow()
                            if val == nil then return obj_source_t._virtual.alignment end
                            return obj_source_t._safe_run(function()
                                return obj_source_t.transform({
                                    alignment = val
                                })
                            end)
                        end,

                        bounds = function(size)
                            obj_source_t._sync_shadow()
                            if size == nil or not (type(size) == "table") then
                                return { x = obj_source_t._virtual.bounds.x, y = obj_source_t._virtual.bounds.y }
                            end
                            return obj_source_t._safe_run(function()
                                return obj_source_t.transform({
                                    bounds = size
                                })
                            end)
                        end,

                        width = function(val)
                            obj_source_t._sync_shadow()
                            if val == nil or type(val) ~= "number" then
                                local is_bounded = obj_source_t._virtual.bounds_type ~= obslua.OBS_BOUNDS_NONE
                                local base_w = obslua.obs_source_get_base_width(obj_source_t.get_source())
                                return is_bounded and obj_source_t._virtual.bounds.x or (base_w * obj_source_t._virtual.scale.x)
                            end

                            return obj_source_t._safe_run(function()
                                return obj_source_t.size({
                                    width=val
                                })
                            end)
                        end,

                        height = function(val)
                            obj_source_t._sync_shadow()
                            if val == nil or type(val) ~= "number" then
                                local is_bounded = obj_source_t._virtual.bounds_type ~= obslua.OBS_BOUNDS_NONE
                                local base_h = obslua.obs_source_get_base_height(obj_source_t.get_source())
                                return is_bounded and obj_source_t._virtual.bounds.y or (base_h * obj_source_t._virtual.scale.y)
                            end

                            return obj_source_t._safe_run(function()
                                return obj_source_t.size({
                                    height=val
                                })
                            end)
                        end,
                        size= function(size)
                            obj_source_t._sync_shadow()
                            local is_bounded = obj_source_t._virtual.bounds_type ~= obslua.OBS_BOUNDS_NONE
                            if size == nil or not (type(size) == "table") then
                                return {
                                    x = is_bounded and obj_source_t._virtual.bounds.x or (obslua.obs_source_get_base_width(obj_source_t.get_source()) * obj_source_t._virtual.scale.x),
                                    y = is_bounded and obj_source_t._virtual.bounds.y or (obslua.obs_source_get_base_height(obj_source_t.get_source()) * obj_source_t._virtual.scale.y),
                                    width = is_bounded and obj_source_t._virtual.bounds.x or (obslua.obs_source_get_base_width(obj_source_t.get_source()) * obj_source_t._virtual.scale.x),
                                    height = is_bounded and obj_source_t._virtual.bounds.y or (obslua.obs_source_get_base_height(obj_source_t.get_source()) * obj_source_t._virtual.scale.y)
                                }
                            end
                            return obj_source_t._safe_run(function()
                                if is_bounded then
                                    return obj_source_t.transform({
                                        bounds = { x = (size.x and size.x or size.width), y = (size.y and size.y or size.height) }
                                    })
                                else
                                    local base_w = obslua.obs_source_get_base_width(obj_source_t.get_source())
                                    local base_h = obslua.obs_source_get_base_height(obj_source_t.get_source())
                                    if base_w > 0 and base_h > 0 then
                                        return obj_source_t.transform({
                                            scale = { x = (size.x and size.x or size.width) / base_w, y = (size.y and size.y or size.height) / base_h }
                                        })
                                    end
                                end
                            end)
                        end,

                        crop = function(c)
                            if c == nil then
                                obslua.obs_sceneitem_get_crop(obj_source_t.data, obj_source_t._cached_crop)
                                return obj_source_t._cached_crop
                            end

                            return obj_source_t._safe_run(function()
                                -- Use Cached Crop Struct
                                obslua.obs_sceneitem_get_crop(obj_source_t.data, obj_source_t._cached_crop)

                                if c.top then obj_source_t._cached_crop.top = c.top end
                                if c.bottom then obj_source_t._cached_crop.bottom = c.bottom end
                                if c.left then obj_source_t._cached_crop.left = c.left end
                                if c.right then obj_source_t._cached_crop.right = c.right end

                                obslua.obs_sceneitem_set_crop(obj_source_t.data, obj_source_t._cached_crop)
                                return true
                            end)
                        end,

                        transform = function(tf)
                            if obslua.obs_source_removed(obj_source_t.get_source()) then
                                return nil
                            end
                            obj_source_t._sync_shadow()
                            if not tf or not (type(tf) == "userdata" or type(tf) == "table") then
                                return {
                                    pos = { x = obj_source_t._virtual.pos.x, y = obj_source_t._virtual.pos.y },
                                    scale = { x = obj_source_t._virtual.scale.x, y = obj_source_t._virtual.scale.y },
                                    rot = obj_source_t._virtual.rot,
                                    bounds = { x = obj_source_t._virtual.bounds.x, y = obj_source_t._virtual.bounds.y },
                                    alignment = obj_source_t._virtual.alignment,
                                    bounds_type = obj_source_t._virtual.bounds_type
                                }
                            end

                            return obj_source_t._safe_run(function()
                                local info;
                                if type(tf) == "userdata" then
                                    info = tf
                                elseif type(tf) == "table" then
                                    info = obj_source_t._cached_info
                                    obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                    for k, v in pairs(tf) do
                                        if k == "pos" and type(v) == "table" then

                                            if type(v.x) == "number" then 
                                                obj_source_t._virtual.pos.x = v.x
                                                obj_source_t._cached_info.pos.x = v.x 
                                            end
                                            if type(v.y) == "number" then 
                                                obj_source_t._virtual.pos.y = v.y
                                                obj_source_t._cached_info.pos.y = v.y 
                                            end
                                        elseif k == "scale" and type(v) == "table" then

                                            if type(v.x) == "number" then
                                                obj_source_t._virtual.scale.x = v.x
                                                obj_source_t._cached_info.scale.x = v.x 
                                            end
                                            if type(v.y) == "number" then 
                                                obj_source_t._virtual.scale.y = v.y
                                                obj_source_t._cached_info.scale.y = v.y 
                                            end
                                        elseif k == "rot" and type(v) == "number" then
                                            obj_source_t._virtual.rot = v
                                            obj_source_t._cached_info.rot = v
                                        elseif k == "bounds" and type(v) == "table" then
                                            if type(v.x) == "number" then 
                                                obj_source_t._virtual.bounds.x = v.x
                                                obj_source_t._cached_info.bounds.x = v.x 
                                            end
                                            if type(v.y) == "number" then 
                                                obj_source_t._virtual.bounds.y = v.y
                                                obj_source_t._cached_info.bounds.y = v.y 
                                            end
                                        elseif k == "alignment" and type(v) == "number" then
                                            obj_source_t._virtual.alignment = v
                                            obj_source_t._cached_info.alignment = v
                                        elseif k == "bounds_type" and type(v) == "number" then
                                            obj_source_t._virtual.bounds_type = v
                                            obj_source_t._cached_info.bounds_type = v
                                        end
                                    end
                                else
                                    return
                                end
                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,

                        get_source = function() return obslua.obs_sceneitem_get_source(obj_source_t.data) end,
                        get_name = function() return obslua.obs_source_get_name(obj_source_t.get_source()) end,

                        bounding = function()
                            if not obj_source_t or not obj_source_t.data then return 0 end
                            return obslua.obs_sceneitem_get_bounds_type(obj_source_t.data)
                        end,

                        remove = function()
                            if obj_source_t.data == nil then return true end
                            obslua.obs_sceneitem_remove(obj_source_t.data)
                            obj_source_t.free(); obj_source_t.data = nil; obj_source_t.item = nil
                            return true
                        end,

                        hide = function() return obslua.obs_sceneitem_set_visible(obj_source_t.data, false) end,
                        show = function() return obslua.obs_sceneitem_set_visible(obj_source_t.data, true) end,
                        isHidden = function() return obslua.obs_sceneitem_visible(obj_source_t.data) end,
                        insert = {
                            filter = function(filter_source_or_id, name)
                                local filter_ptr = nil
                                local created_locally = false

                                -- 1. Determine if we are creating new (String ID) or adding existing (Source Object)
                                if type(filter_source_or_id) == "string" then
                                    local function insert_filter(id)
                                        local source_name= obj_source_t.get_name()
                                        if not source_name then return nil end
                                        local source = obslua.obs_get_source_by_name(source_name)
                                        if source == nil then
                                            return
                                        end
                                        local settings = obslua.obs_data_create()
                                        local a_name= name or id
                                        local filter = obslua.obs_source_create_private(id, a_name, settings)
                                        obslua.obs_source_filter_add(source, filter)
                                        obslua.obs_data_release(settings)
                                        obslua.obs_source_release(source)
                                        return filter
                                    end
                                    filter_ptr= insert_filter(filter_source_or_id)
                                elseif type(filter_source_or_id) == "table" and filter_source_or_id.data then
                                    -- Handle custom wrapper object
                                    filter_ptr = filter_source_or_id.data
                                    obslua.obs_source_filter_add(src, filter_ptr)
                                elseif type(filter_source_or_id) == "userdata" then
                                    -- Handle raw userdata
                                    filter_ptr = filter_source_or_id
                                    obslua.obs_source_filter_add(src, filter_ptr)
                                end

                                if not filter_ptr then return nil end


                                -- 4. Construct and return the wrapper (consistent with obj_source_t.filter)
                                local filter_wrapper = obs.wrap({ data = filter_ptr, type = obs.utils.OBS_SRC_TYPE })
                                
                                local self; self = {
                                    remove = function()
                                        local src=nil;local source_name= obj_source_t.get_name()
                                        if source_name then src= obslua.obs_get_source_by_name(source_name) end
                                        if src then
                                            obslua.obs_source_filter_remove(src, filter_wrapper.data)
                                            obslua.obs_source_release(src)
                                        end
                                        self.free()
                                        self = nil
                                        return true
                                    end,
                                    commit = function()
                                        if self.settings and self.settings.data then
                                            obslua.obs_source_update(filter_wrapper.data, self.settings.data)
                                        end
                                        return self
                                    end,
                                    data = filter_wrapper.data,
                                    free = function()
                                        if self.settings and self.settings.data then self.settings.free() end
                                        if filter_wrapper and filter_wrapper.data then
                                            filter_wrapper.free(); filter_wrapper = nil
                                        end
                                    end,
                                    settings = obs.PairStack(obslua.obs_source_get_settings(filter_wrapper.data)),
                                    id = function() return obslua.obs_source_get_unversioned_id(filter_wrapper.data) end,
                                }
                                return self
                            end
                        },
                        filter = function(name_or_id)
                            local source = obj_source_t.get_source()
                            if not source then return nil end
                            local found_ptr = obslua.obs_source_get_filter_by_name(source, name_or_id)
                            local filter_wrapper = nil
                            if not found_ptr then
                                local fb = function(parent, filter, param)
                                    local id = obslua.obs_source_get_unversioned_id(filter)
                                    local id2= obslua.obs_source_get_id(filter)
                                    if id == name_or_id or id2 == name_or_id then
                                        found_ptr = obslua.obs_source_get_ref(filter)
                                        return true
                                    end
                                    return false
                                end
                                local filter_list = obs.wrap({
                                    data = obslua.obs_source_enum_filters(source),
                                    type = obs.utils
                                        .OBS_SRC_LIST_TYPE
                                })
                                for _, filter in ipairs(filter_list.data) do
                                    if fb(source, filter, nil) then break end
                                end
                                filter_list.free()
                            end
                            if not found_ptr then return nil end
                            filter_wrapper = obs.wrap({ data = found_ptr, type = obs.utils.OBS_SRC_TYPE })
                            if not filter_wrapper or not filter_wrapper.data then return nil end

                            local self; self = {
                                remove = function()
                                    obslua.obs_source_filter_remove(source, filter_wrapper.data)
                                    self.free()
                                    self = nil
                                    return true
                                end,
                                data = filter_wrapper.data,
                                commit = function()
                                    if self.settings and self.settings.data and filter_wrapper and filter_wrapper.data then
                                        if obslua.obs_source_removed(filter_wrapper.data) then
                                            return self
                                        end
                                        obslua.obs_source_update(filter_wrapper.data,
                                            self.settings.data)
                                    end
                                    return self
                                end,
                                free = function()
                                    if self.settings and self.settings.data then self.settings.free() end
                                    if filter_wrapper and filter_wrapper.data then
                                        filter_wrapper.free(); filter_wrapper = nil
                                    end
                                end,
                                settings = obs.PairStack(obslua.obs_source_get_settings(filter_wrapper.data)),
                                id = function() return obslua.obs_source_get_unversioned_id(filter_wrapper.data) end,
                            }
                            return self
                        end,
                        style = {
                            grad = {
                                enable = function()
                                    local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                    if not src or not src.data then src = obs.PairStack() end
                                    src.bul("gradient", true)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end,
                                disable = function()
                                    local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                    if not src or not src.data then src = obs.PairStack() end
                                    src.bul("gradient", false)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end,
                                dir = function(val)
                                    local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                    if not src or not src.data then src = obs.PairStack() end
                                    if val == nil then
                                        local tempv = src.dbl("gradient_dir"); src.free(); return tempv
                                    end
                                    src.dbl("gradient_dir", val)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end,
                                color = function(r, g, b)
                                    local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                    if not src or not src.data then src = obs.PairStack() end
                                    if not r or not g or not b then
                                        local tempv = src.int("gradient_color"); src.free(); return obs.utils.argb_to_rgb(tempv)
                                    end
                                    src.int("gradient_color", obs.utils.rgb_to_argb(r, g, b))
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                    return true
                                end,
                                opacity = function(val)
                                    local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                    if not src or not src.data then src = obs.PairStack() end
                                    if val == nil then
                                        local tempv = src.dbl("gradient_opacity"); src.free(); return tempv
                                    end
                                    src.dbl("gradient_opacity", val)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end
                            },
                            bg_opacity = function(val)
                                local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                if not src or not src.data then src = obs.PairStack() end
                                if val == nil then
                                    local tempv = src.dbl("bk_opacity"); src.free(); return tempv
                                end
                                src.dbl("bk_opacity", val)
                                obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                src.free()
                            end,
                            opacity = function(val)
                                local src = obs.PairStack(obslua.obs_source_get_settings(obj_source_t.get_source()))
                                if not src or not src.data then src = obs.PairStack() end
                                if val == nil then
                                    local tempv = src.dbl("opacity"); src.free(); return tempv
                                end
                                src.dbl("opacity", val)
                                obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                src.free()
                            end,
                        },
                        font = {
                            size = function(font_size)
                                local src = obs.PairStack(
                                    obslua.obs_source_get_settings(source.get_source())
                                )
                                if not src or not src.data then
                                    src = obs.PairStack()
                                end
                                local font = src.get_obj("font")
                                if not font or not font.data then
                                    font = obs.PairStack()
                                    --font.str("face","Arial")
                                end
                                if font_size == nil or not type(font_size) == "number" or font_size <= 0 then
                                    font_size = font.get_int("size")
                                    font.free(); src.free();
                                    return font_size
                                else
                                    font.int("size", font_size)
                                end
                                font.free();
                                obslua.obs_source_update(source.get_source(), src.data)
                                src.free()
                                return true
                            end,
                            face = function(face_name)
                            end
                        },
                        text = function(txt)
                            local src = obs.PairStack(
                                obslua.obs_source_get_settings(obj_source_t.get_source())
                            )
                            if not src or not src.data then
                                src = obs.PairStack()
                            end
                            local res = true
                            if txt == nil or txt == "" or type(txt) ~= "string" then
                                res = src.get_str("text")
                                if not res == nil then
                                    res = ""
                                end
                            else
                                src.str("text", txt)
                            end
                            obslua.obs_source_update(obj_source_t.get_source(), src.data)
                            src.free()
                            return res
                        end,
                    }


                    function obj_source_t.style.bg_color(r, g, b)
                        local src = obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src = obs.PairStack()
                        end
                        if not r or not g or not b then
                            local tempv = src.int("bk_color")
                            src.free()
                            return obs.utils.argb_to_rgb(tempv)
                        end
                        src.int("bk_color", obs.utils.rgb_to_argb(r, g, b))
                        obslua.obs_source_update(obj_source_t.get_source(), src.data)
                        src.free()
                    end

                    function obj_source_t.style.color(r, g, b)
                        local src = obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src = obs.PairStack()
                        end
                        if not r or not g or not b then
                            local tempv = src.int("color")
                            src.free()
                            return obs.utils.argb_to_rgb(tempv)
                        end
                        local src = obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src = obs.PairStack()
                        end
                        src.int("color", obs.utils.rgb_to_argb(r, g, b))
                        obslua.obs_source_update(obj_source_t.get_source(), src.data)
                        src.free()
                    end

                    function obj_source_t.style.get()
                        local src = obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src = obs.PairStack()
                        end
                        local json = src.json(true)
                        src.free()
                        return json
                    end

                    function obj_source_t.style.set(val)
                        local src = obs.PairStack(val)
                        if not src or not src.data then
                            return nil
                        end
                        obslua.obs_source_update(obj_source_t.get_source(), src.data)
                        src.free()
                    end
                    function obj_source_t.opacity(val)
                        local color_filter= obj_source_t.filter("color_filter_v2")
                        if not color_filter or not color_filter.data then
                            color_filter= obj_source_t.insert.filter("color_filter_v2", "Color Correction")
                            if not color_filter or not color_filter.data then
                                return
                            end
                        end
                        if val == nil or type(val) ~= "number" then
                            local tempv = color_filter.settings.dbl("opacity")
                            color_filter.free()
                            return tempv
                        end
                        color_filter.settings.dbl("opacity", val)
                        return color_filter.commit().free()
                    end
                    return obj_source_t
                end,
                add = function(source)
                    if not source then return false end
                    local sceneitem = obslua.obs_scene_add(scene, source)
                    if sceneitem == nil then return nil end
                    obslua.obs_sceneitem_addref(sceneitem)
                    local dt = obs.wrap({
                        data = sceneitem, type = obs.utils.OBS_SCENEITEM_TYPE
                    })
                    return dt
                end,
                free = function()
                    if not source_scene then return end
                    obslua.obs_source_release(source_scene)
                    scene = nil
                end,
                release = function()
                    return obj_scene_t.free()
                end,
                get_width = function()
                    return obslua.obs_source_get_base_width(source_scene)
                end,
                get_height = function()
                    return obslua.obs_source_get_base_height(source_scene)
                end,
                data = scene,
                item = scene,
                source = source_scene
            };
            return obj_scene_t
        end

        function obs.scene:scene_from(source)
            if not source or type(source) == 'string' then
                return nil
            end
            local sc = obslua.obs_scene_from_source(source)
            local ss = obslua.obs_scene_get_source(sc)
            return obs.scene:get_scene(obslua.obs_source_get_name(ss))
        end

        function obs.scene:name()
            source_scene = obslua.obs_frontend_get_current_scene()
            if not source_scene then
                return nil
            end
            local source_name = obslua.obs_source_get_name(source_scene)
            obslua.obs_source_release(source_scene)
            return source_name
        end

        function obs.scene:add_to_scene(source)
            if not source then
                return false
            end
            local current_source_scene = obslua.obs_frontend_get_current_scene()
            if not current_source_scene then
                return false
            end
            local current_scene = obslua.obs_scene_from_source(current_source_scene)
            if not current_scene then
                obslua.obs_source_release(current_source_scene)
                return false
            end
            obslua.obs_scene_add(current_scene, source)
            obslua.obs_source_release(current_source_scene)
            return true
        end

        function obs.scene:names()
            local scenes = obs.wrap({
                data = obslua.obs_frontend_get_scenes(),
                type = obs.utils.OBS_SRC_LIST_TYPE
            })
            local obj_table_t = {}
            for _, a_scene in pairs(scenes.data) do
                if a_scene then
                    local scene_source_name = obslua.obs_source_get_name(a_scene)
                    table.insert(obj_table_t, scene_source_name)
                end
            end
            scenes.free()
            return obj_table_t
        end

        function obs.scene:size()
            local scene = obs.scene:get_scene()
            if not scene or not scene.data then
                return nil
            end
            local w = scene:get_width()
            local h = scene:get_height()
            scene.free()
            return { width = w, height = h }
        end

    -- [[ OBS SCENE API CUSTOM END ]]
    -- [[ OBS FRONT API ]]
        function obs.front.source_names()
            local list = {}
            local all_sources = obs.wrap({
                data = obslua.obs_enum_sources(),
                type = obs.utils.OBS_SRC_LIST_TYPE
            })
            for _, source in pairs(all_sources.data) do
                if source then
                    local source_name = obslua.obs_source_get_name(source)
                    table.insert(list, source_name)
                end
            end
            all_sources.free()
            return list
        end

        function obs.front.source(source)
            local scene; local source_name;
            if source and type(source) ~= "string" and type(source) == "userdata" then
                scene = obs.scene:scene_from(source)
                source_name = obslua.obs_source_get_name(source)
            elseif type(source) == "string" then
                source_name = source
                local temp = obslua.obs_get_source_by_name(source_name)
                if not temp then return nil end
                scene = obs.scene:scene_from(temp)
                obslua.obs_source_release(temp)
            end
            if not scene or not scene.data then return end
            local sct = scene.get(source_name)
            scene.free()
            return sct
        end

    -- [[ OBS FRONT API END ]]
    -- [[ OBS SCRIPT PROPERTIES CUSTOM API]]
        function obs.script:ui(clb, s)
            if obs.utils.ui then
                obslua.script_log(obslua.LOG_ERROR, "[SCRIPT.UI] UI is already created")
                return false
            end
            if type(clb) ~= "function" then
                obslua.script_log(obslua.LOG_ERROR, "[SCRIPT.UI] Invalid callback provided")
                return false
            end

            obs.utils.ui = function()
                obs.utils.properties = { list = {}, options = {}, }
                local p = obs.script.create(s)
                local self = {}; for key, fnc in pairs(obs.script) do
                    self[key] = function(...)
                        return fnc(p, ...)
                    end
                end
                clb(self, p)
                return p
            end
            return true
        end

        function obs.script.create(settings)
            local p = obslua.obs_properties_create()
            if type(settings) == "userdata" then
                settings = obs.PairStack(settings, nil, nil, true)
            end
            obs.utils.properties[p] = settings
            return p
        end

        function obs.script.options(p, unique_id, desc, enum_type_id, enum_format_id)
            if not desc or type(desc) ~= "string" then
                desc = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            if enum_format_id == nil then
                enum_format_id = obs.enum.options.string;
            end
            if enum_type_id == nil then
                enum_type_id = obs.enum.options.default;
            end

            local obj = obslua.obs_properties_add_list(p, unique_id, desc, enum_type_id, enum_format_id);
            if not obj then
                obslua.script_log(obslua.LOG_ERROR,
                    "[obsapi_custom.lua] Failed to create options property: " ..
                    tostring(unique_id) ..
                    " description: " ..
                    tostring(desc) ..
                    " enum_type_id: " .. tostring(enum_type_id) .. " enum_format_id: " .. tostring(enum_format_id))
                return nil
            end

            obs.utils.properties.options[unique_id] = {
                enum_format_id = enum_format_id,
                enum_type_id = enum_type_id,
                type = enum_format_id
            }
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(obj, p)
            return obs.utils.properties[unique_id]
        end

        function obs.script.button(p, unique_id, label, callback)
            if not label or type(label) ~= "string" then
                label = "button"
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            if type(callback) ~= "function" then callback = function() end end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_button(p, unique_id, label, function(properties_t, property_t)
                    return callback(
                        property_t, properties_t,
                        obs.utils.properties[properties_t] and obs.utils.properties[properties_t] or obs.utils.settings
                    )
                end)
                , p)
            return obs.utils.properties[unique_id]
        end

        function obs.script.label(p, unique_id, text, enum_type)
            if not text or type(text) ~= "string" then
                text = ""
            end
            if not unique_id or type(unique_id) == nil or unique_id == "" or type(unique_id) ~= "string" then
                unique_id = obs.utils.get_unique_id(20)
            end
            local default_enum_type = obslua.OBS_TEXT_INFO;
            if (enum_type == nil) then
                enum_type = default_enum_type
            end
            local obj = obs.utils.obs_api_properties_patch(obslua.obs_properties_add_text(p, unique_id, text, default_enum_type),
                p)
            if enum_type == obs.enum.text.error then
                obj.error(text)
            elseif enum_type == obs.enum.text.warn then
                obj.warn(text)
            end
            obj.type = enum_type;
            obs.utils.properties[unique_id] = obj
            return obj;
        end

        function obs.script.group(p, unique_id, desc, enum_type)
            local pp = obs.script.create()
            if not desc or type(desc) ~= "string" then
                desc = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            if enum_type == nil then
                enum_type = obs.enum.group.normal;
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_group(p, unique_id, desc, enum_type, pp), pp)
            obs.utils.properties[unique_id].parent = pp
            obs.utils.properties[unique_id].add = {}
            for key, fnc in pairs(obs.script) do
                obs.utils.properties[unique_id].add[key] = function(...)
                    return fnc(obs.utils.properties[unique_id].parent, ...)
                end
            end
            return obs.utils.properties[unique_id]
        end

        function obs.script.bool(p, unique_id, desc)
            if not desc or type(desc) ~= "string" then
                desc = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_bool(p, unique_id, desc), p)
            return obs.utils.properties[unique_id]
        end

        function obs.script.path(p, unique_id, desc, enum_type_id, filter_string, default_path_string)
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            if not desc or type(desc) ~= "string" then
                desc = ""
            end
            if enum_type_id == nil or type(enum_type_id) ~= "number" then
                enum_type_id = obs.enum.path.read
            end
            if filter_string == nil or type(filter_string) ~= "string" then
                filter_string = ""
            end
            if default_path_string == nil or type(default_path_string) ~= "string" then
                default_path_string = ""
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_path(p, unique_id, desc, enum_type_id, filter_string, default_path_string), p)
            return obs.utils.properties[unique_id]
        end

        function obs.script.form(properties, title, unique_id)
            local pp = obs.script.create(); local __exit_click_callback__ = nil; local __onexit_type__ = 1;
            local __cancel_click_callback__ = nil; local __oncancel_type__ = 1;
            if unique_id == nil then
                unique_id = obs.utils.get_unique_id(20)
            end
            local group_form = obs.script.group(properties, unique_id, "", pp, obs.enum.group.normal)
            local label = obs.script.label(pp, unique_id .. "_label", title, obslua.OBS_TEXT_INFO);
            obs.script.label(pp, "form_tt", "<hr/>", obslua.OBS_TEXT_INFO);
            local ipp = obs.script.create()
            local group_inner = obs.script.group(pp, unique_id .. "_inner", "", ipp, obs.enum.group.normal)
            local exit = obs.script.button(pp, unique_id .. "_exit", "Confirm", function(pp, s, ss)
                if __exit_click_callback__ and type(__exit_click_callback__) == "function" then
                    __exit_click_callback__(pp, s, obs.PairStack(ss, nil, nil, true))
                end
                if __onexit_type__ == -1 then
                    group_form.free()
                elseif __onexit_type__ == 1 then
                    group_form.hide()
                end
                return true
            end)
            local cancel = obs.script.button(pp, unique_id .. "_cancel", "Cancel", function(pp, s, ss)
                if __cancel_click_callback__ and type(__cancel_click_callback__) == "function" then
                    __cancel_click_callback__(pp, s, obs.PairStack(ss, nil, nil, true))
                end
                if __oncancel_type__ == -1 then
                    group_form.free()
                elseif __oncancel_type__ == 1 then
                    group_form.hide()
                end
                return true
            end)
            local obj_t; obj_t = {
                add = {
                    button = function(...)
                        return obs.script.button(ipp, ...)
                    end,
                    options = function(...)
                        return obs.script.options(ipp, ...)
                    end,
                    label = function(...)
                        return obs.script.label(ipp, ...)
                    end,
                    group = function(...)
                        return obs.script.group(ipp, ...)
                    end,
                    bool = function(...)
                        return obs.script.bool(ipp, ...)
                    end,
                    path = function(...)
                        return obs.script.path(ipp, ...)
                    end,
                    input = function(...)
                        return obs.script.input(ipp, ...)
                    end,
                    number = function(...)
                        return obs.script.number(ipp, ...)
                    end
                },
                get = function(name)
                    return obs.script.get(name)
                end,
                free = function()
                    group_form.free();
                    obslua.obs_properties_destroy(ipp); ipp = nil
                    obslua.obs_properties_destroy(pp); pp = nil
                    return true
                end,
                data = ipp,
                item = ipp,
                confirm = {},
                onconfirm = {},
                oncancel = {},
                cancel = {}
            }
            function obj_t.confirm:click(clb)
                __exit_click_callback__ = clb
                return obj_t
            end; function obj_t.confirm:text(title_value)
                if not title_value or type(title_value) ~= "string" or title_value == "" then
                    return false
                end
                exit.text(title_value)
                return true
            end

            function obj_t.onconfirm:hide()
                __onexit_type__ = 1
                return obj_t
            end; function obj_t.onconfirm:remove()
                __onexit_type__ = -1
                return obj_t
            end; function obj_t.onconfirm:idle()
                __onexit_type__ = 0
                return obj_t
            end

            function obj_t.cancel:click(clb)
                __cancel_click_callback__ = clb
                return obj_t
            end; function obj_t.cancel:text(txt)
                if not txt or type(txt) ~= "string" or txt == "" then
                    return false
                end
                cancel.text(txt)
                return true
            end

            function obj_t.oncancel:idle()
                __oncancel_type__ = 0
                return obj_t
            end; function obj_t.oncancel:remove()
                __oncancel_type__ = -1
                return obj_t
            end; function obj_t.oncancel:hide()
                __oncancel_type__ = 1
                return obj_t
            end

            function obj_t.show()
                return group_form.show();
            end; function obj_t.hide()
                return group_form.hide();
            end; function obj_t.remove()
                return obj_t.free()
            end

            obs.utils.properties[unique_id] = obj_t
            return obj_t
        end

        function obs.script.fps(properties_t, unique_id, title)
            if not title or type(title) ~= "string" then
                title = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_frame_rate(properties_t, unique_id, title),
                properties_t
            )
            return obs.utils.properties[unique_id]
        end

        function obs.script.list(properties_t, unique_id, title, enum_type_id, filter_string, default_path_string)
            if not filter_string or type(filter_string) ~= "string" then
                filter_string = ""
            end
            if not default_path_string or type(default_path_string) ~= "string" then
                default_path_string = ""
            end
            if not enum_type_id or type(enum_type_id) ~= "number" or (
                    enum_type_id ~= obs.enum.list.string
                    and enum_type_id ~= obs.enum.list.file and
                    enum_type_id ~= obs.enum.list.url
                ) then
                enum_type_id = obs.enum.list.string
            end
            if not title or type(title) ~= "string" then
                title = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_editable_list(
                    properties_t, unique_id, title, enum_type_id,
                    filter_string, default_path_string
                ),
                properties_t)
            return obs.utils.properties[unique_id]
        end

        function obs.script.input(p, unique_id, title, enum_type_id, callback)
            if not title or type(title) ~= "string" then
                title = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            if not enum_type_id == nil or (
                    enum_type_id ~= obs.enum.text.input and enum_type_id ~= obs.enum.text.textarea and
                    enum_type_id ~= obs.enum.text.password) then
                enum_type_id = obs.enum.text.input
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_text(
                    p, unique_id, title, enum_type_id
                ),
                p)
            return obs.utils.properties[unique_id]
        end

        function obs.script.color(properties_t, unique_id, title)
            if not title or type(title) ~= "string" then
                title = ""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id] = obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_color_alpha(
                    properties_t, unique_id, title
                ),
                properties_t)
            return obs.utils.properties[unique_id]
        end

        function obs.script.number(properties_t, min, max, steps, unique_id, title, enum_number_type_id, enum_type_id)
            if not enum_number_type_id then
                enum_number_type_id = obs.enum.number.int
            end
            if not enum_type_id then
                enum_type_id = obs.enum.number.input
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == "" then
                unique_id = obs.utils.get_unique_id(20)
            end
            local obj; if enum_type_id == obs.enum.number.slider then
                if enum_number_type_id == obs.enum.number.float then
                    obj = obs.utils.obs_api_properties_patch(obslua.obs_properties_add_float(
                        properties_t, unique_id, title, min, max, steps
                    ))
                else
                    obj = obs.utils.obs_api_properties_patch(obslua.obs_properties_add_int_slider(
                        properties_t, unique_id, title, min, max, steps
                    ))
                end
            else
                if enum_number_type_id == obs.enum.number.float then
                    obj = obs.utils.obs_api_properties_patch(obslua.obs_properties_add_float(
                        properties_t, unique_id, title, min, max, steps
                    ))
                else
                    obj = obs.utils.obs_api_properties_patch(obslua.obs_properties_add_int(
                        properties_t, unique_id, title, min, max, steps
                    ))
                end
            end
            if obj then
                obj["type"] = enum_number_type_id
            end
            obs.utils.properties[unique_id] = obj

            return obj
        end

        function obs.script.get(name)
            return obs.utils.properties[name]
        end

    -- [[ OBS SCRIPT PROPERTIES CUSTOM API END ]]
    -- [[ API UTILS ]]
        function obs.utils.rgb_to_argb(r, g, b)
            r = math.max(0, math.min(255, math.floor(r)))
            g = math.max(0, math.min(255, math.floor(g)))
            b = math.max(0, math.min(255, math.floor(b)))

            -- OBS expects the order to be Blue-Green-Red (BGR)
            -- Red:   bits 0-7    (multiply by 1)
            -- Green: bits 8-15   (multiply by 2^8)
            -- Blue:  bits 16-23  (multiply by 2^16)

            return (b * 2 ^ 16) + (g * 2 ^ 8) + r
        end

        function obs.utils.argb_to_rgb(val)
            if type(val) ~= "number" then
                return nil
            end
            local b = math.floor(val / 2 ^ 16) % 256
            local g = math.floor(val / 2 ^ 8) % 256
            local r = val % 256

            return r, g, b
        end

        function obs.utils.obs_api_properties_patch(pp, pp_t, cb)
            -- if pp_t ~= nil and not obs.utils.properties[pp] then
            -- 	obs.utils.properties[pp]=pp_t;
            -- end
            local pp_unique_name = obslua.obs_property_name(pp)
            local obs_pp_t = pp; -- extra

            -- onchange [Event Handler]
            local __onchange_list = {}

            local item = nil; local objText; local objInput; local objGlobal; objGlobal = {
                cb = cb,
                disable = function()
                    obslua.obs_property_set_disabled(pp, true)
                    return nil
                end,
                enable = function()
                    obslua.obs_property_set_disabled(obs_pp_t, false)
                    return nil
                end,
                onchange = function(callback)
                    if type(callback) ~= "function" then
                        return false
                    end
                    table.insert(__onchange_list, callback)
                    return true
                end,
                hide = function()
                    obslua.obs_property_set_visible(obs_pp_t, false)
                end,
                show = function()
                    obslua.obs_property_set_visible(obs_pp_t, true)
                    return nil
                end,
                get = function()
                    return obs_pp_t
                end,
                hint = function(txt)
                    if txt == nil or type(txt) ~= "string" or txt == "" then
                        return obslua.obs_property_long_description(obs_pp_t)
                    end
                    item = obslua.obs_property_set_long_description(obs_pp_t, txt)
                    return nil
                end,
                free = function()
                    obs.utils.properties[pp_unique_name] = nil
                    local pv = obslua.obs_properties_get_parent(pp_t)
                    obslua.obs_properties_remove_by_name(pp_t, pp_unique_name)
                    while pv do
                        obslua.obs_properties_remove_by_name(pv, pp_unique_name)
                        pv = obslua.obs_properties_get_parent(pv)
                    end
                    return true
                end,
                remove = function()
                    return objGlobal.free()
                end,
                data = pp,
                item = pp,
                title = function(txt)
                    if txt == nil or type(txt) ~= "string" then
                        return obslua.obs_property_description(pp)
                    end
                    obslua.obs_property_set_description(pp, txt)
                    return objGlobal
                end,
                parent = pp_t
            }; objText = {
                error = function(txt)
                    if txt == nil or type(txt) ~= "string" then
                        return obslua.obs_property_description(pp)
                    end

                    obslua.obs_property_text_set_info_type(pp, obslua.OBS_TEXT_INFO_ERROR)
                    obslua.obs_property_set_description(pp, txt)
                    return objText
                end,
                text = function(txt)
                    local id_name = obslua.obs_property_name(pp)
                    objText.type = obs.enum.text.default
                    obslua.obs_property_text_set_info_type(pp, objText.type)
                    if txt ~= nil and type(txt) == "string" then obslua.obs_property_set_description(pp, txt) end
                    return objText
                end,
                warn = function(txt)
                    local id_name = obslua.obs_property_name(pp)
                    local textarea_id = id_name .. "_obsapi_hotfix_textarea"
                    local input_id = id_name .. "_obsapi_hotfix_input"
                    local property = obs.script.get(id_name)
                    local textarea_property = obs.script.get(textarea_id)
                    local input_property = obs.script.get(input_id)
                    objText.type = obs.enum.text.input
                    if property then property.show() end
                    if input_property then input_property.hide() end
                    if textarea_property then textarea_property.hide() end
                    objText.type = obs.enum.text.warn
                    obslua.obs_property_text_set_info_type(pp, objText.type)
                    if txt ~= nil and type(txt) == "string" then obslua.obs_property_set_description(pp, txt) end
                    return objText
                end,
                type = -1
            }; objInput = {
                value = obs.expect(function(txt)
                    local settings = nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings = obs.utils.properties[pp_t]
                    else
                        settings = obs.utils.settings
                    end
                    if txt ~= nil and type(txt) == "string" then
                        if settings then
                            settings.str(pp_unique_name, txt)
                        end
                    end
                    if settings then
                        return settings.str(pp_unique_name)
                    end
                    return nil
                end),
                type = -1
            };
            local objOption; objOption = {
                item = nil,
                clear = function()
                    objOption.item = obslua.obs_property_list_clear(pp)
                    return objOption
                end,
                add = {
                    str = function(title, id)
                        if id == nil or type(id) ~= "string" or id == "" then
                            --id= obs.utils.get_unique_id(20)
                            obslua.script_log(obslua.LOG_INFO, "[obs.script.options.str] id is nil or invalid!")
                            return objOption
                        end
                        objOption.item = obslua.obs_property_list_add_string(pp, title, id)
                        return objOption
                    end,
                    int = function(title, id)
                        if id == nil or type(id) ~= "number" then
                            --id= obs.utils.get_unique_id(20)
                            obslua.script_log(obslua.LOG_INFO, "[obs.script.options.int] id is nil or invalid!")
                            return objOption
                        end
                        objOption.item = obslua.obs_property_list_add_int(pp, title, id)
                        return objOption
                    end,
                    dbl = function(title, id)
                        if id == nil or type(id) ~= "number" then
                            --id= obs.utils.get_unique_id(20)
                            obslua.script_log(obslua.LOG_INFO, "[obs.script.options.dbl] id is nil or invalid!")
                            return objOption
                        end
                        objOption.item = obslua.obs_property_list_add_float(pp, title, id)
                        return objOption
                    end,
                    bul = function(title, id)
                        if id == nil or type(id) ~= "boolean" then
                            id = obs.utils.get_unique_id(20)
                        end
                        objOption.item = obslua.obs_property_list_add_bool(pp, title, id)
                        return objOption
                    end
                },
                cursor = function(index)
                    if index == nil or type(index) ~= "number" or index < 0 then
                        if type(index) == "string" then -- find the index by the id value
                            for i = 0, obslua.obs_property_list_item_count(pp) - 1 do
                                if obslua.obs_property_list_item_string(pp, i) == index then
                                    index = i
                                    break
                                end
                            end
                            if type(index) ~= "number" then
                                return nil
                            end
                        else
                            index = objOption.item; if type(index) ~= "number" or index < 0 then
                                index = obslua.obs_property_list_item_count(pp) - 1
                            end
                        end
                    end
                    local info_title; local info_id
                    info_title = obslua.obs_property_list_item_name(pp, index)
                    if obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.string then
                        info_id = obslua.obs_property_list_item_string(pp, index)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.int then
                        info_id = obslua.obs_property_list_item_int(pp, index)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.float then
                        info_id = obslua.obs_property_list_item_float(pp, index)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.bool then
                        info_id = obslua.obs_property_list_item_bool(pp, index)
                    else
                        info_id = nil
                    end
                    local nn_obj = nil; nn_obj = {
                        disable = function()
                            obslua.obs_property_list_item_disable(pp, index, true)
                            return nn_obj
                        end,
                        enable = function()
                            obslua.obs_property_list_item_disable(pp, index, false)
                            return nn_obj
                        end,
                        remove = function()
                            obslua.obs_property_list_item_remove(pp, index)
                            return true
                        end,
                        title = info_title,
                        value = info_id,
                        index = index,
                        ret = function()
                            return objOption
                        end,
                        isDisabled = function()
                            return obslua.obs_property_list_item_disabled(pp, index)
                        end
                    }
                    return nn_obj;
                end,
                current = function()
                    local current_selected_option = nil
                    local settings = nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings = obs.utils.properties[pp_t]
                    else
                        settings = obs.utils.settings
                    end
                    if obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.string then
                        current_selected_option = settings.str(pp_unique_name)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.int then
                        current_selected_option = settings.int(pp_unique_name)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.float then
                        current_selected_option = settings.float(pp_unique_name)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.bool then
                        current_selected_option = settings.bool(pp_unique_name)
                    end
                    return objOption.cursor(current_selected_option)
                end
            }; local fr_rt = false
            local objButton; objButton = {
                item = nil,
                click = function(callback)
                    if type(callback) ~= "function" then
                        obslua.script_log(obslua.LOG_ERROR,
                            "[button.click] invalid callback type " .. type(callback) .. " expected function")
                        return objButton
                    end
                    local tk = os.clock()
                    objButton.item = obslua.obs_property_set_modified_callback(pp, function(properties_t, property_t, obs_data_t)
                        if os.clock() - tk <= 0.01 then
                            return true
                        end

                        return callback(properties_t, property_t, obs.PairStack(obs_data_t, nil, nil, true))
                    end)
                    return objButton
                end,
                text = function(txt)
                    if txt == nil or type(txt) ~= "string" or txt == "" then
                        return obslua.obs_property_description(pp)
                    end
                    obslua.obs_property_set_description(pp, txt)
                    return objButton
                end,
                url = function(url)
                    if not url or type(url) ~= "string" or url == "" then
                        obslua.script_log(obslua.LOG_ERROR, "[button.url] invalid url type, expected string, got " .. type(url))
                        return objButton --obslua.obs_property_button_get_url(pp)
                    end
                    obslua.obs_property_button_set_url(pp, url)
                    return objButton
                end,
                type = function(button_type)
                    if button_type == nil or (button_type ~= obs.enum.button.url and button_type ~= obs.enum.button.default) then
                        obslua.script_log(obslua.LOG_ERROR,
                            "[button.type] invalid type, expected obs.enum.button.url | obs.enum.button.default, got " ..
                            type(button_type))
                        return objButton --obslua.obs_property_button_get_type(pp)
                    end
                    obslua.obs_property_button_set_type(pp, button_type)
                    return objButton
                end
            };
            -- [[ GROUP ]]
            local objGroup; objGroup = {

            };
            --
            local objBool; objBool = {
                checked = function(bool_value)
                    local settings = nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings = obs.utils.properties[pp_t]
                    else
                        settings = obs.utils.settings
                    end
                    if not settings then
                        obslua.script_log(obslua.LOG_ERROR, "[obs.utils.settings] is not set, please use 'script_load' to set it")
                        return nil
                    end
                    local property_id = obslua.obs_property_name(pp)
                    if bool_value == nil or type(bool_value) ~= "boolean" then
                        return settings.get_bul(property_id)
                    end
                    settings.bul(property_id, bool_value)
                    return objBool
                end,
            }; local objColor; objColor = {
                value = obs.expect(function(r_color, g_color, b_color, alpha_value)
                    local settings = nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings = obs.utils.properties[pp_t]
                    else
                        settings = obs.utils.settings
                    end
                    if r_color == nil then
                        return settings.int(pp_unique_name)
                    end
                    if type(r_color) ~= "number" or type(g_color) ~= "number" or type(b_color) ~= "number" then
                        return false
                    end
                    if alpha_value == nil then
                        alpha_value = 1
                    end
                    local color_value = bit.bor(
                        bit.lshift(alpha_value * 255, 24),
                        bit.lshift(b_color, 16),
                        bit.lshift(g_color, 8),
                        r_color
                    )

                    --(alpha_value << 24) | (b_color << 16) | (g_color << 8) | r_color
                    settings.int(pp_unique_name, color_value)
                    return color_value
                end),
                type = obslua.OBS_PROPERTY_COLOR_ALPHA
            }
            local objList; objList = {
                insert = function(value, selected, hidden)
                    if type(value) ~= "string" then
                        return objList
                    end
                    if type(selected) ~= "boolean" then
                        selected = false
                    end
                    if type(hidden) ~= "boolean" then
                        hidden = false
                    end
                    local settings = nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings = obs.utils.properties[pp_t]
                    else
                        settings = obs.utils.settings
                    end
                    local unique_id = obs.utils.get_unique_id(20)
                    local obs_data_t = obs.PairStack()
                    obs_data_t.str("value", value)
                    obs_data_t.bul("selected", selected)
                    obs_data_t.bul("hidden", hidden)
                    obs_data_t.str("uuid", unique_id)
                    local obs_curr_data_t = settings.arr(pp_unique_name)
                    obs_curr_data_t.insert(obs_data_t.data)
                    obs_data_t.free(); obs_curr_data_t.free()
                    return objList
                end,
                filter = function()
                    return obslua.obs_property_editable_list_filter(pp)
                end,
                default = function()
                    return obslua.obs_property_editable_list_default_path(pp)
                end,
                type = function()
                    return obslua.obs_property_editable_list_type(pp)
                end,
            }; local objNumber; objNumber = {
                suffix = function(text)
                    obslua.obs_property_float_set_suffix(pp, text)
                    obslua.obs_property_int_set_suffix(pp, text)
                    return objNumber
                end,
                value = function(value)
                    local settings = nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings = obs.utils.properties[pp_t]
                    else
                        settings = obs.utils.settings
                    end
                    if objNumber.type == obs.enum.number.int then
                        settings.int(pp_unique_name, value)
                    elseif objNumber.type == obs.enum.number.float then
                        settings.dbl(pp_unique_name, value)
                    else
                        return nil
                    end
                    return value
                end,
                type = nil
            }


            local property_type = obslua.obs_property_get_type(pp)
            -- [[ ON-CHANGE EVENT HANDLE FOR ANY KIND OF USER INTERACTIVE INPUT ]]
            if property_type == obslua.OBS_PROPERTY_COLOR or property_type == obslua.OBS_PROPERTY_COLOR_ALPHA or
                property_type == obslua.OBS_PROPERTY_BOOL or property_type == obslua.OBS_PROPERTY_LIST or
                property_type == obslua.OBS_PROPERTY_EDITABLE_LIST or property_type == obslua.OBS_PROPERTY_PATH or
                (property_type == obslua.OBS_PROPERTY_TEXT and (
                    obslua.obs_property_text_type(pp) == obs.enum.text.textarea or
                    obslua.obs_property_text_type(pp) == obs.enum.text.input or
                    obslua.obs_property_text_type(pp) == obs.enum.text.password
                )) then
                local tk = os.clock()
                obslua.obs_property_set_modified_callback(obs_pp_t, function(properties_t, property_t, settings)
                    if os.clock() - tk <= 0.01 then
                        return true
                    end
                    settings = obs.PairStack(settings, nil, nil, true)
                    local pp_unique_name = obslua.obs_property_name(property_t)
                    local current_value; property_type = obslua.obs_property_get_type(property_t)
                    if property_type == obslua.OBS_PROPERTY_BOOL then
                        current_value = settings.bul(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_TEXT or
                        property_type == obslua.OBS_PROPERTY_PATH or
                        property_type == obslua.OBS_PROPERTY_BUTTON then
                        current_value = settings.str(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_INT or property_type == obslua.OBS_PROPERTY_COLOR_ALPHA or property_type == obslua.OBS_PROPERTY_COLOR then
                        current_value = settings.int(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_FLOAT then
                        current_value = settings.dbl(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_LIST then
                        if obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.string then
                            current_value = settings.str(pp_unique_name)
                        elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.int then
                            current_value = settings.int(pp_unique_name)
                        elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.float then
                            current_value = settings.dbl(pp_unique_name)
                        elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.bool then
                            current_value = settings.bul(pp_unique_name)
                        end
                    elseif property_type == obslua.OBS_PROPERTY_FONT then
                        current_value = settings.obj(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_EDITABLE_LIST then
                        current_value = settings.arr(pp_unique_name)
                    end
                    local result = nil
                    for _, vclb in pairs(__onchange_list) do
                        local temp = vclb(current_value, obs.script.get(obslua.obs_property_name(property_t)), properties_t,
                            settings)
                        if result == nil then
                            result = temp
                        end
                    end
                    if type(current_value) == "table" then
                        current_value.free()
                    end
                    return result
                end);
            end


            if property_type == obslua.OBS_PROPERTY_GROUP then
                obs.utils.table.append(objGroup, objGlobal)
                return objGroup;
            elseif property_type == obslua.OBS_PROPERTY_EDITABLE_LIST then
                obs.utils.table.append(objList, objGlobal)
                return objList
            elseif property_type == obslua.OBS_PROPERTY_LIST then
                obs.utils.table.append(objOption, objGlobal)
                return objOption;
            elseif property_type == obslua.OBS_PROPERTY_INT or property_type == obslua.OBS_PROPERTY_FLOAT then
                obs.utils.table.append(objNumber, objGlobal)
                return objNumber
            elseif property_type == obslua.OBS_PROPERTY_BUTTON then
                obs.utils.table.append(objButton, objGlobal)
                return objButton
            elseif property_type == obslua.OBS_PROPERTY_COLOR_ALPHA or property_type == obslua.OBS_PROPERTY_COLOR then
                obs.utils.table.append(objColor, objGlobal)
                return objColor
            elseif property_type == obslua.OBS_PROPERTY_TEXT then
                local obj_enum_type_id = obslua.obs_property_text_type(pp)
                if obj_enum_type_id == obs.enum.text.textarea or
                    obj_enum_type_id == obs.enum.text.input or
                    obj_enum_type_id == obs.enum.text.password then
                    objInput.type = obj_enum_type_id
                    obs.utils.table.append(objInput, objGlobal)
                    return objInput;
                else
                    objText.type = obj_enum_type_id
                    obs.utils.table.append(objText, objGlobal)
                    return objText;
                end
            elseif property_type == obslua.OBS_PROPERTY_BOOL then
                obs.utils.table.append(objBool, objGlobal)
                return objBool;
            else
                return objGlobal;
            end
        end

        function obs.utils.get_unique_id(rs, i, mpc, cmpc)
            local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
            if i == nil then
                i = true;
            end
            if mpc == nil or type(mpc) ~= "string" then
                mpc = tostring(os.time());
                mpc = obs.utils.get_unique_id(rs, false, mpc, true)
            elseif cmpc == true then
                chars = mpc
            end

            local index = math.random(1, #chars)
            local c = chars:sub(index, index)
            if c == nil then
                c = ""
            end
            if rs <= 0 then
                return c;
            end
            local val = obs.utils.get_unique_id(rs - 1, false, mpc, cmpc)

            if i == true and mpc ~= nil and type(mpc) == "string" and #val > 1 then
                val = val .. "_" .. mpc
            end
            return c .. val
        end

        function obs.utils.table.append(tb, vv)
            for k, v in pairs(vv) do
                if type(v) == "function" then
                    local old_v = v
                    v = function(...)
                        local retValue = old_v(...)
                        if retValue == nil then
                            return tb;
                        end
                        return retValue;
                    end
                end
                if type(k) == "string" then
                    tb[k] = v;
                else
                    table.insert(tb, k, v)
                end
            end
        end

        function obs.utils.json(s)
            local i = 1
            local function v()
                i = s:find("%S", i) -- Find next non-whitespace
                if not i then return nil end
                local c = s:sub(i, i); i = i + 1
                if c == '{' then
                    local r = {}
                    if s:match("^%s*}", i) then
                        i = s:find("}", i) + 1
                        return r
                    end
                    repeat
                        local k = v()
                        i = s:find(":", i) + 1
                        r[k] = v()
                        i = s:find("[%,%}]", i)
                        local x = s:sub(i, i)
                        i = i + 1
                    until x == '}'
                    return r
                elseif c == '[' then
                    local r = {}
                    if s:match("^%s*]", i) then
                        i = s:find("]", i) + 1
                        return r
                    end
                    repeat
                        r[#r + 1] = v()
                        i = s:find("[%,%]]", i)
                        local x = s:sub(i, i)
                        i = i + 1
                    until x == ']'
                    return r
                elseif c == '"' then
                    local _, e = i, i
                    repeat _, e = s:find('"', e) until s:sub(e - 1, e - 1) ~= "\\"
                    local res = s:sub(i, e - 1):gsub("\\", "")
                    i = e + 1
                    return res
                end
                local n = s:match("^([%-?%d%.eE]+)()", i - 1)
                if n then
                    i = i + #n - 1
                    return tonumber(n)
                end
                local l = { t = true, f = false, n = nil }
                i = i + (c == 'f' and 4 or 3)
                return l[c]
            end
            return v()
        end
    -- [[ API UTILS END ]]
-- [[ OBS CUSTOM API END ]]