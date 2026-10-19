-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Final one-way associated-content stage. Only the selected provider may add
-- outputs, and an associated output can never become another source.
local hot = require("zhvjia/hot").F
local interaction = require("zhvjia/interaction")
local presentation = require("zhvjia/presentation")
local content = require("zhvjia/content")
local plans = require("zhvjia/association_plan")
local F = {}
function F.init(env)
    hot.init(env)
    local at = presentation.setting_path(env, "content/english_template") or
        "zhvjia_associations/templates/english_translation"
    env.gloss_plan, env.gloss_plan_error = plans.load(env.engine.schema.config, at)
    env.engine.context:set_property("zhvjia_translation_error", env.gloss_plan_error or "")
end
F.fini = hot.fini
function F.tags_match(_, env)
    return content.includes(env, "english_translation")
end
local function english(env, source)
    local genuine = source:get_genuine()
    local values = hot.lookup_all(env, source.text) or hot.lookup_all(env, genuine.text)
    if not values then return {source} end
    local pool, rows = {}, {}
    for _, value in ipairs(values) do
        if value ~= source.text then
            local item = Candidate("zhvjia_gloss", source.start, source._end, value, "")
            item.preedit, item.quality = source.preedit, source.quality
            pool[#pool + 1] = item
            rows[#rows + 1] = {kind="output", candidate=item, style_key="translation.rod"}
        end
    end
    if #pool == 0 then return {source} end
    local spec = plans.instantiate(env.gloss_plan, pool, {style_key="translation.source"}, "translation") or
        {source={style_key="translation.source", rod=rows}}
    spec.tip = presentation.dedicated_tip(env, source)
    return interaction.build(env, source, spec)
end
function F.func(input, env)
    if not F.tags_match(nil, env) then
        for candidate in input:iter() do yield(candidate) end
        return
    end
    for candidate in input:iter() do
        if presentation.is_associated(env, candidate) or candidate.type == "zhvjia_gloss" then yield(candidate)
        else
            for _, item in ipairs(english(env, candidate)) do yield(item) end
        end
    end
end
return {F=F}
