-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- One owner per key: explicit modes first, then shared primary editing.
local settings = require("zhvjia/config")
local runtime = require("zhvjia/runtime")
local modes = require("zhvjia/modes")
local primary = require("zhvjia/primary")
local auxiliary = require("zhvjia/auxiliary")
local creation = require("zhvjia/creation")
local calculator = require("zhvjia/calculator_mode")
local code = require("zhvjia/code_mode")
local catalog = require("zhvjia/catalog_mode")
local unicode = require("zhvjia/unicode_mode")
local interaction = require("zhvjia/interaction")
local clock = require("zhvjia/clock")
local literal_editor = require("zhvjia/literal_editor")
local content = require("zhvjia/content")
local characters = require("zhvjia/select_char").P
local tips = require("super_tips")
local M,P = {},{}
local ACCEPT,NOOP,REJECT = 1,2,0
local SWITCH = { [0xFFE1]=true,[0xFFE2]=true,[0xFFE5]=true,[0xff30]=true }
local function literal(key)
    return key.keycode>=32 and key.keycode<127 and string.char(key.keycode) or nil
end
local function native(env,key,names)
    for _,name in ipairs(names) do
        local result=env._native[name]:process_key_event(key)
        if result~=NOOP then return result end
    end
    return REJECT
end
local function fallback(key)
    return (key:ctrl() or key:alt() or key:super()) and REJECT or ACCEPT
end
local function once(key,env)
    if env._once_in_event then return true end
    local caps=interaction.capabilities(env)
    if not caps.key_release or not caps.focus_cancel or caps.epoch=="" then return true end
    local held=env._action_keys[key.keycode]
    if held==caps.epoch then return false end
    env._action_keys[key.keycode]=caps.epoch
    env._once_in_event=true
    return true
end
local function content_gesture(key,env,current)
    local ctx,kc=env.engine.context,key.keycode
    local epoch=interaction.capabilities(env).epoch
    if env._content_epoch~=epoch then
        env._content_epoch=epoch; env._content_keys={}; env._content_hold=nil
    end
    local pending=env._content_hold
    if pending and (env._zhvjia_config_error or current~="primary" or ctx.input_revision~=pending.revision or
        ctx.view_revision~=pending.view or interaction.capabilities(env).epoch~=pending.epoch) then
        env._content_hold=nil; pending=nil
    end
    if key:release() then
        if env._content_keys[kc] then
            env._content_keys[kc]=nil
            if pending and pending.key==kc then
                env._content_hold=nil; content.handle(env,pending.config.unused_release)
            end
            return ACCEPT
        end
        return nil
    end
    if env._content_keys[kc] then return ACCEPT end
    if pending then
        env._content_hold=nil
        local action=pending.config.secondary[key:repr()]
        if action then
            once(key,env); content.handle(env,action); return ACCEPT
        end
        -- Unregistered keys cancel, then have their ordinary meaning once.
    end
    local hold=current=="primary" and not env._zhvjia_config_error and content.hold(env)
    if hold and hold.first==key:repr() and ctx:has_menu() then
        interaction.cancel(env)
        env._content_keys[kc]=true
        env._content_hold={key=kc,config=hold,revision=ctx.input_revision,
            view=ctx.view_revision,epoch=interaction.capabilities(env).epoch}
        return ACCEPT
    end
end
function M.visible_body(ctx)
    if type(ctx.get_preedit_body)=="function" then return ctx:get_preedit_body() end
    local preedit=ctx:get_preedit()
    if not preedit then return nil end
    local prompt=not ctx.composition:empty() and ctx.composition:back().prompt or ""
    local decoration=(ctx:get_option("soft_cursor") and "‸" or "")..(prompt or "")
    if decoration=="" then return preedit.text end
    local at=preedit.caret_pos
    if preedit.text:sub(at+1,at+#decoration)~=decoration then return nil end
    return preedit.text:sub(1,at)..preedit.text:sub(at+#decoration+1)
end
local function choose(env,index)
    local ctx=env.engine.context
    if ctx.composition:empty() then return false end
    local seg=ctx.composition:back()
    if index then
        local size=env.engine.schema.page_size or 9
        local at=math.floor((seg.selected_index or 0)/size)*size+index-1
        if seg:get_candidate_at(at) then return interaction.select_main(env,at) end
    else
        if ctx:get_selected_candidate() then return interaction.select_main(env,seg.selected_index or 0) end
    end
    return false
end
local function candidate_key(key,env)
    local ctx,repr=env.engine.context,key:repr()
    if key:ctrl() or key:alt() or key:super() or key:shift() then return nil end
    local kc=key.keycode
    -- Page_Down/KP_Page_Down stringify as Next/KP_Next on this Rime build.
    -- The native selector also owns lazy page loading, boundaries and paging.
    if kc==0xff55 or kc==0xff56 or kc==0xff9a or kc==0xff9b then
        native(env,key,{"selector"})
        env._primary_undo=nil
        primary.project(env)
        if unicode.active(ctx) then unicode.view(env) end
        return ACCEPT
    end
    if repr=="Up" or repr=="KP_Up" or repr=="Down" or repr=="KP_Down" then
        if not ctx.composition:empty() then
            local current=ctx.composition:back().selected_index or 0
            local previous=repr:find("Up",1,true)~=nil
            if ctx:highlight(math.max(0,current+(previous and -1 or 1))) then
                local seg=ctx.composition:back()
                seg.tags=seg.tags+Set({"paging"})
            end
        end
        env._primary_undo=nil
        primary.project(env)
        if unicode.active(ctx) then unicode.view(env) end
        return ACCEPT
    end
    local n=(kc>=0x31 and kc<=0x39 and kc-0x30) or (kc>=0xFFB1 and kc<=0xFFB9 and kc-0xFFB0)
    if n then if once(env._physical_key or key,env) then choose(env,n) end; return ACCEPT end
    if repr=="space" then if once(env._physical_key or key,env) then choose(env) end; return ACCEPT end
end
function P.init(env)
    local snapshot=modes.options(env)
    env._control_switches={}
    env._action_keys={}
    env._content_keys={}
    env._native={}
    for _,name in ipairs({"ascii_composer","recognizer","speller","punctuator","selector","navigator","express_editor"}) do
        env._native[name]=assert(Component.Processor(env.engine,name,name))
    end
    env._tips_env={engine=env.engine,name_space="super_tips"}
    tips.init(env._tips_env)
    interaction.P.init(env)
    require("zhvjia/presentation").set_compact_access(env,next(snapshot.variants)~=nil)
    env.engine.context:set_property("zhvjia_config_error",env._zhvjia_config_error or "")
    env.control_update=env.engine.context.update_notifier:connect(function(ctx)
        runtime.publish(env)
        if ctx.input=="" then
            ctx:set_property("zhvjia_last_cursor_key","")
            interaction.clear_focus(env)
        end
    end)
    env.creation_edit=primary.handle
    env.creation_after_selection=auxiliary.after_selection
    creation.init(env)
    primary.init(env)
    unicode.P.init(env)
    code.P.init(env)
    calculator.P.init(env)
    catalog.P.init(env)
    runtime.publish(env)
end
function P.fini(env)
    interaction.P.fini(env)
    tips.fini(env._tips_env)
    interaction.clear_focus(env)
    catalog.P.fini(env); calculator.P.fini(env); code.P.fini(env); unicode.P.fini(env); primary.fini(env); creation.fini(env)
    if env.control_update then env.control_update:disconnect() end
    env._native=nil
end
function P.func(key,env)
    env._physical_key=key
    env._once_in_event=false
    local ctx,repr=env.engine.context,key:repr() or ""
    local current=runtime.publish(env)
    local snapshot,diagnostic=settings.get(env)
    if ctx:get_property("zhvjia_config_error")~=(diagnostic or "") then
        ctx:set_property("zhvjia_config_error",diagnostic or "")
        if diagnostic and log and log.warning then log.warning("zhvjia: "..diagnostic) end
    end
    local switches=env._control_switches
    if key:release() and switches[key.keycode] then switches[key.keycode]=nil; return ACCEPT end
    local special=current~="primary" and current~="idle" and current~="ascii" and current~="literal"
    if special and SWITCH[key.keycode] then
        if not key:release() then switches[key.keycode]=true end
        return ACCEPT
    end
    if special and key.caps and key:caps() and not key:release() then
        key=KeyEvent(key.keycode,key.modifier-2)
        repr=key:repr()
    end
    -- One real composer sees both halves of every modifier combination before
    -- any Lua action can consume its second key. Never simulate its state.
    local ascii=env._native.ascii_composer:process_key_event(key)
    if ascii~=NOOP then return ascii end
    if key:release() then
        if key.keycode==0xff08 then env._backspace_guard=nil end
        local owned=env._action_keys[key.keycode]
        env._action_keys[key.keycode]=nil
        local gesture=content_gesture(key,env,current)
        if gesture then return gesture end
        local result=interaction.P.func(key,env)
        if result~=NOOP then return result end
        return owned and ACCEPT or REJECT
    end
    local pressed=env._action_keys[key.keycode]
    if pressed and pressed==interaction.capabilities(env).epoch then return ACCEPT end
    -- Preserve the desktop habit: a continuous Backspace that started in a
    -- composition stops once that composition is empty. A fresh idle press
    -- still reaches the host and Rime's native recent-learning undo handler.
    if key.keycode==0xff08 then
        if key:release() then env._backspace_guard=nil
        elseif not key:alt() and not key:super() and snapshot.modes.primary.protect_backspace then
            local caps=interaction.capabilities(env)
            local guard=env._backspace_guard
            if not caps.key_release or not caps.focus_cancel or caps.epoch=="" then
                env._backspace_guard=nil
            elseif guard and guard.epoch==caps.epoch and guard.schema==env.engine.schema.schema_id then
                if ctx.input=="" then return ACCEPT end
            elseif current=="primary" then
                env._backspace_guard={epoch=caps.epoch,schema=env.engine.schema.schema_id}
            else env._backspace_guard=nil end
        end
    elseif not key:release() then env._backspace_guard=nil end
    local modified=key:ctrl() or key:alt() or key:super()
    local char=not modified and literal(key)
    local gesture=content_gesture(key,env,current)
    if gesture then return gesture end
    local content_action=current=="primary" and snapshot.content[repr]
    if content_action then
        interaction.cancel(env)
        local caps=interaction.capabilities(env)
        if content_action=="cycle" and not (caps.key_release and caps.focus_cancel and caps.epoch~="") then
            ctx:set_property("zhvjia_content_error","Cycle requires reliable key release; configure direct mode keys on this device")
            return ACCEPT
        end
        if once(env._physical_key,env) then content.handle(env,content_action) end
        return ACCEPT
    end
    local held=interaction.P.func(key,env)
    if held~=NOOP then return held end
    local variant=current=="primary" and snapshot.variants[repr]
    if variant then
        interaction.cancel(env)
        if once(env._physical_key,env) and not ctx.composition:empty() then
            interaction.select_variant(env,ctx.composition:back().selected_index or 0,variant)
        end
        return ACCEPT
    end
    local rule=snapshot.modes[current]
    local binding,first_page_comma=settings.binding(snapshot,current,repr,ctx)
    if first_page_comma then
        interaction.clear_focus(env)
        if not once(env._physical_key,env) then return ACCEPT end
        -- Finish an owned command prefix before punctuation changes its route.
        -- Primary input keeps the native punctuation/partial-phrase behavior.
        if current~="primary" then
            if not choose(env) then return ACCEPT end
            if ctx:is_composing() and ctx.composition:has_finished_composition() then ctx:commit() end
            if ctx:is_composing() then return ACCEPT end
        end
        return native(env,key,{"punctuator","express_editor"})
    end
    if rule and rule.reserved[repr] and not binding then return ACCEPT end
    if binding and binding.canonical then
        key=KeyEvent(binding.canonical)
        repr=key:repr()
        modified=key:ctrl() or key:alt() or key:super()
        char=not modified and literal(key)
    end
    if binding and binding.action=="consume_no_action" then return ACCEPT end
    if binding and (binding.id=="previous_page" or binding.id=="next_page") then
        interaction.clear_focus(env)
        if current=="creation" then creation.edited(env) end
        return candidate_key(key,env) or ACCEPT
    end
    -- Atomic/special translators may confirm inside their own processor. Mark
    -- those physical keys before delegating, just like ordinary selection.
    if current~="primary" and current~="idle" and current~="ascii" and current~="literal" then
        local code=key.keycode
        local digit=not (key:shift() or modified) and
            ((code>=0x31 and code<=0x39) or (code>=0xffb1 and code<=0xffb9))
        local literal_digit=current=="calculator" or (current=="code" and
            snapshot.modes.code.digits[code>=0xffb0 and "keypad" or "main"]=="literal")
        if ((binding and (binding.id=="select_current" or binding.id=="select_result" or binding.id=="save")) or
            (digit and not literal_digit)) and not once(env._physical_key,env) then return ACCEPT end
    end
    -- Keep configurable symbolic entries in composition until they route.
    if char and (current=="idle" or current=="slash" or current=="literal") then
        local next_raw=ctx.input..char
        for _,entry in ipairs(snapshot.entries) do
            if entry.entry:sub(1,#next_raw)==next_raw then ctx:push_input(char); return ACCEPT end
        end
    end
    if current=="literal" and ctx.input:match("^[a-z]+/$") then
        local result=require("zhvjia/session").P.func(key,env)
        if result~=NOOP then return result end
    end
    if current=="idle" or current=="ascii" or current=="literal" then
        if modified then return REJECT end
        if key:release() then return REJECT end
        if char or repr=="BackSpace" or repr=="Delete" or repr=="Escape" or
            repr=="Return" or repr=="KP_Enter" or repr=="Tab" or
            repr=="Left" or repr=="Right" or repr=="Home" or repr=="End" then
            return native(env,key,{"recognizer","speller","punctuator","selector","navigator","express_editor"})
        end
        return REJECT
    end
    if current=="invalid" then
        if repr=="Escape" then ctx:clear(); return ACCEPT end
        local editing=literal_editor.handle(key,env,0)
        return editing~=NOOP and editing or fallback(key)
    end
    if current=="calculator" then
        if binding and binding.action=="activate_current" then
            if once(env._physical_key,env) then calculator.confirm(env) end
            return ACCEPT
        end
        local result=calculator.P.func(key,env)
        return result~=NOOP and result or fallback(key)
    end
    if current=="creation" then
        local result=creation.handle(key,env,primary.handle)
        if result~=NOOP then return result end
        local selection=candidate_key(key,env)
        return selection or fallback(key)
    end
    if current=="code" then
        local result=code.P.func(key,env)
        if result~=NOOP then return result end
        return candidate_key(key,env) or (modified and REJECT or ACCEPT)
    end
    if current=="catalog" then
        local result=catalog.P.func(key,env)
        if result~=NOOP then return result end
        return candidate_key(key,env) or (modified and REJECT or ACCEPT)
    end
    if current=="primary" or current=="unicode" then
        -- No arrow enters a rod implicitly. Only configured actions do so.
        local action=current=="primary" and snapshot.navigation[repr]
        if action then
            if action=="enter" then interaction.enter_rod(env)
            elseif action=="leave" then interaction.leave_rod(env)
            elseif action=="confirm" then interaction.select_focused(env)
            elseif interaction.has_focus(env) then interaction.navigate(env,action) end
            return ACCEPT
        end
        if interaction.has_focus(env) then
            if repr=="Escape" then interaction.leave_rod(env); return ACCEPT end
            if repr=="space" or repr=="Return" or repr=="KP_Enter" then interaction.select_focused(env); return ACCEPT end
            interaction.clear_focus(env) -- unrelated edits retain ordinary meaning
        end
        if current=="unicode" then
            local result=unicode.P.func(key,env)
            if result~=NOOP then return result end
            return candidate_key(key,env) or fallback(key)
        end
        if ctx.input=="chapianduan`" and char=="`" and ctx.caret_pos==#ctx.input then
            ctx:push_input("`"); return ACCEPT
        end
        local code_result=code.P.func(key,env)
        if code_result~=NOOP then return code_result end
        local unicode_result=unicode.P.func(key,env)
        if unicode_result~=NOOP then return unicode_result end
        if binding and binding.action=="commit_visible_preedit" then
            if once(env._physical_key,env) then
                local view=primary.view(env)
                local body=view and view.text or M.visible_body(ctx)
                body=primary.enter_body(body)
                if body and body~="" then env.engine:commit_text(body); ctx:clear() end
            end
            return ACCEPT
        end
        local edit=primary.handle(key,env)
        if edit~=NOOP then return edit end
        local selection=candidate_key(key,env)
        if selection then return selection end
        local option=settings.compatibility[repr]
        if option then
            if once(env._physical_key,env) then ctx:set_option(option,not ctx:get_option(option)) end
            return ACCEPT
        end
        if repr=="Control+Delete" then
            local candidate=ctx:get_selected_candidate()
            local genuine=candidate and candidate:get_genuine()
            if genuine and candidate.text==genuine.text and
                (genuine.type=="phrase" or genuine.type=="user_phrase") and once(env._physical_key,env) then
                return native(env,key,{"express_editor"})
            end
            return ACCEPT
        end
        if modified then return REJECT end
        if repr=="0" or repr=="KP_0" then
            tips.func(KeyEvent("0"),env._tips_env); return ACCEPT
        end
        if char then
            local result=characters.func(key,env)
            if result~=NOOP then return result end
            return native(env,key,{"recognizer","speller","punctuator","express_editor"})
        end
        return ACCEPT
    end
    if current=="slash" then
        local legacy=require("zhvjia/session").P.func(key,env)
        if legacy~=NOOP then return legacy end
        local range=require("zhvjia/letters").P.func(key,env)
        if range~=NOOP then return range end
    end
    if current=="clock" then
        if repr=="space" and not modified and snapshot.modes.clock.space_format~="current" then
            if not clock.select_format(env,snapshot.modes.clock.space_format) then
                ctx:set_property("zhvjia_clock_error","Space format is absent from the current group: "..snapshot.modes.clock.space_format)
            end
            return ACCEPT
        end
        if repr=="Return" or repr=="KP_Enter" then choose(env); return ACCEPT end
        if repr=="semicolon" or repr=="colon" then clock.select_format(env,"colon"); return ACCEPT end
        if repr=="minus" or repr=="KP_Subtract" then clock.select_format(env,"hyphen"); return ACCEPT end
        local selection=candidate_key(key,env)
        if selection then return selection end
    end
    if current=="reverse" or current=="letters" or current=="slash" or current=="clock" then
        if repr=="Escape" then ctx:clear(); return ACCEPT end
        local _,entry=runtime.of(env)
        local editing=literal_editor.handle(key,env,current=="reverse" and #entry or 0)
        if editing~=NOOP then return editing end
        if repr=="Return" or repr=="KP_Enter" then choose(env); return ACCEPT end
        if current~="slash" or #ctx.input>1 then
            local selection=candidate_key(key,env)
            if selection then return selection end
        end
        if char and char:match("^[A-Za-z]$") then ctx:push_input(char); return ACCEPT end
        -- Symbol command prefix and /0..10 retain native punctuator admission.
        if current=="slash" and char and (char:match("^[0-9]$") or char=="/") then
            return native(env,key,{"recognizer","speller","punctuator"})
        end
        return modified and REJECT or ACCEPT
    end
    if special and (repr=="Tab" or repr=="Shift+Tab" or repr=="ISO_Left_Tab") then return ACCEPT end
    if repr=="Escape" then ctx:clear(); return ACCEPT end
    -- Remaining slash/reverse/catalog providers have no competing old mode
    -- processors. Their literal editing and native selector remain available.
    return fallback(key)
end
M.P=P
M.mode=function(ctx) return runtime.mode(ctx,assert(settings.load(nil))) end
return M
