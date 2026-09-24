Config = {}

Config.Range = 35.0
Config.AcePermission = 'darkmagic.use'
Config.CastKey = 'E'
Config.SpellKey = 'CAPITAL'
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
    on          = ('~p~Dark magic~s~ awakened. Hold ~b~%s~s~ to channel, ~b~%s~s~ to change spell.'):format(Config.CastKey, Config.SpellKey),
    off         = '~p~Dark magic~s~ dismissed.',
    offDead     = '~p~Dark magic~s~ fades with your life...',
    offWeapon   = '~p~Dark magic~s~ dismissed: weapon drawn.',
    offUnarmed  = '~p~Dark magic~s~ needs a weapon in hand.',
    noPerm      = '~r~You are not allowed to wield dark magic.',
    spell       = 'Spell: ~p~%s~s~',
    overheat    = '~r~Overheated.~s~ Your dark magic must cool down.',
    noMana      = '~r~Not enough dark energy.',
    cooldown    = '~r~Too soon.',
    noGrasp     = '~r~Nothing to grasp there.',
    castLabel   = 'Dark Magic - Channel',
    spellLabel  = 'Dark Magic - Next spell',
    toggleLabel = 'Dark Magic - Toggle',
    hud         = 'DARK MAGIC',
    hudOverheat = 'OVERHEATED',
}

Config.Spells = {
    order = { 'beam', 'orb', 'curse', 'lift' },
    names = { beam = 'Beam', orb = 'Dark Orb', curse = 'Curse', lift = 'Grasp' },
    orb   = { manaCost = 25, cooldownMs = 700, speed = 30.0, size = 0.28, rangeMul = 1.5, trailMs = 40 },
    curse = { manaCost = 40, cooldownMs = 6000, radius = 4.0, durationMs = 8000, tickMs = 1000, damage = 4 },
    lift  = { drainPerSec = 22.0, holdDistance = 7.0, follow = 3.5, maxSpeed = 18.0, throwSpeed = 32.0, bob = 0.4 },
}

Config.Mana = {
    enabled         = true,
    max             = 100.0,
    beamDrainPerSec = 20.0,
    regenPerSec     = 14.0,
    regenDelayMs    = 1000,
    overheatMs      = 3500,
    minToCast       = 10.0,
}

Config.Blast = {
    burst = {
        manaCost = 30.0, radius = 6.0, explosionType = 4, damageScale = 0.55,
        shake = 'MEDIUM_EXPLOSION_SHAKE', shakeAmp = 0.6,
        light = { range = 14.0, intensity = 8.0, ms = 700 },
        fx = {
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 1.10 },
            { asset = 'scr_rcbarry2',  name = 'scr_exp_clown',              scale = 0.90 },
            { asset = 'core',          name = 'ent_sht_electrical_box',     scale = 1.30, colour = { 0.55, 0.10, 1.00 } },
        },
    },
    orb = {
        manaCost = 0.0, radius = 3.5, explosionType = 4, damageScale = 0.30,
        shake = 'SMALL_EXPLOSION_SHAKE', shakeAmp = 0.4,
        light = { range = 9.0, intensity = 5.0, ms = 500 },
        fx = {
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.60 },
            { asset = 'scr_rcbarry2',  name = 'scr_exp_clown',              scale = 0.50 },
        },
    },
}

Config.Debuff = {
    enabled      = true,
    slow         = 0.62,
    dotDamage    = 2,
    dotTickMs    = 500,
    darkness     = 'Glasses_BlackOut',
    darkStrength = 0.55,
    hit   = { slowMs = 1500, dotMs = 2500, darkMs = 1500 },
    blast = { slowMs = 2500, dotMs = 3000, darkMs = 2500 },
    curse = { slowMs = 1300, dotMs = 0,    darkMs = 1300 },
}

Config.Materials = {
    metal = { 0xA9BC4217, 0xEA34E8F8, 0x2CD49BD1, 0xF3B93B, 0x6E3DBFB8, 0xDD3CDCF9, 0x2D6E26CD, 0x781FA34, 0x31B80AD6,
              0xE699F485, 0x7D368D93, 0x68FEB9FD, 0xF2373DE9, 0xD2FFA63D, 0xD48AA0F2, 0xFA73FCA1, 0x7F630AE2 },
    stone = { 0x46CA81E8, 0x1567BF52, 0xBF59B491, 0x78239B1A, 0x10DD5498, 0xB26EEFB0, 0x70726A55, 0x2D9C1E0D, 0xCDEB5023,
              0xF8902AC8, 0x79E4953, 0x61B1F936, 0xBB9CA6D8, 0xDDC7963F, 0xF0FC7AFE, 0x73EF7697, 0x2257A573, 0x71AB3FEE, 0xF116BC2D },
    wood  = { 0xE82A6F1C, 0x2114B37D, 0x309F8BB7, 0x789C7AB, 0xD35443DE, 0x76D9AC2F, 0xEA3746BD, 0xC8D738E7, 0x461D0E9B,
              0x2B13503D, 0x981E5200, 0x77E08A22, 0x8070DCF9, 0x8DD4EBB9, 0xE18DFF5, 0xAC038918 },
    dirt  = { 0xA0EBF7E4, 0x1E6D775E, 0x363CBCD5, 0x8E4D8AFF, 0x1E5E7A48, 0x4CCC2AFF, 0x8F9CD58F, 0x8C31B7EA, 0x129ECA2A,
              0x61826E7A, 0x42251DC0, 0xE47A3E41, 0x4F747B87, 0xB34E900D, 0x38BBD00C, 0x7EDC5571, 0xEABD174E, 0x72C668B6,
              0xD63CCDDB, 0x4434DFE7, 0x216FF3F0, 0x22AD7B72, 0x55E5AAEE, 0x8C8308CA, 0xCBA23987, 0x608ABC80 },
    water = { 0x19F81600, 0x3B982E13, 0xBC4922A4, 0xEFB2DF09 },
    glass = { 0x37E12A0B, 0xE931A0E, 0x596C55D1, 0x4A57FFCA, 0x23EF48BC, 0x3FD6150A, 0x995DA5E6, 0x1E94B2B7 },
}

Config.Decal = {
    enabled  = true,
    type     = 4421,
    size     = 0.9,
    timeoutS = 25.0,
    on       = { stone = true, wood = true, dirt = true, metal = true, default = true },
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
    smoke = { asset = 'core', name = 'ent_amb_smoke_foundry', scale = 0.60, colour = { 0.20, 0.00, 0.35 } },
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
        default = {
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.32 },
            { asset = 'core',          name = 'ent_sht_electrical_box',     scale = 0.55, colour = { 0.55, 0.10, 1.00 } },
        },
        metal = {
            { asset = 'core', name = 'ent_dst_elec_fire_sp',  scale = 0.55, colour = { 0.60, 0.15, 1.00 } },
            { asset = 'core', name = 'ent_sht_electrical_box', scale = 0.65, colour = { 0.55, 0.10, 1.00 } },
        },
        stone = {
            { asset = 'core',          name = 'ent_sht_dust',                scale = 0.70, colour = { 0.25, 0.15, 0.35 } },
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.30 },
        },
        wood = {
            { asset = 'core', name = 'ent_sht_steam',        scale = 0.60, colour = { 0.08, 0.00, 0.12 } },
            { asset = 'core', name = 'ent_dst_elec_fire_sp', scale = 0.30, colour = { 0.60, 0.15, 1.00 } },
        },
        dirt = {
            { asset = 'core',          name = 'ent_sht_dust',                scale = 0.80, colour = { 0.30, 0.20, 0.15 } },
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.30 },
        },
        water = {
            { asset = 'core', name = 'ent_sht_water', scale = 0.80 },
            { asset = 'core', name = 'ent_sht_steam', scale = 0.70 },
        },
        glass = {
            { asset = 'core',          name = 'ent_dst_elec_fire_sp',        scale = 0.50, colour = { 0.60, 0.15, 1.00 } },
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.25 },
        },
        flesh = {
            { asset = 'scr_rcbarry2',  name = 'scr_clown_appears',          scale = 0.35 },
            { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.30 },
        },
    },
    orbTrail  = { asset = 'core',          name = 'ent_dst_elec_fire_sp',        scale = 0.35, colour = { 0.55, 0.10, 1.00 } },
    curse     = { asset = 'scr_powerplay', name = 'scr_powerplay_beast_appear', scale = 0.35 },
    castStart = { asset = 'scr_rcbarry2',  name = 'scr_clown_appears',          scale = 0.50 },
    castEnd   = { asset = 'scr_powerplay', name = 'scr_powerplay_beast_vanish', scale = 0.30 },
}

Config.Screen = {
    timecycle         = 'BeastLaunch01',
    timecycleStrength = 0.6,
    tintFadeMs        = 250,
    postfx            = 'DrugsMichaelAliensFight',
    postfxEnabled     = false,
    shake             = 'HAND_SHAKE',
    shakeAmplitude    = 1.0,
    releaseShake      = 'SMALL_EXPLOSION_SHAKE',
    releaseAmplitude  = 0.25,
    overheatShake     = 'JOLT_SHAKE',
    padRumble         = true,
    hitFlash          = 'DrugsTrevorClownsFightIn',
    hitFlashMs        = 1500,
}

Config.Audio = {
    enabled   = true,
    armOn     = { name = 'Frontend_Beast_Fade_Screen',    set = 'FM_Events_Sasquatch_Sounds' },
    armOff    = { name = 'Frontend_Beast_Transform_Back', set = 'FM_Events_Sasquatch_Sounds' },
    castStart = { name = 'emp_blast',                     set = 'dlc_heists_biolab_finale_sounds' },
    castLoop  = { name = 'cannon_active',                 set = 'dlc_xm_orbital_cannon_sounds' },
    hit       = { name = 'Checkpoint_Beast_Hit',          set = 'FM_Events_Sasquatch_Sounds' },
    spell     = { name = 'Frontend_Beast_Text_Hit',       set = 'FM_Events_Sasquatch_Sounds' },
    orb       = { name = 'Checkpoint_Beast_Hit',          set = 'FM_Events_Sasquatch_Sounds' },
    curse     = { name = 'Frontend_Beast_Transform_Back', set = 'FM_Events_Sasquatch_Sounds' },
    overheat  = { name = 'Frontend_Beast_Freeze_Screen',  set = 'FM_Events_Sasquatch_Sounds' },
    blast     = { name = 'emp_blast',                     set = 'dlc_heists_biolab_finale_sounds' },
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
