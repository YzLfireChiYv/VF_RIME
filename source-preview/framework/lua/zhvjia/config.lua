-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Compile the merged schema once. Explicit [] disables a binding.
-- Invalid configuration keeps the previous complete snapshot.
local M = {}
local ROOT = "zhvjia/modes/"
local DEFAULTS = {
    primary = { bindings = { commit_preedit = { "Return", "KP_Enter", "Control+Return", "Control+KP_Enter", "Shift+Return", "Shift+KP_Enter" } } },
    calculator = { entry = "/=", priority = 100, bindings = {
        confirm = { "space", "Return", "KP_Enter" }, tab_block = { "Tab", "Shift+Tab" } } },
    creation = { entry = "/+", priority = 100 },
    reverse = { entry = "/`", priority = 100 },
    code = {}, clock = { priority=50 }, unicode={}, catalog={}, slash={}, letters={}, invalid={},
}
local ACTION = { commit_preedit = "commit_visible_preedit", confirm = "activate_current",
    tab_block = "consume_no_action" }
-- Public bindings only rename fixed actions. Body alphabets stay with their
-- mode; a custom key cannot add another interpreter or arbitrary callback.
local EDIT = {
    move_left={"Left","KP_Left"}, move_right={"Right","KP_Right"},
    home={"Home","KP_Home"}, finish={"End","KP_End"},
    backspace={"BackSpace"}, delete={"Delete","KP_Delete"},
    delete_left={"Control+BackSpace","Shift+BackSpace"}, cancel={"Escape"},
}
local CANDIDATE = {
    previous_candidate={"Up","KP_Up"}, next_candidate={"Down","KP_Down"},
    previous_page={"Page_Up","KP_Page_Up"}, next_page={"Page_Down","KP_Page_Down"},
    select_current={"space"},
}
local CANON = { move_left="Left",move_right="Right",home="Home",finish="End",
    backspace="BackSpace",delete="Delete",delete_left="Control+BackSpace",cancel="Escape",
    next_breakpoint="Tab", previous_candidate="Up",next_candidate="Down",
    previous_page="Page_Up",next_page="Page_Down",select_current="space",
    select_result="Return",save="Control+Return",exit_layer="Escape",
    commit_preedit="Return",confirm="space",tab_block="Tab" }
for name,spec in pairs(DEFAULTS) do
    spec.bindings=spec.bindings or {}
    if name~="unicode" then
        for id,keys in pairs(EDIT) do spec.bindings[id]=keys end
    else
        spec.bindings.exit_layer={"Escape","BackSpace"}
    end
    if name~="calculator" and name~="invalid" then
        for id,keys in pairs(CANDIDATE) do
            if not (name=="code" and id~="select_current") then spec.bindings[id]=keys end
        end
    end
    if name=="primary" or name=="creation" then spec.bindings.next_breakpoint={"Tab"}
    else spec.bindings.tab_block={"Tab","Shift+Tab","ISO_Left_Tab"} end
    if name=="creation" then spec.bindings.save={"Control+Return","Control+KP_Enter"} end
    if name~="primary" and name~="calculator" and name~="invalid" then
        spec.bindings.select_result={"Return","KP_Enter"}
    end
end
-- Calculator has one confirm action, not a second space action.
DEFAULTS.calculator.bindings.select_current=nil
local COMPAT = {
    ["Control+a"]="tone_hint",["Control+s"]="tone_display",["Control+t"]="super_tips",
    ["Control+g"]="charset_filter",["Control+Shift+F"]="s2t",
    ["Shift+space"]="full_shape",["Control+period"]="ascii_punct",
}
M.compatibility=COMPAT
local function fail(path, message) error(path .. ": " .. message, 0) end
local function state_key(event)
    return (event.keycode>=0xffe1 and event.keycode<=0xffee) or event.keycode==0xff30
end
local function primary_reserved(key)
    local event=KeyEvent(key)
    return state_key(event) or COMPAT[key] or
        (not event:ctrl() and not event:alt() and not event:super() and
            event.keycode>=0x20 and event.keycode<=0x7e) or key:match("^KP_[0-9]$")
end
local function node(c, p) return c and c:get_item(p) end
local function str(c, p, default)
    if not node(c, p) then return default end
    local v = c:get_string(p)
    if type(v) ~= "string" then fail(p, "expected a string") end
    return v
end
local function list(c, p, defaults)
    if not node(c, p) then
        local out = {}; for i, v in ipairs(defaults or {}) do out[i] = KeyEvent(v):repr() end; return out
    end
    if node(c, p).type ~= "kList" then fail(p, "expected a list of exact key names") end
    local values, seen, out = c:get_list(p), {}, {}
    for i = 0, values.size - 1 do
        local value = values:get_value_at(i)
        local key = value and value:get_string()
        local ok, event = pcall(KeyEvent, key or "")
        if not key or not ok or not event or event.keycode == 0 then
            fail(p, "invalid or repeated key " .. tostring(key))
        end
        key=event:repr()
        if seen[key] then fail(p,"repeated key "..key) end
        if event:release() or state_key(event) or (event.modifier==0 and event.keycode>=0x61 and event.keycode<=0x7a) then
            fail(p,"bare lowercase letters are reserved for text")
        end
        seen[key], out[#out + 1] = true, key
    end
    return out
end
local function compile(c,env)
    local out = { version = 3, modes = {}, entries = {}, navigation = {}, variants={},
        page_size=(c and c:get_int("menu/page_size")) or 9,
        first_page_comma=c and c:get_bool("zhvjia/paging/first_page_comma") or false }
    for name, spec in pairs(DEFAULTS) do
        local p, rule = ROOT .. name .. "/", { key_actions = {}, bindings = {}, reserved={} }
        if spec.priority then
            if node(c,p.."priority") then rule.priority=c:get_int(p.."priority") else rule.priority=spec.priority end
            if not rule.priority or rule.priority < -1000 or rule.priority > 1000 then fail(p.."priority","integer from -1000 to 1000 required") end
        end
        if spec.entry then
            rule.entry = str(c, p .. "entry", spec.entry)
            if #rule.entry < 2 or #rule.entry > 12 or rule.entry:find("[^!-~]") or
                rule.entry:sub(1, 1):match("[%w'`]") then
                fail(p .. "entry", "use 2-12 ASCII characters starting with a symbol; `` is reserved")
            end
            out.entries[#out.entries + 1] = { mode = name, entry = rule.entry, priority = rule.priority }
        end
        for id, keys in pairs(spec.bindings or {}) do
            local base=p.."bindings/"..id
            local b=base.."/"
            local action=ACTION[id] or id
            if str(c,b.."action",action)~=action then fail(b,"unsupported action") end
            local path=node(c,base) and node(c,base).type=="kList" and base or b.."keys"
            rule.bindings[id] = { keys = list(c,path,keys), action=action }
            for _,key in ipairs(keys) do rule.reserved[KeyEvent(key):repr()]=true end
            for _, key in ipairs(rule.bindings[id].keys) do
                if rule.key_actions[key] then fail(b, "key conflicts with " .. rule.key_actions[key].id) end
                if key:match("^[0-9]$") or key:match("^KP_[0-9]$") or
                    (name=="primary" and (COMPAT[key] or key=="U" or key=="Shift+U" or key=="grave" or key=="apostrophe")) then
                    fail(b,"key belongs to text, candidate selection or a compatibility action: "..key)
                end
                rule.key_actions[key] = { id=id,action=action,canonical=CANON[id] }
            end
        end
        if name == "calculator" then
            rule.input_aliases={}
            local at=p.."input_aliases"
            if node(c,at) then
                if not c:is_map(at) then fail(at,"expected a key to arithmetic character map") end
                for _,text in ipairs(c:get_map(at):keys()) do
                    local ok,event=pcall(KeyEvent,text)
                    local value=c:get_string(at.."/"..text)
                    if not ok or not event or event.keycode==0 or event:release() or state_key(event) or
                        not value or #value~=1 or not value:match("^[+*/().-]$") then
                        fail(at.."/"..text,"expected an exact key and one arithmetic character")
                    end
                    local key=event:repr()
                    if rule.reserved[key] or rule.key_actions[key] or rule.input_aliases[key] then fail(at.."/"..text,"key conflicts with a calculator action") end
                    rule.input_aliases[key]=value
                end
            end
        elseif name == "code" then
            rule.digits = {}
            for _, group in ipairs({ "main", "keypad" }) do
                local value = str(c, p .. "digits/" .. group, "candidate")
                if value ~= "candidate" and value ~= "literal" then fail(p .. "digits/" .. group, "candidate or literal required") end
                rule.digits[group] = value
            end
            rule.default_template = str(c, p .. "default_template", nil)
        elseif name == "clock" then
            rule.space_format = str(c, p .. "space_format", "current")
            if not rule.space_format:match("^[A-Za-z0-9_.-]+$") then fail(p.."space_format","a declared format ID or current is required") end
        elseif name == "primary" then
            rule.navigation = str(c, p .. "navigation", "pinyin")
            if rule.navigation ~= "pinyin" and rule.navigation ~= "character" then fail(p .. "navigation", "pinyin or character required") end
            rule.protect_backspace=true
            if node(c,p.."protect_backspace") then
                rule.protect_backspace=c:get_bool(p.."protect_backspace")
                if rule.protect_backspace==nil then fail(p.."protect_backspace","boolean required") end
            end
        end
        out.modes[name] = rule
    end
    -- Follow native key_binder condition order; later entries of the same
    -- condition win. Non-page entries remain barriers, never revived macros.
    local page_actions={[0xff55]="previous_page",[0xff56]="next_page",[0xff9a]="previous_page",[0xff9b]="next_page"}
    local conditions={"predicting","paging","has_menu","composing","always"}
    local legacy={}
    local bindings=c and c:get_list("key_binder/bindings")
    for index=0,(bindings and bindings.size or 0)-1 do
        local path="key_binder/bindings/@"..index.."/"
        local send=c:get_string(path.."send")
        local ok,event=pcall(KeyEvent,send or "")
        local id=ok and event and page_actions[event.keycode]
        local when=c:get_string(path.."when")
        local valid_condition=false
        for _,condition in ipairs(conditions) do if when==condition then valid_condition=true end end
        if valid_condition then
            local key=c:get_string(path.."accept")
            local valid,accepted=pcall(KeyEvent,key or "")
            if valid and accepted and accepted.keycode~=0 and not accepted:release() then
                key=accepted:repr()
                local page=id and event.modifier==0
                legacy[key]=legacy[key] or {}
                legacy[key][when]={id=page and id or nil,action=id,canonical=page and CANON[id] or nil,when=when}
            end
        end
    end
    for name,rule in pairs(out.modes) do
        if rule.bindings.previous_page then
            for key,records in pairs(legacy) do
                local fallback=rule.key_actions[key]
                if not (fallback and node(c,ROOT..name.."/bindings/"..fallback.id)) then
                    local choices,has_page={},false
                    for _,when in ipairs(conditions) do
                        local record=records[when]
                        if record then
                            local enabled=record.id and not node(c,ROOT..name.."/bindings/"..record.id)
                            choices[#choices+1]=enabled and record or {when=when}
                            has_page=has_page or enabled
                        end
                    end
                    if has_page then
                        local accepted=KeyEvent(key)
                        if state_key(accepted) or key:match("^[0-9]$") or key:match("^KP_[0-9]$") or
                            COMPAT[key] or key=="U" or key=="Shift+U" or key=="grave" or key=="apostrophe" or
                            (accepted.modifier==0 and accepted.keycode>=0x61 and accepted.keycode<=0x7a) then
                            fail("key_binder/bindings","page shortcut conflicts with a protected key: "..key)
                        end
                        rule.key_actions[key]={choices=choices,fallback=fallback}
                    end
                end
            end
        end
    end
    table.sort(out.entries, function(a,b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if #a.entry ~= #b.entry then return #a.entry > #b.entry end
        return a.mode < b.mode
    end)
    for i, a in ipairs(out.entries) do
        for j = i + 1, #out.entries do
            local b = out.entries[j]
            if a.entry == b.entry then fail(ROOT, a.mode .. " and " .. b.mode .. " use the same entry") end
            if a.entry:sub(1,#b.entry) == b.entry or b.entry:sub(1,#a.entry) == a.entry then
                fail(ROOT, "an entry may not be a prefix of another entry")
            end
        end
    end
    local occupied = {}
    for _, action in ipairs({ "enter", "leave", "left", "right", "up", "down", "confirm" }) do
        local path=env and require("zhvjia/presentation").setting_path(env,"navigation/"..action)
        for _, key in ipairs(list(c,path or ("zhvjia_interaction/navigation/" .. action), {})) do
            if key:match("^[a-z]$") then fail("zhvjia_interaction/navigation", "bare lowercase letters are reserved for text") end
            if occupied[key] then fail("zhvjia_interaction/navigation", "key has two actions: " .. key) end
            if out.modes.primary.key_actions[key] or primary_reserved(key) then
                fail("zhvjia_interaction/navigation/"..action,"key conflicts with a primary action: "..key)
            end
            occupied[key], out.navigation[key] = action, action
        end
    end
    local variants=env and require("zhvjia/presentation").setting_path(env,"variant_keys")
    for index,key in ipairs(list(c,variants or "zhvjia_interaction/variant_keys",{})) do
        if occupied[key] or out.modes.primary.key_actions[key] or primary_reserved(key) then
            fail("zhvjia_interaction/variant_keys","key conflicts with another action: "..key)
        end
        occupied[key],out.variants[key]="variant",index
    end
    if env then
        local rods=require("zhvjia/interaction").bindings(env)
        if not rods then fail("zhvjia_interaction","invalid rod key lists") end
        for code in pairs(rods.primary) do
            local event=KeyEvent(code,0)
            local key=event:repr()
            if state_key(event) or (code>=0x20 and code<=0x7e and not (code>=0x31 and code<=0x39)) or
                occupied[key] or out.modes.primary.key_actions[key] or COMPAT[key] then
                fail("zhvjia_interaction/primary_keys","key conflicts with text or another action: "..key)
            end
            occupied[key]="rod primary"
        end
        local content=require("zhvjia/content")
        local bindings,why=content.bindings(env)
        if why then fail("zhvjia_interaction/content/bindings",why) end
        for key in pairs(bindings or {}) do
            if occupied[key] or out.modes.primary.key_actions[key] or primary_reserved(key) then
                fail("zhvjia_interaction/content/bindings","key conflicts with a primary or rod action: "..key)
            end
        end
        out.content=bindings or {}
        local hold=content.configured_hold(env)
        if hold then
            local key=hold.first
            if occupied[key] or out.modes.primary.key_actions[key] or primary_reserved(key) or
                (out.content[key] and out.content[key]~=hold.unused_release) then
                fail("zhvjia_interaction/content/hold/first","key conflicts with another action: "..key)
            end
        end
    else out.content={} end
    return out
end
function M.binding(snapshot,mode,key,ctx)
    local rule=snapshot.modes[mode]
    local binding=rule and rule.key_actions[key]
    local first=snapshot.first_page_comma and mode~="creation" and key=="comma" and ctx:has_menu() and
        not ctx.composition:empty() and (ctx.composition:back().selected_index or 0)<snapshot.page_size
    if binding and binding.choices then
        local seg=not ctx.composition:empty() and ctx.composition:back()
        local active={always=true,composing=ctx:is_composing(),has_menu=ctx:has_menu(),
            paging=seg and seg:has_tag("paging"),predicting=seg and seg:has_tag("prediction")}
        local resolved=binding.fallback
        for _,choice in ipairs(binding.choices) do
            if active[choice.when] or (first and choice.when=="paging" and choice.id=="previous_page") then
                resolved=choice.id and choice or nil
                break
            end
        end
        binding=resolved
    end
    return binding,first and binding and binding.id=="previous_page"
end
function M.load(c,env)
    local ok, out = pcall(compile, c,env)
    if ok then return out end
    return nil, tostring(out)
end
function M.get(env, reload)
    local profile=require("zhvjia/presentation").profile(env)
    if env._zhvjia_config and env._config_profile==profile and not reload then return env._zhvjia_config, env._zhvjia_config_error end
    local out, err = M.load(env.engine.schema and env.engine.schema.config,env)
    if out then env._zhvjia_config = out
    elseif not env._zhvjia_config then env._zhvjia_config = assert(M.load(nil)) end
    env._zhvjia_config_error = err
    env._config_profile=profile
    return env._zhvjia_config, err
end
return M
