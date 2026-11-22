-- Lightweight multiplayer gate driven only by the local action transition.
-- It deliberately does not inspect identity, role, manager, performer, pawn,
-- controller, or character ownership data.

local Log = require("fd_tcode.core.log")

local LOCAL_ACTION_HOOK = "/Script/Paralogue.RoomManagerBase:OnLocalPlayerActionChanged"
local ACTION_NONE = 0
local ACTION_IN_H = 2
local ACTION_IN_DUMMY_H = 4

-- LOCAL PATCH (Fallen Doll 0.9.1 rehost build)
-- This build routes player actions through the rehost local DS proxy and does
-- not reach RoomManagerBase:OnLocalPlayerActionChanged, so the hook never
-- fires and the gate stays shut. FD_TCODE_FORCE_GATE=1 keeps it open so the
-- 4 Hz detector can evaluate HAnime state itself (single-player use).
local FORCE = os ~= nil and os.getenv ~= nil and os.getenv("FD_TCODE_FORCE_GATE") == "1"

local Gate = {
    active = false,
    listener = nil,
    started = false,
    hook_attempts = 0,
}

local function enum_number(parameter)
    if parameter == nil then
        return nil
    end
    local ok, value = pcall(function()
        return parameter:get()
    end)
    if ok then
        return tonumber(value)
    end
    return tonumber(parameter)
end

local function notify_listener()
    if type(Gate.listener) ~= "function" then
        return
    end
    local ok, listener_error = pcall(Gate.listener, Gate.active)
    if not ok then
        Log.warn("Local action gate listener failed: " .. tostring(listener_error))
    end
end

local function set_active(active, action)
    active = active == true
    if FORCE and not active then
        return
    end
    if Gate.active == active then
        return
    end
    Gate.active = active
    notify_listener()
    Log.info(string.format(
        "Local action gate active=%s action=%d",
        tostring(active),
        tonumber(action or ACTION_NONE)
    ))
end

local function local_action_callback(new_action_parameter)
    local new_action = enum_number(new_action_parameter)
    if new_action == ACTION_IN_H or new_action == ACTION_IN_DUMMY_H then
        set_active(true, new_action)
    elseif new_action == ACTION_NONE then
        set_active(false, new_action)
    end
    new_action = nil
    new_action_parameter = nil
end

local function stable_hook_callback(_, ...)
    local seen = tonumber(_G.FD_TCODE_GATE_HOOK_SEEN or 0) + 1
    _G.FD_TCODE_GATE_HOOK_SEEN = seen
    if seen <= 10 then
        local arg_count = select("#", ...)
        local a3 = select(3, ...)
        local ok3, text3 = pcall(function()
            return tostring(a3)
        end)
        Log.info(string.format(
            "Local action hook fired seen=%d argc=%d arg3=%s",
            seen,
            arg_count,
            ok3 and text3 or "<unreadable>"
        ))
    end
    local handler = _G.FD_TCODE_LOCAL_ACTION_GATE_HANDLER
    if type(handler) == "function" then
        -- Runtime validation established the new-action enum in slot 3. Only
        -- that enum crosses the stable hook boundary; every other callback
        -- argument is ignored without assignment or conversion.
        handler(select(3, ...))
    end
end

function Gate.try_register()
    _G.FD_TCODE_LOCAL_ACTION_GATE_HANDLER = local_action_callback
    if _G.FD_TCODE_LOCAL_ACTION_GATE_REGISTERED then
        return true
    end
    if type(RegisterHook) ~= "function" then
        return false
    end
    Gate.hook_attempts = Gate.hook_attempts + 1
    local ok, pre_id, post_id = pcall(function()
        return RegisterHook(LOCAL_ACTION_HOOK, stable_hook_callback)
    end)
    if ok and (pre_id ~= nil or post_id ~= nil) then
        _G.FD_TCODE_LOCAL_ACTION_GATE_REGISTERED = true
        Log.info("Local action gate registered")
        return true
    end
    Log.info(string.format(
        "Local action gate pending attempt=%d",
        Gate.hook_attempts
    ))
    return false
end

function Gate.world_changed()
    Gate.active = false
    notify_listener()
    Gate.try_register()
    if FORCE then
        Gate.active = true
        notify_listener()
        Log.info("Local action gate forced open (FD_TCODE_FORCE_GATE=1)")
    end
end

function Gate.start(listener)
    if type(listener) == "function" then
        Gate.listener = listener
    end
    Gate.active = false
    notify_listener()
    Gate.try_register()
    if FORCE then
        Gate.active = true
        notify_listener()
        Log.info("Local action gate forced open (FD_TCODE_FORCE_GATE=1)")
    end
    if not Gate.started then
        Gate.started = true
        Log.info("Local action gate armed; default=inactive")
    end
end

function Gate.is_active()
    if FORCE then
        return true
    end
    return Gate.active == true
end

return Gate
