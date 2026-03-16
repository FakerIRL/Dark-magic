-- Welcome to the script magic test beta 1.1

local on = false

local CFG = {}
CFG.RANGE = 35.0

CFG.LASER_RGBA = { 15, 0, 15, 220 }
CFG.MARKER_RGBA = { 15, 0, 15, 160 }

CFG.FIRE_ENABLED = true
CFG.PATCH_LIFE_MS = 2000
CFG.PATCH_STEP_DIST = 0.9
CFG.PATCH_MAX = 40

CFG.CHANNEL_KEY = 38

CFG.AUTO_OFF_ON_DEATH = true
CFG.AUTO_OFF_ON_UNARMED = true

CFG.PTFX_ASSET = "core"
CFG.PTFX_BEAM = "ent_amb_smoke_black"
CFG.PTFX_IMPACT = "ent_amb_smoke_black"

CFG.BEAM_STEPS = 26
CFG.BEAM_SCALE_MAIN = 1.05
CFG.BEAM_SCALE_SECOND = 0.75

CFG.IMPACT_SCALE_A = 1.75
CFG.IMPACT_SCALE_B = 1.35
CFG.IMPACT_SCALE_C = 1.10

CFG.VEHICLE_DAMAGE = true
CFG.VEH_ENGINE_MINUS = 45.0
CFG.VEH_BODY_MINUS = 25.0

CFG.RAY_FLAGS = (1 + 2 + 8)

local ptfxLoaded = false
local patches = {}
local lastPatchPos = nil
local lastWeapon = nil
local lastDead = false

local function rotToDir(r)
    local z = math.rad(r.z)
    local x = math.rad(r.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function vdist(a, b)
    return #(a - b)
end

local function vadd(a, b)
    return vector3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vsub(a, b)
    return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function vscale(a, s)
    return vector3(a.x * s, a.y * s, a.z * s)
end

local function loadPtfx()
    if ptfxLoaded then return end
    RequestNamedPtfxAsset(CFG.PTFX_ASSET)
    while not HasNamedPtfxAssetLoaded(CFG.PTFX_ASSET) do
        Wait(0)
    end
    ptfxLoaded = true
end

local function getRightHandPos(ped)
    local bone = GetPedBoneIndex(ped, 57005)
    local x, y, z = table.unpack(GetWorldPositionOfEntityBone(ped, bone))
    local f = GetEntityForwardVector(ped)
    return vector3(x, y, z) + vector3(f.x, f.y, f.z) * 0.12
end

local function raycastFromCamera(ped)
    local camC = GetGameplayCamCoord()
    local camR = GetGameplayCamRot(2)
    local dir = rotToDir(camR)
    local dest = camC + dir * CFG.RANGE

    local ray = StartShapeTestRay(
        camC.x, camC.y, camC.z,
        dest.x, dest.y, dest.z,
        CFG.RAY_FLAGS,
        ped,
        7
    )

    local _, hit, endc, _, ent = GetShapeTestResult(ray)
    if hit == 1 then
        return vector3(endc.x, endc.y, endc.z), ent or 0
    end
    return dest, 0
end

local function drawLaser(a, b)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, CFG.LASER_RGBA[1], CFG.LASER_RGBA[2], CFG.LASER_RGBA[3], CFG.LASER_RGBA[4])
    DrawMarker(28, b.x, b.y, b.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.09, 0.09, 0.09,
        CFG.MARKER_RGBA[1], CFG.MARKER_RGBA[2], CFG.MARKER_RGBA[3], CFG.MARKER_RGBA[4],
        false, true, 2, false, nil, nil, false
    )
end

local function smokeAt(pos, scale)
    UseParticleFxAssetNextCall(CFG.PTFX_ASSET)
    StartParticleFxNonLoopedAtCoord(CFG.PTFX_BEAM, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, scale, false, false, false)
end

local function impactAt(pos)
    UseParticleFxAssetNextCall(CFG.PTFX_ASSET)
    StartParticleFxNonLoopedAtCoord(CFG.PTFX_IMPACT, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, CFG.IMPACT_SCALE_A, false, false, false)
    smokeAt(pos + vector3(0.0, 0.0, 0.25), CFG.IMPACT_SCALE_B)
    smokeAt(pos + vector3(0.0, 0.0, 0.50), CFG.IMPACT_SCALE_C)
end

local function removePatch(i)
    local p = patches[i]
    if not p then return end
    if p.fire then
        RemoveScriptFire(p.fire)
    end
    table.remove(patches, i)
end

local function cleanupPatches()
    local now = GetGameTimer()
    for i = #patches, 1, -1 do
        local p = patches[i]
        if (now - p.t) >= CFG.PATCH_LIFE_MS then
            removePatch(i)
        end
    end
end

local function clearAllPatches()
    for i = #patches, 1, -1 do
        removePatch(i)
    end
    patches = {}
    lastPatchPos = nil
end

local function addPatch(pos)
    if #patches >= CFG.PATCH_MAX then
        removePatch(1)
    end

    local fire = nil
    if CFG.FIRE_ENABLED then
        fire = StartScriptFire(pos.x, pos.y, pos.z, 2, false)
    end

    patches[#patches + 1] = { pos = pos, t = GetGameTimer(), fire = fire }
    lastPatchPos = pos
end

local function maybeDropPatch(pos)
    if not lastPatchPos then
        addPatch(pos)
        return
    end
    if vdist(pos, lastPatchPos) >= CFG.PATCH_STEP_DIST then
        addPatch(pos)
    end
end

local function tryDamageVehicle(ent)
    if not CFG.VEHICLE_DAMAGE then return end
    if not ent or ent == 0 then return end
    if not IsEntityAVehicle(ent) then return end

    if not NetworkHasControlOfEntity(ent) then
        NetworkRequestControlOfEntity(ent)
    end

    if NetworkHasControlOfEntity(ent) then
        local eng = GetVehicleEngineHealth(ent)
        local bod = GetVehicleBodyHealth(ent)
        SetVehicleEngineHealth(ent, eng - CFG.VEH_ENGINE_MINUS)
        SetVehicleBodyHealth(ent, bod - CFG.VEH_BODY_MINUS)
    end
end

local function isChanneling()
    return IsControlPressed(0, CFG.CHANNEL_KEY)
end

local function blockCombat()
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 141, true)
    DisableControlAction(0, 142, true)
end

local function shouldAutoOffDeath(ped)
    if not CFG.AUTO_OFF_ON_DEATH then return false end
    return IsEntityDead(ped) == 1
end

local function shouldAutoOffUnarmed(ped)
    if not CFG.AUTO_OFF_ON_UNARMED then return false end
    local w = GetSelectedPedWeapon(ped)
    return w == `WEAPON_UNARMED`
end

local function setOn(v)
    if on == v then return end
    on = v
    if not on then
        clearAllPatches()
    end
end

local function forceOff()
    setOn(false)
end

local function channelTick(ped, startPos, endPos, ent)
    loadPtfx()

    local steps = CFG.BEAM_STEPS
    local delta = vscale(vsub(endPos, startPos), 1.0 / steps)

    local p = startPos
    for i = 1, steps do
        p = vadd(p, delta)
        smokeAt(p, CFG.BEAM_SCALE_MAIN)
        if (i % 2) == 0 then
            smokeAt(p, CFG.BEAM_SCALE_SECOND)
        end
    end

    impactAt(endPos)
    maybeDropPatch(endPos)
    tryDamageVehicle(ent)
end

RegisterNetEvent('darkmagic:toggle', function()
    setOn(not on)
end)

RegisterNetEvent('darkmagic:forceoff', function()
    forceOff()
end)

CreateThread(function()
    while true do
        if on then
            local ped = PlayerPedId()

            if shouldAutoOffDeath(ped) then
                forceOff()
                Wait(250)
            elseif shouldAutoOffUnarmed(ped) then
                forceOff()
                Wait(250)
            else
                local s = getRightHandPos(ped)
                local e, ent = raycastFromCamera(ped)

                drawLaser(s, e)

                if isChanneling() then
                    channelTick(ped, s, e, ent)
                end

                cleanupPatches()
                blockCombat()
                Wait(0)
            end
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if on and CFG.AUTO_OFF_ON_UNARMED then
            local ped = PlayerPedId()
            local w = GetSelectedPedWeapon(ped)

            if lastWeapon == nil then
                lastWeapon = w
            end

            if w ~= lastWeapon then
                lastWeapon = w
                if w == `WEAPON_UNARMED` then
                    forceOff()
                end
            end

            Wait(150)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if on and CFG.AUTO_OFF_ON_DEATH then
            local ped = PlayerPedId()
            local dead = (IsEntityDead(ped) == 1)

            if dead and not lastDead then
                lastDead = true
                forceOff()
            elseif not dead and lastDead then
                lastDead = false
            end

            Wait(200)
        else
            Wait(500)
        end
    end
end)

-- Useful Notes:
-- ScriptFire remains orange (color cannot be changed). The black smoke masks the orange.

-- If you want no orange: CFG.FIRE_ENABLED = false (you keep the visual "burn" as black smoke only).

-- Raycast includes mapping + objects + vehicles (world + vehicles + objects).

-- Patches last 2 seconds and disappear naturally, even if you move the aiming reticle.

-- notes dev by fake
