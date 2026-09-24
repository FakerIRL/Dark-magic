local enabled = {}
local lastHit = {}

local function allowed(src)
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function setState(src, state)
    enabled[src] = state or nil
    TriggerClientEvent('darkmagic:setState', src, state)
end

RegisterCommand('darkmagic', function(src)
    if src == 0 then return end
    if not allowed(src) then
        TriggerClientEvent('darkmagic:denied', src)
        return
    end
    setState(src, not enabled[src])
end, false)

RegisterCommand('darkmagicoff', function(src)
    if src == 0 then return end
    setState(src, false)
end, false)

RegisterNetEvent('darkmagic:requestToggle', function()
    local src = source
    if not allowed(src) then
        TriggerClientEvent('darkmagic:denied', src)
        return
    end
    setState(src, not enabled[src])
end)

RegisterNetEvent('darkmagic:hit', function(targetId, charge)
    local src = source
    if not enabled[src] or not Config.Damage.players.enabled then return end

    local target = tonumber(targetId)
    if not target or target == src then return end

    local casterPed, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    if casterPed == 0 or targetPed == 0 then return end

    local now = GetGameTimer()
    if lastHit[src] and now - lastHit[src] < Config.Damage.intervalMs - 60 then return end
    lastHit[src] = now

    if #(GetEntityCoords(casterPed) - GetEntityCoords(targetPed)) > Config.Range + 15.0 then return end

    local ch = math.min(math.max(tonumber(charge) or 0.0, 0.0), 1.0)
    TriggerClientEvent('darkmagic:takeHit', target, src, math.floor(Config.Damage.ped.amount * ch))
end)

AddEventHandler('playerDropped', function()
    enabled[source] = nil
    lastHit[source] = nil
end)
