-- [[ 1. GLOBAL HELPERS ]] --
ANIM_LIB = {};SCRIPT_FUNCS={}
-- Time Parser: Converts "1s", "500ms", "1mi" to milliseconds

function parse_time(str)
    if not str then return 0 end
    local val = tonumber(string.match(str, "[%d%.]+")) or 0
    local unit = string.match(str, "%a+") or "ms"
    
    if unit == "s" then return val * 1000
    elseif unit == "mi" then return val * 60000
    elseif unit == "hr" then return val * 3600000
    else return val end 
end

function parse_value(src, current_val, input_str)
    -- 1. Check for Math Expression: "( ... )"
    if type(input_str) == "string" and input_str:sub(1,1) == "(" then
        return evaluate_math(src, input_str)
    end

    -- 2. Existing Relative Logic (unchanged)
    if type(input_str) ~= "string" then return tonumber(input_str) or current_val end
    
    local op, val = string.match(input_str, "^([%+%-%*/]+)([%d%.]+)")
    val = tonumber(val)
    if type(op) == "string" then op=op:match("^%s*(.-)%s*$") end
    
    if op == "++" then return current_val + val
    elseif op == "--" then return current_val - val
    elseif op == "**" then return current_val * val
    else return tonumber(input_str) or current_val end
end
-- [[ EASING MATH LIBRARY ]] --
local EASING_FUNCS = {
    linear = function(t) return t end,
    
    -- Smooth Start/End
    quad_in    = function(t) return t * t end,
    quad_out   = function(t) return t * (2 - t) end,
    quad_inout = function(t) 
        if t < 0.5 then return 2 * t * t else return -1 + (4 - 2 * t) * t end 
    end,
    
    sine_inout = function(t) return 0.5 * (1 - math.cos(math.pi * t)) end,
    
    -- Elastic / Bouncy
    back_out = function(t) 
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
    end,
    
    elastic_out = function(t)
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
    end,
    
    bounce_out = function(t)
        local n1 = 7.5625
        local d1 = 2.75
        if t < 1 / d1 then return n1 * t * t
        elseif t < 2 / d1 then t = t - 1.5 / d1 return n1 * t * t + 0.75
        elseif t < 2.5 / d1 then t = t - 2.25 / d1 return n1 * t * t + 0.9375
        else t = t - 2.625 / d1 return n1 * t * t + 0.984375 end
    end
}
-- [[ 3. THE COMPILER ]] --
-- Converts a text command into a high-speed Lua Closure
function compile_line(cmd, args)
    
    -- A. Check for Built-in Presets (!move, !var, !if)
    if ANIM_LIB[cmd] then
        local preset_func = ANIM_LIB[cmd]
        -- Return a closure that runs the preset
        return function(src, override_state) 
            return preset_func(src, override_state or src.state, args) 
        end
    end

    -- B. Check for @Functions (!@alert)
    if cmd:sub(1,1) == "@" then
        local func_name, args_block = cmd:match("@(%w+)(%b())")
        if not func_name then func_name = cmd:sub(2) end
        local func = SCRIPT_FUNCS[func_name]
        
        return function(src)
            if not func then return true end
            local resolved_args = {}
            -- 1. Parse Block Args "(a,b)"
            if args_block then
                local clean = args_block:sub(2, -2)
                for arg in string.gmatch(clean, "([^,]+)") do
                    table.insert(resolved_args, resolve_path(src, arg:match("^%s*(.-)%s*$")))
                end
            end
            -- 2. Parse Pipe Args "|a|b"
            for _, arg in ipairs(args) do
                table.insert(resolved_args, resolve_path(src, arg))
            end
            func(src, unpack(resolved_args))
            return true
        end
    end
    return function(src)
        if not src.scene_item then return true end

        -- 1. Walk the Dot-Path (style -> grad -> enable)
        local func = src.scene_item
        for part in string.gmatch(cmd, "[^%.]+") do
            if type(func) == "table" then
                func = func[part]
            else
                func = nil
                break
            end
        end
        
        if not func then return true end -- Function not found

        -- 2. Process Arguments
        local final_args = {}
        
        for _, raw_arg in ipairs(args) do
            -- CASE A: Key-Value Table (e.g., "x:100, y:200")
            if raw_arg:find(":") then
                local kv_table = {}
                -- Try to fetch current state for relative math (optional/best-effort)
                local current_state = {}
                pcall(function() current_state = func() end)
                if type(current_state) ~= "table" then current_state = {} end

                for _, pair in ipairs(safe_split(raw_arg)) do
                    local k, v = string.match(pair, "%s*([^:]+)%s*:%s*(.+)%s*")
                    if k and v then
                        local resolved_v = resolve_path(src, v)
                        local base = current_state[k] or 0
                        -- Use parse_value to handle ++/-- relative math
                        kv_table[k] = parse_value(src, base, resolved_v)
                    end
                end
                -- Merge missing keys from current state
                for k, v in pairs(current_state) do
                    if kv_table[k] == nil then kv_table[k] = v end
                end
                table.insert(final_args, kv_table)

            -- CASE B: Comma-Separated List (e.g., "0, 255, 0")
            elseif raw_arg:find(",") then
                for val in string.gmatch(raw_arg, "([^,]+)") do
                    val = val:match("^%s*(.-)%s*$") -- Trim whitespace
                    table.insert(final_args, resolve_path(src, val))
                end

            -- CASE C: Single Value (e.g., "255" or variables)
            else
                table.insert(final_args, resolve_path(src, raw_arg))
            end
        end

        -- 3. Execute with Unpacked Arguments
        if type(func) == "function" then
            pcall(func, unpack(final_args))
        end
        
        return true
    end
end

-- String Splitter
function split(str, sep)
    local result = {}
    local start = 1
    
    -- Use plain find to treat '|+|' as a literal string, not a regex pattern
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
-- Helper: Splits strings by comma, but ignores commas inside parentheses (math/functions)
function safe_split(str)
    if not str then return {} end
    local chunks = {}
    local depth = 0
    local start = 1
    
    for i = 1, #str do
        local c = str:sub(i,i)
        if c == "(" then depth = depth + 1
        elseif c == ")" then depth = depth - 1
        elseif c == "," and depth == 0 then
            -- Found a top-level comma, split here
            table.insert(chunks, str:sub(start, i-1))
            start = i + 1
        end
    end
    -- Add the final chunk
    table.insert(chunks, str:sub(start))
    return chunks
end
-- Easing Helper (Linear)
function lerp(a, b, t) return a + (b - a) * t end


-- [[ 2. ANIMATION PRESETS LIBRARY ]] --
-- These are defined OUTSIDE setup() for easy editing.
-- Each function receives: (src_wrapper, state_table, args_table)
-- Return TRUE when finished.


ANIM_LIB["easing"] = function(src, state, args)
    -- Store the easing type on the 'src' object so it persists
    src.current_easing = args[1] or "linear"
    return true -- Instant (Non-blocking)
end
-- !wait | duration_or_var
ANIM_LIB["wait"] = function(src, state, args)
    local duration_raw = resolve_path(src, args[1])
    local duration = parse_time(tostring(duration_raw or "0ms"))
    
    if not state.init then
        state.start_time = os.clock()
        state.init = true
    end
    
    -- Check if time has passed
    if (os.clock() - state.start_time) * 1000 >= duration then
        return true -- Done! (Allow loop to continue)
    else
        return false -- Still waiting! (Break the loop)
    end
end

-- !move | x:var,y:var | duration_or_var
ANIM_LIB["move"] = function(src, state, args)
    -- 1. Initialize (Run once)
    
    if not state.init then
        state.targets = {}
        state.starts = {}
        state.duration = parse_time(args[#args]) or 1000 -- Last arg is time
        state.start_time = os.clock()
        src.opt={
            pos= src.scene_item.pos(),
            rot= src.scene_item.rot(),
            scale= src.scene_item.scale(),

        }
        -- Parse target values (e.g., x:100, y:200)
        -- We handle the weird syntax: "!move|x:10,y:20|1s"
        local move_args = args[1]
        for _, pair in ipairs(safe_split(move_args)) do
            local k, v = string.match(pair, "([^:]+):(.+)")
            if k and v then
                k = k:match("^%s*(.-)%s*$") -- Trim
                v = v:match("^%s*(.-)%s*$")
                
                -- Get Start Value
                local current_val = 0
                if k == "x" then current_val = src.opt.pos.x
                elseif k == "y" then current_val = src.opt.pos.y
                elseif k == "rot" then current_val = src.opt.rot
                elseif k:match("scale") then current_val = src.opt.scale[k:match("scale%.(%w+)")] or 1
                elseif src.scene_item[k] then current_val = src.scene_item[k]() or 0
                end
                
                state.starts[k] = current_val
                
                -- Calculate Target (Support ++/-- relative math)
                local resolved_v = resolve_path(src, v) -- Resolve @funcs or variables
                state.targets[k] = parse_value(src, current_val, resolved_v)
            end
        end
        state.init = true
    end

    -- 2. Calculate Progress (0.0 to 1.0)
    local now = os.clock()
    local elapsed = (now - state.start_time) * 1000
    local t = elapsed / state.duration
    if t > 1 then t = 1 end

    -- [[ NEW: APPLY EASING ]] --
    local ease_name = src.current_easing or "linear"
    local ease_func = EASING_FUNCS[ease_name] or EASING_FUNCS.linear
    local eased_t = ease_func(t) -- Warps time based on the curve

    -- 3. Interpolate & Apply
    for k, target in pairs(state.targets) do
        local start = state.starts[k]
        local val = start + (target - start) * eased_t
        
        -- Route to correct API
        if k == "x" then src.opt.pos.x = val; src.scene_item.pos(src.opt.pos)
        elseif k == "y" then src.opt.pos.y = val; src.scene_item.pos(src.opt.pos)
        elseif k == "rot" then src.opt.rot = val; src.scene_item.rot(src.opt.rot)
        elseif k == "scale.x" then src.opt.scale.x = val; src.scene_item.scale(src.opt.scale)
        elseif k == "scale.y" then src.opt.scale.y = val; src.scene_item.scale(src.opt.scale)
        elseif src.scene_item[k] then src.scene_item[k](val)
        end
    end

    -- 4. Finish Check
    if t >= 1 then return true else return false end
end

-- !loop | (No args: restarts from beginning)
ANIM_LIB["loop"] = function(src, state, args)
    -- Returns a special signal to the engine to reset index
    return "RESET" 
end




-- !label | name
ANIM_LIB["label"] = function(src, state, args)
    return true -- Labels are just markers, they finish instantly
end

-- !if | property | operator | value | jump_to_label
-- !if | prop.key | operator | value_or_var | jump_label
-- !if | val1 | op | val2 | label_OR_@function
ANIM_LIB["if"] = function(src, state, args)
    -- 1. Resolve Values
    local v1 = resolve_path(src, args[1])
    local op = args[2]
    local v2 = resolve_path(src, args[3])
    local target = args[4]

    -- 2. Compare (Numeric or String)
    local n1, n2 = tonumber(v1), tonumber(v2)
    if n1 and n2 then v1, v2 = n1, n2 else v1, v2 = tostring(v1), tostring(v2) end

    local condition = false
    if op == "==" then condition = v1 == v2
    elseif op == "!=" then condition = v1 ~= v2
    elseif n1 and n2 then 
        if op == ">=" then condition = v1 >= v2
        elseif op == "<=" then condition = v1 <= v2
        elseif op == ">"  then condition = v1 > v2
        elseif op == "<"  then condition = v1 < v2
        end
    end

    -- 3. Execution (The Fixed Part)
    if condition then
        -- A. Check if 'target' is a known Label in our map
        -- (src.labels is built during compilation, so it's safe to read)
        if src.labels and src.labels[target] then
            return "JUMP", target
        end

        -- B. Check if it's a Function call (@func)
        if type(target) == "string" and target:match("@") then
            resolve_path(src, target) -- Triggers the function execution
            return true
        end

        -- C. Fallback: Return JUMP anyway. 
        -- If the label doesn't exist, _.tick will handle the warning safely.
        return "JUMP", target
    end

    return true
end



-- !var | name | value_or_path
ANIM_LIB["var"] = function(src, state, args)
    if not src.vars then src.vars = {} end
    local name = args[1]
    local input_value = args[2]
    if not name or name == "" then return true end

    -- 1. Try to resolve as a math equation first (e.g., "(sum + 1)")
    if type(input_value) == "string" and input_value:match("^%b()$") then
        src.vars[name] = evaluate_math(src, input_value)
        return true
    end

    -- 2. Handle Relative Math (e.g., ++1 or ++pos.x)
    local current_var_val = tonumber(src.vars[name]) or 0
    local op, math_path = string.match(tostring(input_value), "^([%+%-%*/]+)(.+)")
    
    if op then
        -- Resolve the part after the operator. If it's a number like '1', it returns 1.
        local resolved_num = tonumber(resolve_path(src, math_path)) or 0
        src.vars[name] = parse_value(src, current_var_val, op .. resolved_num)
    else
        -- 3. Absolute assignment
        local resolved_val = resolve_path(src, input_value)
        src.vars[name] = tonumber(resolved_val) or resolved_val
    end

    return true
end
-- !jump | LABEL_NAME
ANIM_LIB["jump"] = function(src, state, args)
    -- We return "JUMP" and the label name so 'tick' knows where to go
    return "JUMP", args[1]
end

-- !log | property_or_var_or_msg
ANIM_LIB["log"] = function(src, state, args)
    local path = args[1]
    local value = resolve_path(src, path)
    
    -- If resolver returns nil, it might be a literal message (e.g., !log|Hello)
    local output = (value ~= nil) and tostring(value) or path
    
    obslua.script_log(obslua.LOG_INFO, "[4IM3-Script] " .. tostring(output))
    return true
end

-- [[ PREDEFINED ANIMATIONS ]]
-- [[ 4IM3 EFFECTS LIBRARY ]] --

-- !rainbow | speed | duration
    -- Cycles the gradient color through the rainbow
    ANIM_LIB["rainbow"] = function(src, state, args)
        if not src.scene_item then return true end
        
        local speed = tonumber(args[1]) or 0.01
        local duration = parse_time(args[2] or "0ms") -- 0 = Infinite

        if not state.init then
            state.hue = 0
            state.start_time = os.clock()
            -- Ensure gradient is on
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
            if i == 0 then r,g,b = 1,t,0 
            elseif i == 1 then r,g,b = q,1,0 
            elseif i == 2 then r,g,b = 0,1,t 
            elseif i == 3 then r,g,b = 0,q,1 
            elseif i == 4 then r,g,b = t,0,1 
            elseif i == 5 then r,g,b = 1,0,q end
            return math.floor(r*255), math.floor(g*255), math.floor(b*255)
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
    -- Randomly offsets the source position
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
            src.scene_item.pos({x = state.base_x, y = state.base_y})
            return true
        end
        return false
    end

    -- !glitch | intensity | duration
    -- Occasional stuttering position/scale changes
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
            
            src.scene_item.pos({x = state.base_x + dx, y = state.base_y + dy})
            src.scene_item.scale({x = ds, y = 1}) -- Stretch width only for "digital" feel
        else
            -- Snap back to normal
            src.scene_item.pos({x = state.base_x, y = state.base_y})
            src.scene_item.scale({x = 1, y = 1})
        end

        local elapsed = (os.clock() - state.start_time) * 1000
        if duration > 0 and elapsed >= duration then
            src.scene_item.pos({x = state.base_x, y = state.base_y})
            src.scene_item.scale({x = 1, y = 1})
            return true
        end
        return false
    end

    -- !breathing | speed | duration
    -- Gentle scale and opacity pulse
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
        
        -- Scale: 1.0 to 1.05
        local s = 1 + (wave * 0.025 + 0.025)
        src.scene_item.scale({x = s, y = s})
        
        -- Opacity: 50% to 90%
        local op = 70 + (wave * 20)
        src.scene_item.style.opacity(op/100) -- Convert 0-100 to 0.0-1.0 if needed by your wrapper

        if duration > 0 then
            return (os.clock() - state.start_time) * 1000 >= duration
        end
        return false
    end

    -- !dvd | speed | duration
    -- Bounces off screen edges like a DVD logo
    ANIM_LIB["dvd"] = function(src, state, args)
        if not src.scene_item then return true end
        
        local speed = tonumber(args[1]) or 5
        local duration = parse_time(args[2] or "0ms")
        
        if not state.init then
            local pos = src.scene_item.pos()
            local bounds = src.vars.screen or {width=1920, height=1080}
            
            state.x, state.y = pos.x, pos.y
            state.vx, state.vy = speed, speed
            state.w = src.scene_item.width()
            state.h = src.scene_item.height()
            state.sw, state.sh = bounds.width, bounds.height
            
            state.start_time = os.clock()
            state.init = true
        end

        -- Update Physics
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
        src.scene_item.pos({x = next_x, y = next_y})

        if duration > 0 then
            return (os.clock() - state.start_time) * 1000 >= duration
        end
        return false
    end

    -- !sway | speed | duration
    -- Gentle rotation back and forth
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
-- [[ END PREDEFINED ANIMATIONS ]]
-- !run | command | arg1 | arg2 ...
-- Spawns a command to run in the background (Parallel)
ANIM_LIB["run"] = function(src, state, args)
    local cmd = args[1]
    if not cmd or not ANIM_LIB[cmd] then return true end

    -- Initialize the Async List if missing
    if not src.async_tasks then src.async_tasks = {} end

    -- Create a new independent task
    local new_task = {
        cmd = cmd,
        args = {},     -- We will copy the rest of the args here
        state = { init = false } -- Give it its own fresh state
    }

    -- Copy args (skipping the first one which is the command name)
    for i = 2, #args do
        table.insert(new_task.args, args[i])
    end

    table.insert(src.async_tasks, new_task)
    return true -- Return TRUE immediately so the main script continues!
end

-- !stop
-- Kills all background tasks immediately
ANIM_LIB["stop"] = function(src, state, args)
    src.async_tasks = {}
    return true
end

function resolve_path(src, path)
    if path == nil then return nil end
    
    -- [[ NEW FEATURE: Detect Math Equations ]]
    -- Check if it starts with "(" and ends with ")"
    if type(path) == "string" and (path:match("^%b()$") or path:match("@")) then
        return evaluate_math(src, path)
    end
    -- [[ END NEW FEATURE ]]

    if type(path) ~= "string" then return path end
    
    -- ... (Rest of your existing logic) ...
    local parts = split(path, ".")
    local root_key = parts[1]
    local current_val = nil

    if src.scene_item and type(src.scene_item[root_key]) == "function" then
        current_val = src.scene_item[root_key]()
    elseif src.vars and src.vars[root_key] ~= nil then
        current_val = src.vars[root_key]
    else
        return tonumber(path) or path
    end

    for i = 2, #parts do
        if type(current_val) == "table" then
            current_val = current_val[parts[i]]
        else
            return nil 
        end
    end

    return current_val
end
SCRIPT_FUNCS= {
    -- Usage: @random(min, max)
    random = function(src, min, max)
        return math.random(tonumber(min) or 0, tonumber(max) or 100) 
    end,
    
    -- Usage: @sin(value)
    sin = function(src, val) 
        return math.sin(tonumber(val) or 0) 
    end,
    asin= function(src, val) 
        return math.asin(tonumber(val) or 0) 
    end,
    sinh= function(src, val) 
        return math.sinh(tonumber(val) or 0) 
    end,

    -- Usage: @time() -> returns seconds since start
    time = function(src) 
        return os.clock() 
    end,
    
    -- Usage: @round(value)
    round = function(src, val) 
        local n = tonumber(val) or 0
        return math.floor(n + 0.5)
    end,

    -- Usage: @abs(value)
    abs = function(src, val) 
        return math.abs(tonumber(val) or 0) 
    end,

    -- Usage: @min(value1, value2)
    min = function(src, val1, val2) 
        return math.min(tonumber(val1) or 0, tonumber(val2) or 0) 
    end,
    -- Usage: @max(value1, value2)
    max = function(src, val1, val2) 
        return math.max(tonumber(val1) or 0, tonumber(val2) or 0) 
    end,

    floor = function(src, val)
        return math.floor(tonumber(val) or 0)
    end,
    ceil = function(src, val)
        return math.ceil(tonumber(val) or 0)
    end,
    cos = function(src, val)
        return math.cos(tonumber(val) or 0)
    end,
    acos= function(src, val)
        return math.acos(tonumber(val) or 0)
    end,
    cosh= function(src, val)
        return math.cosh(tonumber(val) or 0)
    end,
    tan = function(src, val)
        return math.tan(tonumber(val) or 0)
    end,
    atan= function(src, val)
        return math.atan(tonumber(val) or 0)
    end,
    atan2 = function(src, y, x)
        return math.atan2(tonumber(y) or 0, tonumber(x) or 0)
    end,
    tanh= function(src, val)
        return math.tanh(tonumber(val) or 0)
    end,
    exp= function(src, val)
        return math.exp(tonumber(val) or 0)
    end,
    log= function(src, val)
        return math.log(tonumber(val) or 1)
    end,
    fmod= function(src, val1, val2)
        return math.fmod(tonumber(val1) or 0, tonumber(val2) or 1)
    end,
    deg= function(src, val)
        return math.deg(tonumber(val) or 0)
    end,
    rad= function(src, val)
        return math.rad(tonumber(val) or 0)
    end,
    sqrt= function(src, val)
        return math.sqrt(tonumber(val) or 0)
    end,
    modf= function(src, val)
        return math.modf(tonumber(val) or 0)
    end,
    pow= function(src, base, exp)
        return math.pow(tonumber(base) or 0, tonumber(exp) or 0)
    end,
    ldexp= function(src, m, e)
        return math.ldexp(tonumber(m) or 0, tonumber(e) or 0)
    end,
    frexp= function(src, val)
        return math.frexp(tonumber(val) or 0)
    end,
    alert= function(src, msg)
        obslua.script_log(obslua.LOG_WARNING, "[4IM3-Script] " .. tostring(msg))
        return 0
    end,
    dist = function(src, x1, y1, x2, y2)
        local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
        local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
        return math.sqrt(dx*dx + dy*dy)
    end,
    

}
-- [[ NEW HELPER: Math Evaluator ]]
function evaluate_math(src, expr)
    if not expr then return 0 end
    
    local working_expr = expr:match("^%((.*)%)$") or expr

    -- [[ FIX: Added extra () around %b() to capture the arguments ]]
    working_expr = working_expr:gsub("@(%w+)(%b())", function(func_name, args_block)
        local func = SCRIPT_FUNCS[func_name]
        if not func then return 0 end

        -- Now args_block is valid (e.g., "(1, 2)")
        local clean_args = args_block:sub(2, -2)
        local resolved_args = {}
        
        for arg in string.gmatch(clean_args, "([^,]+)") do
            arg = arg:match("^%s*(.-)%s*$")
            table.insert(resolved_args, resolve_path(src, arg))
        end

        return func(src, unpack(resolved_args))
    end)

    -- Variable replacement logic (Existing)
    working_expr = working_expr:gsub("([%a_][%w_%.]*)", function(var_name)
        if var_name == "math" or var_name == "floor" or var_name == "ceil" then return var_name end
        if tonumber(var_name) then return var_name end 
        
        local val = resolve_path(src, var_name)
        return tonumber(val) or 0
    end)

    local func = load("return " .. working_expr)
    if func then
        local success, result = pcall(func)
        if success then return result end
    end
    
    return 0
end
-- [[ 4IM3 FUNCTION REGISTRY ]] --

-- !log | message_or_var
-- Prints to the OBS Script Log for easier debugging
-- !log | property_or_var_or_msg


-- [[ 3. MAIN SCRIPT SETUP ]] --

function setup()
    local _= obs.script.filter({
        name= "4IM3-SCRIPT (ver| 1.0.0)", id="4im3_script_source_filter_ver2",
    })
    function _.defaults(settings)
        settings.str("output","text", true)
        settings.str("code","", true)
        settings.str("input","", true)
    end
    function _.properties(src)
        local p= obs.script.create()
        local opt= obs.script.options(p, "output","")
        opt.add.str("< OUTPUT: TEXT >","text").add.str(
            "< OUTPUT: INPUT >","input"
        ).add.str("< OUTPUT: FILE >","file")
        local text= obs.script.input(p,  "text", "", obs.enum.text.textarea)
        local input= obs.script.input(p, "input", "")
        local file= obs.script.path(p, "file", "")
        file.hide();input.hide();text.hide()
        local run= obs.script.button(p,"run_code", "Execute", function()
            run_code(src, src.settings)
        end)
        local function init_show(value)
            if value == "text" then
                text.show();input.hide();file.hide()
            elseif value == "input" then
                text.hide();input.show();file.hide()
            elseif value == "file" then
                text.hide();input.hide();file.show()
            end
        end
        opt.onchange(function(value)
            init_show(value)
            return true
        end)
        init_show(src.settings.str("output"))
        return p
    end
    function _.destroy(src)
        if src and src.scene_item and src.scene_item.data then
            src.scene_item.free()
        end
    end
    function _.finally(src)
        -- Initialize the API wrapper 'obj_source_t'
        local scene_item = obs.front:weak_source(src.source)
        if not scene_item then 
            return 
        end        
        src.transform= scene_item.transform()
        local pos= scene_item.pos()
        src.style= scene_item.style.get()
        src.defaultX= pos.x;src.defaultY= pos.y
        src.defaultWidth= scene_item.width();src.defaultHeight= scene_item.height()
        local scale= scene_item.scale()
        if scale then src.defaultScaleX= scale.x;src.defaultScaleY= scale.y end
        local bounds= scene_item.bounds()
        src.defaultBoundsX= bounds.x;src.defaultBoundsY= bounds.y
        src.defaultCrop= scene_item.crop()
        src.scene_item = scene_item
        -- Auto-run code on initialization
        run_code(src, src.settings)
    end

    function _.tick(src)
        if not src.isInitialized or not src.queue then return end
        
        -- [[ 1. ASYNC TASKS (Parallel) ]] --
        if src.async_tasks then
            for i = #src.async_tasks, 1, -1 do
                local task = src.async_tasks[i]
                if not task.exe then task.exe = compile_line(task.cmd, task.args) end
                
                if task.exe then
                    -- Async tasks run once per frame (usually fine for backgrounds)
                    local is_finished = task.exe(src, task.state)
                    if is_finished then table.remove(src.async_tasks, i) end
                end
            end
        end

        -- [[ 2. MAIN QUEUE (Instant Batch Processing) ]] --
        if not src.filter or not src.isAlive or not obslua.obs_source_enabled(src.filter) then return end
        
        local safety_brake = 0
        local MAX_OPS = 100 -- Prevents infinite loops from freezing OBS
        
        -- LOOP: Keep running commands until we hit a "Wait" or "Animation"
        while src.queue[src.current_idx] do
            
            -- Safety: If we run too many lines in one frame (infinite loop), force a break
            if safety_brake > MAX_OPS then 
                break 
            end
            
            local execute_func = src.queue[src.current_idx]
            local result, target = execute_func(src)

            -- CASE 1: BLOCKING (Animation in progress)
            -- If function returns FALSE, it means "I am not done yet, come back next frame"
            if result == false then
                break -- Stop processing for this frame
            end

            -- CASE 2: INSTANT (Logic/Math/Jumps)
            -- If function returns TRUE/JUMP/RESET, we move to the next line IMMEDIATELY
            safety_brake = safety_brake + 1
            
            if result == "RESET" then
                src.current_idx = 1
                src.state = {}
                
            elseif result == "JUMP" then
                local jump_index = src.labels[target]
                if jump_index then
                    src.current_idx = jump_index
                else
                    src.current_idx = src.current_idx + 1
                end
                src.state = {}
                
            elseif result == true then
                src.current_idx = src.current_idx + 1
                src.state = {}
            end
            
            -- If we reached the end of the script, stop
            if src.current_idx > #src.queue then break end
        end
    end




    -- [[ RUN CODE ]]
    function run_code(src, settings)
        local raw_code = ""
        local output_type = settings.str("output")
        if output_type == "text" then raw_code = settings.str("text")
        elseif output_type == "input" then raw_code = settings.str("input")
        elseif output_type == "file" then
            local file_path = settings.str("file")
            local file = io.open(file_path, "r")
            if file then raw_code = file:read("*all"); file:close() end
        end

        -- [[ 1. CLEAN & PREPARE ]] --
        src.queue = {}
        src.labels = {}
        src.async_tasks = {}
        src.current_idx = 1
        src.state = {}
        src.vars = src.vars or { screen = obs.scene:size() }

        -- Clean comments
        local clean_lines = {}
        for line in raw_code:gmatch("([^\r\n]*)\r?\n?") do
            local result_line = line
            local search_start = 1
            while true do
                local s, e = string.find(result_line, "%-%-", search_start)
                if not s then break end
                local char_before = (s > 1) and string.sub(result_line, s-1, s-1) or ""
                if char_before == "|" or char_before == ":" or char_before == "," then
                    search_start = e + 1
                else
                    result_line = string.sub(result_line, 1, s-1)
                    break
                end
            end
            table.insert(clean_lines, result_line)
        end
        local code = table.concat(clean_lines, "\n")
        
        -- [[ 2. COMPILE ]] --
        local steps = split(code, "|+|")
        for _, step in ipairs(steps) do
            local clean_step = step:match("^%s*(.-)%s*$")
            
            if clean_step ~= "" and clean_step:sub(1,1) == "!" then
                -- Parse command structure
                local parts = split(clean_step:sub(2), "|")
                local cmd = parts[1]
                table.remove(parts, 1) 
                
                -- Pre-calculate Label Index
                if cmd == "label" and parts[1] then
                    local label_name = parts[1]:match("^%s*(.-)%s*$")
                    if not src.labels[label_name] then
                        src.labels[label_name] = #src.queue + 1 -- Point to next instruction
                    end
                end

                -- COMPILATION: Create the closure
                local compiled_func = compile_line(cmd, parts)
                
                if compiled_func then
                    table.insert(src.queue, compiled_func)
                else
                    -- Insert a dummy no-op if compilation failed to keep index sync
                    table.insert(src.queue, function() return true end)
                end
            end
        end
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

	obs={
        utils={
            scheduled={},script_shutdown=false,
            OBS_SCENEITEM_TYPE = 1;OBS_SRC_TYPE = 2;OBS_OBJ_TYPE = 3;
            OBS_ARR_TYPE = 4;OBS_SCENE_TYPE = 5;OBS_SCENEITEM_LIST_TYPE = 6,
            OBS_SRC_LIST_TYPE = 7;OBS_UN_IN_TYPE = -1;OBS_SRC_WEAK_TYPE=8,
            table={},expect_wrapper={},properties={
                list={};options={};
            },filters={}
        },time={},
        scene={};client={};mem={freeup={}};script={},
        enum={
            path={
                read=obslua.OBS_PATH_FILE;write=obslua.OBS_PATH_FILE_SAVE;folder=obslua.OBS_PATH_DIRECTORY
            };
            button={
                default=obslua.OBS_BUTTON_DEFAULT;url=obslua.OBS_BUTTON_URL;
            };list={
                string=obslua.OBS_EDITABLE_LIST_TYPE_STRINGS;
                url=obslua.OBS_EDITABLE_LIST_TYPE_FILES_AND_URLS;
                file=obslua.OBS_EDITABLE_LIST_TYPE_FILES
            };
            text={
                error=obslua.OBS_TEXT_INFO_ERROR;
                default=obslua.OBS_TEXT_INFO;
                warn=obslua.OBS_TEXT_INFO_WARNING;
                input=obslua.OBS_TEXT_DEFAULT;password=obslua.OBS_TEXT_PASSWORD;
                textarea=obslua.OBS_TEXT_MULTILINE;
            };group={
                normal= obslua.OBS_GROUP_NORMAL;checked= obslua.OBS_GROUP_CHECKABLE;
            };options={
                string=obslua.OBS_COMBO_FORMAT_STRING; int=obslua.OBS_COMBO_FORMAT_INT;
                float=obslua.OBS_COMBO_FORMAT_FLOAT;bool=obslua.OBS_COMBO_FORMAT_BOOL;
                edit=obslua.OBS_COMBO_TYPE_EDITABLE;default=obslua.OBS_COMBO_TYPE_LIST;
                radio=obslua.OBS_COMBO_TYPE_RADIO;
            };number={
                int=obslua.OBS_COMBO_FORMAT_INT;float=obslua.OBS_COMBO_FORMAT_FLOAT;
                slider=1000;input=2000
            },bound={
                none= obslua.OBS_BOUNDS_NONE;
                scale_inner= obslua.OBS_BOUNDS_SCALE_INNER;
                scale_outer= obslua.OBS_BOUNDS_SCALE_OUTER;
                stretch= obslua.OBS_BOUNDS_STRETCH;
                scale_width= obslua.OBS_BOUNDS_SCALE_WIDTH;
                scale_height= obslua.OBS_BOUNDS_SCALE_HEIGHT;
                max= obslua.OBS_BOUNDS_MAX_ONLY;
            }
        },register={
            hotkey_id_list={},event_id_list={}
        },front={},shared={}
    };
	bit= require('bit')
    os= require('os')
	-- dkjson= require('dkjson')
	math.randomseed(os.time())
	-- schedule an event
    -- [[  MEMORY MANAGE API ]]
        function obs.shared.api(named_api)
            local arr_data_t= nil
            local function init_obs_data_t()
                for _, scene_name in pairs(obs.scene:names()) do
                    local a_scene= obs.scene:get_scene(scene_name)
                    if a_scene and a_scene.source then
                        local s_data_t= obs.PairStack(
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
                                
                                arr_data_t= s_data_t.arr(named_api)
                                if not arr_data_t or arr_data_t.data == nil then
                                    arr_data_t= obs.ArrayStack()
                                    s_data_t.arr(named_api, arr_data_t.data)
                                    arr_data_t.free()
                                    arr_data_t=nil
                                end
                            end
                            s_data_t.free()
                            a_scene.free()
                        end
                    end
                end
                if not arr_data_t or arr_data_t.data == nil then
                    arr_data_t= obs.ArrayStack()
                end
            end
            init_obs_data_t()
            function arr_data_t.save()
                init_obs_data_t()
            end
            function arr_data_t.del()
                local del_count=0
                for _, scene_name in pairs(obs.scene:names()) do
                    local a_scene= obs.scene:get_scene(scene_name)
                    if a_scene and a_scene.source then
                        local s_data_t= obs.PairStack(
                            obslua.obs_source_get_settings(a_scene.source)
                        )
                        if not s_data_t or s_data_t.data == nil then
                            a_scene.free()
                        else
                            s_data_t.del(named_api)
                            del_count=del_count+1
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
                local args = {...}
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
                local free_count=0
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
                fallback=true
            end
            local self = nil
            self = {
                index = 0;get = function(index)
                    if type(index) ~= "number" or index < 0 or index > self.size() then
                        return nil
                    end
                    return obs.PairStack(obslua.obs_data_array_item(self.data, index), nil, true)
                end;next = obs.expect(function(__index)
                    if type(self.index) ~= "number" or self.index < 0 or self.index > self.size() then
                        return assert(false,"[ArrayStack] Invalid data provided or corrupted data for (" .. tostring(name)..")")
                    end
                    return coroutine.wrap(function()
                        if self.size() <= 0 then
                            return nil
                        end
                        local i =0
                        if __index == nil or type(__index) ~= "number" or __index < 0 or __index > self.size() then
                            __index=0
                        end
                        for i=__index, self.size()-1 do
                            coroutine.yield(i, obs.PairStack(
                                obslua.obs_data_array_item(self.data, i), nil, false
                            ))
                        end
                    end)
                    -- local temp = self.index;self.index = self.index + 1
                    -- return obs.PairStack(obslua.obs_data_array_item(self.data, temp), nil, true)
                end);find= function(key, value)
                    local index=0
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
                end;
                
                free = function()
                    if self.data == nil or unsafe then
                        return false
                    end
                    obslua.obs_data_array_release(self.data)
                    self.data = nil
                    return true
                end;insert = obs.expect(function(value)
                    if type(value) ~= "userdata" and type(value) == "table" and value["data"] and type(value["data"]) == "userdata" then
                        value= value.data
                    end
                    if value == nil or type(value) ~= "userdata" then
                        obslua.script_log("FAILED TO INSERT OBJECT INTO [ArrayStack]")
                        return false
                    end
                    obslua.obs_data_array_push_back(self.data, value)
                    return self
                end); size = obs.expect(function()

                    if self.data == nil then
                        return 0
                    end
                    return obslua.obs_data_array_count(self.data);
                end); rm= obs.expect(function(idx)
                    if type(idx) ~= "number" or idx < 0 or self.size() <=0 or idx > self.size() then
                        obslua.script_log("FAILED TO RM DATA FROM [ArrayStack] (INVALID INDEX)")
                        return false
                    end
                    obslua.obs_data_array_erase(self.data, idx)
                    return self
                end)
            }
            if stack and name  then
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
                    interval= nil
                else
                    return
                end
                
                -- Safety check
                if obs.utils.script_shutdown or type(scheduler_callback) ~= "function" then
                    return
                end
                return scheduler_callback(scheduler_callback)
            end
            local interval_list= {}
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
                end;
                clear = function()
                    if interval ~= nil then
                        obslua.timer_remove(interval)
                        interval= nil
                    end
                end;
                update=function(timeout_t)
                    if type(timeout_t) ~= "number" or timeout_t < 0 then
                        obslua.script_log(obslua.LOG_ERROR, "[Scheduler] invalid timeout value")
                        return false
                    end
                    if type(interval) ~= "function" then
                        obslua.script_log(obslua.LOG_ERROR, "[Scheduler] invalid callback function")
                        return false
                    end
                    obslua.timer_remove(interval)
                    timeout= timeout_t
                    obslua.timer_add(interval, timeout)
                    return self
                end
            }
            return self
        end

        function obs.time.tick(fn, interval)
            local tm= nil
            local wrapper = function()
                if obs.utils.script_shutdown then return end
                return fn(tm, os.clock())
            end
            if not interval or type(interval) ~= "number" or interval == 0 or (interval <= 0 and not interval > 0) then
                interval=0.001
            end
            tm={
                clear=function()
                    return obslua.timer_remove(wrapper)
                end
            }
            obslua.timer_add(wrapper, interval)
            return tm
        end

        function obs.wrap(self)
            if not self or self == nil then
                self = {type= obs.utils.OBS_UN_IN_TYPE, data=nil, item= nil}
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
                -- 1. Shutdown Guard
                if obs.utils.script_shutdown then return end
                
                -- 2. Validity Guard
                if self.released or not self.data then return end

                -- 3. Borrowed/Unsafe Guard (Do NOT free if unsafe=true)
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

            if not self.unsafe then
                table.insert(obs.utils.expect_wrapper, self)
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
                end, json = function(p)
                    if not p then return obslua.obs_data_get_json(self.data) else
                    return obslua.obs_data_get_json_pretty(self.data) end
                end,
                -- ... (rest of PairStack methods are fine) ...
                str = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_str(name) end
                    if self.data and name then
                         if def then obslua.obs_data_set_default_string(self.data, name, value)
                         else obslua.obs_data_set_string(self.data, name, value) end
                    end
                    return self
                end);
                int = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_int(name) end
                    if self.data and name then
                        if def then obslua.obs_data_set_default_int(self.data, name, value)
                        else obslua.obs_data_set_int(self.data, name, value) end
                    end
                    return self
                end);
                dbl = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_dbl(name) end
                    if self.data and name then
                        if def then obslua.obs_data_set_default_double(self.data, name, value)
                        else obslua.obs_data_set_double(self.data, name, value) end
                    end
                    return self
                end);
                bul = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_bul(name) end
                    if self.data and name then
                        if def then obslua.obs_data_set_default_bool(self.data, name, value)
                        else obslua.obs_data_set_bool(self.data, name, value) end
                    end
                    return self
                end);
                arr = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_arr(name) end
                    -- Unwrap wrapper if passed
                    if type(value) ~= "userdata" and type(value) == "table" and value["data"] then value = value.data end
                    if self.data and name and value then
                         if def then obslua.obs_data_set_default_array(self.data, name, value)
                         else obslua.obs_data_set_array(self.data, name, value) end
                    end
                    return self
                end);
                obj = obs.expect(function(name, value, def)
                    if name and value == nil then return self.get_obj(name) end
                    if type(value) ~= "userdata" and type(value) == "table" and value["data"] then value = value.data end
                    if self.data and name and value then
                        if def then obslua.obs_data_set_default_obj(self.data, name, value)
                        else obslua.obs_data_set_obj(self.data, name, value) end
                    end
                    return self
                end);
                
                -- Getters (Simplified for brevity, logic unchanged)
                get_str = obs.expect(function(name, def) return def and obslua.obs_data_get_default_string(self.data, name) or obslua.obs_data_get_string(self.data, name) end);
                get_int = obs.expect(function(name, def) return def and obslua.obs_data_get_default_int(self.data, name) or obslua.obs_data_get_int(self.data, name) end);
                get_dbl = obs.expect(function(name, def) return def and obslua.obs_data_get_default_double(self.data, name) or obslua.obs_data_get_double(self.data, name) end);
                get_bul = obs.expect(function(name, def) return def and obslua.obs_data_get_default_bool(self.data, name) or obslua.obs_data_get_bool(self.data, name) end);
                get_obj = obs.expect(function(name, def) 
                    local res = def and obslua.obs_data_get_default_obj(self.data, name) or obslua.obs_data_get_obj(self.data, name)
                    return obs.PairStack(res, nil, false) -- Return safe wrapper
                end);
                get_arr = obs.expect(function(name, def)
                    local res = def and obslua.obs_data_get_default_array(self.data, name) or obslua.obs_data_get_array(self.data, name)
                    return obs.ArrayStack(res, nil, false)
                end);
                del = obs.expect(function(name) obslua.obs_data_erase(self.data, name) return true end);
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
            local script_path_value= script_path()
            unique_id= tostring(script_path_value) .. "_" .. tostring(unique_id)
            local hotkey_id= obslua.obs_hotkey_register_frontend(
                unique_id, title, callback
            )
            -- load from data
            local hotkey_load_data= obs.utils.settings.get_arr(unique_id);
            if hotkey_load_data and hotkey_load_data.data ~= nil then
                obslua.obs_hotkey_load(hotkey_id, hotkey_load_data.data)
                hotkey_load_data.free()
            end
            obs.register.hotkey_id_list[unique_id]= {
                id= hotkey_id, title= title, callback= callback,
                remove=function(rss)
                    if rss == nil then
                        rss= false
                    end
                    -- obs.utils.settings.del(unique_id)
                    if rss then
                        if obs.register.hotkey_id_list[unique_id] and type(obs.register.hotkey_id_list[unique_id].callback) == "function" then
                            obslua.obs_hotkey_unregister(
                                obs.register.hotkey_id_list[unique_id].callback
                            )
                        end
                    end
                    obs.register.hotkey_id_list[unique_id]= nil
                end
            }
            return obs.register.hotkey_id_list[unique_id]
        end
        function obs.register.get_hotkey(unique_id)
            unique_id= tostring(script_path()) .. "_" .. tostring(unique_id)
            if obs.register.hotkey_id_list[unique_id] then
                return obs.register.hotkey_id_list[unique_id]
            end
            return nil
        end
        function obs.register.event(unique_id, callback)
            if not callback and unique_id and type(unique_id) == "function" then
                callback= unique_id
                unique_id= tostring(script_path()) .. "_" .. obs.utils.get_unique_id(3) .. "_event"
            else
                unique_id= tostring(script_path()) .. "_" .. tostring(unique_id) .. "_event"
            end
            if type(callback) ~= "function" then
                obslua.script_log(obslua.LOG_ERROR, "[OBS REGISTER EVENT] Invalid callback provided")
                return nil
            end
            local event_id= obslua.obs_frontend_add_event_callback(callback)
            obs.register.event_id_list[unique_id]= {
                id= event_id,callback= callback,
                unique_id= unique_id,
                remove= function(rss)
                    if rss == nil then
                        rss= false
                    end
                    if rss then obslua.obs_frontend_remove_event_callback(callback) end
                    obs.register.event_id_list[unique_id]= nil
                end
            };
            
        end
        function obs.register.get_event(unique_id)
            unique_id= tostring(script_path()) .. "_" .. tostring(unique_id) .. "_event"
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
                    -- 1. Check custom create logic
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

                    -- 2. Default creation
                    local src = {
                        filter = source, source = nil,
                        params = nil,height = 0,  width = 0,
                        isAlive = true, -- explicit alive flag
                        settings = obs.PairStack(settings, nil, nil, true),aliveScheduledEvents= {},
                    }

                    -- 3. Initial sizing (Safe check)
                    if source ~= nil then
                        local target = obslua.obs_filter_get_parent(source)
                        if target ~= nil then
                            src.source= target
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
                    src.shader= obslua.gs_effect_create(shader, nil, nil)
                    obslua.obs_leave_graphics()
					if src.shader ~= nil then
						src.params= {
							width= obslua.gs_effect_get_param_by_name(src.shader, "width"),
							height= obslua.gs_effect_get_param_by_name(src.shader, "height"),
							image= obslua.gs_effect_get_param_by_name(src.shader, "image"),
						}
					else
						return self.destroy()
					end

                    if filter and filter["setup"] and type(filter["setup"]) == "function" then
                        filter.setup(src)
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
                        src.isInitialized= true
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
                        src.width=0;src.height=0
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
                        local width= src.width;local height= src.height
                        if not obslua.obs_source_process_filter_begin(
                            src.filter,obslua.GS_RGBA, obslua.OBS_NO_DIRECT_RENDERING
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
            local scene;local source_scene;
            if not scene_name or not type(scene_name) == "string" then
                source_scene=obslua.obs_frontend_get_current_scene()
                if not source_scene then
                    return nil
                end
                scene= obslua.obs_scene_from_source(source_scene)
            else
                source_scene= obslua.obs_get_source_by_name(scene_name)
                if not source_scene then
                    return nil
                end
                scene=obslua.obs_scene_from_source(source_scene)
            end
            local obj_scene_t;obj_scene_t= {
                group_names=function()
                    local scene_items_list = obs.wrap({
                        data= obslua.obs_scene_enum_items(scene),
                        type=obs.utils.OBS_SCENEITEM_LIST_TYPE
                    })
                    if scene_items_list == nil or scene_items_list.data == nil then
                        return nil
                    end
                    local list={}
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
                end;source_names=function(source_id_type)
                    local scene_nodes_name_list= {}
                    local scene_items_list = obs.wrap({
                        data=obslua.obs_scene_enum_items(scene),
                        type=obs.utils.OBS_SCENEITEM_LIST_TYPE
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
                            source= nil
                        end
                    end
                    scene_items_list.free()
                    return scene_nodes_name_list
                end;get= function(source_name)
                    if not scene  then
                        return nil
                    end
                    local c=1
                    local scene_item;local scene_items_list = obs.wrap({
                        data=obslua.obs_scene_enum_items(scene),
                        type=obs.utils.OBS_SCENEITEM_LIST_TYPE
                    })
                    if scene_items_list == nil or scene_items_list.data == nil then
                        return nil
                    end
                    for _, item in ipairs(scene_items_list.data) do
                        c = c + 1
                        local src= obslua.obs_sceneitem_get_source(item)
                        local src_name= obslua.obs_source_get_name(src)
                        if src ~= nil and src_name == source_name then
                            obslua.obs_sceneitem_addref(item)
                            scene_item= obs.wrap({
                                data=item, type=obs.utils.OBS_SCENEITEM_TYPE, 
                                name=source_name
                            })
                            break
                        end
                    end
                    scene_items_list.free()
                    if scene_item == nil or scene_item.data == nil then
                        return nil
                    end
                    local obj_source_t;

                    obj_source_t={
                        free=scene_item.free;
                        item=scene_item.data;
                        data=scene_item.data;

                        align = function(val)
                            if not obj_source_t or not obj_source_t.data then return nil end
                            _cached_info = obslua.obs_transform_info(),
                            obslua.obs_sceneitem_get_info2(obj_source_t.data, _cached_info)
                            
                            if val == nil then return _cached_info.alignment end
                            
                            _cached_info.alignment = val
                            obslua.obs_sceneitem_set_info2(obj_source_t.data, _cached_info)
                            return true
                        end,
                        crop = function(c)
                            if not obj_source_t or not obj_source_t.data then return nil end
                            local crop= obslua.obs_sceneitem_crop()
                            obslua.obs_sceneitem_get_crop(obj_source_t.data, crop)
                            
                            if c == nil then return crop end
                            
                            if c.top then crop.top = c.top end
                            if c.bottom then crop.bottom = c.bottom end
                            if c.left then crop.left = c.left end
                            if c.right then crop.right = c.right end
                            obslua.obs_sceneitem_set_crop(obj_source_t.data, crop)
                            return true
                        end,
                        filter = function(name_or_id)
                            return obj_source_t._safe_run(function()
                                local source = obj_source_t.get_source()
                                if not source then return nil end
                                -- 1. Try to find by NAME first (fastest)
                                local found_ptr = obslua.obs_source_get_filter_by_name(source, name_or_id)
                                local filter_wrapper= nil
                                -- 2. If not found by name, try to find by ID (Fallback)
                                if not found_ptr then
                                    local fb = function(parent, filter, param)
                                        local id = obslua.obs_source_get_unversioned_id(filter)
                                        if id == name_or_id then
                                            -- Increment reference since we are keeping it
                                            -- obslua.obs_weak_source_addref(filter) 
                                            found_ptr = obslua.obs_source_get_ref(filter)
                                            return true -- Stop searching
                                        end
                                        return false -- Keep searching
                                    end
                                    local filter_list = obs.wrap({data=obslua.obs_source_enum_filters(source), type=obs.utils.OBS_SRC_LIST_TYPE})
                                    for _, filter in ipairs(filter_list.data) do
                                        if fb(source, filter, nil) then
                                            break
                                        end
                                    end
                                    filter_list.free()
                                    -- if found_ptr then
                                    --     filter_wrapper = obs.wrap({ data = found_ptr, type = obs.utils.OBS_SRC_WEAK_TYPE})
                                    -- end
                                    
                                end

                                -- If still nothing, give up
                                if not found_ptr then return nil end
                                
                                -- 3. Wrap the result
                                filter_wrapper = obs.wrap({ data = found_ptr, type = obs.utils.OBS_SRC_TYPE})
                                
                                -- We must release our manual reference because obs.wrap takes ownership 
                                -- (or rather, we treat the wrapper as the owner now). 
                                -- However, standard obs.wrap usually adds its own ref or expects one. 
                                -- *Crucial Note:* obs_source_get_filter_by_name returns a NEW reference. 
                                -- Our enum fallback manually added a reference. So we are consistent.
                                -- obslua.obs_source_release(found_ptr) -- RELEASED via wrapper now
                                if not filter_wrapper or not filter_wrapper.data then return nil end

                                local self;self= {
                                    remove = function()
                                        obslua.obs_source_filter_remove(source, filter_wrapper.data)
                                        self.free()
                                        self = nil
                                        return true
                                    end,
                                    commit= function()
                                        if self.settings and self.settings.data then 
                                            obslua.obs_source_update(filter_wrapper.data, self.settings.data)
                                        end
                                        return true
                                    end,
                                    free = function()
                                        if self.settings and self.settings.data then 
                                            self.settings.free() 
                                        end
                                        if filter_wrapper and filter_wrapper.data then
                                            filter_wrapper.free()
                                            filter_wrapper = nil
                                        end
                                    end,
                                    settings = obs.PairStack(
                                        obslua.obs_source_get_settings(filter_wrapper.data)
                                    ),
                                    id= function()
                                        return obslua.obs_source_get_unversioned_id(filter_wrapper.data)
                                    end,
                                }
                                return self
                            end)
                        end,
                        -- [[ SAFETY & OPTIMIZATION VARIABLES ]]
                        -- 1. Create the transform object ONCE to prevent memory leaks/crashes
                        _cached_info = obslua.obs_transform_info(),
                        
                        -- 2. Busy flag to prevent race conditions (The "Lock")
                        _busy = false,

                        -- [[ HELPER: SAFE EXECUTION WRAPPER ]]
                        -- This handles the locking mechanism automatically for all functions
                        _safe_run = function(func)
                            -- If busy (locked) or shutting down, SKIP execution to prevent crash
                            if obj_source_t._busy or (obs and obs.utils and obs.utils.script_shutdown) then
                                return nil
                            end
                            
                            if not obj_source_t.data then return nil end

                            -- Lock
                            obj_source_t._busy = true
                            
                            -- Run the function safely (pcall ensures we unlock even if it fails)
                            local status, result = pcall(func)

                            
                            -- Unlock
                            obj_source_t._busy = false
                            
                            if not status then
                                return nil
                            end
                            return result
                        end,

                        -- [[ METHODS ]]
                        pos = function(pos)
                            return obj_source_t._safe_run(function()
                                -- Reuse the cached transform object instead of creating a new one
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                -- Getter Mode
                                if pos == nil or not (type(pos) == "table") or (pos.x == nil and pos.y == nil) then
                                    return {x = info.pos.x, y = info.pos.y}
                                end

                                -- Setter Mode
                                if type(pos.x) == "number" then info.pos.x = pos.x end
                                if type(pos.y) == "number" then info.pos.y = pos.y end
                                
                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,

                        scale = function(scale)
                            return obj_source_t._safe_run(function()
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                -- Getter
                                if scale == nil or not (type(scale) == "table") or (scale.x == nil and scale.y == nil) then
                                    return {x = info.scale.x, y = info.scale.y}
                                end

                                -- Setter
                                if type(scale.x) == "number" then info.scale.x = scale.x end
                                if type(scale.y) == "number" then info.scale.y = scale.y end
                                
                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,

                        rot = function(val)
                            return obj_source_t._safe_run(function()
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                if val == nil then
                                    return info.rot
                                end
                                
                                info.rot = val
                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,

                        transform = function(tf)
                            return obj_source_t._safe_run(function()
                                -- Note: transform returns the C-object, which we shouldn't really expose directly
                                -- but to keep your logic logic:
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                if not tf then
                                    -- Return a COPY of the data to avoid leaking the internal pointer
                                    -- (Or return specific fields if possible)
                                    return info 
                                end
                                obslua.obs_sceneitem_set_info2(obj_source_t.data, tf)
                                return true
                            end)
                        end,

                        bounds = function(size)
                            return obj_source_t._safe_run(function()
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                -- Getter
                                if size == nil or not (type(size) == "table") then
                                    return {x = info.bounds.x, y = info.bounds.y}
                                end
                                
                                -- Setter
                                if type(size.x) == "number" then info.bounds.x = size.x end
                                if type(size.y) == "number" then info.bounds.y = size.y end
                                
                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,

                        width = function(val)
                            return obj_source_t._safe_run(function()
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                local is_bounded = info.bounds_type ~= obslua.OBS_BOUNDS_NONE
                                local base_w = obslua.obs_source_get_base_width(obj_source_t.get_source())

                                -- Getter
                                if val == nil then
                                    return is_bounded and info.bounds.x or (base_w * info.scale.x)
                                end

                                -- Setter
                                if is_bounded then
                                    info.bounds.x = val
                                else
                                    if base_w > 0 then info.scale.x = val / base_w end
                                end

                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,

                        height = function(val)
                            return obj_source_t._safe_run(function()
                                local info = obslua.obs_transform_info()
                                obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                                
                                local is_bounded = info.bounds_type ~= obslua.OBS_BOUNDS_NONE
                                local base_h = obslua.obs_source_get_base_height(obj_source_t.get_source())

                                -- Getter
                                if val == nil then
                                    return is_bounded and info.bounds.y or (base_h * info.scale.y)
                                end

                                -- Setter
                                if is_bounded then
                                    info.bounds.y = val
                                else
                                    if base_h > 0 then info.scale.y = val / base_h end
                                end

                                obslua.obs_sceneitem_set_info2(obj_source_t.data, info)
                                return true
                            end)
                        end,
                        get_source=function()
                            return obslua.obs_sceneitem_get_source(scene_item.data)
                        end;get_name= function()
                            return obslua.obs_source_get_name(obj_source_t.get_source())
                        end, 
                        bounding = function()
                            if not obj_source_t or not obj_source_t.data then return 0 end
                            local info = obslua.obs_transform_info()
                            obslua.obs_sceneitem_get_info2(obj_source_t.data, info)
                            -- 0 = No Bounds, 2 = Stretch to bounds
                            local temp=info.bounds_type
                            info=nil
                            return temp
                        end,
                        remove= function()
                            if obj_source_t.data == nil then return true end
                            
                            obslua.obs_sceneitem_remove(obj_source_t.data)
                            obj_source_t.free();obj_source_t.data=nil;obj_source_t.item=nil
                            return true
                        end,hide= function()
                            return obslua.obs_sceneitem_set_visible(obj_source_t.data, false)
                        end,show = function()
                            return obslua.obs_sceneitem_set_visible(obj_source_t.data, true)
                        end, isHidden=function() return obslua.obs_sceneitem_visible(obj_source_t.data) end,
                        style= {
                            grad= {
                                enable= function()
                                    local src= obs.PairStack(
                                        obslua.obs_source_get_settings(obj_source_t.get_source())
                                    )
                                    if not src or not src.data then
                                        src= obs.PairStack()
                                    end
                                    src.bul("gradient", true)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end, disable= function()
                                    local src= obs.PairStack(
                                        obslua.obs_source_get_settings(obj_source_t.get_source())
                                    )
                                    if not src or not src.data then
                                        src= obs.PairStack()
                                    end
                                    src.bul("gradient", false)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end, dir= function(val)
                                    local src= obs.PairStack(
                                        obslua.obs_source_get_settings(obj_source_t.get_source())
                                    )
                                    if not src or not src.data then
                                        src= obs.PairStack()
                                    end
                                    if val == nil then
                                        local tempv= src.dbl("gradient_dir")
                                        src.free()
                                        return tempv
                                    end
                                    src.dbl("gradient_dir", val)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end, color= function(r, g, b)
                                    local src= obs.PairStack(
                                        obslua.obs_source_get_settings(obj_source_t.get_source())
                                    )
                                    if not src or not src.data then
                                        src= obs.PairStack()
                                    end
                                    if not r or not g or not b then
                                        local tempv= src.int("gradient_color")
                                        src.free()
                                        return obs.utils.argb_to_rgb(tempv)
                                    end
                                    src.int("gradient_color", obs.utils.rgb_to_argb(r, g, b))
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                    return true
                                end, opacity = function(val)
                                    local src= obs.PairStack(
                                        obslua.obs_source_get_settings(obj_source_t.get_source())
                                    )
                                    if not src or not src.data then
                                        src= obs.PairStack()
                                    end
                                    if val == nil then
                                        local tempv= src.dbl("gradient_opacity")
                                        src.free()
                                        return tempv
                                    end
                                    src.dbl("gradient_opacity", val)
                                    obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                    src.free()
                                end
                            },
                            bg_opacity= function(val)
                                local src= obs.PairStack(
                                    obslua.obs_source_get_settings(obj_source_t.get_source())
                                )
                                if not src or not src.data then
                                    src= obs.PairStack()
                                end
                                if val == nil then
                                    local tempv= src.dbl("bk_opacity")
                                    src.free()
                                    return tempv
                                end
                                src.dbl("bk_opacity", val)
                                obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                src.free()
                            end,
                            opacity= function(val)
                                local src= obs.PairStack(
                                    obslua.obs_source_get_settings(obj_source_t.get_source())
                                )
                                if not src or not src.data then
                                    src= obs.PairStack()
                                end
                                if val == nil then
                                    local tempv= src.dbl("opacity")
                                    src.free()
                                    return tempv
                                end
                                src.dbl("opacity", val)
                                obslua.obs_source_update(obj_source_t.get_source(), src.data)
                                src.free()
                            end,
                        },
                    }
                    function obj_source_t.style.bg_color(r, g, b)
                        local src= obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src= obs.PairStack()
                        end
                        if not r or not g or not b then
                            local tempv= src.int("bk_color")
                            src.free()
                            return obs.utils.argb_to_rgb(tempv)
                        end
                        src.int("bk_color", obs.utils.rgb_to_argb(r, g, b))
                        obslua.obs_source_update(obj_source_t.get_source(), src.data)
                        src.free()
                    end
                    function obj_source_t.style.color(r, g, b)
                        local src= obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src= obs.PairStack()
                        end
                        if not r or not g or not b then
                            local tempv= src.int("color")
                            src.free()
                            return obs.utils.argb_to_rgb(tempv)
                        end
                        local src= obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src= obs.PairStack()
                        end
                        src.int("color", obs.utils.rgb_to_argb(r, g, b))
                        obslua.obs_source_update(obj_source_t.get_source(), src.data)
                        src.free()
                    end
                    function obj_source_t.style.get()
                        local src= obs.PairStack(
                            obslua.obs_source_get_settings(obj_source_t.get_source())
                        )
                        if not src or not src.data then
                            src= obs.PairStack()
                        end
                        local json= src.json(true)
                        src.free()
                        return json
                    end
                    function obj_source_t.style.set(val)
                        local src= obs.PairStack(val)
                        if not src or not src.data then
                            return nil
                        end
                        obslua.obs_source_update(obj_source_t.get_source(), src.data)
                        src.free()
                    end
                    return obj_source_t
                end;add=function(source)
                    if not source then return false end
                    local sceneitem= obslua.obs_scene_add(scene, source)
                    if sceneitem == nil then return nil end
                    obslua.obs_sceneitem_addref(sceneitem)
                    local dt=obs.wrap({
                        data=sceneitem, type=obs.utils.OBS_SCENEITEM_TYPE
                    })
                    return dt
                end;get_label=function(name, source)
                    if (source == nil or source.data == nil) and name ~= nil and type(name) == "string" and name ~= "" then
                        source= obj_scene_t.get(name)
                    end
                    if not source or not source.data then
                        return nil 
                    end
                    local obj_label_t;obj_label_t={
                        font= {
                            size= function(font_size)
                                local src= obs.PairStack(
                                    obslua.obs_source_get_settings(source.get_source())
                                )
                                if not src or not src.data then
                                    src= obs.PairStack()
                                end
                                local font= src.get_obj("font")
                                if not font or not font.data then
                                    font= obs.PairStack()
                                    --font.str("face","Arial")
                                end
                                if font_size == nil or not type(font_size) == "number" or font_size <= 0 then
                                    font_size=font.get_int("size")
                                    font.free();src.free();
                                    return font_size
                                else
                                    font.int("size", font_size)
                                end
                                font.free();
                                obslua.obs_source_update(source.get_source(), src.data)
                                src.free()
                                return true
                            end;face= function(face_name)
                            end
                        };text=function(txt)
                            local src= obs.PairStack(
                                obslua.obs_source_get_settings(source.get_source())
                            )
                            if not src or not src.data then
                                src= obs.PairStack()
                            end
                            local res=true
                            if txt == nil or txt == "" or type(txt) ~= "string" then
                                res=src.get_str("text")
                                if not res == nil then
                                    res= ""
                                end
                            else
                                src.str("text", txt)
                            end
                            obslua.obs_source_update(source.get_source(), src.data)
                            src.free()
                            return res
                        end;free=function()
                            source.free()
                            obj_label_t=nil
                            return true
                        end
                    }
                    obs.utils.table.append(obj_label_t, source)                    
                    return obj_label_t
                end;
                add_label= function(name, text)
                    local src= obs.PairStack()
                    if not text then
                        text= "Text - Label"
                    end
                    src.str("text", text)
                    local source_label=obslua.obs_source_create("text_gdiplus", name, src.data, nil)
                    src.free()
                    local obj= obj_scene_t.get_label(
                        nil, obj_scene_t.add(source_label)
                    )
                    if not obj or not obj.data then 
                        if source_label then obslua.obs_source_release(source_label) end
                        return nil
                    end
                    -- re-write the release function
                    -- [[SEEM LIKE THIS LEADS TO CRUSHES?]]
                    local free_func= obj.free;
                    obj.free= function()
                        if source_label == nil or not source_label then return end
                        obslua.obs_source_release(source_label)
                        return free_func()
                    end
                    return obj
                end;add_group= function(name, refresh)
                    if refresh == nil then
                        refresh=true
                    end
                    local obj=obj_scene_t.get_group(nil, obslua.obs_scene_add_group2(scene, name, refresh))
                    if not obj or obj.data == nil then return nil end
                    obj.free=function() end

                    return obj
                end;get_group= function(name, gp)
                    local obj;if not gp and name ~= nil then
                        obj= obs.wrap({
                            data=obslua.obs_scene_get_group(scene, name), 
                            type=obs.utils.OBS_SCENEITEM_TYPE
                        })
                    elseif gp ~= nil then
                        obj= obs.wrap({
                            data=gp, type=obs.utils.OBS_SCENEITEM_TYPE
                        })
                    else
                        return nil
                    end
                    obj["add"]= function(sceneitem)
                        if not sceneitem then
                            return false
                        end
                        obslua.obs_sceneitem_group_add_item(obj.data, sceneitem)
                        return true
                    end
                    obj["release"]= function()
                        return obj.free()
                    end;obj["item"]= obj.data
                    return obj
                end;free= function()
                    if not source_scene then return end
                    obslua.obs_source_release(source_scene)
                    scene=nil
                end;release= function()
                    return obj_scene_t.free()
                end;get_width= function()
                    return obslua.obs_source_get_base_width(source_scene)
                end;get_height = function()
                    return obslua.obs_source_get_base_height(source_scene)
                end;data=scene;item=scene;source=source_scene
            };
            return obj_scene_t
        end
        function obs.scene:scene_from(source)
            if not source or type(source) == 'string' then
                return nil
            end
            local sc= obslua.obs_scene_from_source(source)
            local ss= obslua.obs_scene_get_source(sc)
            return obs.scene:get_scene(obslua.obs_source_get_name(ss))
        end
        function obs.scene:name()
            source_scene=obslua.obs_frontend_get_current_scene()
            if not source_scene then
                return nil
            end
            local source_name= obslua.obs_source_get_name(source_scene)
            obslua.obs_source_release(source_scene)
            return source_name
        end
        function obs.scene:add_to_scene(source)
            if not source then
                return false
            end
            local current_source_scene= obslua.obs_frontend_get_current_scene()
            if not current_source_scene then
                return false
            end
            local current_scene= obslua.obs_scene_from_source(current_source_scene)
            if not current_scene then
                obslua.obs_source_release(current_source_scene)
                return false
            end
            obslua.obs_scene_add(current_scene, source)
            obslua.obs_source_release(current_source_scene)
            return true
        end
        function obs.scene:names()
            local scenes= obs.wrap({
                data=obslua.obs_frontend_get_scenes(),
                type=obs.utils.OBS_SRC_LIST_TYPE
            })
            local obj_table_t= {}
            for _, a_scene in pairs(scenes.data) do
                if a_scene then
                    local scene_source_name= obslua.obs_source_get_name(a_scene)
                    table.insert(obj_table_t, scene_source_name)
                end
            end
            scenes.free()
            return obj_table_t
        end
        function obs.scene:size()
            local scene= obs.scene:get_scene()
            if not scene or not scene.data then
                return nil
            end
            local w= scene:get_width()
            local h= scene:get_height()
            scene.free()
            return {width= w, height= h}
        end
    -- [[ OBS SCENE API CUSTOM END ]]
    -- [[ OBS FRONT API ]]
        function obs.front.source_names()
            local list={}
            local all_sources= obs.wrap({
                data=obslua.obs_enum_sources(),
                type=obs.utils.OBS_SRC_LIST_TYPE
            })
            for _, source in pairs(all_sources.data) do
                if source then
                    local source_name= obslua.obs_source_get_name(source)
                    table.insert(list, source_name)
                end
            end
            all_sources.free()
            return list
        end
        function obs.front.source(source_name)
            local source=nil
            if not source_name or not type(source_name) == "string" then
                if(type(source_name) == "userdata") then
                    source= source_name
                else
                    return
                end
            else
                source=obslua.obs_get_source_by_name(source_name)
            end
            if not source then
                return nil
            end
            local dt=  obs.wrap({
                data=source, type=obs.utils.OBS_SRC_TYPE
            })
            return dt
        end
        function obs.front:weak_source(source)

            local scene;local source_name;
            if source and type(source) ~= "string" then 
                scene= obs.scene:scene_from(source)
                source_name=obslua.obs_source_get_name(source)
            elseif type(source) == "string" then
                source_name= source
                local temp= obs.front.source(source_name)
                if not temp or not temp.data then return nil end
                scene= obs.scene:scene_from(temp.get_source())
                temp.free()
            end
            if not scene or not scene.data then return end
            local sct= scene.get(source_name)
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

            obs.utils.ui= function()
                obs.utils.properties={list={};options={};}
                local p= obs.script.create(s)
                local self= {};for key, fnc in pairs(obs.script) do
                    self[key]= function(...)
                        return fnc(p, ...)
                    end
                end
                clb(self, p)
                return p
            end
            return true
        end
        function obs.script.create(settings)
            local p= obslua.obs_properties_create()
            if type(settings) == "userdata" then
                settings= obs.PairStack(settings, nil, nil, true)
            end
            obs.utils.properties[p]= settings
            return p
        end
        function obs.script.options(p, unique_id, desc, enum_type_id, enum_format_id)
            if not desc or type(desc) ~= "string" then
                desc=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            if enum_format_id == nil then
                enum_format_id= obs.enum.options.string;
            end
            if enum_type_id == nil then
                enum_type_id= obs.enum.options.default;
            end
            
            local obj=obslua.obs_properties_add_list(p, unique_id, desc, enum_type_id, enum_format_id);
            if not obj then
                obslua.script_log(obslua.LOG_ERROR, "[obsapi_custom.lua] Failed to create options property: " .. tostring(unique_id) .. " description: " .. tostring(desc) .. " enum_type_id: " .. tostring(enum_type_id) .. " enum_format_id: " .. tostring(enum_format_id))
                return nil
            end
            
            obs.utils.properties.options[unique_id]= {
                enum_format_id= enum_format_id;
                enum_type_id= enum_type_id;type=enum_format_id
            }
            obs.utils.properties[unique_id]= obs.utils.obs_api_properties_patch(obj, p)
            return obs.utils.properties[unique_id]
        end
        function obs.script.button(p, unique_id, label, callback)
            if not label or type(label) ~= "string" then
                label="button"
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            if type(callback)~="function" then callback=function() end end
            obs.utils.properties[unique_id]=obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_button(p, unique_id, label, function(properties_t, property_t)

                    return callback(
                        property_t, properties_t, 
                        obs.utils.properties[properties_t] and obs.utils.properties[properties_t] or obs.utils.settings
                    )
                end)
            ,p)
            return obs.utils.properties[unique_id]
        end
        function obs.script.label(p, unique_id, text, enum_type)
            if not text or type(text) ~= "string" then
                text=""
            end
            if not unique_id or type(unique_id) == nil or unique_id == "" or type(unique_id) ~= "string" then
                unique_id= obs.utils.get_unique_id(20)
            end
            local default_enum_type= obslua.OBS_TEXT_INFO;
            if(enum_type == nil) then
                enum_type= default_enum_type
            end
            local obj= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_text(p, unique_id, text, default_enum_type), p)
            if enum_type == obs.enum.text.error then
                obj.error(text)
            elseif enum_type == obs.enum.text.warn then
                obj.warn(text)
            end
            obj.type= enum_type;
            obs.utils.properties[unique_id]= obj
            return obj;

        end 
        function obs.script.group(p, unique_id, desc, enum_type)
            local pp= obs.script.create()
            if not desc or type(desc) ~= "string" then
                desc=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            if enum_type == nil then
                enum_type= obs.enum.group.normal;
            end
            obs.utils.properties[unique_id]= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_group(p, unique_id, desc, enum_type, pp), pp)
            obs.utils.properties[unique_id].parent= pp
            obs.utils.properties[unique_id].add={}
            for key, fnc in pairs(obs.script) do
                obs.utils.properties[unique_id].add[key]= function(...)
                    return fnc(obs.utils.properties[unique_id].parent, ...)
                end
            end
            return obs.utils.properties[unique_id]
        end
        function obs.script.bool(p, unique_id, desc)
            if not desc or type(desc) ~= "string" then
                desc=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id]=obs.utils.obs_api_properties_patch(obslua.obs_properties_add_bool(p, unique_id, desc), p)
            return obs.utils.properties[unique_id]
        end
        function obs.script.path(p, unique_id, desc, enum_type_id, filter_string, default_path_string)
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            if not desc or type(desc) ~= "string" then
                desc= ""
            end
            if enum_type_id == nil or type(enum_type_id) ~= "number" then
                enum_type_id= obs.enum.path.read
            end
            if filter_string == nil or type(filter_string) ~= "string" then
                filter_string=""
            end
            if default_path_string == nil or type(default_path_string) ~= "string" then
                default_path_string= ""
            end
            obs.utils.properties[unique_id]= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_path(p, unique_id, desc, enum_type_id, filter_string, default_path_string), p)
            return obs.utils.properties[unique_id]
        end
        function obs.script.form(properties, title, unique_id)
            local pp= obs.script.create();local __exit_click_callback__=nil;local __onexit_type__=1;
            local __cancel_click_callback__=nil;local __oncancel_type__=1;
            if unique_id == nil then
                unique_id=obs.utils.get_unique_id(20)
            end
            local group_form= obs.script.group(properties,unique_id, "", pp, obs.enum.group.normal)
            local label= obs.script.label(pp, unique_id .. "_label", title, obslua.OBS_TEXT_INFO);
            obs.script.label(pp,"form_tt","<hr/>", obslua.OBS_TEXT_INFO);
            local ipp= obs.script.create()
            local group_inner= obs.script.group(pp, unique_id .. "_inner", "", ipp, obs.enum.group.normal)
            local exit= obs.script.button(pp, unique_id .. "_exit", "Confirm",function(pp, s, ss)
                if __exit_click_callback__ and type(__exit_click_callback__) == "function" then
                    __exit_click_callback__(pp,s, obs.PairStack(ss, nil, nil, true))
                end
                if __onexit_type__ == -1 then
                    group_form.free()
                elseif __onexit_type__ == 1 then
                    group_form.hide()
                end
                return true
            end)
            local cancel= obs.script.button(pp, unique_id .. "_cancel", "Cancel", function(pp, s, ss)
                if __cancel_click_callback__ and type(__cancel_click_callback__) == "function" then
                    __cancel_click_callback__(pp,s, obs.PairStack(ss, nil, nil, true))
                end
                if __oncancel_type__ == -1 then
                    group_form.free()
                elseif __oncancel_type__ == 1 then
                    group_form.hide()
                end
                return true
            end)
            local obj_t;obj_t={
                add={
                    button= function(...)
                        return obs.script.button(ipp, ...)
                    end;options= function(...)
                        return obs.script.options(ipp,...)
                    end;label= function(...)
                        return obs.script.label(ipp,...)
                    end;group= function(...)
                        return obs.script.group(ipp, ...)
                    end;bool= function(...)
                        return obs.script.bool(ipp, ...)
                    end;path=function(...)
                        return obs.script.path(ipp,...)
                    end;input= function(...)
                        return obs.script.input(ipp, ...)
                    end;number=function(...)
                        return obs.script.number(ipp, ...)
                    end
                };get= function(name)
                    return obs.script.get(name)
                end;free= function()
                    group_form.free();
                    obslua.obs_properties_destroy(ipp);ipp=nil
                    obslua.obs_properties_destroy(pp);pp=nil
                    return true
                end;data=ipp;item=ipp;confirm={};onconfirm={};oncancel={};cancel={}
            }
            function obj_t.confirm:click(clb)
                __exit_click_callback__=clb
                return obj_t
            end;function obj_t.confirm:text(title_value)
                if not title_value or type(title_value) ~= "string" or title_value == "" then
                    return false
                end
                exit.text(title_value)
                return true
            end
            function obj_t.onconfirm:hide()
                __onexit_type__= 1
                return obj_t
            end;function obj_t.onconfirm:remove()
                __onexit_type__=-1
                return obj_t
            end;function obj_t.onconfirm:idle()
                __onexit_type__= 0
                return obj_t
            end

            function obj_t.cancel:click(clb)
                __cancel_click_callback__=clb
                return obj_t
            end;function obj_t.cancel:text(txt)
                if not txt or type(txt) ~= "string" or txt == "" then
                    return false
                end
                cancel.text(txt)
                return true
            end
            function obj_t.oncancel:idle()
                __oncancel_type__= 0
                return obj_t
            end;function obj_t.oncancel:remove()
                __oncancel_type__= -1
                return obj_t
            end;function obj_t.oncancel:hide()
                __oncancel_type__= 1
                return obj_t
            end
            function obj_t.show()
                return group_form.show();
            end;function obj_t.hide()
                return group_form.hide();
            end;function obj_t.remove()
                return obj_t.free()
            end
            obs.utils.properties[unique_id]= obj_t
            return obj_t
        end
        function obs.script.fps(properties_t, unique_id, title)
            if not title or type(title) ~= "string" then
                title=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id]=obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_frame_rate(properties_t, unique_id, title),
                properties_t
            )
            return obs.utils.properties[unique_id]
        end
        function obs.script.list(properties_t, unique_id, title, enum_type_id, filter_string, default_path_string)
            if not filter_string or type(filter_string) ~= "string" then
                filter_string=""
            end
            if not default_path_string or type(default_path_string) ~= "string" then
                default_path_string= ""
            end
            if not enum_type_id or type(enum_type_id) ~= "number" or (
                enum_type_id ~= obs.enum.list.string 
                and enum_type_id ~= obs.enum.list.file and
                enum_type_id ~= obs.enum.list.url
            ) then
                enum_type_id= obs.enum.list.string
            end
            if not title or type(title) ~= "string" then
                title=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id]=obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_editable_list(
                    properties_t, unique_id, title, enum_type_id, 
                    filter_string, default_path_string
                ), 
            properties_t)
            return obs.utils.properties[unique_id]
        end
        function obs.script.input(p, unique_id, title, enum_type_id, callback)
            if not title or type(title) ~= "string" then
                title=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            if not enum_type_id == nil or (
            enum_type_id ~= obs.enum.text.input and enum_type_id ~= obs.enum.text.textarea and
            enum_type_id ~= obs.enum.text.password) then
                enum_type_id= obs.enum.text.input
            end
            obs.utils.properties[unique_id]=obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_text(
                    p, unique_id, title, enum_type_id
                ),
            p)
            return obs.utils.properties[unique_id]
        end
        function obs.script.color(properties_t, unique_id, title)
            if not title or type(title) ~= "string" then
                title=""
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            obs.utils.properties[unique_id]=obs.utils.obs_api_properties_patch(
                obslua.obs_properties_add_color_alpha(
                    properties_t, unique_id, title
                ), 
            properties_t)
            return obs.utils.properties[unique_id]
        end
        function obs.script.number(properties_t, min, max,steps, unique_id, title, enum_number_type_id, enum_type_id)
            if not enum_number_type_id then
                enum_number_type_id= obs.enum.number.int
            end
            if not enum_type_id then
                enum_type_id= obs.enum.number.input
            end
            if not unique_id or type(unique_id) ~= "string" or unique_id == ""  then
                unique_id= obs.utils.get_unique_id(20)
            end
            local obj;if enum_type_id == obs.enum.number.slider then
                if enum_number_type_id == obs.enum.number.float then
                    obj= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_float(
                        properties_t, unique_id, title, min, max,steps
                    ))
                else
                    obj= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_int_slider(
                        properties_t, unique_id, title, min, max, steps
                    ))
                end
            else
                if enum_number_type_id == obs.enum.number.float then
                    obj= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_float(
                        properties_t, unique_id, title, min, max,steps
                    ))
                else
                    obj= obs.utils.obs_api_properties_patch(obslua.obs_properties_add_int(
                        properties_t, unique_id, title, min, max, steps
                    ))
                end
            end
            if obj then
                obj["type"]= enum_number_type_id
            end
            obs.utils.properties[unique_id]=obj
            
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
            
            return (b * 2^16) + (g * 2^8) + r
        end
        function obs.utils.argb_to_rgb(val)
            if type(val) ~= "number" then
                return nil
            end
            local b = math.floor(val / 2^16) % 256
            local g = math.floor(val / 2^8) % 256
            local r = val % 256

            return r, g, b
        end
        function obs.utils.obs_api_properties_patch(pp,pp_t, cb)
            -- if pp_t ~= nil and not obs.utils.properties[pp] then
            -- 	obs.utils.properties[pp]=pp_t;
            -- end
            local pp_unique_name= obslua.obs_property_name(pp)
            local obs_pp_t=pp; -- extra

            -- onchange [Event Handler]
            local __onchange_list={}

            local item=nil;local objText;local objInput;local objGlobal;objGlobal={
                cb=cb;disable=function()
                    obslua.obs_property_set_disabled(pp, true)
                    return nil
                end;enable=function()
                    obslua.obs_property_set_disabled(obs_pp_t, false)
                    return nil
                end;onchange=function(callback)
                    if type(callback) ~= "function" then
                        return false
                    end
                    table.insert(__onchange_list, callback)
                    return true
                end;hide= function()
                    obslua.obs_property_set_visible(obs_pp_t, false)
                end;show = function()
                    obslua.obs_property_set_visible(obs_pp_t, true)
                    return nil
                end;get= function()
                    return obs_pp_t
                end;hint= function(txt)
                    if txt == nil or type(txt) ~= "string" or txt == "" then
                        return obslua.obs_property_long_description(obs_pp_t)
                    end
                    item=obslua.obs_property_set_long_description(obs_pp_t, txt)
                    return nil
                end;free= function()
                    obs.utils.properties[pp_unique_name]=nil
                    local pv=obslua.obs_properties_get_parent(pp_t)
                    obslua.obs_properties_remove_by_name(pp_t, pp_unique_name)
                    while pv do
                        obslua.obs_properties_remove_by_name(pv, pp_unique_name)
                        pv=obslua.obs_properties_get_parent(pv)
                    end
                    return true
                end;remove=function()
                    return objGlobal.free()
                end;data=pp;item=pp;title=function(txt)
                    if txt == nil or type(txt) ~= "string" then
                        return obslua.obs_property_description(pp)
                    end
                    obslua.obs_property_set_description(pp, txt)
                    return objGlobal
                end;parent=pp_t
            };objText={
                error=function(txt)
                    if txt == nil or type(txt) ~= "string" then
                        return obslua.obs_property_description(pp)
                    end

                    obslua.obs_property_text_set_info_type(pp, obslua.OBS_TEXT_INFO_ERROR)
                    obslua.obs_property_set_description(pp, txt)
                    return objText
                end;
                text=function(txt)
                    local id_name= obslua.obs_property_name(pp)
                    objText.type=obs.enum.text.default
                    obslua.obs_property_text_set_info_type(pp, objText.type)
                    if txt ~= nil and type(txt) == "string" then obslua.obs_property_set_description(pp, txt) end
                    return objText
                end;warn=function(txt)
                    local id_name= obslua.obs_property_name(pp)
                    local textarea_id= id_name .. "_obsapi_hotfix_textarea"
                    local input_id= id_name .. "_obsapi_hotfix_input"
                    local property= obs.script.get(id_name)
                    local textarea_property= obs.script.get(textarea_id)
                    local input_property= obs.script.get(input_id)
                    objText.type=obs.enum.text.input
                    if property then property.show() end
                    if input_property then input_property.hide() end 
                    if textarea_property then textarea_property.hide() end
                    objText.type=obs.enum.text.warn
                    obslua.obs_property_text_set_info_type(pp, objText.type)
                    if txt ~= nil and type(txt) == "string" then obslua.obs_property_set_description(pp, txt) end
                    return objText
                end;
                type=-1
            };objInput={
                value=obs.expect(function(txt)
                    local settings=nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings= obs.utils.properties[pp_t]
                    else
                        settings= obs.utils.settings
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
                end);type=-1
            };
            local objOption;objOption={
                item=nil;clear= function()
                    objOption.item=obslua.obs_property_list_clear(pp)
                    return objOption
                end;add={
                    str= function(title, id)
                        if id == nil or type(id) ~= "string" or id == "" then
                            --id= obs.utils.get_unique_id(20)
                            obslua.script_log(obslua.LOG_INFO, "[obs.script.options.str] id is nil or invalid!")
                            return objOption
                        end
                        objOption.item=obslua.obs_property_list_add_string(pp, title, id)
                        return objOption
                    end;int= function(title, id)
                        if id == nil or type(id) ~= "number" then
                            --id= obs.utils.get_unique_id(20)
                            obslua.script_log(obslua.LOG_INFO, "[obs.script.options.int] id is nil or invalid!")
                            return objOption
                        end
                        objOption.item=obslua.obs_property_list_add_int(pp, title, id)
                        return objOption
                    end;dbl=function(title, id)
                        if id == nil or type(id) ~= "number" then
                            --id= obs.utils.get_unique_id(20)
                            obslua.script_log(obslua.LOG_INFO, "[obs.script.options.dbl] id is nil or invalid!")
                            return objOption
                        end
                        objOption.item=obslua.obs_property_list_add_float(pp, title, id)
                        return objOption
                    end;bul=function(title, id)
                        if id == nil or type(id) ~= "boolean" then
                            id= obs.utils.get_unique_id(20)
                        end
                        objOption.item=obslua.obs_property_list_add_bool(pp, title, id)
                        return objOption
                    
                    end
                };cursor = function(index)
                    if index == nil or type(index) ~= "number" or index < 0 then
                        if type(index) == "string" then -- find the index by the id value
                            for i=0, obslua.obs_property_list_item_count(pp)-1 do
                                if obslua.obs_property_list_item_string(pp, i) == index then
                                    index= i
                                    break
                                end
                            end
                            if type(index) ~= "number" then
                                return nil
                            end
                        else
                            index= objOption.item;if  type(index) ~= "number" or index < 0 then
                                index=obslua.obs_property_list_item_count(pp)-1
                            end
                        end
                    end
                    local info_title;local info_id
                    info_title=obslua.obs_property_list_item_name(pp, index)
                    if obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.string then
                        info_id= obslua.obs_property_list_item_string(pp, index)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.int then
                        info_id= obslua.obs_property_list_item_int(pp, index)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.float then
                        info_id= obslua.obs_property_list_item_float(pp, index)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.bool then
                        info_id= obslua.obs_property_list_item_bool(pp, index)
                    else
                        info_id= nil
                    end
                    local nn_obj=nil;nn_obj={
                        disable= function()
                            obslua.obs_property_list_item_disable(pp, index, true)
                            return nn_obj
                        end; enable= function()
                            obslua.obs_property_list_item_disable(pp, index, false)
                            return nn_obj
                        end;remove=function()
                            obslua.obs_property_list_item_remove(pp, index)
                            return true
                        end;title=info_title;value=info_id;index=index;
                        ret=function()
                            return objOption
                        end;isDisabled=function()
                            return obslua.obs_property_list_item_disabled(pp, index)
                        end
                    }
                    return nn_obj;
                end;current=function()
                    local current_selected_option=nil
                    local settings=nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings= obs.utils.properties[pp_t]
                    else
                        settings= obs.utils.settings
                    end
                    if obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.string then
                        current_selected_option= settings.str(pp_unique_name)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.int then
                        current_selected_option= settings.int(pp_unique_name)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.float then
                        current_selected_option= settings.float(pp_unique_name)
                    elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].enum_format_id == obs.enum.options.bool then
                        current_selected_option= settings.bool(pp_unique_name)
                    end
                    return objOption.cursor(current_selected_option)
                end
            };local fr_rt= false
            local objButton;objButton={
                item=nil;click= function(callback)
                    if type(callback) ~= "function" then
                        obslua.script_log(obslua.LOG_ERROR, "[button.click] invalid callback type " .. type(callback) .. " expected function")
                        return objButton
                    end
                    local tk=os.clock()
                    objButton.item=obslua.obs_property_set_modified_callback(pp,function(properties_t, property_t, obs_data_t)
                        if os.clock() - tk <= 0.01 then
                            return true
                        end
                        
                        return callback(properties_t, property_t, obs.PairStack(obs_data_t, nil, nil, true))
                    end)
                    return objButton
                end;text= function(txt)
                    if txt == nil or type(txt) ~= "string" or txt == "" then
                        return obslua.obs_property_description(pp)
                    end
                    obslua.obs_property_set_description(pp, txt)
                    return objButton
                end;url=function(url)
                    if not url or type(url) ~= "string" or url == "" then
                        obslua.script_log(obslua.LOG_ERROR, "[button.url] invalid url type, expected string, got " .. type(url))
                        return objButton --obslua.obs_property_button_get_url(pp)
                    end
                    obslua.obs_property_button_set_url(pp, url)
                    return objButton
                end;type=function(button_type)
                    if button_type == nil or (button_type ~= obs.enum.button.url and button_type ~= obs.enum.button.default) then
                        obslua.script_log(obslua.LOG_ERROR, "[button.type] invalid type, expected obs.enum.button.url | obs.enum.button.default, got " .. type(button_type))
                        return objButton --obslua.obs_property_button_get_type(pp)
                    end
                    obslua.obs_property_button_set_type(pp, button_type)
                    return objButton
                end
            };
            -- [[ GROUP ]]
            local objGroup;objGroup={

            };
            --
            local objBool;objBool={
                checked=function(bool_value)
                    local settings=nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings= obs.utils.properties[pp_t]
                    else
                        settings= obs.utils.settings
                    end
                    if not settings then
                        obslua.script_log(obslua.LOG_ERROR, "[obs.utils.settings] is not set, please use 'script_load' to set it")
                        return nil
                    end
                    local property_id=obslua.obs_property_name(pp)
                    if bool_value == nil or type(bool_value) ~= "boolean" then
                        return settings.get_bul(property_id)
                    end
                    settings.bul(property_id, bool_value)
                    return objBool
                end;
            };local objColor;objColor={
                value= obs.expect(function(r_color, g_color, b_color, alpha_value)
                    local settings=nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings= obs.utils.properties[pp_t]
                    else
                        settings= obs.utils.settings
                    end
                    if r_color == nil then
                        return settings.int(pp_unique_name)
                    end
                    if type(r_color) ~= "number" or type(g_color) ~= "number" or type(b_color) ~= "number" then
                        return false
                    end
                    if alpha_value == nil then
                        alpha_value=1
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
                end);type= obslua.OBS_PROPERTY_COLOR_ALPHA
            }local objList;objList={
                insert=function(value, selected, hidden)

                    if type(value) ~= "string" then
                        return objList
                    end
                    if type(selected) ~= "boolean" then
                        selected= false
                    end
                    if type(hidden) ~= "boolean" then
                        hidden= false
                    end
                    local settings=nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings= obs.utils.properties[pp_t]
                    else
                        settings= obs.utils.settings
                    end
                    local unique_id= obs.utils.get_unique_id(20)
                    local obs_data_t= obs.PairStack()
                    obs_data_t.str("value", value)
                    obs_data_t.bul("selected", selected)
                    obs_data_t.bul("hidden", hidden)
                    obs_data_t.str("uuid", unique_id)
                    local obs_curr_data_t= settings.arr(pp_unique_name)
                    obs_curr_data_t.insert(obs_data_t.data)
                    obs_data_t.free();obs_curr_data_t.free()
                    return objList
                end,filter= function()
                    return obslua.obs_property_editable_list_filter(pp)
                end,default=function()
                    return obslua.obs_property_editable_list_default_path(pp)
                end,type=function()
                    return obslua.obs_property_editable_list_type(pp)
                end;
            };local objNumber;objNumber={
                suffix= function(text)
                    obslua.obs_property_float_set_suffix(pp, text)
                    obslua.obs_property_int_set_suffix(pp, text)
                    return objNumber
                end;value=function(value)
                    local settings=nil;
                    if pp_t and obs.utils.properties[pp_t] then
                        settings= obs.utils.properties[pp_t]
                    else
                        settings= obs.utils.settings
                    end
                    if objNumber.type == obs.enum.number.int then
                        settings.int(pp_unique_name, value)
                    elseif objNumber.type == obs.enum.number.float then
                        settings.dbl(pp_unique_name, value)
                    else
                        return nil
                    end
                    return value
                end;type=nil
            }


            local property_type= obslua.obs_property_get_type(pp)
            -- [[ ON-CHANGE EVENT HANDLE FOR ANY KIND OF USER INTERACTIVE INPUT ]]
            if property_type == obslua.OBS_PROPERTY_COLOR or property_type == obslua.OBS_PROPERTY_COLOR_ALPHA or 
            property_type == obslua.OBS_PROPERTY_BOOL or property_type == obslua.OBS_PROPERTY_LIST or 
            property_type == obslua.OBS_PROPERTY_EDITABLE_LIST or property_type == obslua.OBS_PROPERTY_PATH or
            (property_type == obslua.OBS_PROPERTY_TEXT and (
                obslua.obs_property_text_type(pp) == obs.enum.text.textarea or 
                obslua.obs_property_text_type(pp) == obs.enum.text.input or 
                obslua.obs_property_text_type(pp) == obs.enum.text.password
            )) then
                local tk=os.clock()
                obslua.obs_property_set_modified_callback(obs_pp_t, function(properties_t, property_t, settings)
                    if os.clock() - tk <= 0.01 then
                        return true
                    end
                    settings=obs.PairStack(settings, nil, nil, true)
                    local pp_unique_name= obslua.obs_property_name(property_t)
                    local current_value;property_type= obslua.obs_property_get_type(property_t)
                    if property_type == obslua.OBS_PROPERTY_BOOL then
                        current_value= settings.bul(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_TEXT or  
                    property_type == obslua.OBS_PROPERTY_PATH or 
                    property_type == obslua.OBS_PROPERTY_BUTTON then
                        current_value= settings.str(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_INT or property_type == obslua.OBS_PROPERTY_COLOR_ALPHA or property_type == obslua.OBS_PROPERTY_COLOR then
                        current_value= settings.int(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_FLOAT then
                        current_value= settings.dbl(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_LIST then

                        if obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.string then
                            current_value= settings.str(pp_unique_name)

                        elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.int then
                            current_value= settings.int(pp_unique_name)
                        elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.float then
                            current_value= settings.dbl(pp_unique_name)
                        elseif obs.utils.properties.options[pp_unique_name] and obs.utils.properties.options[pp_unique_name].type == obs.enum.options.bool then
                            current_value= settings.bul(pp_unique_name)
                        end
                    elseif property_type == obslua.OBS_PROPERTY_FONT then
                        current_value= settings.obj(pp_unique_name)
                    elseif property_type == obslua.OBS_PROPERTY_EDITABLE_LIST then
                        current_value= settings.arr(pp_unique_name)
                    end
                    local result= nil
                    for _, vclb in pairs(__onchange_list) do
                        local temp=vclb(current_value, obs.script.get(obslua.obs_property_name(property_t)), properties_t, settings)
                        if result == nil then
                            result= temp
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
                local obj_enum_type_id= obslua.obs_property_text_type(pp)
                if obj_enum_type_id == obs.enum.text.textarea or 
                obj_enum_type_id == obs.enum.text.input or 
                obj_enum_type_id == obs.enum.text.password then
                    objInput.type= obj_enum_type_id
                    obs.utils.table.append(objInput, objGlobal)
                    return objInput;
                else
                    objText.type= obj_enum_type_id
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
            local chars= "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
            if i == nil then
                i= true;
            end
            if mpc == nil or type(mpc) ~= "string" then
                mpc= tostring(os.time());
                mpc=obs.utils.get_unique_id(rs, false, mpc, true)
            elseif cmpc == true then
                chars=mpc
            end
            
            local index= math.random(1, #chars)
            local c= chars:sub(index, index)
            if c == nil then
                c=""
            end
            if rs <= 0 then
                return c;
            end
            local val= obs.utils.get_unique_id(rs - 1,false, mpc, cmpc)
            
            if i == true and mpc ~= nil and type(mpc) == "string" and #val > 1 then
                val= val .. "_" .. mpc
            end
            return c .. val
        end
        function obs.utils.table.append(tb, vv)
            for k, v in pairs(vv) do
                if type(v) == "function" then
                    local old_v = v
                    v = function(...)
                        local retValue= old_v(...)
                        if retValue== nil then
                            return tb;
                        end
                        return retValue;
                    end
                end
                if type(k) == "string" then
                tb[k]= v;
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
                local c = s:sub(i, i);i = i + 1
                if c == '{' then
                    local r = {}
                    if s:match("^%s*}", i) then i = s:find("}", i) + 1 return r end
                    repeat
                        local k = v() i = s:find(":", i) + 1
                        r[k] = v() i = s:find("[%,%}]", i)
                        local x = s:sub(i, i) i = i + 1
                    until x == '}'
                    return r
                elseif c == '[' then
                    local r = {}
                    if s:match("^%s*]", i) then i = s:find("]", i) + 1 return r end
                    repeat
                        r[#r+1] = v() i = s:find("[%,%]]", i)
                        local x = s:sub(i, i) i = i + 1
                    until x == ']'
                    return r
                elseif c == '"' then
                    local _, e = i, i
                    repeat _, e = s:find('"', e) until s:sub(e-1, e-1) ~= "\\"
                    local res = s:sub(i, e-1):gsub("\\", "") i = e + 1
                    return res
                end
                local n = s:match("^([%-?%d%.eE]+)()", i-1)
                if n then i = i + #n - 1 return tonumber(n) end
                local l = {t=true, f=false, n=nil}
                i = i + (c == 'f' and 4 or 3)
                return l[c]
            end
            return v()
        end
    -- [[ API UTILS END ]]
-- [[ OBS CUSTOM API END ]]
