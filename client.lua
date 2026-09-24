local Cfg = Config
local UNARMED = GetHashKey('WEAPON_UNARMED')
local HAND_BONE = 57005
local RAY_FLAGS = 1 + 2 + 8 + 16
local COMBAT_CONTROLS = { 24, 25, 140, 141, 142, 257, 263, 264 }
local CAST_CONTROLS = { 38, 51 }
local TAU = 6.28318

local armed, ready, casting, keyDown = false, false, false, false
local armedAt, castStart, charge = 0, 0, 0.0
local lastAim, lastHitEnt, impactIndex = nil, 0, 0
local timers, patches, remote = {}, {}, {}
local lastPatchPos, loopSound
local aura = { ped = 0, fx = {} }
local loaded = { ptfx = {}, anim = {} }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function easeOut(t)
    return 1.0 - (1.0 - t) * (1.0 - t)
end

local function normalize(v)
    local l = #v
    if l < 0.0001 then return vector3(0.0, 1.0, 0.0) end
    return v * (1.0 / l)
end

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function due(store, key, ms, now)
    local t = store[key]
    if t and now - t < ms then return false end
    store[key] = now
    return true
end

local function rotToDir(r)
    local z, x = math.rad(r.z), math.rad(r.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function notify(msg)
    if not Cfg.Notify or not msg then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

local function waitFor(kind, key, request, check)
    local cache = loaded[kind]
    if cache[key] ~= nil then return cache[key] end
    request(key)
    local deadline = GetGameTimer() + Cfg.LoadTimeoutMs
    while not check(key) do
        if GetGameTimer() > deadline then
            cache[key] = false
            print(('[dark_magic] failed to load %s "%s"'):format(kind, key))
            return false
        end
        Wait(0)
    end
    cache[key] = true
    return true
end

local function loadPtfx(asset)
    return waitFor('ptfx', asset, RequestNamedPtfxAsset, HasNamedPtfxAssetLoaded)
end

local function loadAnim(dict)
    return waitFor('anim', dict, RequestAnimDict, HasAnimDictLoaded)
end

local function preload()
    local P = Cfg.Ptfx
    for _, fx in ipairs(P.hand) do loadPtfx(fx.asset) end
    for _, fx in ipairs(P.beam.fx) do loadPtfx(fx.asset) end
    for _, fx in ipairs(P.impact.fx) do loadPtfx(fx.asset) end
    loadPtfx(P.castStart.asset)
    loadPtfx(P.castEnd.asset)
    if Cfg.Anim.enabled then loadAnim(Cfg.Anim.dict) end
end

--------------------------------------------------------------------------------
-- Audio
--------------------------------------------------------------------------------

local function oneShot(snd)
    if Cfg.Audio.enabled and snd then
        PlaySoundFrontend(-1, snd.name, snd.set, true)
    end
end

local function startLoopSound(snd)
    if not Cfg.Audio.enabled or not snd then return nil end
    local id = GetSoundId()
    PlaySoundFrontend(id, snd.name, snd.set, true)
    return id
end

local function stopLoopSound(id)
    if id then
        StopSound(id)
        ReleaseSoundId(id)
    end
end

--------------------------------------------------------------------------------
-- Particles
--------------------------------------------------------------------------------

local function burst(fx, pos, mul)
    if not fx or not loadPtfx(fx.asset) then return end
    UseParticleFxAssetNextCall(fx.asset)
    if fx.colour then SetParticleFxNonLoopedColour(fx.colour[1], fx.colour[2], fx.colour[3]) end
    StartParticleFxNonLoopedAtCoord(fx.name, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fx.scale * (mul or 1.0), false, false, false)
end

local function beamBursts(from, to, ch)
    local B = Cfg.Ptfx.beam
    local step = (to - from) * (1.0 / B.points)
    local j = B.jitter
    for i = 1, B.points do
        local p = from + step * i
        if j > 0 then
            p = p + vector3((math.random() - 0.5) * j, (math.random() - 0.5) * j, (math.random() - 0.5) * j)
        end
        for _, fx in ipairs(B.fx) do
            if i % fx.every == 0 then burst(fx, p, 0.5 + 0.5 * ch) end
        end
    end
end

local function impactBurst(pos, ch)
    local list = Cfg.Ptfx.impact.fx
    if #list == 0 then return end
    impactIndex = impactIndex + 1
    burst(list[(impactIndex % #list) + 1], pos, 0.6 + 0.4 * ch)
end

local function spawnAura(ped)
    local list = {}
    local bone = GetPedBoneIndex(ped, HAND_BONE)
    for _, fx in ipairs(Cfg.Ptfx.hand) do
        if loadPtfx(fx.asset) then
            UseParticleFxAssetNextCall(fx.asset)
            local h = StartParticleFxLoopedOnEntityBone(fx.name, ped, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, bone, fx.scale, false, false, false)
            if fx.colour then SetParticleFxLoopedColour(h, fx.colour[1], fx.colour[2], fx.colour[3], false) end
            list[#list + 1] = { h = h, base = fx.scale }
        end
    end
    return list
end

local function killAura(list)
    if not list then return end
    for _, f in ipairs(list) do StopParticleFxLooped(f.h, false) end
end

local function scaleAura(list, mul)
    for _, f in ipairs(list) do SetParticleFxLoopedScale(f.h, f.base * mul) end
end

local function stopAura()
    killAura(aura.fx)
    aura.fx, aura.ped = {}, 0
end

local function ensureAura(ped)
    if aura.ped == ped and #aura.fx > 0 and DoesParticleFxLoopedExist(aura.fx[1].h) then return end
    stopAura()
    aura.fx, aura.ped = spawnAura(ped), ped
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function sphere(pos, size, c, alpha)
    DrawMarker(28, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, size,
        c[1], c[2], c[3], alpha, false, false, 2, false, nil, nil, false)
end

local function drawBeam(from, to, ch, t)
    local B = Cfg.Beam
    local delta = to - from
    local len = #delta
    if len < 0.05 then return end

    local dir = delta * (1.0 / len)
    local up = math.abs(dir.z) > 0.95 and vector3(1.0, 0.0, 0.0) or vector3(0.0, 0.0, 1.0)
    local u = normalize(cross(dir, up))
    local v = cross(dir, u)
    local a = math.floor(B.alpha * ch)
    local radius = B.radius * ch
    local core, glow, shadow = B.core, B.glow, B.shadow

    DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, core[1], core[2], core[3], a)

    for k = 1, B.strands do
        local phase = t * B.spin + (k / B.strands) * TAU
        local c = (k % 2 == 0) and glow or shadow
        local px, py, pz = from.x, from.y, from.z
        for i = 1, B.segments do
            local s = i / B.segments
            local ang = phase + s * B.twist
            local r = radius * (0.55 + 0.45 * math.sin(s * 3.14159))
            local p = from + dir * (len * s) + u * (math.cos(ang) * r) + v * (math.sin(ang) * r)
            DrawLine(px, py, pz, p.x, p.y, p.z, c[1], c[2], c[3], a)
            px, py, pz = p.x, p.y, p.z
        end
    end

    local orbSize = B.orbSize * (0.6 + 0.4 * ch)
    local orbAlpha = math.floor(180 * ch)
    for k = 1, B.orbs do
        local s = (t * B.orbFlow + k / B.orbs) % 1.0
        local ang = t * B.spin * 1.5 + s * B.twist
        local p = from + dir * (len * s) + u * (math.cos(ang) * radius * 1.4) + v * (math.sin(ang) * radius * 1.4)
        sphere(p, orbSize, core, orbAlpha)
    end
end

local function drawImpact(pos, normal, ch, t)
    local I = Cfg.Impact
    local pulse = 0.5 + 0.5 * math.sin(t * 9.0)
    sphere(pos, I.sphereSize * ch * (0.85 + 0.3 * pulse), I.sphere, math.floor(I.sphere[4] * ch))

    if normal and normal.z > 0.6 then
        local r, c = I.ring, I.sphere
        local alpha = math.floor(r[4] * ch)
        local outer = I.ringSize * ch * (0.9 + 0.2 * pulse)
        local inner = outer * 0.55
        DrawMarker(25, pos.x, pos.y, pos.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, (t * I.ringSpin) % 360.0,
            outer, outer, outer, r[1], r[2], r[3], alpha, false, false, 2, false, nil, nil, false)
        DrawMarker(25, pos.x, pos.y, pos.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, (-t * I.ringSpin * 1.6) % 360.0,
            inner, inner, inner, c[1], c[2], c[3], alpha, false, false, 2, false, nil, nil, false)
    end
end

local function drawLights(from, to, dir, ch, t)
    local L = Cfg.Lights
    if not L.enabled then return end
    local c = L.colour
    local pulse = 0.8 + 0.2 * math.sin(t * 14.0)
    DrawLightWithRange(to.x, to.y, to.z, c[1], c[2], c[3], L.impactRange * ch, L.impactIntensity * ch * pulse)
    DrawLightWithRange(from.x, from.y, from.z, c[1], c[2], c[3], L.handRange, L.handIntensity * ch)
    if L.spot then
        DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, c[1], c[2], c[3], Cfg.Range, L.spotBrightness * ch, 0.0, 8.0, 1.0)
    end
end

local function drawAimPreview(from, to, t)
    local c = Cfg.Beam.glow
    local a = math.floor(60 + 30 * math.sin(t * 4.0))
    DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, c[1], c[2], c[3], a)
    sphere(to, 0.07, c, a + 40)
end

local function drawHud(ch, t)
    local H = Cfg.Hud
    if not H.enabled then return end
    local pulse = casting and 1.0 or (0.55 + 0.45 * math.sin(t * 2.5))
    local textAlpha = math.floor(90 + 120 * pulse)

    DrawRect(H.x, H.y, H.width + 0.004, H.height + 0.006, 0, 0, 0, 150)
    DrawRect(H.x, H.y, H.width, H.height, 40, 0, 70, 200)
    if casting and ch > 0.0 then
        local w = H.width * ch
        DrawRect(H.x - H.width / 2 + w / 2, H.y, w, H.height, 170, 60, 255, 230)
    end

    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(200, 140, 255, textAlpha)
    SetTextCentre(true)
    SetTextDropshadow(0, 0, 0, 0, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(Cfg.Text.hud)
    EndTextCommandDisplayText(H.x, H.y - 0.03)
end

--------------------------------------------------------------------------------
-- Aim
--------------------------------------------------------------------------------

local function handPos(ped)
    return GetPedBoneCoords(ped, HAND_BONE, 0.0, 0.0, 0.0)
end

local function aimRay(ped)
    local camPos = GetGameplayCamCoord()
    local dest = camPos + rotToDir(GetGameplayCamRot(2)) * Cfg.Range
    local ray = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, RAY_FLAGS, ped, 4)
    local _, hit, endPos, normal, ent = GetShapeTestResult(ray)
    if hit == 1 or hit == true then
        return endPos, true, ent or 0, normal
    end
    return dest, false, 0, nil
end

--------------------------------------------------------------------------------
-- Fire zones
--------------------------------------------------------------------------------

local function removePatch(i)
    local p = table.remove(patches, i)
    if not p then return end
    if p.fire then RemoveScriptFire(p.fire) end
    if p.pos == lastPatchPos then lastPatchPos = nil end
end

local function cleanupPatches(now)
    for i = #patches, 1, -1 do
        if now - patches[i].t >= Cfg.Fire.lifeMs then removePatch(i) end
    end
end

local function clearPatches()
    for i = #patches, 1, -1 do removePatch(i) end
    lastPatchPos = nil
end

local function dropPatch(pos, now)
    if lastPatchPos and #(pos - lastPatchPos) < Cfg.Fire.stepDist then return end
    if #patches >= Cfg.Fire.max then removePatch(1) end
    patches[#patches + 1] = { t = now, pos = pos, fire = StartScriptFire(pos.x, pos.y, pos.z, Cfg.Fire.children, false) }
    lastPatchPos = pos
end

--------------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------------

local function takeControl(ent)
    if not NetworkGetEntityIsNetworked(ent) then return true end
    if not NetworkHasControlOfEntity(ent) then NetworkRequestControlOfEntity(ent) end
    return NetworkHasControlOfEntity(ent)
end

local function shove(ent, dir, force, lift)
    ApplyForceToEntity(ent, 1, dir.x * force, dir.y * force, lift, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
end

local function hitEntity(ent, dir, ch)
    if ent == 0 or not DoesEntityExist(ent) then return end
    local D = Cfg.Damage
    if ent ~= lastHitEnt then
        lastHitEnt = ent
        oneShot(Cfg.Audio.hit)
    end

    if IsEntityAVehicle(ent) then
        if D.vehicle.enabled and takeControl(ent) then
            SetVehicleEngineHealth(ent, GetVehicleEngineHealth(ent) - D.vehicle.engine * ch)
            SetVehicleBodyHealth(ent, GetVehicleBodyHealth(ent) - D.vehicle.body * ch)
        end
    elseif IsEntityAPed(ent) then
        if not D.ped.enabled then return end
        if IsPedAPlayer(ent) then
            if D.players.enabled then
                TriggerServerEvent('darkmagic:hit', GetPlayerServerId(NetworkGetPlayerIndexFromPed(ent)), ch)
            end
        elseif takeControl(ent) then
            ApplyDamageToPed(ent, math.floor(D.ped.amount * ch), false)
            SetPedToRagdoll(ent, D.ped.ragdollMs, D.ped.ragdollMs, 0, false, false, false)
            shove(ent, dir, D.ped.push * ch, 1.5 * ch)
        end
    elseif IsEntityAnObject(ent) and D.objects.push > 0 and takeControl(ent) then
        shove(ent, dir, D.objects.push * ch, 1.0 * ch)
    end
end

--------------------------------------------------------------------------------
-- Sync (state bags)
--------------------------------------------------------------------------------

local function publish(target)
    if not Cfg.Sync.enabled then return end
    LocalPlayer.state:set('darkmagic', target and { x = target.x, y = target.y, z = target.z } or false, true)
end

AddStateBagChangeHandler('darkmagic', nil, function(bagName, _, value)
    local sid = tonumber(bagName:match('^player:(%d+)$'))
    if not sid or sid == GetPlayerServerId(PlayerId()) then return end
    local now = GetGameTimer()
    if value and type(value) == 'table' and value.x then
        local target = vector3(value.x + 0.0, value.y + 0.0, value.z + 0.0)
        local r = remote[sid]
        if r then
            r.target, r.t, r.done = target, now, nil
        else
            remote[sid] = { target = target, smooth = target, t = now, start = now, timers = {} }
        end
    elseif remote[sid] then
        remote[sid].done = true
    end
end)

local function dropRemote(sid, r, quiet)
    killAura(r.fx)
    remote[sid] = nil
    if r.lastPos and not quiet then burst(Cfg.Ptfx.castEnd, r.lastPos, 1.0) end
end

--------------------------------------------------------------------------------
-- Cast lifecycle
--------------------------------------------------------------------------------

local function playAnim(ped)
    local A = Cfg.Anim
    if not A.enabled or not loadAnim(A.dict) then return end
    TaskPlayAnim(ped, A.dict, A.clip, 4.0, -4.0, -1, A.flag, 0.0, false, false, false)
end

local function keepAnim(ped)
    local A = Cfg.Anim
    if A.enabled and not IsEntityPlayingAnim(ped, A.dict, A.clip, 3) then playAnim(ped) end
end

local function beginCast(ped)
    local S = Cfg.Screen
    casting, castStart, charge, lastHitEnt = true, GetGameTimer(), 0.0, 0
    burst(Cfg.Ptfx.castStart, handPos(ped), 1.0)
    if S.timecycle then
        SetTimecycleModifier(S.timecycle)
        SetTimecycleModifierStrength(0.0)
    end
    if S.postfxEnabled and S.postfx then AnimpostfxPlay(S.postfx, 0, true) end
    if S.shake then ShakeGameplayCam(S.shake, 0.0) end
    playAnim(ped)
    oneShot(Cfg.Audio.castStart)
    loopSound = startLoopSound(Cfg.Audio.castLoop)
end

local function endCast(ped)
    local S = Cfg.Screen
    casting, charge = false, 0.0
    if lastAim then burst(Cfg.Ptfx.castEnd, lastAim, 1.0) end
    if S.timecycle then ClearTimecycleModifier() end
    if S.postfxEnabled and S.postfx then AnimpostfxStop(S.postfx) end
    if S.shake then StopGameplayCamShaking(true) end
    if Cfg.Anim.enabled then StopAnimTask(ped, Cfg.Anim.dict, Cfg.Anim.clip, 1.0) end
    stopLoopSound(loopSound)
    loopSound = nil
    scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
    publish(false)
end

local function castTick(ped, from, to, dir, hit, ent, normal, ch, t, now)
    local S = Cfg.Screen
    drawBeam(from, to, ch, t)
    drawImpact(to, hit and normal or nil, ch, t)
    drawLights(from, to, dir, ch, t)
    scaleAura(aura.fx, 0.6 + 0.9 * ch)

    if S.timecycle then SetTimecycleModifierStrength(S.timecycleStrength * ch) end
    if S.shake then SetGameplayCamShakeAmplitude(S.shakeAmplitude * ch) end
    if S.padRumble and due(timers, 'rumble', 100, now) then SetPadShake(0, 120, math.floor(220 * ch)) end

    if due(timers, 'beamfx', Cfg.Ptfx.beam.intervalMs, now) then beamBursts(from, to, ch) end
    if due(timers, 'impactfx', Cfg.Ptfx.impact.intervalMs, now) then impactBurst(to, ch) end
    if due(timers, 'anim', 400, now) then keepAnim(ped) end
    if due(timers, 'hit', Cfg.Damage.intervalMs, now) then hitEntity(ent, dir, ch) end
    if due(timers, 'sync', Cfg.Sync.intervalMs, now) then publish(to) end
    if hit and Cfg.Fire.enabled and ch >= Cfg.Fire.minCharge then dropPatch(to, now) end

    for i = 1, #CAST_CONTROLS do DisableControlAction(0, CAST_CONTROLS[i], true) end
end

local function autoOffReason(ped, now)
    if Cfg.AutoOffOnDeath and IsEntityDead(ped) then return Cfg.Text.offDead end
    if not ready or now - armedAt < 500 then return nil end
    local w = GetSelectedPedWeapon(ped)
    if Cfg.WeaponPolicy == 'holster' and w ~= UNARMED then return Cfg.Text.offWeapon end
    if Cfg.WeaponPolicy == 'require' and w == UNARMED then return Cfg.Text.offUnarmed end
    return nil
end

local function setArmed(v, reason, silent)
    if armed == v then return end
    local ped = PlayerPedId()
    armed, ready = v, false
    if v then
        preload()
        if not armed then return end
        armedAt, ready = GetGameTimer(), true
        if Cfg.WeaponPolicy == 'holster' then SetCurrentPedWeapon(ped, UNARMED, true) end
        ensureAura(ped)
        scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
        oneShot(Cfg.Audio.armOn)
        notify(Cfg.Text.on)
    else
        if casting then endCast(ped) end
        stopAura()
        clearPatches()
        lastAim = nil
        if not silent then
            oneShot(Cfg.Audio.armOff)
            notify(reason or Cfg.Text.off)
        end
    end
end

--------------------------------------------------------------------------------
-- Threads
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        if not armed then
            Wait(300)
        else
            local ped = PlayerPedId()
            local now = GetGameTimer()
            local t = now / 1000.0
            local reason = autoOffReason(ped, now)

            if reason then
                setArmed(false, reason)
            else
                for i = 1, #COMBAT_CONTROLS do DisableControlAction(0, COMBAT_CONTROLS[i], true) end
                if due(timers, 'aura', 1000, now) then ensureAura(ped) end

                local from = handPos(ped)
                local to, hit, ent, normal = aimRay(ped)
                local dir = normalize(to - from)
                local canCast = keyDown and not IsPauseMenuActive() and (Cfg.AllowInVehicle or not IsPedInAnyVehicle(ped, false))

                if canCast and not casting then
                    beginCast(ped)
                elseif not canCast and casting then
                    endCast(ped)
                end

                if casting then
                    charge = easeOut(clamp((now - castStart) / Cfg.ChargeMs, 0.0, 1.0))
                    lastAim = to
                    castTick(ped, from, to, dir, hit, ent, normal, charge, t, now)
                else
                    drawAimPreview(from, to, t)
                end

                cleanupPatches(now)
                drawHud(charge, t)
                Wait(0)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if next(remote) == nil then
            Wait(500)
        else
            local myPos = GetEntityCoords(PlayerPedId())
            local now = GetGameTimer()
            local t = now / 1000.0

            for sid, r in pairs(remote) do
                local pid = GetPlayerFromServerId(sid)
                local ped = pid ~= -1 and GetPlayerPed(pid) or 0
                if r.done or ped == 0 or not DoesEntityExist(ped) or now - r.t > Cfg.Sync.staleMs then
                    dropRemote(sid, r)
                else
                    local from = handPos(ped)
                    if #(from - myPos) <= Cfg.Sync.maxDistance then
                        if not r.fx then
                            r.fx = spawnAura(ped)
                            burst(Cfg.Ptfx.castStart, from, 1.0)
                        end
                        r.smooth = lerp(r.smooth, r.target, 0.25)
                        r.lastPos = r.smooth
                        local ch = easeOut(clamp((now - r.start) / Cfg.ChargeMs, 0.0, 1.0))
                        local dir = normalize(r.smooth - from)
                        scaleAura(r.fx, 0.6 + 0.9 * ch)
                        drawBeam(from, r.smooth, ch, t + sid)
                        drawImpact(r.smooth, nil, ch, t)
                        drawLights(from, r.smooth, dir, ch, t)
                        if due(r.timers, 'beamfx', Cfg.Ptfx.beam.intervalMs, now) then beamBursts(from, r.smooth, ch) end
                        if due(r.timers, 'impactfx', Cfg.Ptfx.impact.intervalMs, now) then impactBurst(r.smooth, ch) end
                    elseif r.fx then
                        killAura(r.fx)
                        r.fx = nil
                    end
                end
            end
            Wait(0)
        end
    end
end)

--------------------------------------------------------------------------------
-- Input, events, cleanup
--------------------------------------------------------------------------------

RegisterCommand('+darkmagic_cast', function() keyDown = true end, false)
RegisterCommand('-darkmagic_cast', function() keyDown = false end, false)
RegisterKeyMapping('+darkmagic_cast', Cfg.Text.castLabel, 'keyboard', Cfg.CastKey)

RegisterCommand('darkmagic_toggle', function() TriggerServerEvent('darkmagic:requestToggle') end, false)
RegisterKeyMapping('darkmagic_toggle', Cfg.Text.toggleLabel, 'keyboard', Cfg.ToggleKey or '')

RegisterNetEvent('darkmagic:setState', function(state)
    setArmed(state == true)
end)

RegisterNetEvent('darkmagic:denied', function()
    notify(Cfg.Text.noPerm)
end)

RegisterNetEvent('darkmagic:takeHit', function(fromId, damage)
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    local D, S = Cfg.Damage.ped, Cfg.Screen
    ApplyDamageToPed(ped, damage, false)
    SetPedToRagdoll(ped, D.ragdollMs, D.ragdollMs, 0, false, false, false)

    local caster = GetPlayerFromServerId(fromId)
    if caster ~= -1 then
        local dir = normalize(GetEntityCoords(ped) - GetEntityCoords(GetPlayerPed(caster)))
        shove(ped, dir, D.push, 1.5)
    end
    burst(Cfg.Ptfx.castStart, GetEntityCoords(ped), 0.8)
    if S.hitFlash then
        AnimpostfxPlay(S.hitFlash, 0, true)
        SetTimeout(S.hitFlashMs, function() AnimpostfxStop(S.hitFlash) end)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    setArmed(false, nil, true)
    for sid, r in pairs(remote) do dropRemote(sid, r, true) end
end)
