
PSConfig = {}

PSConfig.PlayerCommand = 'prace'
PSConfig.PlayerKey = 'F7'

PSConfig.AdminCommands = {
    give   = 'prace_daj',     -- /cs_daj <id> <punkty> <powod>
    remove = 'cs_zdejmij', -- /cs_zdejmij <id>
    check  = 'cs_status',  -- /cs_status <id>
}

PSConfig.AdminGroups = { 'admin', 'headadmin', 'manager', 'owner', 'developer', 'mod', 'support' }

PSConfig.MaxAssignAtOnce = 50      -- max punktow nadanych jedna komenda
PSConfig.MaxTotalPoints  = 100     -- twardy sufit w bazie

PSConfig.MinigameCooldown = 15

PSConfig.MinigameFailCooldown = 30

PSConfig.StreakReward    = 1   -- ile dodatkowych punktow zniknie
PSConfig.StreakRequired  = 5   -- ile w rzedu trzeba zrobic

PSConfig.Minigames = {
    memory = {
        label       = 'Sekwencja',
        description = 'Zapamietaj i powtorz sekwencje kolorow.',
        icon        = 'puzzle',
        reward      = 1,         -- ile punktow zdejmuje wygrana
        minTimeMs   = 6000,      -- jezeli klient zglosi szybciej -> cheat
        maxTimeMs   = 60000,     -- jezeli zwleka dluzej -> fail
        sequenceLen = 6,         -- ile elementow do zapamietania
    },
    reaction = {
        label       = 'Refleks',
        description = 'Klikaj cele tak szybko jak sie pojawiaja.',
        icon        = 'zap',
        reward      = 1,
        minTimeMs   = 5000,
        maxTimeMs   = 30000,
        targetsToHit = 12,
    },
    anagram = {
        label       = 'Anagram',
        description = 'Ulóz prawidlowe slowo z liter.',
        icon        = 'type',
        reward      = 1,
        minTimeMs   = 4000,
        maxTimeMs   = 90000,
    },
    lockpick = {
        label       = 'Wlam',
        description = 'Trafiaj w pasek 5 razy z rzedu.',
        icon        = 'key',
        reward      = 1,
        minTimeMs   = 4000,
        maxTimeMs   = 45000,
        rounds      = 5,
    },
}

PSConfig.AnagramWords = {
    'KOMPUTER', 'TELEFON', 'SAMOCHOD', 'KOMORKA', 'PILKARZ',
    'SZKOLA', 'KSIAZKA', 'PIENIADZ', 'KAWALER', 'BANANY',
    'POLSKA', 'WARSZAWA', 'KRAKOW', 'GDANSK', 'WROCLAW',
    'ZAMEK', 'OKULARY', 'KOMNATA', 'PROGRAM', 'KAMIEN',
    'KUMPEL', 'KIEROWCA', 'POCZTA', 'BIBLIOTEKA', 'PRZYJACIEL',
}

PSConfig.DuelWinReward = 2     -- punkty zdjete za wygrany duel
PSConfig.DuelLossReward = 0    -- (na wszelki wypadek)

PSConfig.KillsPerPoint = 5

PSConfig.BuyoutEnabled    = true
PSConfig.BuyoutBasePrice  = 100
PSConfig.BuyoutPriceCurve = 0.15
PSConfig.BuyoutMaxAtOnce  = 10
PSConfig.BuyoutCooldown   = 60      -- sekundy miedzy wykupami

PSConfig.GreenzonePolicy = 'block'

PSConfig.PanelAccess = 'anywhere'

PSConfig.AutoOpenOnAssign = true
PSConfig.RemindEvery = 600

PSConfig.AutoDecrement = {
    enabled        = true,
    onlineEvery    = 180,  -- 3 minuty kiedy gracz jest online
    offlineEvery   = 600,  -- 10 minut kiedy gracz jest offline
    pointsPerTick  = 1,    -- ile punktow zdjac za jedna iteracje
}

PSConfig.Prison = {
    enabled         = true,
    coords          = vector3(1665.0446, 2551.2271, 44.6649),
    heading         = 270.0,
    radius          = 100.0, -- promien strefy w metrach (czerwone kolo na mapie)
    freedomCoords   = vector3(1003.28, -2522.52, 28.30), -- greenzona Doki
    freedomHeading  = 0.0,
    returnAfterDuel = true,

}

PSConfig.DiscordWebhook = ''

PSConfig.NotifyEvent       = 'erkamon_notify:Send'      -- event powiadomien (z lunatic-notify)
PSConfig.MatchResultEvent  = 'mm:client:matchResult'    -- event z lunatic-matchmaking
PSConfig.KillReportEvent   = 'kd:reportDeath'           -- event z kdsystem