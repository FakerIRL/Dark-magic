local Cfg = Config
local UNARMED = GetHashKey('WEAPON_UNARMED')
local HAND_BONE = 57005
local RAY_FLAGS = 1 + 2 + 8 + 16 + 32
local COMBAT_CONTROLS = { 24, 25, 140, 141, 142, 257, 263, 264 }
local CAST_CONTROLS = { 38, 51 }
local TAU = 6.28318
local UP = vector3(0.0, 0.0, 1.0)
local POINT_DICT = 'anim@mp_point'
local MATERIALS = {}

local armed, ready, casting, keyDown, pressEdge = false, false, false, false, false
local gen, armedAt, castStart, castEnded, charge = 0, 0, 0, 0, 0.0
local lastAim, lastHitEnt, impactIndex, seq = nil, 0, 0, 0
local lastSent, lastSentAt, tintOn, tintUntil, hudUntil, poseUntil = nil, 0, false, 0, 0, 0
local timers, patches, remote, zones, blasts, ray = {}, {}, {}, {}, {}, nil
local lastPatchPos, loopSound
local aura = { ped = 0, fx = {} }
local stations = {}
local loaded, pending = { ptfx = {}, anim = {} }, {}
local spellIndex, spell = 1, Cfg.Spells.order[1]
local mana, overheatUntil, lastManaUse, disarmedAt = Cfg.Mana.max, 0, 0, 0
local lastOrbAt, lastCurseAt = 0, 0
local orb, lift = nil, nil
local debuff = { active = false, slowUntil = 0, dotUntil = 0, darkUntil = 0, nextDot = 0, darkOn = false }

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

local function point(x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) or x ~= x or y ~= y or z ~= z then return nil end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then return nil end
    return vector3(x, y, z)
end

local function mySid()
    return GetPlayerServerId(PlayerId())
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
    for _, list in ipairs({ P.hand, P.stations.fx, P.beam.fx }) do
        for _, fx in ipairs(list) do fix(fx) end
    end
    for k, list in pairs(P.impact) do
        if type(list) == 'table' then for _, fx in ipairs(list) do fix(fx) end end
    end
    for _, K in pairs(Cfg.Blast) do for _, fx in ipairs(K.fx) do fix(fx) end end
    for _, fx in ipairs({ P.smoke, P.orbTrail, P.curse, P.castStart, P.castEnd }) do fix(fx) end
    for cat, list in pairs(Cfg.Materials) do
        for _, h in ipairs(list) do MATERIALS[h % 4294967296] = cat end
    end
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
    for _, list in ipairs({ P.hand, P.stations.fx, P.beam.fx }) do
        for _, fx in ipairs(list) do loadPtfx(fx.asset) end
    end
    for _, list in pairs(P.impact) do
        if type(list) == 'table' then for _, fx in ipairs(list) do loadPtfx(fx.asset) end end
    end
    for _, K in pairs(Cfg.Blast) do for _, fx in ipairs(K.fx) do loadPtfx(fx.asset) end end
    for _, fx in ipairs({ P.smoke, P.orbTrail, P.curse, P.castStart, P.castEnd }) do loadPtfx(fx.asset) end
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

local function impactBurst(pos, ch, cat)
    local list = Cfg.Ptfx.impact[cat or 'default'] or Cfg.Ptfx.impact.default
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

local function startStations(origin, count, fxList)
    local S = Cfg.Ptfx.stations
    count, fxList = count or S.count, fxList or S.fx
    local list = {}
    for i = 1, count do
        local fx = fxList[((i - 1) % #fxList) + 1]
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
    if not list then return end
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

local function ring(pos, normal, size, c, alpha, rotZ, kind)
    local n = normal or UP
    DrawMarker(kind or 25, pos.x, pos.y, pos.z + 0.03, n.x, n.y, n.z, 0.0, 0.0, rotZ or 0.0,
        size, size, size, c[1], c[2], c[3], alpha, false, false, 2, false, nil, nil, false)
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
    local up = math.abs(dir.z) > 0.95 and vector3(1.0, 0.0, 0.0) or UP
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
        local phase = (t % I.ringPeriod) / I.ringPeriod
        ring(pos, normal, I.ringSize * ch * (0.3 + 0.9 * phase), I.ring, math.floor(I.ring[4] * ch * (1.0 - phase)))
        ring(pos, nil, I.ringSize * ch * 0.45 * (0.9 + 0.2 * pulse), I.sphere, math.floor(I.ring[4] * ch), (t * I.runeSpin) % 360.0, 27)
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

local function drawOrb(pos, t, lod)
    local O, B = Cfg.Spells.orb, Cfg.Beam
    local pulse = 0.85 + 0.15 * math.sin(t * 18.0)
    sphere(pos, O.size * pulse, B.shadow, 200)
    sphere(pos, O.size * 0.55 * pulse, B.core, 230)
    for k = 1, 3 do
        local a = t * 9.0 + k * TAU / 3.0
        local p = pos + vector3(math.cos(a), math.sin(a), math.sin(a * 1.7) * 0.5) * (O.size * 1.6)
        sphere(p, O.size * 0.25, B.glow, 180)
    end
    if lod >= 0.5 and Cfg.Lights.enabled then
        local c = Cfg.Lights.colour
        DrawLightWithRange(pos.x, pos.y, pos.z, c[1], c[2], c[3], 5.0, 3.0 * pulse)
    end
end

local function drawAimPreview(to, normal, t)
    local c = Cfg.Beam.glow
    local a = math.floor(70 + 30 * math.sin(t * 4.0))
    sphere(to, 0.07, c, a)
    if normal and normal.z > 0.6 then
        ring(to, normal, spell == 'curse' and Cfg.Spells.curse.radius * 2.0 or 0.35, c, a - 30)
    end
end

local function drawText(label, x, y, c, alpha)
    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(c[1], c[2], c[3], alpha)
    SetTextCentre(true)
    SetTextDropshadow(0, 0, 0, 0, 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(x, y)
end

local function drawHud(now)
    local H, M = Cfg.Hud, Cfg.Mana
    if not H.enabled then return end
    local busy = casting or lift ~= nil or now < hudUntil
    local hot = now < overheatUntil
    if not busy and not (M.enabled and (mana < M.max or hot)) then return end
    local k = busy and 1.0 or 0.75
    local frac = M.enabled and clamp(mana / M.max, 0.0, 1.0) or 1.0

    DrawRect(H.x, H.y, H.width + 0.004, H.height + 0.006, 0, 0, 0, math.floor(150 * k))
    DrawRect(H.x, H.y, H.width, H.height, 40, 0, 70, math.floor(200 * k))
    if frac > 0.0 then
        local w = H.width * frac
        if hot then
            DrawRect(H.x - H.width / 2 + w / 2, H.y, w, H.height, 200, 40, 60, math.floor(230 * k))
        else
            DrawRect(H.x - H.width / 2 + w / 2, H.y, w, H.height, 170, 60, 255, math.floor(230 * k))
        end
    end
    if casting and charge > 0.0 then
        local w = H.width * charge
        DrawRect(H.x - H.width / 2 + w / 2, H.y - H.height - 0.004, w, 0.003, 230, 200, 255, math.floor(220 * k))
    end

    if hot then
        drawText(Cfg.Text.hudOverheat, H.x, H.y - 0.03, { 255, 80, 100 }, math.floor(210 * k * (0.6 + 0.4 * math.sin(now / 90.0))))
    else
        drawText(Cfg.Text.hud .. ' - ' .. (Cfg.Spells.names[spell] or spell), H.x, H.y - 0.03, { 200, 140, 255 }, math.floor(210 * k))
    end
end

-- Aim and materials

local function handPos(ped)
    return GetPedBoneCoords(ped, HAND_BONE, 0.0, 0.0, 0.0)
end

local function materialOf(hash, ent, pos)
    if ent ~= 0 then
        if IsEntityAVehicle(ent) then return 'metal' end
        if IsEntityAPed(ent) then return 'flesh' end
    end
    local cat = hash and MATERIALS[hash % 4294967296]
    if cat then return cat end
    local hasWater, h = GetWaterHeight(pos.x, pos.y, pos.z)
    if hasWater and math.abs(float(h) - pos.z) < 0.4 then return 'water' end
    return 'default'
end

local function aim(ped, now, force)
    if ray and not force and not casting and not lift and not due(timers, 'ray', 50, now) then return ray end
    local camPos = GetGameplayCamCoord()
    local dest = camPos + rotToDir(GetGameplayCamRot(2)) * Cfg.Range
    local ignore = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
    local probe = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, RAY_FLAGS, ignore, 4)
    local _, hit, endPos, normal, material, ent = GetShapeTestResultIncludingMaterial(probe)
    if hit == 1 or hit == true then
        ent = ent or 0
        ray = { to = endPos, hit = true, ent = ent, normal = normal, cat = materialOf(material, ent, endPos) }
    else
        ray = { to = dest, hit = false, ent = 0, normal = nil, cat = 'default' }
    end
    return ray
end

local function scorch(pos, normal, cat)
    local D = Cfg.Decal
    if not D.enabled or not D.on[cat] then return end
    local n = normal or UP
    local side = normalize(cross(n, math.abs(n.z) > 0.9 and vector3(0.0, 1.0, 0.0) or UP))
    AddDecal(D.type, pos.x, pos.y, pos.z, -n.x, -n.y, -n.z, side.x, side.y, side.z,
        D.size, D.size, 1.0, 1.0, 1.0, 1.0, D.timeoutS, false, false, false)
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

local function dropPatch(pos, now, normal, cat)
    local F = Cfg.Fire
    local step = cat == 'wood' and F.stepDist * 0.7 or F.stepDist
    if #patches >= F.max then return end
    if lastPatchPos and #(pos - lastPatchPos) < step then return end
    local children = cat == 'wood' and F.children + 1 or F.children
    patches[#patches + 1] = { t = now, pos = pos, fire = StartScriptFire(pos.x, pos.y, pos.z, children, false) }
    lastPatchPos = pos
    scorch(pos, normal, cat)
end

-- Damage

local function takeControl(ent)
    if not NetworkGetEntityIsNetworked(ent) then return true end
    if not NetworkHasControlOfEntity(ent) then NetworkRequestControlOfEntity(ent) end
    return NetworkHasControlOfEntity(ent)
end

local function shove(ent, dir, force, lift_)
    ApplyForceToEntity(ent, 1, dir.x * force, dir.y * force, lift_, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
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

-- Mana and debuffs

local function spendMana(amount, now)
    mana = math.max(0.0, mana - amount)
    lastManaUse = now
end

local function hasMana(cost, now)
    if not Cfg.Mana.enabled then return true end
    return now >= overheatUntil and mana >= math.max(cost, Cfg.Mana.minToCast)
end

local function manaTick(now, dt)
    local M = Cfg.Mana
    if not M.enabled then
        mana = M.max
        return
    end
    if now < overheatUntil or casting or lift then return end
    if now - lastManaUse >= M.regenDelayMs then mana = math.min(M.max, mana + M.regenPerSec * dt) end
end

local function overheat(ped, now)
    overheatUntil = now + Cfg.Mana.overheatMs
    mana, lastManaUse = 0.0, now
    notify(Cfg.Text.overheat)
    oneShot(Cfg.Audio.overheat)
    if Cfg.Screen.overheatShake then ShakeGameplayCam(Cfg.Screen.overheatShake, 0.5) end
    burst(Cfg.Ptfx.castEnd, handPos(ped), 1.2)
end

local function applyDebuff(kind, now)
    local D = Cfg.Debuff
    if not D.enabled then return end
    local K = D[kind] or D.hit
    debuff.slowUntil = math.max(debuff.slowUntil, now + K.slowMs)
    debuff.dotUntil = math.max(debuff.dotUntil, now + K.dotMs)
    debuff.darkUntil = math.max(debuff.darkUntil, now + K.darkMs)
    if not debuff.active then
        debuff.active, debuff.nextDot = true, now + D.dotTickMs
        SetPlayerSprint(PlayerId(), false)
    end
end

local function endDebuff(ped)
    debuff.active = false
    SetPedMoveRateOverride(ped, 1.0)
    SetPlayerSprint(PlayerId(), true)
    if debuff.darkOn then
        debuff.darkOn = false
        if not tintOn then ClearExtraTimecycleModifier() end
    end
end

-- Sync (state bags)

local function publishState(state, now, force)
    if not Cfg.Sync.enabled then return end
    if not state then
        lastSent, lastSentAt = nil, 0
        LocalPlayer.state:set('darkmagic', false, true)
        return
    end
    if not force and now - lastSentAt < Cfg.Sync.keepaliveMs then return end
    seq = seq + 1
    state.n, lastSentAt = seq, now
    LocalPlayer.state:set('darkmagic', state, true)
end

local function publishBeam(to, ground, now, force)
    if not Cfg.Sync.enabled then return end
    if not force and lastSent and #(to - lastSent) < Cfg.Sync.moveEpsilon and now - lastSentAt < Cfg.Sync.keepaliveMs then return end
    lastSent = to
    publishState({ s = 'beam', x = to.x, y = to.y, z = to.z, g = ground and 1 or 0 }, now, true)
end

local function sleepRemote(r)
    killAura(r.fx)
    stopStations(r.stations)
    stopLoopSound(r.sound)
    r.fx, r.stations, r.sound, r.started = nil, nil, nil, false
end

local function dropRemote(sid, r, quiet)
    sleepRemote(r)
    remote[sid] = nil
    if r.lastPos and not quiet then burst(Cfg.Ptfx.castEnd, r.lastPos, 1.0) end
end

AddStateBagChangeHandler('darkmagic', nil, function(bagName, _, value)
    local sid = tonumber(bagName:match('^player:(%d+)$'))
    if not sid or sid == mySid() then return end
    local now = GetGameTimer()
    if type(value) ~= 'table' then
        if remote[sid] then remote[sid].done = true end
        return
    end

    local kind, parsed = value.s or 'beam', nil
    if kind == 'beam' then
        local p = point(value.x, value.y, value.z)
        if not p then return end
        parsed = { target = p, ground = value.g == 1 }
    elseif kind == 'lift' then
        local v = tonumber(value.v)
        if not v then return end
        parsed = { veh = v }
    elseif kind == 'orb' then
        local p, dir = point(value.x, value.y, value.z), point(value.dx, value.dy, value.dz)
        if not p or not dir or #dir < 0.5 or #dir > 1.5 then return end
        parsed = { origin = p, pos = p, dir = normalize(dir), speed = clamp(float(value.sp) > 0 and float(value.sp) or 30.0, 5.0, 80.0), launched = now, orbDone = false }
    else
        return
    end

    local r = remote[sid]
    if not r or r.kind ~= kind then
        if r then sleepRemote(r) end
        r = { kind = kind, timers = {}, pid = GetPlayerFromServerId(sid), start = now }
        remote[sid] = r
    end
    for k, v in pairs(parsed) do r[k] = v end
    r.t, r.done = now, nil
    if kind == 'beam' and not r.smooth then r.smooth = parsed.target end
end)

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

-- Blasts, orb, curse, grasp

local function playBlast(pos, kind, mine)
    local K = Cfg.Blast[kind]
    for _, fx in ipairs(K.fx) do burst(fx, pos, 1.0) end
    blasts[#blasts + 1] = { pos = pos, t0 = GetGameTimer(), kind = kind }
    if Cfg.Audio.enabled and Cfg.Audio.blast then
        PlaySoundFromCoord(-1, Cfg.Audio.blast.name, pos.x, pos.y, pos.z, Cfg.Audio.blast.set, false, 80, false)
    end
    if not mine then
        local ped = PlayerPedId()
        if not IsEntityDead(ped) and #(GetEntityCoords(ped) - pos) <= K.radius then applyDebuff('blast', GetGameTimer()) end
    end
end

local function detonate(pos, kind, now)
    local K = Cfg.Blast[kind]
    spendMana(K.manaCost, now)
    AddExplosion(pos.x, pos.y, pos.z, K.explosionType, K.damageScale, true, true, 0.0, false)
    TriggerServerEvent('darkmagic:blast', pos.x, pos.y, pos.z, kind)
    if K.shake then ShakeGameplayCam(K.shake, K.shakeAmp) end
    playBlast(pos, kind, true)
end

local function drawBlasts(now)
    for i = #blasts, 1, -1 do
        local b = blasts[i]
        local K = Cfg.Blast[b.kind]
        local age = now - b.t0
        if age > K.light.ms then
            table.remove(blasts, i)
        else
            local k = 1.0 - age / K.light.ms
            local c = Cfg.Lights.colour
            DrawLightWithRange(b.pos.x, b.pos.y, b.pos.z, c[1], c[2], c[3], K.light.range * (0.4 + 0.6 * k), K.light.intensity * k)
            ring(b.pos, nil, K.radius * (0.15 + 0.85 * (1.0 - k)), Cfg.Impact.ring, math.floor(Cfg.Impact.ring[4] * k))
            ring(b.pos, nil, K.radius * 0.5 * (1.0 - k), Cfg.Impact.sphere, math.floor(120 * k), (age * 0.5) % 360.0, 27)
            sphere(b.pos, K.radius * 0.35 * k, Cfg.Impact.sphere, math.floor(180 * k))
        end
    end
end

local function clearOrb()
    if not orb then return end
    stopStations(orb.fx)
    orb = nil
    publishState(nil)
end

local function castOrb(ped, now)
    local O = Cfg.Spells.orb
    if now - lastOrbAt < O.cooldownMs then return end
    if not hasMana(O.manaCost, now) then
        notify(Cfg.Text.noMana)
        return
    end
    local r = aim(ped, now, true)
    local from = handPos(ped)
    local dir = normalize(r.to - from)
    spendMana(O.manaCost, now)
    lastOrbAt = now
    clearOrb()
    orb = { pos = from, origin = from, dir = dir, fx = startStations(from, 1, { Cfg.Ptfx.smoke }) }
    burst(Cfg.Ptfx.castStart, from, 0.6)
    oneShot(Cfg.Audio.orb)
    startPose(ped)
    poseUntil = now + 500
    publishState({ s = 'orb', x = from.x, y = from.y, z = from.z, dx = dir.x, dy = dir.y, dz = dir.z, sp = O.speed }, now, true)
end

local function orbTick(ped, now, dt, t)
    local O = Cfg.Spells.orb
    local nextPos = orb.pos + orb.dir * (O.speed * dt)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(orb.pos.x, orb.pos.y, orb.pos.z, nextPos.x, nextPos.y, nextPos.z, RAY_FLAGS, ped, 4)
    local _, hit, endPos = GetShapeTestResult(probe)
    if hit == 1 or hit == true then
        clearOrb()
        detonate(endPos, 'orb', now)
    elseif #(nextPos - orb.origin) >= Cfg.Range * O.rangeMul then
        clearOrb()
        detonate(nextPos, 'orb', now)
    else
        orb.pos = nextPos
        drawOrb(nextPos, t, 1.0)
        moveStations(orb.fx, nextPos, nextPos, 1.0, t)
        if due(timers, 'orbtrail', O.trailMs, now) then burst(Cfg.Ptfx.orbTrail, nextPos, 1.0) end
    end
end

local function castCurse(ped, now)
    local C = Cfg.Spells.curse
    if now - lastCurseAt < C.cooldownMs then
        notify(Cfg.Text.cooldown)
        return
    end
    if not hasMana(C.manaCost, now) then
        notify(Cfg.Text.noMana)
        return
    end
    local r = aim(ped, now, true)
    if not r.hit then return end
    spendMana(C.manaCost, now)
    lastCurseAt = now
    TriggerServerEvent('darkmagic:curse', r.to.x, r.to.y, r.to.z)
    burst(Cfg.Ptfx.castStart, handPos(ped), 0.6)
    oneShot(Cfg.Audio.curse)
    startPose(ped)
    poseUntil = now + 600
end

local function zoneTick(id, zn, now, t, myPos, myPed)
    local C = Cfg.Spells.curse
    if now >= zn.expires then
        stopStations(zn.fx)
        zones[id] = nil
        burst(Cfg.Ptfx.castEnd, zn.pos, 1.0)
        return
    end
    if #(zn.pos - myPos) <= Cfg.Sync.maxDistance then
        if not zn.fx then zn.fx = startStations(zn.pos, 2, { Cfg.Ptfx.smoke, Cfg.Ptfx.stations.fx[1] }) end
        local k = clamp((zn.expires - now) / 800.0, 0.0, 1.0)
        local pulse = 0.5 + 0.5 * math.sin(t * 4.0)
        local phase = (t % 1.2) / 1.2
        ring(zn.pos, nil, zn.radius * 1.6 * k, Cfg.Impact.sphere, math.floor(150 * k), (t * 40.0) % 360.0, 27)
        ring(zn.pos, nil, zn.radius * 2.0 * phase, Cfg.Impact.ring, math.floor(Cfg.Impact.ring[4] * k * (1.0 - phase)))
        DrawMarker(1, zn.pos.x, zn.pos.y, zn.pos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, zn.radius * 2.0, zn.radius * 2.0, 1.2,
            Cfg.Beam.glow[1], Cfg.Beam.glow[2], Cfg.Beam.glow[3], math.floor(22 * k), false, false, 2, false, nil, nil, false)
        if Cfg.Lights.enabled then
            local c = Cfg.Lights.colour
            DrawLightWithRange(zn.pos.x, zn.pos.y, zn.pos.z + 0.5, c[1], c[2], c[3], zn.radius * 2.0, (1.0 + 0.6 * pulse) * k)
        end
        moveStations(zn.fx, zn.pos, zn.pos, 0.6 + 0.4 * pulse, t)
        if due(zn.timers, 'puff', 700, now) then
            local a = math.random() * TAU
            local d = math.random() * zn.radius
            burst(Cfg.Ptfx.curse, zn.pos + vector3(math.cos(a) * d, math.sin(a) * d, 0.2), 0.6)
        end
    elseif zn.fx then
        stopStations(zn.fx)
        zn.fx = nil
    end

    if not due(zn.timers, 'tick', C.tickMs, now) then return end
    if zn.caster == mySid() then
        for _, p in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(p) and not IsEntityDead(p) and #(GetEntityCoords(p) - zn.pos) <= zn.radius and takeControl(p) then
                ApplyDamageToPed(p, C.damage, false)
            end
        end
    elseif not IsEntityDead(myPed) then
        local d = myPos - zn.pos
        if math.abs(d.z) <= 2.5 and #(vector3(d.x, d.y, 0.0)) <= zn.radius then
            ApplyDamageToPed(myPed, C.damage, false)
            applyDebuff('curse', now)
        end
    end
end

local function liftable(veh)
    if not IsEntityAVehicle(veh) then return false end
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local p = GetPedInVehicleSeat(veh, seat)
        if p ~= 0 and IsPedAPlayer(p) then return false end
    end
    return takeControl(veh)
end

local function grab(ped, veh, now)
    local from = handPos(ped)
    local net = NetworkGetEntityIsNetworked(veh) and NetworkGetNetworkIdFromEntity(veh) or 0
    lift = { veh = veh, net = net, since = now, fx = startStations(GetEntityCoords(veh), 2, { Cfg.Ptfx.smoke, Cfg.Ptfx.stations.fx[1] }) }
    stopStations(stations)
    stations = startStations(from)
    startPose(ped)
    if Cfg.Screen.shake then ShakeGameplayCam(Cfg.Screen.shake, 0.0) end
    loopSound = startLoopSound(Cfg.Audio.castLoop)
    burst(Cfg.Ptfx.castStart, from, 0.7)
    publishState({ s = 'lift', v = net }, now, true)
end

local function release(ped, now, throw)
    local L = Cfg.Spells.lift
    if lift then
        if throw and DoesEntityExist(lift.veh) then
            local dir = rotToDir(GetGameplayCamRot(2))
            SetEntityVelocity(lift.veh, dir.x * L.throwSpeed, dir.y * L.throwSpeed, dir.z * L.throwSpeed + 3.0)
            burst(Cfg.Ptfx.castEnd, GetEntityCoords(lift.veh), 1.0)
        end
        stopStations(lift.fx)
        lift = nil
    end
    stopStations(stations)
    stations = {}
    stopPose(ped)
    if Cfg.Screen.shake then StopGameplayCamShaking(true) end
    if throw and Cfg.Screen.releaseShake then ShakeGameplayCam(Cfg.Screen.releaseShake, Cfg.Screen.releaseAmplitude) end
    stopLoopSound(loopSound)
    loopSound = nil
    scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
    publishState(nil)
end

local function liftTick(ped, from, now, dt, t, camPos)
    local L = Cfg.Spells.lift
    local veh = lift.veh
    if not DoesEntityExist(veh) then
        release(ped, now, false)
        return
    end
    takeControl(veh)
    spendMana(L.drainPerSec * dt, now)
    if Cfg.Mana.enabled and mana <= 0.0 then
        release(ped, now, false)
        overheat(ped, now)
        return
    end

    local target = camPos + rotToDir(GetGameplayCamRot(2)) * L.holdDistance + vector3(0.0, 0.0, math.sin(t * 2.0) * L.bob)
    local vpos = GetEntityCoords(veh)
    local want = (target - vpos) * L.follow
    local speed = #want
    if speed > L.maxSpeed then want = want * (L.maxSpeed / speed) end
    SetEntityVelocity(veh, want.x, want.y, want.z)

    local ch = easeOut(clamp((now - lift.since) / 400.0, 0.0, 1.0))
    local delta = vpos - from
    drawBeam(from, vpos, ch, t, 1.0, camPos)
    drawImpact(vpos, nil, ch, t)
    drawLights(from, vpos, normalize(delta), #delta, ch, t, 1.0)
    moveStations(stations, from, vpos, ch, t)
    moveStations(lift.fx, vpos, vpos, ch, t)
    scaleAura(aura.fx, 0.6 + 0.9 * ch)
    hudUntil = now + Cfg.Hud.fadeMs
    if Cfg.Screen.shake then SetGameplayCamShakeAmplitude(Cfg.Screen.shakeAmplitude * 0.5 * ch) end
    updatePose(ped, now)
    if due(timers, 'liftfx', 150, now) then impactBurst(vpos, ch, 'metal') end
    if due(timers, 'sync', Cfg.Sync.keepaliveMs, now) then publishState({ s = 'lift', v = lift.net }, now, true) end
end

-- Beam cast lifecycle

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

local function endCast(ped, now, forced)
    local S, B = Cfg.Screen, Cfg.Blast.burst
    local full = not forced and charge >= 0.999 and lastAim ~= nil and hasMana(B.manaCost, now)
    local target = lastAim
    casting, charge, castEnded = false, 0.0, now
    stopStations(stations)
    stations = {}
    if tintOn then tintUntil = now + S.tintFadeMs end
    if S.postfxEnabled and S.postfx then AnimpostfxStop(S.postfx) end
    if S.shake then StopGameplayCamShaking(true) end
    stopPose(ped)
    stopLoopSound(loopSound)
    loopSound = nil
    scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
    publishState(nil)
    if full then
        detonate(target, 'burst', now)
    else
        if target and now - castStart >= 200 then burst(Cfg.Ptfx.castEnd, target, 1.0) end
        if S.releaseShake then ShakeGameplayCam(S.releaseShake, S.releaseAmplitude) end
    end
end

local function castTick(ped, from, r, ch, t, now, dt, camPos)
    local S = Cfg.Screen
    local to = r.to
    local delta = to - from
    local len = #delta
    local dir = normalize(delta)
    local ground = r.hit and r.normal and r.normal.z > 0.6

    spendMana(Cfg.Mana.beamDrainPerSec * dt, now)
    if Cfg.Mana.enabled and mana <= 0.0 then
        endCast(ped, now, true)
        overheat(ped, now)
        return
    end

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
    if due(timers, 'impactfx', Cfg.Ptfx.impact.intervalMs, now) then impactBurst(to, ch, r.cat) end
    if due(timers, 'hit', Cfg.Damage.intervalMs, now) then hitEntity(r.ent, dir, ch) end
    if due(timers, 'sync', math.max(Cfg.Sync.intervalMs, 50), now) then publishBeam(to, ground, now, false) end
    if r.hit and Cfg.Fire.enabled and r.cat ~= 'water' and now - castStart >= Cfg.Fire.delayMs then dropPatch(to, now, r.normal, r.cat) end
end

local function setSpell(i, now)
    spellIndex = ((i - 1) % #Cfg.Spells.order) + 1
    spell = Cfg.Spells.order[spellIndex]
    notify(Cfg.Text.spell:format(Cfg.Spells.names[spell] or spell))
    oneShot(Cfg.Audio.spell)
    hudUntil = now + 1500
end

local function autoOffReason(ped, now)
    if Cfg.AutoOffOnDeath and IsEntityDead(ped) then return Cfg.Text.offDead end
    if now - armedAt < 500 then return nil end
    local w = GetSelectedPedWeapon(ped)
    if Cfg.WeaponPolicy == 'holster' and w ~= UNARMED then return Cfg.Text.offWeapon end
    if Cfg.WeaponPolicy == 'require' and w == UNARMED then return Cfg.Text.offUnarmed end
    return nil
end

local function stopEverything(ped, now)
    if casting then endCast(ped, now, true) end
    if lift then release(ped, now, false) end
    clearOrb()
    if poseUntil > 0 then
        stopPose(ped)
        poseUntil = 0
    end
    clearTint()
    stopAura()
    clearPatches()
    lastAim, ray = nil, nil
end

local function setArmed(v, reason, silent)
    if armed == v then return end
    local ped = PlayerPedId()
    local now = GetGameTimer()
    armed, ready = v, false
    gen = gen + 1
    if v then
        local my = gen
        preload()
        if my ~= gen or not armed then return end
        now = GetGameTimer()
        if disarmedAt > 0 then mana = math.min(Cfg.Mana.max, mana + Cfg.Mana.regenPerSec * (now - disarmedAt) / 1000.0) end
        armedAt, ready = now, true
        if Cfg.WeaponPolicy == 'holster' then SetCurrentPedWeapon(ped, UNARMED, true) end
        ensureAura(ped)
        scaleAura(aura.fx, Cfg.Ptfx.idleAuraScale)
        oneShot(Cfg.Audio.armOn)
        notify(Cfg.Text.on)
    else
        stopEverything(ped, now)
        disarmedAt = now
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
            local dt = GetFrameTime()
            local reason = autoOffReason(ped, now)

            if reason then
                setArmed(false, reason)
            else
                local pressed = pressEdge
                pressEdge = false
                for i = 1, #COMBAT_CONTROLS do DisableControlAction(0, COMBAT_CONTROLS[i], true) end
                if keyDown then
                    for i = 1, #CAST_CONTROLS do DisableControlAction(0, CAST_CONTROLS[i], true) end
                end
                if IsPauseMenuActive() or IsNuiFocused() then keyDown = false end
                if due(timers, 'aura', 1000, now) then ensureAura(ped) end
                manaTick(now, dt)

                local from = handPos(ped)
                local r = aim(ped, now, pressed)
                local camPos = GetGameplayCamCoord()
                local inVehicle = IsPedInAnyVehicle(ped, false)
                local can = keyDown and not IsEntityDead(ped) and (Cfg.AllowInVehicle or not inVehicle)

                if poseUntil > 0 then
                    if now >= poseUntil and not casting and not lift then
                        stopPose(ped)
                        poseUntil = 0
                    else
                        updatePose(ped, now)
                    end
                end

                if spell == 'beam' then
                    if can and not casting and now - castEnded >= Cfg.RecastMs and hasMana(0.0, now) then
                        beginCast(ped, from, now)
                        publishBeam(r.to, r.hit and r.normal and r.normal.z > 0.6, now, true)
                    elseif casting and not can then
                        endCast(ped, now, keyDown)
                    end
                    if casting then
                        charge = easeOut(clamp((now - castStart) / Cfg.ChargeMs, 0.0, 1.0))
                        lastAim = r.to
                        castTick(ped, from, r, charge, t, now, dt, camPos)
                    end
                elseif spell == 'lift' then
                    if lift then
                        if can then liftTick(ped, from, now, dt, t, camPos) else release(ped, now, not keyDown) end
                    elseif pressed and can then
                        if r.hit and r.ent ~= 0 and hasMana(0.0, now) and liftable(r.ent) then
                            grab(ped, r.ent, now)
                        else
                            notify(Cfg.Text.noGrasp)
                        end
                    end
                elseif spell == 'orb' then
                    if pressed and can then castOrb(ped, now) end
                elseif spell == 'curse' then
                    if pressed and can then castCurse(ped, now) end
                end

                if orb then orbTick(ped, now, dt, t) end

                if not casting and not lift then
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
                drawHud(now)
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
                    dropRemote(sid, r, ped == 0 or r.kind ~= 'beam')
                elseif r.kind == 'orb' then
                    if not r.orbDone then
                        local prev = r.pos
                        r.pos = r.origin + r.dir * (r.speed * (now - r.launched) / 1000.0)
                        local probe = StartExpensiveSynchronousShapeTestLosProbe(prev.x, prev.y, prev.z, r.pos.x, r.pos.y, r.pos.z, RAY_FLAGS, ped, 4)
                        local _, hit = GetShapeTestResult(probe)
                        if hit == 1 or hit == true or #(r.pos - r.origin) > Cfg.Range * Cfg.Spells.orb.rangeMul then
                            r.orbDone = true
                            sleepRemote(r)
                        elseif #(r.pos - myPos) <= S.maxDistance then
                            active = true
                            if not r.started then
                                r.started, r.stations = true, startStations(r.pos, 1, { Cfg.Ptfx.smoke })
                            end
                            drawOrb(r.pos, t + sid, 1.0)
                            moveStations(r.stations, r.pos, r.pos, 1.0, t)
                            if due(r.timers, 'trail', Cfg.Spells.orb.trailMs, now) then burst(Cfg.Ptfx.orbTrail, r.pos, 1.0) end
                        elseif r.started then
                            sleepRemote(r)
                        end
                    end
                else
                    local from = handPos(ped)
                    local d = #(from - myPos)
                    local target = r.target
                    if r.kind == 'lift' then
                        target = nil
                        if r.veh and r.veh ~= 0 and NetworkDoesNetworkIdExist(r.veh) then
                            local veh = NetworkGetEntityFromNetworkId(r.veh)
                            if veh ~= 0 and DoesEntityExist(veh) then target = GetEntityCoords(veh) end
                        end
                    end
                    if target and d <= S.maxDistance and #(target - from) <= Cfg.Range + 5.0 then
                        active = true
                        if not r.started then
                            r.started = true
                            r.fx = spawnAura(ped)
                            r.stations = startStations(from)
                            r.sound = startLoopSound(Cfg.Audio.castLoop, ped)
                            burst(Cfg.Ptfx.castStart, from, 1.0)
                        end
                        if r.kind == 'beam' then
                            r.smooth = lerp(r.smooth or target, target, smoothing)
                        else
                            r.smooth = target
                        end
                        r.lastPos = r.smooth
                        local ch = easeOut(clamp((now - r.start) / Cfg.ChargeMs, 0.0, 1.0))
                        local lod = d < S.nearLod and 1.0 or (d < S.midLod and 0.5 or 0.25)
                        local delta = r.smooth - from
                        local len = #delta
                        scaleAura(r.fx, 0.6 + 0.9 * ch)
                        moveStations(r.stations, from, r.smooth, ch, t)
                        drawBeam(from, r.smooth, ch, t + sid, lod, camPos)
                        drawImpact(r.smooth, (r.kind == 'beam' and r.ground) and UP or nil, ch, t)
                        drawLights(from, r.smooth, normalize(delta), len, ch, t, lod)
                        if lod >= 0.5 and due(r.timers, 'beamfx', Cfg.Ptfx.beam.intervalMs, now) then beamBursts(from, r.smooth, len, ch, lod) end
                        if lod >= 0.25 and due(r.timers, 'impactfx', Cfg.Ptfx.impact.intervalMs, now) then impactBurst(r.smooth, ch, r.kind == 'lift' and 'metal' or 'default') end
                    elseif r.started then
                        sleepRemote(r)
                    end
                end
            end
            Wait(active and 0 or 100)
        end
    end
end)

CreateThread(function()
    while true do
        if next(zones) == nil and #blasts == 0 then
            Wait(200)
        else
            local ped = PlayerPedId()
            local myPos = GetEntityCoords(ped)
            local now = GetGameTimer()
            local t = now / 1000.0
            drawBlasts(now)
            for id, zn in pairs(zones) do zoneTick(id, zn, now, t, myPos, ped) end
            Wait(0)
        end
    end
end)

CreateThread(function()
    while true do
        if not debuff.active then
            Wait(200)
        else
            local D = Cfg.Debuff
            local ped = PlayerPedId()
            local now = GetGameTimer()
            local slow, dot, dark = now < debuff.slowUntil, now < debuff.dotUntil, now < debuff.darkUntil
            if slow then SetPedMoveRateOverride(ped, D.slow) end
            if dot and now >= debuff.nextDot then
                debuff.nextDot = now + D.dotTickMs
                if not IsEntityDead(ped) then ApplyDamageToPed(ped, D.dotDamage, false) end
            end
            if dark and not tintOn then
                if not debuff.darkOn then
                    SetExtraTimecycleModifier(D.darkness)
                    debuff.darkOn = true
                end
                SetExtraTimecycleModifierStrength(D.darkStrength * math.min(1.0, (debuff.darkUntil - now) / 600.0))
            elseif debuff.darkOn then
                debuff.darkOn = false
                if not tintOn then ClearExtraTimecycleModifier() end
            end
            if not (slow or dot or dark) then endDebuff(ped) end
            Wait(0)
        end
    end
end)

-- Input, events, cleanup

RegisterCommand('+darkmagic_cast', function()
    keyDown, pressEdge = true, true
end, false)
RegisterCommand('-darkmagic_cast', function() keyDown = false end, false)
RegisterKeyMapping('+darkmagic_cast', Cfg.Text.castLabel, 'keyboard', Cfg.CastKey)

RegisterCommand('darkmagic_spell', function()
    if not armed then return end
    local ped, now = PlayerPedId(), GetGameTimer()
    if casting then endCast(ped, now, true) end
    if lift then release(ped, now, false) end
    setSpell(spellIndex + 1, now)
end, false)
RegisterKeyMapping('darkmagic_spell', Cfg.Text.spellLabel, 'keyboard', Cfg.SpellKey)

RegisterCommand('darkspell', function(_, args)
    for i, name in ipairs(Cfg.Spells.order) do
        if name == args[1] then
            setSpell(i, GetGameTimer())
            return
        end
    end
end, false)

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
    local now = GetGameTimer()
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
    applyDebuff('hit', now)
end)

RegisterNetEvent('darkmagic:vehicleHit', function(netId, engine, body)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh == 0 or not DoesEntityExist(veh) or not NetworkHasControlOfEntity(veh) then return end
    SetVehicleEngineHealth(veh, GetVehicleEngineHealth(veh) - float(engine))
    SetVehicleBodyHealth(veh, GetVehicleBodyHealth(veh) - float(body))
end)

RegisterNetEvent('darkmagic:zone', function(id, casterSid, x, y, z, radius, durationMs)
    local pos = point(x, y, z)
    if not pos or not id then return end
    local now = GetGameTimer()
    zones[id] = { pos = pos, radius = clamp(float(radius), 1.0, 20.0), expires = now + clamp(float(durationMs), 1000.0, 60000.0), caster = casterSid, timers = {} }
    burst(Cfg.Ptfx.curse, pos, 1.2)
end)

RegisterNetEvent('darkmagic:blastFx', function(casterSid, x, y, z, kind)
    local pos = point(x, y, z)
    if not pos or not Cfg.Blast[kind] or casterSid == mySid() then return end
    playBlast(pos, kind, false)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    setArmed(false, nil, true)
    for sid, r in pairs(remote) do dropRemote(sid, r, true) end
    for id, zn in pairs(zones) do
        stopStations(zn.fx)
        zones[id] = nil
    end
    if debuff.active then endDebuff(PlayerPedId()) end
    if Cfg.Screen.hitFlash then AnimpostfxStop(Cfg.Screen.hitFlash) end
    for asset, ok in pairs(loaded.ptfx) do if ok then RemoveNamedPtfxAsset(asset) end end
    for dict, ok in pairs(loaded.anim) do if ok then RemoveAnimDict(dict) end end
end)
