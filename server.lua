local enabled, lastHit, lastToggle = {}, {}, {}

local function allowed(src)
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function throttled(store, src, ms)
    local now = GetGameTimer()
    if store[src] and now - store[src] < ms then return true end
    store[src] = now
    return false
end

local function setState(src, state)
    enabled[src] = state or nil
    if not state then Player(src).state:set('darkmagic', false, true) end
    TriggerClientEvent('darkmagic:setState', src, state == true)
end

local function toggle(src)
    if throttled(lastToggle, src, 500) then return end
    if not allowed(src) then
        TriggerClientEvent('darkmagic:denied', src)
        return
    end
    setState(src, not enabled[src])
end

local function casterOk(src, key)
    if not enabled[src] or not allowed(src) then return nil end
    if throttled(lastHit, key, Config.Damage.intervalMs - 60) then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then return nil end
    return ped
end

local function inRange(a, b)
    return #(GetEntityCoords(a) - GetEntityCoords(b)) <= Config.Range + 15.0
end

local function chargeOf(v)
    local ch = tonumber(v)
    if not ch or ch ~= ch then return nil end
    return math.min(math.max(ch, 0.0), 1.0)
end

RegisterCommand('darkmagic', function(src)
    if src ~= 0 then toggle(src) end
end, false)

RegisterCommand('darkmagicoff', function(src)
    if src ~= 0 then setState(src, false) end
end, false)

RegisterNetEvent('darkmagic:requestToggle', function()
    toggle(source)
end)

RegisterNetEvent('darkmagic:clientOff', function()
    enabled[source] = nil
    Player(source).state:set('darkmagic', false, true)
end)

RegisterNetEvent('darkmagic:hit', function(targetId, charge)
    local src = source
    if not Config.Damage.players.enabled then return end
    local target = tonumber(targetId)
    if not target or target == src then return end
    local ch = chargeOf(charge)
    if not ch then return end

    local casterPed = casterOk(src, src)
    local targetPed = GetPlayerPed(target)
    if not casterPed or targetPed == 0 then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return end
    if not inRange(casterPed, targetPed) then return end

    local dmg = math.floor(Config.Damage.ped.amount * ch)
    if dmg <= 0 then return end
    TriggerClientEvent('darkmagic:takeHit', target, src, dmg)
end)

RegisterNetEvent('darkmagic:hitVehicle', function(netId, charge)
    local src = source
    if not Config.Damage.vehicle.enabled then return end
    local ch = chargeOf(charge)
    local id = tonumber(netId)
    if not ch or not id then return end

    local casterPed = casterOk(src, 'veh' .. src)
    if not casterPed then return end
    local veh = NetworkGetEntityFromNetworkId(id)
    if not veh or veh == 0 or GetEntityType(veh) ~= 2 then return end
    if not inRange(casterPed, veh) then return end

    local owner = NetworkGetEntityOwner(veh)
    if owner and owner > 0 then
        TriggerClientEvent('darkmagic:vehicleHit', owner, id, Config.Damage.vehicle.engine * ch, Config.Damage.vehicle.body * ch)
    end
end)

AddStateBagChangeHandler('darkmagic', nil, function(bagName, _, value, _, replicated)
    local src = tonumber(bagName:match('^player:(%d+)$'))
    if src and replicated and value and not enabled[src] then
        Player(src).state:set('darkmagic', false, true)
    end
end)

AddEventHandler('playerDropped', function()
    enabled[source], lastHit[source], lastHit['veh' .. source], lastToggle[source] = nil, nil, nil, nil
end)

exports('setState', function(src, state)
    src = tonumber(src)
    if src and GetPlayerPed(src) ~= 0 then setState(src, state == true) end
end)

exports('isEnabled', function(src)
    return enabled[tonumber(src)] == true
end)

if GetConvar('onesync', 'off') == 'off' then
    print('[dark_magic] OneSync is required for player damage and beam sync')
end
