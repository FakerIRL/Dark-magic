local Cfg = Config
local UNARMED = GetHashKey('WEAPON_UNARMED')
local HAND_BONE = 57005
local RAY_FLAGS = 1 + 2 + 8 + 16
local COMBAT_CONTROLS = { 24, 25, 140, 141, 142, 257, 263, 264 }
local CAST_CONTROLS = { 38, 51 }
local TAU = 6.28318
local POINT_DICT = 'anim@mp_point'

local armed, ready, casting, keyDown = false, false, false, false
local gen, armedAt, castStart, castEnded, charge = 0, 0, 0, 0, 0.0
local lastAim, lastHitEnt, impactIndex, seq = nil, 0, 0, 0
local lastSent, lastSentAt, tintOn, tintUntil, hudUntil = nil, 0, false, 0, 0
local timers, patches, remote, ray = {}, {}, {}, nil
local lastPatchPos, loopSound
local aura = { ped = 0, fx = {} }
local stations = {}
local loaded, pending = { ptfx = {}, anim = {} }, {}

-- Helpers

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

local function float(v)
    return (tonumber(v) or 0) + 0.0
end

do
    local L, H, P = Cfg.Lights, Cfg.Hud, Cfg.Ptfx
    Cfg.Range = float(Cfg.Range)
    for _, k in ipairs({ 'impactRange', 'impactIntensity', 'handRange', 'handIntensity', 'spotBrightness' }) do L[k] = float(L[k]) end
    for _, k in ipairs({ 'x', 'y', 'width', 'height' }) do H[k] = float(H[k]) end
    local function fix(fx)
        fx.scale = float(fx.scale)
        if fx.colour then for i = 1, 3 do fx.colour[i] = float(fx.colour[i]) end end
    end
    for _, list in ipairs({ P.hand, P.stations.fx, P.beam.fx, P.impact.fx }) do
        for _, fx in ipairs(list) do fix(fx) end
    end
    fix(P.castStart)
    fix(P.castEnd)
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
    local pendingKey = kind .. ':' .. key
    if pending[pendingKey] then
        while cache[key] == nil do Wait(50) end
        return cache[key]
    end
    pending[pendingKey] = true
    request(key)
    local deadline = GetGameTimer() + Cfg.LoadTimeoutMs
    local ok = true
    while not check(key) do
        if GetGameTimer() > deadline then
            ok = false
            print(('[dark_magic] failed to load %s "%s"'):format(kind, key))
            break
        end
        Wait(0)
    end
    cache[key], pending[pendingKey] = ok, nil
    return ok
end

local function loadPtfx(asset)
    return waitFor('ptfx', asset, RequestNamedPtfxAsset, HasNamedPtfxAssetLoaded)
end

local function loadAnim(dict)
    return waitFor('anim', dict, RequestAnimDict, HasAnimDictLoaded)
end

local function ptfxReady(asset)
    local state = loaded.ptfx[asset]
    if state ~= nil then return state end
    RequestNamedPtfxAsset(asset)
    if HasNamedPtfxAssetLoaded(asset) then
        loaded.ptfx[asset] = true
        return true
    end
    return false
end

local function preloadPtfx()
    local P = Cfg.Ptfx
    for _, list in ipairs({ P.hand, P.stations.fx, P.beam.fx, P.impact.fx }) do
        for _, fx in ipairs(list) do loadPtfx(fx.asset) end
    end
    loadPtfx(P.castStart.asset)
    loadPtfx(P.castEnd.asset)
end

local function preload()
    preloadPtfx()
    local A = Cfg.Anim
    if A.enabled then loadAnim(A.mode == 'point' and POINT_DICT or A.dict) end
end

-- Audio

local function oneShot(snd)
    if Cfg.Audio.enabled and snd then
        PlaySoundFrontend(-1, snd.name, snd.set, true)
    end
end

local function startLoopSound(snd, ent)
    if not Cfg.Audio.enabled or not snd then return nil end
    local id = GetSoundId()
    if ent then
        PlaySoundFromEntity(id, snd.name, ent, snd.set, true, 30)
    else
        PlaySoundFrontend(id, snd.name, snd.set, true)
    end
    return id
end

local function stopLoopSound(id)
    if id then
        StopSound(id)
        ReleaseSoundId(id)
    end
end

-- Particles

local function burst(fx, pos, mul)
    if not fx or not ptfxReady(fx.asset) then return end
    UseParticleFxAssetNextCall(fx.asset)
    if fx.colour then
        SetParticleFxNonLoopedColour(fx.colour[1], fx.colour[2], fx.colour[3])
    else
        SetParticleFxNonLoopedColour(1.0, 1.0, 1.0)
    end
    StartParticleFxNonLoopedAtCoord(fx.name, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fx.scale * (mul or 1.0), false, false, false)
end

local function beamBursts(from, to, len, ch, lod)
    local B = Cfg.Ptfx.beam
    local n = math.max(2, math.floor(clamp(math.ceil(len / B.spacing), 2, B.points) * lod))
    local step = (to - from) * (1.0 / n)
    local j = B.jitter
    for i = 1, n do
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
        if ptfxReady(fx.asset) then
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

local function startStations(origin)
    local S = Cfg.Ptfx.stations
    local list = {}
    for i = 1, S.count do
        local fx = S.fx[((i - 1) % #S.fx) + 1]
        if ptfxReady(fx.asset) then
            UseParticleFxAssetNextCall(fx.asset)
            local h = StartParticleFxLoopedAtCoord(fx.name, origin.x, origin.y, origin.z, 0.0, 0.0, 0.0, fx.scale, false, false, false, false)
            if fx.colour then SetParticleFxLoopedColour(h, fx.colour[1], fx.colour[2], fx.colour[3], false) end
            list[#list + 1] = { h = h, base = fx.scale, origin = origin }
        end
    end
    return list
end

local function moveStations(list, from, to, ch, t)
    local n = #list
    if n == 0 then return end
    local delta = to - from
    for i, s in ipairs(list) do
        local f = ((i - 0.5) / n + t * Cfg.Ptfx.stations.drift) % 1.0
        local p = from + delta * f
        SetParticleFxLoopedOffsets(s.h, p.x - s.origin.x, p.y - s.origin.y, p.z - s.origin.z, 0.0, 0.0, 0.0)
        SetParticleFxLoopedScale(s.h, s.base * (0.4 + 0.8 * ch))
    end
end

local function stopStations(list)
    if not list then return end
    for _, s in ipairs(list) do StopParticleFxLooped(s.h, false) end
end

-- Drawing

local function sphere(pos, size, c, alpha)
    DrawMarker(28, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, size,
        c[1], c[2], c[3], alpha, false, false, 2, false, nil, nil, false)
end

local function quad(a, b, c, d, col, alpha)
    local r, g, bl = col[1], col[2], col[3]
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, r, g, bl, alpha)
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, r, g, bl, alpha)
    DrawPoly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, r, g, bl, alpha)
    DrawPoly(d.x, d.y, d.z, c.x, c.y, c.z, a.x, a.y, a.z, r, g, bl, alpha)
end

local function ribbon(from, dir, len, camPos, halfW, segs, col, alpha, t)
    local function width(s)
        return halfW * (0.35 + 0.65 * math.min(1.0, s * 3.0)) * (0.9 + 0.1 * math.sin(t * 20.0 - s * 10.0))
    end
    local a = from
    local sa = normalize(cross(dir, camPos - a)) * width(0.0)
    for i = 1, segs do
        local s = i / segs
        local b = from + dir * (len * s)
        local sb = normalize(cross(dir, camPos - b)) * width(s)
        quad(a - sa, a + sa, b + sb, b - sb, col, alpha)
        a, sa = b, sb
    end
end

local function drawBeam(from, to, ch, t, lod, camPos)
    local B = Cfg.Beam
    local delta = to - from
    local len = #delta
    if len < 0.05 then return end

    local dir = delta * (1.0 / len)
    local up = math.abs(dir.z) > 0.95 and vector3(1.0, 0.0, 0.0) or vector3(0.0, 0.0, 1.0)
    local u = normalize(cross(dir, up))
    local v = cross(dir, u)
    local radius = B.radius * ch
    local core, glow, shadow = B.core, B.glow, B.shadow

    local segs = math.max(2, math.floor(B.ribbonSegs * lod))
    ribbon(from, dir, len, camPos, B.glowWidth * (0.5 + 0.5 * ch), segs, glow, math.floor(B.glowAlpha * ch), t)
    ribbon(from, dir, len, camPos, B.coreWidth * (0.5 + 0.5 * ch), segs, core, math.floor(B.coreAlpha * ch), t)

    local strandAlpha = math.floor(200 * ch)
    local strands = math.max(1, math.floor(B.strands * lod))
    local segments = math.max(4, math.floor(B.segments * lod))
    for k = 1, strands do
        local phase = t * B.spin + (k / strands) * TAU
        local c = (k % 2 == 0) and glow or shadow
        local px, py, pz = from.x, from.y, from.z
        for i = 1, segments do
            local s = i / segments
            local ang = phase + s * B.twist
            local r = radius * (0.55 + 0.45 * math.sin(s * 3.14159))
            local p = from + dir * (len * s) + u * (math.cos(ang) * r) + v * (math.sin(ang) * r)
            DrawLine(px, py, pz, p.x, p.y, p.z, c[1], c[2], c[3], strandAlpha)
            px, py, pz = p.x, p.y, p.z
        end
    end

    local orbs = math.floor(B.orbs * lod)
    local orbAlpha = math.floor(190 * ch)
    for k = 1, orbs do
        local s = (t * B.orbFlow + k / orbs) % 1.0
        local ang = t * B.spin * 1.5 + s * B.twist
        local p = from + dir * (len * s) + u * (math.cos(ang) * radius * 1.4) + v * (math.sin(ang) * radius * 1.4)
        local size = B.orbSize * (0.6 + 0.4 * ch) * (1.0 + #(p - camPos) / 12.0)
        sphere(p, size, core, orbAlpha)
    end
end

local function drawImpact(pos, normal, ch, t)
    local I = Cfg.Impact
    local pulse = 0.5 + 0.5 * math.sin(t * 9.0)
    sphere(pos, I.sphereSize * ch * (0.85 + 0.3 * pulse), I.sphere, math.floor(I.sphere[4] * ch))

    if normal and normal.z > 0.6 then
        local r, c = I.ring, I.sphere
        local phase = (t % I.ringPeriod) / I.ringPeriod
        local shock = I.ringSize * ch * (0.3 + 0.9 * phase)
        DrawMarker(25, pos.x, pos.y, pos.z + 0.03, normal.x, normal.y, normal.z, 0.0, 0.0, 0.0,
            shock, shock, shock, r[1], r[2], r[3], math.floor(r[4] * ch * (1.0 - phase)), false, false, 2, false, nil, nil, false)
        local rune = I.ringSize * ch * 0.45 * (0.9 + 0.2 * pulse)
        DrawMarker(27, pos.x, pos.y, pos.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, (t * I.runeSpin) % 360.0,
            rune, rune, rune, c[1], c[2], c[3], math.floor(r[4] * ch), false, false, 2, false, nil, nil, false)
    end
end

local function drawLights(from, to, dir, len, ch, t, lod)
    local L = Cfg.Lights
    if not L.enabled or lod < 0.25 then return end
    local c = L.colour
    local pulse = 0.8 + 0.2 * math.sin(t * 14.0)
    DrawLightWithRange(to.x, to.y, to.z, c[1], c[2], c[3], L.impactRange * ch, L.impactIntensity * ch * pulse)
    DrawLightWithRange(from.x, from.y, from.z, c[1], c[2], c[3], L.handRange, L.handIntensity * ch)
    if L.spot and lod >= 0.5 then
        DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, c[1], c[2], c[3],
            math.min(len + 1.5, Cfg.Range), L.spotBrightness * ch, 0.0, 8.0, 1.0)
    end
end

local function drawAimPreview(to, normal, t)
    local c = Cfg.Beam.glow
    local a = math.floor(70 + 30 * math.sin(t * 4.0))
    sphere(to, 0.07, c, a)
    if normal and normal.z > 0.6 then
        DrawMarker(25, to.x, to.y, to.z + 0.03, normal.x, normal.y, normal.z, 0.0, 0.0, 0.0,
            0.35, 0.35, 0.35, c[1], c[2], c[3], a - 30, false, false, 2, false, nil, nil, false)
    end
end

local function drawHud(ch, now)
    local H = Cfg.Hud
    if not H.enabled then return end
    local k = casting and 1.0 or clamp((hudUntil - now) / H.fadeMs, 0.0, 1.0)
    if k <= 0.0 then return end

    DrawRect(H.x, H.y, H.width + 0.004, H.height + 0.006, 0, 0, 0, math.floor(150 * k))
    DrawRect(H.x, H.y, H.width, H.height, 40, 0, 70, math.floor(200 * k))
    if ch > 0.0 then
        local w = H.width * ch
        DrawRect(H.x - H.width / 2 + w / 2, H.y, w, H.height, 170, 60, 255, math.floor(230 * k))
    end

    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(200, 140, 255, math.floor(210 * k))
    SetTextCentre(true)
    SetTextDropshadow(0, 0, 0, 0, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(Cfg.Text.hud)
    EndTextCommandDisplayText(H.x, H.y - 0.03)
end

-- Aim

local function handPos(ped)
    return GetPedBoneCoords(ped, HAND_BONE, 0.0, 0.0, 0.0)
end

local function aim(ped, now)
    if ray and not casting and not due(timers, 'ray', 50, now) then return ray end
    local camPos = GetGameplayCamCoord()
    local dest = camPos + rotToDir(GetGameplayCamRot(2)) * Cfg.Range
    local ignore = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
    local probe = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, RAY_FLAGS, ignore, 4)
    local _, hit, endPos, normal, ent = GetShapeTestResult(probe)
    if hit == 1 or hit == true then
        ray = { to = endPos, hit = true, ent = ent or 0, normal = normal }
    else
        ray = { to = dest, hit = false, ent = 0, normal = nil }
    end
    return ray
end

-- Fire zones

local function removePatch(i)
    local p = table.remove(patches, i)
    if not p then return end
    if p.fire then RemoveScriptFire(p.fire) end
    StopFireInRange(p.pos.x, p.pos.y, p.pos.z, 1.5)
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
    if #patches >= Cfg.Fire.max then return end
    if lastPatchPos and #(pos - lastPatchPos) < Cfg.Fire.stepDist then return end
    patches[#patches + 1] = { t = now, pos = pos, fire = StartScriptFire(pos.x, pos.y, pos.z, Cfg.Fire.children, false) }
    lastPatchPos = pos
end

-- Damage

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
        if Cfg.Screen.padRumble then SetPadShake(0, 150, 200) end
    end

    if IsEntityAVehicle(ent) then
        if not D.vehicle.enabled then return end
        if not NetworkGetEntityIsNetworked(ent) or NetworkHasControlOfEntity(ent) then
            SetVehicleEngineHealth(ent, GetVehicleEngineHealth(ent) - D.vehicle.engine * ch)
            SetVehicleBodyHealth(ent, GetVehicleBodyHealth(ent) - D.vehicle.body * ch)
        else
            TriggerServerEvent('darkmagic:hitVehicle', NetworkGetNetworkIdFromEntity(ent), ch)
        end
    elseif IsEntityAPed(ent) then
        if IsPedAPlayer(ent) then
            if D.players.enabled then
                TriggerServerEvent('darkmagic:hit', GetPlayerServerId(NetworkGetPlayerIndexFromPed(ent)), ch)
            end
        elseif D.ped.enabled and takeControl(ent) then
            ApplyDamageToPed(ent, math.floor(D.ped.amount * ch), false)
            SetPedToRagdoll(ent, D.ped.ragdollMs, D.ped.ragdollMs, 0, false, false, false)
            shove(ent, dir, D.ped.push * ch, 1.5 * ch)
        end
    elseif IsEntityAnObject(ent) and D.objects.push > 0 and takeControl(ent) then
        shove(ent, dir, D.objects.push * ch, 1.0 * ch)
    end
end

-- Sync (state bags)

local function publish(target, ground, now, force)
    if not Cfg.Sync.enabled then return end
    if not target then
        lastSent = nil
        LocalPlayer.state:set('darkmagic', false, true)
        return
    end
    local S = Cfg.Sync
    if not force and lastSent and #(target - lastSent) < S.moveEpsilon and now - lastSentAt < S.keepaliveMs then return end
    seq = seq + 1
    lastSent, lastSentAt = target, now
    LocalPlayer.state:set('darkmagic', { x = target.x, y = target.y, z = target.z, g = ground and 1 or 0, n = seq }, true)
end

AddStateBagChangeHandler('darkmagic', nil, function(bagName, _, value)
    local sid = tonumber(bagName:match('^player:(%d+)$'))
    if not sid or sid == GetPlayerServerId(PlayerId()) then return end
    local now = GetGameTimer()
    if type(value) == 'table' then
        local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
        if not (x and y and z) or x ~= x or y ~= y or z ~= z then return end
        if math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then return end
        local target = vector3(x, y, z)
        local r = remote[sid]
        if r then
            r.target, r.t, r.ground, r.done = target, now, value.g == 1, nil
        else
            remote[sid] = { target = target, smooth = target, ground = value.g == 1, t = now, start = now, timers = {}, pid = GetPlayerFromServerId(sid) }
        end
    elseif remote[sid] then
        remote[sid].done = true
    end
end)

local function dropRemote(sid, r, quiet)
    killAura(r.fx)
    stopStations(r.stations)
    stopLoopSound(r.sound)
    remote[sid] = nil
    if r.lastPos and not quiet then burst(Cfg.Ptfx.castEnd, r.lastPos, 1.0) end
end

local function sleepRemote(r)
    killAura(r.fx)
    stopStations(r.stations)
    stopLoopSound(r.sound)
    r.fx, r.stations, r.sound = nil, nil, nil
end

-- Pose

local function startPose(ped)
    local A = Cfg.Anim
    if not A.enabled then return end
    if A.mode == 'point' then
        if not loadAnim(POINT_DICT) then return end
        SetPedConfigFlag(ped, 36, true)
        TaskMoveNetworkByName(ped, 'task_mp_pointing', 0.5, false, POINT_DICT, 24)
    elseif loadAnim(A.dict) then
        TaskPlayAnim(ped, A.dict, A.clip, 4.0, -4.0, -1, A.flag, 0.0, false, false, false)
    end
end

local function updatePose(ped, now)
    local A = Cfg.Anim
    if not A.enabled then return end
    if A.mode == 'point' then
        if not IsTaskMoveNetworkActive(ped) then
            if due(timers, 'pose', 400, now) then startPose(ped) end
            return
        end
        local pitch = clamp(GetGameplayCamRelativePitch(), -70.0, 42.0)
        local heading = clamp(GetGameplayCamRelativeHeading(), -180.0, 180.0)
        SetTaskMoveNetworkSignalFloat(ped, 'Pitch', (pitch + 70.0) / 112.0)
        SetTaskMoveNetworkSignalFloat(ped, 'Heading', 1.0 - (heading + 180.0) / 360.0)
        SetTaskMoveNetworkSignalBool(ped, 'isBlocked', false)
        SetTaskMoveNetworkSignalBool(ped, 'isFirstPerson', GetFollowPedCamViewMode() == 4)
    elseif due(timers, 'pose', 400, now) and not IsEntityPlayingAnim(ped, A.dict, A.clip, 3) then
        startPose(ped)
    end
end

local function stopPose(ped)
    local A = Cfg.Anim
    if not A.enabled then return end
    if A.mode == 'point' then
        RequestTaskMoveNetworkStateTransition(ped, 'Stop')
        SetPedConfigFlag(ped, 36, false)
    else
        StopAnimTask(ped, A.dict, A.clip, 1.0)
    end
end

-- Cast lifecycle

local function clearTint()
    if tintOn then ClearExtraTimecycleModifier() end
    tintOn, tintUntil = false, 0
end

local function beginCast(ped, from, now)
    local S = Cfg.Screen
    casting, castStart, charge, lastHitEnt = true, now, 0.0, 0
    stopStations(stations)
    stations = startStations(from)
    burst(Cfg.Ptfx.castStart, from, 1.0)
    if S.timecycle then
        clearTint()
        SetExtraTimecycleModifier(S.timecycle)
        SetExtraTimecycleModifierStrength(0.0)
        tintOn = true
    end
    if S.postfxEnabled and S.postfx then AnimpostfxPlay(S.postfx, 0, true) end
    if S.shake then ShakeGameplayCam(S.shake, 0.0) end
    startPose(ped)
    oneShot(Cfg.Audio.castStart)
    loopSound = startLoopSound(Cfg.Audio.castLoop)
end

local function endCast(ped, now)
    local S = Cfg.Screen
    casting, charge, castEnded = false, 0.0, now
    stopStations(stations)
    stations = {}
    if lastAim and now - castStart >= 200 then burst(Cfg.Ptfx.castEnd, lastAim, 1.0) end
    if tintOn then tintUntil = now + S.tintFadeMs end
    if S.postfxEnabled and S.postfx then AnimpostfxStop(S.postfx) end
    if S.shake then StopGameplayCamShaking(true) end
    if S.releaseShake then ShakeGameplayCam(S.releaseShake, S.releaseAmplitude) end
    stopPose(ped)
    stopLoopSound(loopSound)
    loopSound = nil
    scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
    publish(nil)
end

local function castTick(ped, from, r, ch, t, now, camPos)
    local S = Cfg.Screen
    local to = r.to
    local delta = to - from
    local len = #delta
    local dir = normalize(delta)
    local ground = r.hit and r.normal and r.normal.z > 0.6

    drawBeam(from, to, ch, t, 1.0, camPos)
    drawImpact(to, r.hit and r.normal or nil, ch, t)
    drawLights(from, to, dir, len, ch, t, 1.0)
    moveStations(stations, from, to, ch, t)
    scaleAura(aura.fx, 0.6 + 0.9 * ch)
    hudUntil = now + Cfg.Hud.fadeMs

    if tintOn then SetExtraTimecycleModifierStrength(S.timecycleStrength * ch) end
    if S.shake then SetGameplayCamShakeAmplitude(S.shakeAmplitude * ch) end
    if S.padRumble and due(timers, 'rumble', 250, now) then SetPadShake(0, 80, math.floor(60 + 90 * ch)) end

    updatePose(ped, now)
    if due(timers, 'beamfx', Cfg.Ptfx.beam.intervalMs, now) then beamBursts(from, to, len, ch, 1.0) end
    if due(timers, 'impactfx', Cfg.Ptfx.impact.intervalMs, now) then impactBurst(to, ch) end
    if due(timers, 'hit', Cfg.Damage.intervalMs, now) then hitEntity(r.ent, dir, ch) end
    if due(timers, 'sync', math.max(Cfg.Sync.intervalMs, 50), now) then publish(to, ground, now, false) end
    if r.hit and Cfg.Fire.enabled and now - castStart >= Cfg.Fire.delayMs then dropPatch(to, now) end
end

local function autoOffReason(ped, now)
    if Cfg.AutoOffOnDeath and IsEntityDead(ped) then return Cfg.Text.offDead end
    if now - armedAt < 500 then return nil end
    local w = GetSelectedPedWeapon(ped)
    if Cfg.WeaponPolicy == 'holster' and w ~= UNARMED then return Cfg.Text.offWeapon end
    if Cfg.WeaponPolicy == 'require' and w == UNARMED then return Cfg.Text.offUnarmed end
    return nil
end

local function setArmed(v, reason, silent)
    if armed == v then return end
    local ped = PlayerPedId()
    armed, ready = v, false
    gen = gen + 1
    if v then
        local my = gen
        preload()
        if my ~= gen or not armed then return end
        armedAt, ready = GetGameTimer(), true
        if Cfg.WeaponPolicy == 'holster' then SetCurrentPedWeapon(ped, UNARMED, true) end
        ensureAura(ped)
        scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
        oneShot(Cfg.Audio.armOn)
        notify(Cfg.Text.on)
    else
        if casting then endCast(ped, GetGameTimer()) end
        clearTint()
        stopAura()
        clearPatches()
        lastAim, ray = nil, nil
        if reason then TriggerServerEvent('darkmagic:clientOff') end
        if not silent then
            oneShot(Cfg.Audio.armOff)
            notify(reason or Cfg.Text.off)
        end
    end
end

-- Threads

CreateThread(function()
    preloadPtfx()
end)

CreateThread(function()
    while true do
        if not armed or not ready then
            Wait(100)
        else
            local ped = PlayerPedId()
            local now = GetGameTimer()
            local t = now / 1000.0
            local reason = autoOffReason(ped, now)

            if reason then
                setArmed(false, reason)
            else
                for i = 1, #COMBAT_CONTROLS do DisableControlAction(0, COMBAT_CONTROLS[i], true) end
                if keyDown then
                    for i = 1, #CAST_CONTROLS do DisableControlAction(0, CAST_CONTROLS[i], true) end
                end
                if IsPauseMenuActive() or IsNuiFocused() then keyDown = false end
                if due(timers, 'aura', 1000, now) then ensureAura(ped) end

                local from = handPos(ped)
                local r = aim(ped, now)
                local inVehicle = IsPedInAnyVehicle(ped, false)
                local canCast = keyDown and not IsEntityDead(ped) and (Cfg.AllowInVehicle or not inVehicle)

                if canCast and not casting and now - castEnded >= Cfg.RecastMs then
                    beginCast(ped, from, now)
                    publish(r.to, r.hit and r.normal and r.normal.z > 0.6, now, true)
                elseif not canCast and casting then
                    endCast(ped, now)
                end

                if casting then
                    charge = easeOut(clamp((now - castStart) / Cfg.ChargeMs, 0.0, 1.0))
                    lastAim = r.to
                    castTick(ped, from, r, charge, t, now, GetGameplayCamCoord())
                else
                    if tintOn then
                        if now < tintUntil then
                            SetExtraTimecycleModifierStrength(Cfg.Screen.timecycleStrength * (tintUntil - now) / Cfg.Screen.tintFadeMs)
                        else
                            clearTint()
                        end
                    end
                    if not inVehicle then drawAimPreview(r.to, r.hit and r.normal or nil, t) end
                end

                cleanupPatches(now)
                drawHud(charge, now)
                Wait(0)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if next(remote) == nil then
            Wait(100)
        else
            local myPos = GetEntityCoords(PlayerPedId())
            local camPos = GetGameplayCamCoord()
            local now = GetGameTimer()
            local t = now / 1000.0
            local S = Cfg.Sync
            local smoothing = 1.0 - math.exp(-GetFrameTime() * 12.0)
            local active = false

            for sid, r in pairs(remote) do
                local ped = r.pid ~= -1 and GetPlayerPed(r.pid) or 0
                if ped == 0 then
                    r.pid = GetPlayerFromServerId(sid)
                    ped = r.pid ~= -1 and GetPlayerPed(r.pid) or 0
                end
                if r.done or ped == 0 or not DoesEntityExist(ped) or now - r.t > S.staleMs then
                    dropRemote(sid, r, ped == 0)
                else
                    local from = handPos(ped)
                    local d = #(from - myPos)
                    if d <= S.maxDistance and #(r.target - from) <= Cfg.Range + 5.0 then
                        active = true
                        if not r.fx then
                            r.fx = spawnAura(ped)
                            r.stations = startStations(from)
                            r.sound = startLoopSound(Cfg.Audio.castLoop, ped)
                            burst(Cfg.Ptfx.castStart, from, 1.0)
                        end
                        r.smooth = lerp(r.smooth, r.target, smoothing)
                        r.lastPos = r.smooth
                        local ch = easeOut(clamp((now - r.start) / Cfg.ChargeMs, 0.0, 1.0))
                        local lod = d < S.nearLod and 1.0 or (d < S.midLod and 0.5 or 0.25)
                        local delta = r.smooth - from
                        local len = #delta
                        local dir = normalize(delta)
                        scaleAura(r.fx, 0.6 + 0.9 * ch)
                        moveStations(r.stations, from, r.smooth, ch, t)
                        drawBeam(from, r.smooth, ch, t + sid, lod, camPos)
                        drawImpact(r.smooth, r.ground and vector3(0.0, 0.0, 1.0) or nil, ch, t)
                        drawLights(from, r.smooth, dir, len, ch, t, lod)
                        if lod >= 0.5 and due(r.timers, 'beamfx', Cfg.Ptfx.beam.intervalMs, now) then beamBursts(from, r.smooth, len, ch, lod) end
                        if lod >= 0.25 and due(r.timers, 'impactfx', Cfg.Ptfx.impact.intervalMs, now) then impactBurst(r.smooth, ch) end
                    elseif r.fx then
                        sleepRemote(r)
                    end
                end
            end
            Wait(active and 0 or 100)
        end
    end
end)

-- Input, events, cleanup

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
    local dmg = clamp(math.tointeger(damage) or 0, 0, D.amount)
    local k = D.amount > 0 and dmg / D.amount or 1.0
    if dmg > 0 then ApplyDamageToPed(ped, dmg, false) end
    SetPedToRagdoll(ped, math.floor(D.ragdollMs * k), math.floor(D.ragdollMs * k), 0, false, false, false)

    local caster = GetPlayerFromServerId(fromId)
    local cped = caster ~= -1 and GetPlayerPed(caster) or 0
    if cped ~= 0 and DoesEntityExist(cped) then
        shove(ped, normalize(GetEntityCoords(ped) - GetEntityCoords(cped)), D.push * k, 1.5 * k)
    end
    burst(Cfg.Ptfx.castStart, GetEntityCoords(ped), 0.8)
    if S.hitFlash then AnimpostfxPlay(S.hitFlash, S.hitFlashMs, false) end
end)

RegisterNetEvent('darkmagic:vehicleHit', function(netId, engine, body)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh == 0 or not DoesEntityExist(veh) or not NetworkHasControlOfEntity(veh) then return end
    SetVehicleEngineHealth(veh, GetVehicleEngineHealth(veh) - float(engine))
    SetVehicleBodyHealth(veh, GetVehicleBodyHealth(veh) - float(body))
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    setArmed(false, nil, true)
    for sid, r in pairs(remote) do dropRemote(sid, r, true) end
    if Cfg.Screen.hitFlash then AnimpostfxStop(Cfg.Screen.hitFlash) end
    for asset, ok in pairs(loaded.ptfx) do if ok then RemoveNamedPtfxAsset(asset) end end
    for dict, ok in pairs(loaded.anim) do if ok then RemoveAnimDict(dict) end end
end)
