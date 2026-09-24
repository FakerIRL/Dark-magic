Config = {}

Config.Range = 35.0
Config.AcePermission = 'darkmagic.use'
Config.CastKey = 'E'
Config.ToggleKey = ''
Config.ChargeMs = 900
Config.RecastMs = 350
Config.LoadTimeoutMs = 4000

-- 'holster': magic replaces the weapon, drawing one turns magic off
-- 'require': needs a weapon in hand, switching to unarmed turns magic off
-- 'ignore' : no weapon rule
Config.WeaponPolicy = 'holster'
Config.AutoOffOnDeath = true
Config.AllowInVehicle = false
Config.Notify = true

Config.Text = {
    on          = ('~p~Dark magic~s~ awakened. Hold ~b~%s~s~ to channel.'):format(Config.CastKey),
    off         = '~p~Dark magic~s~ dismissed.',
    offDead     = '~p~Dark magic~s~ fades with your life...',
    offWeapon   = '~p~Dark magic~s~ dismissed: weapon drawn.',
    offUnarmed  = '~p~Dark magic~s~ needs a weapon in hand.',
    noPerm      = '~r~You are not allowed to wield dark magic.',
    castLabel   = 'Dark Magic - Channel',
    toggleLabel = 'Dark Magic - Toggle',
    hud         = 'DARK MAGIC',
}

Config.Beam = {
    core       = { 215, 150, 255 },
    glow       = { 110, 0, 200 },
    shadow     = { 8, 0, 16 },
    coreWidth  = 0.045,
    glowWidth  = 0.17,
    coreAlpha  = 225,
    glowAlpha  = 60,
    ribbonSegs = 6,
    strands    = 4,
    segments   = 12,
    radius     = 0.13,
    twist      = 9.0,
    spin       = 6.0,
    orbs       = 4,
    orbSize    = 0.12,
    orbFlow    = 0.9,
}

Config.Impact = {
    sphere     = { 120, 20, 220, 160 },
    ring       = { 165, 70, 255, 140 },
    sphereSize = 0.18,
    ringSize   = 1.2,
    ringPeriod = 0.7,
    runeSpin   = 140.0,
}

Config.Lights = {
    enabled         = true,
    colour          = { 140, 40, 255 },
    impactRange     = 6.0,
    impactIntensity = 2.2,
    handRange       = 2.5,
    handIntensity   = 1.2,
    spot            = true,
    spotBrightness  = 1.6,
}

Config.Ptfx = {
    idleAuraScale = 0.35,
    hand = {
        { asset = 'core', name = 'ent_amb_smoke_foundry', scale = 0.30, colour = { 0.35, 0.05, 0.55 } },
        { asset = 'core', name = 'ent_amb_elec_crackle',  scale = 0.35, colour = { 0.60, 0.15, 1.00 } },
    },
    stations = {
        count = 4,
        drift = 0.35,
        fx = {
            { asset = 'core', name = 'ent_amb_elec_crackle',  scale = 0.55, colour = { 0.60, 0.15, 1.00 } },
            { asset = 'core', name = 'ent_amb_smoke_foundry', scale = 0.40, colour = { 0.20, 0.00, 0.35 } },
        },
    },
    beam = {
        intervalMs = 100,
        points     = 8,
        spacing    = 3.0,
        jitter     = 0.12,
        fx = {
            { asset = 'core', name = 'ent_dst_elec_fire_sp', scale = 0.28, colour = { 0.55, 0.10, 1.00 }, every = 1 },
            { asset = 'core', name = 'ent_sht_steam',        scale = 0.40, colour = { 0.06, 0.00, 0.10 }, every = 2 },
        },
    },
    impact = {
        intervalMs = 180,
        fx = {
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.32 },
            { asset = 'core',          name = 'ent_sht_electrical_box',     scale = 0.55, colour = { 0.55, 0.10, 1.00 } },
        },
    },
    castStart = { asset = 'scr_rcbarry2',  name = 'scr_clown_appears',          scale = 0.50 },
    castEnd   = { asset = 'scr_powerplay', name = 'scr_powerplay_beast_vanish', scale = 0.30 },
}

Config.Screen = {
    timecycle         = 'glasses_purple',
    timecycleStrength = 0.65,
    tintFadeMs        = 250,
    postfx            = 'DrugsMichaelAliensFight',
    postfxEnabled     = false,
    shake             = 'HAND_SHAKE',
    shakeAmplitude    = 1.0,
    releaseShake      = 'SMALL_EXPLOSION_SHAKE',
    releaseAmplitude  = 0.25,
    padRumble         = true,
    hitFlash          = 'Dont_tazeme_bro',
    hitFlashMs        = 600,
}

Config.Audio = {
    enabled   = true,
    armOn     = { name = 'Frontend_Beast_Fade_Screen',    set = 'FM_Events_Sasquatch_Sounds' },
    armOff    = { name = 'Frontend_Beast_Transform_Back', set = 'FM_Events_Sasquatch_Sounds' },
    castStart = { name = 'emp_blast',                     set = 'dlc_heists_biolab_finale_sounds' },
    castLoop  = { name = 'cannon_active',                 set = 'dlc_xm_orbital_cannon_sounds' },
    hit       = { name = 'Checkpoint_Beast_Hit',          set = 'FM_Events_Sasquatch_Sounds' },
}

-- 'point': the arm follows the camera (GTA Online pointing move network)
-- 'clip' : play dict/clip as an upper-body loop
Config.Anim = {
    enabled = true,
    mode    = 'point',
    dict    = 'anim@mp_player_intupperraining_cash',
    clip    = 'idle_a',
    flag    = 49,
}

Config.Fire = {
    enabled  = true,
    delayMs  = 450,
    lifeMs   = 2000,
    stepDist = 1.2,
    max      = 12,
    children = 1,
}

Config.Damage = {
    intervalMs = 250,
    vehicle = { enabled = true, engine = 45.0, body = 25.0 },
    ped     = { enabled = true, amount = 12, ragdollMs = 900, push = 6.0 },
    players = { enabled = true },
    objects = { push = 4.0 },
}

Config.Sync = {
    enabled     = true,
    intervalMs  = 100,
    keepaliveMs = 500,
    moveEpsilon = 0.2,
    staleMs     = 3000,
    maxDistance = 150.0,
    nearLod     = 30.0,
    midLod      = 70.0,
}

Config.Hud = {
    enabled = true,
    fadeMs  = 600,
    x = 0.5, y = 0.955,
    width = 0.10, height = 0.006,
}
