-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Presentation policy reads the merged schema and the frontend's current view.
-- A platform preset is a preference, never proof that rods/geometry exist.
local M = {}
local ROOT = "zhvjia_interaction/"
local SESSION = "zhvjia_presentation_session"
local buckets, sequence = {}, 0
local runtime_token = tostring({})
local KNOWN_PROFILES = {
    weasel = true, squirrel = true, fallback = true,
    fcitx5 = true, ["fcitx5-linux"] = true, ["fcitx5-android"] = true,
}

local function config(env)
    return env.engine.schema and env.engine.schema.config
end
local function property(ctx, name)
    return ctx.get_property and (ctx:get_property(name) or "") or ""
end
local function distribution()
    if rime_api and rime_api.get_distribution_code_name then
        return (rime_api.get_distribution_code_name() or ""):lower()
    end
    return ""
end
function M.device_id(env)
    if env._presentation_device_id~=nil then return env._presentation_device_id end
    local value=rime_api and rime_api.get_user_id and rime_api.get_user_id() or ""
    -- Installation IDs may contain Chinese device names. Only configuration
    -- path separators and control bytes are forbidden here.
    if type(value)~="string" or #value>256 or value:find("[%z\1-\31\127/\\]") then value="" end
    env._presentation_device_id=value
    return value
end
local function device_path(env,name)
    local id=M.device_id(env)
    if id~="" then return ROOT.."devices/"..id.."/"..name end
end
function M.profile(env)
    local c = config(env)
    local device=device_path(env,"profile")
    local choice = (c and device and c:get_string(device)) or (c and c:get_string(ROOT .. "profile")) or "auto"
    if choice ~= "auto" then
        return KNOWN_PROFILES[choice] and choice or "fallback"
    end
    local ctx, dist = env.engine.context, distribution()
    local client = property(ctx, "client_type"):lower()
    if dist:find("squirrel", 1, true) or client == "squirrel" then return "squirrel" end
    if dist:find("weasel", 1, true) or client == "tsf" or client == "imm" or
        property(ctx, "_interaction_frontend"):match("^weasel") then return "weasel" end
    local normalized = dist:gsub("[%s_]", "-")
    if normalized:find("fcitx5-android", 1, true) then return "fcitx5-android" end
    if normalized:find("fcitx5-linux", 1, true) then return "fcitx5-linux" end
    if normalized:find("fcitx5", 1, true) then return "fcitx5" end
    return "fallback"
end
function M.setting_path(env, name)
    local c = config(env)
    if not c then return nil end
    local local_path=device_path(env,name)
    if local_path and c:get_item(local_path) then return local_path end
    local preset = M.profile(env)
    local scoped = ROOT .. "profiles/" .. preset .. "/" .. name
    if c:get_item(scoped) then return scoped end
    if preset == "fcitx5-linux" or preset == "fcitx5-android" then
        local common = ROOT .. "profiles/fcitx5/" .. name
        if c:get_item(common) then return common end
    end
    local shared = ROOT .. name
    if c:get_item(shared) then return shared end
end
function M.setting(env, name, fallback)
    local c, path = config(env), M.setting_path(env, name)
    if not path then return fallback end
    local value = c:get_bool(path)
    if value == nil then return fallback end
    return value
end
function M.string(env, name, fallback)
    local c, path = config(env), M.setting_path(env, name)
    return (path and c:get_string(path)) or fallback
end
local function feature(env, name, reported, fallback)
    local path = M.setting_path(env, "capabilities/" .. name)
    if path then
        local value = config(env):get_bool(path)
        if value ~= nil then return value and reported ~= false end
    end
    if reported ~= nil then return reported end
    return fallback or false
end
-- The controller advertises validated immediate variant bindings. Without
-- those keys or a reliable hold gesture, flatten every emoji into a normal
-- candidate so a compact row never hides keyboard-only choices.
function M.set_compact_access(env, available)
    local ctx, value = env.engine.context, available and "1" or "0"
    if property(ctx, "zhvjia_compact_variant_keys") ~= value then
        ctx:set_property("zhvjia_compact_variant_keys", value)
    end
end
function M.capabilities(env)
    local ctx, preset = env.engine.context, M.profile(env)
    local reported = property(ctx, "_interaction_capability_version") ~= ""
    local layout = M.string(env, "layout", "auto")
    if layout == "auto" then
        layout = property(ctx, "_interaction_layout")
        -- Squirrel documents these as panel state. Do not interpret _vertical
        -- (text orientation) as the candidate-list direction.
        if layout == "" and preset == "squirrel" then
            layout = ctx:get_option("_linear") and "horizontal" or "vertical"
        end
    end
    if layout:match("^horizontal") then layout = "horizontal"
    elseif layout:match("^vertical") then layout = "vertical"
    else layout = "unknown" end
    -- Preserve explicit false from a capability-reporting frontend.
    local function exact(name)
        if reported then return property(ctx, "_interaction_" .. name) == "1" end
        return nil
    end
    local native = type(Interaction) == "table" and
        type(Interaction.decorate) == "function" and type(Interaction.attach) == "function" and
        type(Interaction.get_snapshot) == "function"
    -- An ordinary frontend cannot be upgraded by a user preference. Custom
    -- disables a real rod capability; it cannot manufacture a private renderer.
    local rods = exact("rods") == true and M.setting(env, "rods", true)
    rods = native and rods and layout == "horizontal" and
        M.setting(env, "enabled", true) and M.setting(env, "rich", true)
    local c = config(env)
    if c and c:get_bool("zhvjia_opencc/ui_rod") == false then rods = false end
    local key_release = feature(env, "key_release", exact("key_release"))
    local focus_cancel = feature(env, "focus_cancel", exact("focus_cancel"))
    local epoch = property(ctx, "_interaction_epoch")
    local hold = key_release and focus_cancel and epoch ~= "" and M.setting(env, "enabled", true) and
        property(ctx, "zhvjia_hold_keys") ~= "0"
    local compact = M.setting(env, "compact_emoji", layout == "vertical") and
        (hold or property(ctx, "zhvjia_compact_variant_keys") == "1")
    return {
        profile = preset, layout = layout, rods = rods, native = native,
        regions = feature(env, "regions", exact("regions")),
        spatial = native and feature(env, "spatial", exact("spatial")),
        key_release = key_release,
        focus_cancel = focus_cancel,
        compact_emoji = not rods and compact,
        epoch = epoch,
        text_orientation = property(ctx, "_interaction_text_orientation"),
    }
end

function M.same_genuine(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local ok, same = pcall(function()
        return a:get_genuine():is_same(b:get_genuine())
    end)
    return ok and same == true
end
function M.same(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local ok, identical = pcall(function() return a:is_same(b) end)
    if ok and identical then return true end
    -- Origin alone is insufficient: OpenCC source and all derived forms share
    -- a genuine Phrase. Preserve the semantic wrapper and payload as well;
    -- these fields only guard a retained genuine identity, never locate by text.
    return a.type == b.type and a.text == b.text and a.start == b.start and a._end == b._end and
        M.same_genuine(a, b)
end
local function bucket(env, create)
    local ctx = env.engine.context
    local token = property(ctx, SESSION)
    if token == "" then
        if not create then return nil end
        sequence = sequence + 1
        token = runtime_token .. ":" .. tostring(sequence)
        ctx:set_property(SESSION, token)
    end
    local current = buckets[token]
    local raw = ctx.input or ""
    local mode = property(ctx, "_interaction_mode") .. "/" .. property(ctx, "zhvjia_unicode")
    if current and (current.input ~= raw or current.mode ~= mode or
        (ctx.input_revision and current.revision ~= ctx.input_revision)) then
        current = nil
    end
    if not current and create then
        current = { input = raw, mode = mode, revision = ctx.input_revision, records = {} }
        buckets[token] = current
    end
    return current
end
function M.forget(env)
    local ctx = env.engine.context
    local token = property(ctx, SESSION)
    if token ~= "" then buckets[token] = nil end
end
function M.remember(env, record)
    local current = bucket(env, true)
    -- Candidate generation is lazy. Bound retained genuine identities even if
    -- a user requests arbitrarily many pages from a long composition.
    if #current.records >= 512 then table.remove(current.records, 1) end
    current.records[#current.records + 1] = record
    return record
end
function M.record_for(env, candidate)
    local current = bucket(env, false)
    if not current then return nil end
    for i = #current.records, 1, -1 do
        local record = current.records[i]
        if M.same(record.source, candidate) then return record end
        for _, member in ipairs(record.members or {}) do
            if M.same(member, candidate) then return record end
        end
    end
end
function M.is_associated(env, candidate)
    local record = M.record_for(env, candidate)
    if record and not M.same(record.source, candidate) then return true end
    local kind = candidate and candidate.interaction_kind
    return kind == "associated" or kind == "output" or
        (candidate and (candidate.type or ""):match("^zhvg") ~= nil)
end

-- Standard frontend fallback: output stays the first real value. Remaining
-- emoji use the comment area on that same row; a click can never commit a pack.
-- Legacy keyboard selection changes only this synthetic SimpleCandidate, then
-- asks Context::Select to preserve confirmed prefixes and unconsumed suffixes.
function M.pack(env, candidates, source)
    if #candidates == 0 then return nil end
    local first, rest = candidates[1], {}
    for i = 2, #candidates do rest[#rest + 1] = candidates[i].text end
    local type_name = (first.type or ""):match("^zhvjia_unicode_output:") and
        "zhvjia_unicode_output:zhvg_compact" or "zhvg_compact"
    local packed = Candidate(type_name, first.start, first._end, first.text, table.concat(rest, " "))
    packed.preedit, packed.quality = first.preedit, first.quality
    local record = M.remember(env, {
        source = source, members = { packed }, packed = packed, outputs = candidates,
        default_text = packed.text, default_comment = packed.comment,
    })
    return packed, record
end
function M.pack_for(env, candidate)
    local current = bucket(env, false)
    if not current then return nil end
    for i = #current.records, 1, -1 do
        local record = current.records[i]
        if record.packed and M.same(record.packed, candidate) then return record end
    end
end
function M.select_pack(env, record, index, ordinal)
    if not record or record ~= M.pack_for(env, record.packed) then return false end
    local ctx = env.engine.context
    if ctx.composition:empty() then return false end
    local menu_candidate = ctx.composition:back():get_candidate_at(index)
    local target = record.outputs[ordinal]
    if not target or not M.same(menu_candidate, record.packed) then return false end
    local previous_text, previous_comment = record.packed.text, record.packed.comment
    record.packed.text, record.packed.comment = target.text, ""
    local ok, selected = pcall(function() return ctx:select(index) end)
    if not ok or selected == false then
        record.packed.text, record.packed.comment = previous_text, previous_comment
        return false
    end
    return true
end

local tip_resolver
function M.set_tip_resolver(resolver) tip_resolver = resolver end
function M.dedicated_tip(env, source)
    if not tip_resolver then return nil end
    return tip_resolver(env, source)
end
function M.tip_for_candidate(env, candidate)
    local record = M.record_for(env, candidate)
    return record and record.tip or nil, record and record.source or candidate, record ~= nil
end

function M.select_tip(env, selected, text)
    local ctx = env.engine.context
    local mode = property(ctx, "_interaction_mode")
    if (mode ~= "" and mode ~= "primary") or (ctx.input or ""):sub(1, 1) == "/" or
        (ctx.input or ""):find("`", 1, true) or property(ctx, "zhvjia_unicode") == "1" then return false end
    if not selected or type(text) ~= "string" or text == "" or
        type(Menu) ~= "function" or type(Translation) ~= "function" or ctx.composition:empty() then return false end
    if not M.same(selected, ctx:get_selected_candidate()) then return false end
    local _, source = M.tip_for_candidate(env, selected)
    local raw, revision = ctx.input or "", ctx.input_revision
    local seg = ctx.composition:back()
    local first, last = source.start, source._end
    local function boundary(pos)
        if type(pos) ~= "number" or pos % 1 ~= 0 or pos < 0 or pos > #raw then return false end
        local next = raw:byte(pos + 1)
        return not next or next < 128 or next >= 192
    end
    if not boundary(first) or not boundary(last) or last <= first or first < seg.start or last > seg._end then
        return false
    end
    local output = Candidate("zhvjia_tip_output", first, last, text, "")
    local replacement = Menu()
    replacement:add_translation(Translation(function() yield(output) end))
    replacement:prepare(1)
    if not M.same(replacement:get_candidate_at(0), output) or not M.same(selected, ctx:get_selected_candidate()) or ctx.input ~= raw or
        (revision and ctx.input_revision ~= revision) then return false end
    local previous_menu, previous_index, previous_status = seg.menu, seg.selected_index, seg.status
    local previous_start, previous_end = seg.start, seg._end
    seg.menu, seg.selected_index = replacement, 0
    local ok, value = pcall(function() return ctx:select(0) end)
    if ok and value ~= false then return true end
    -- Only restore an unchanged transaction. A notifier may already have
    -- selected a prefix or completed composition before reporting its error.
    if ctx.input == raw and (not revision or ctx.input_revision == revision) and not ctx.composition:empty() then
        local current = ctx.composition:back()
        if current.start == previous_start and current._end == previous_end and current.menu and
            M.same(current.menu:get_candidate_at(0), output) then
            current.menu, current.selected_index, current.status = previous_menu, previous_index, previous_status
        end
    end
    return false
end
return M
