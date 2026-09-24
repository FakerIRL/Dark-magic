local enabled, lastHit, lastToggle, lastSpell = {}, {}, {}, {}
local nextZone = 0

local function allowed(src)
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function throttled(store, key, ms)
    local now = GetGameTimer()
    if store[key] and now - store[key] < ms then return true end
    store[key] = now
    return false
end

local function finite(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
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

local function casterPed(src)
    if not enabled[src] or not allowed(src) then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then return nil end
    return ped
end

local function withinOf(ped, target, extra)
    return #(GetEntityCoords(ped) - target) <= Config.Range + extra
end

local function chargeOf(v)
    local ch = finite(v)
    if not ch and tonumber(v) == math.huge then ch = 1.0 end
    if not ch then return nil end
    return math.min(math.max(ch, 0.0), 1.0)
end

local function pointOf(x, y, z)
    x, y, z = finite(x), finite(y), finite(z)
    if not (x and y and z) then return nil end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then return nil end
    return vector3(x, y, z)
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

    local ped = casterPed(src)
    local targetPed = GetPlayerPed(target)
    if not ped or targetPed == 0 then return end
    if throttled(lastHit, src, Config.Damage.intervalMs - 60) then return end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then return end
    if not withinOf(ped, GetEntityCoords(targetPed), 15.0) then return end

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

    local ped = casterPed(src)
    if not ped then return end
    if throttled(lastHit, 'veh' .. src, Config.Damage.intervalMs - 60) then return end
    local veh = NetworkGetEntityFromNetworkId(id)
    if not veh or veh == 0 or GetEntityType(veh) ~= 2 then return end
    if not withinOf(ped, GetEntityCoords(veh), 15.0) then return end

    local owner = NetworkGetEntityOwner(veh)
    if owner and owner > 0 then
        TriggerClientEvent('darkmagic:vehicleHit', owner, id, Config.Damage.vehicle.engine * ch, Config.Damage.vehicle.body * ch)
    end
end)

RegisterNetEvent('darkmagic:curse', function(x, y, z)
    local src = source
    local C = Config.Spells.curse
    local pos = pointOf(x, y, z)
    local ped = casterPed(src)
    if not pos or not ped then return end
    if throttled(lastSpell, 'curse' .. src, C.cooldownMs - 100) then return end
    if not withinOf(ped, pos, 15.0) then return end

    nextZone = nextZone + 1
    TriggerClientEvent('darkmagic:zone', -1, nextZone, src, pos.x, pos.y, pos.z, C.radius, C.durationMs)
end)

RegisterNetEvent('darkmagic:blast', function(x, y, z, kind)
    local src = source
    if kind ~= 'burst' and kind ~= 'orb' then return end
    local pos = pointOf(x, y, z)
    local ped = casterPed(src)
    if not pos or not ped then return end
    if throttled(lastSpell, 'blast' .. src, 300) then return end
    if not withinOf(ped, pos, Config.Range * (Config.Spells.orb.rangeMul - 1.0) + 15.0) then return end

    TriggerClientEvent('darkmagic:blastFx', -1, src, pos.x, pos.y, pos.z, kind)
end)

AddStateBagChangeHandler('darkmagic', nil, function(bagName, _, value, _, replicated)
    local src = tonumber(bagName:match('^player:(%d+)$'))
    if src and replicated and value and not enabled[src] then
        Player(src).state:set('darkmagic', false, true)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    enabled[src], lastHit[src], lastHit['veh' .. src], lastToggle[src] = nil, nil, nil, nil
    lastSpell['curse' .. src], lastSpell['blast' .. src] = nil, nil
end)

exports('setState', function(src, state)
    src = tonumber(src)
    if src and GetPlayerPed(src) ~= 0 then setState(src, state == true) end
end)

exports('isEnabled', function(src)
    return enabled[tonumber(src)] == true
end)

if GetConvar('onesync', 'off') == 'off' then
    print('[dark_magic] OneSync is required for player damage, curses and beam sync')
end
