
local function getNow() return GetGameTimer() end -- ms od startu serwera

local function generateSequence(len)
    local out = {}
    for i = 1, len do out[i] = math.random(1, 4) end
    return out
end

local function pickAnagramWord()
    return PSConfig.AnagramWords[math.random(#PSConfig.AnagramWords)]
end

local function shuffleString(s)
    local t = {}
    for c in s:gmatch('.') do t[#t + 1] = c end
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    if table.concat(t) == s and #s > 2 then
        t[1], t[#t] = t[#t], t[1]
    end
    return table.concat(t)
end


ESX.RegisterServerCallback('ps:server:startMinigame', function(source, cb, gameType)
    local identifier = PSGetIdentifier(source)
    if not identifier then cb({ ok = false, reason = 'no_identifier' }) return end

    local d = PSData[identifier]
    if not d or d.points <= 0 then
        cb({ ok = false, reason = 'no_points' })
        return
    end

    local now = os.time()
    if (d.last_minigame_at or 0) + PSConfig.MinigameCooldown > now then
        cb({ ok = false, reason = 'cooldown',
             secondsLeft = (d.last_minigame_at + PSConfig.MinigameCooldown) - now })
        return
    end

    local cfg = PSConfig.Minigames[gameType]
    if not cfg then cb({ ok = false, reason = 'invalid_game' }) return end

    local payload = { type = gameType, label = cfg.label, reward = cfg.reward }
    local serverState = { type = gameType, startMs = getNow() }

    if gameType == 'memory' then
        local seq = generateSequence(cfg.sequenceLen)
        serverState.sequence = seq
        payload.sequence = seq -- klient pokazuje, gracz musi powtorzyc
        payload.sequenceLen = cfg.sequenceLen

    elseif gameType == 'reaction' then
        payload.targetsToHit = cfg.targetsToHit

    elseif gameType == 'anagram' then
        local word = pickAnagramWord()
        local scrambled = shuffleString(word)
        serverState.word = word
        payload.scrambled = scrambled
        payload.wordLength = #word

    elseif gameType == 'lockpick' then
        payload.rounds = cfg.rounds
    end

    PSActiveSessions[source] = serverState
    cb({ ok = true, payload = payload })
end)


ESX.RegisterServerCallback('ps:server:endMinigame', function(source, cb, result)
    local identifier = PSGetIdentifier(source)
    if not identifier then cb({ ok = false }) return end

    local d = PSData[identifier]
    if not d then cb({ ok = false, reason = 'no_data' }) return end

    local sess = PSActiveSessions[source]
    if not sess then cb({ ok = false, reason = 'no_session' }) return end

    local cfg = PSConfig.Minigames[sess.type]
    if not cfg then PSActiveSessions[source] = nil; cb({ ok = false }) return end

    local elapsed = getNow() - sess.startMs

    if elapsed < cfg.minTimeMs then
        PSActiveSessions[source] = nil
        d.streak = 0
        d.last_minigame_at = os.time()
        saveToDb_inline(identifier, d)
        PSSendUpdate(source, identifier)
        cb({ ok = false, reason = 'too_fast' })
        PSDiscordLog('⚠️ ANTYCHEAT — minigra',
            ('**Gracz:** %s\n**Mini-gra:** %s\n**Czas zgloszony:** %d ms (min %d)'):format(
                d.player_name or 'Unknown', sess.type, elapsed, cfg.minTimeMs), 16711680)
        return
    end

    if elapsed > cfg.maxTimeMs then
        PSActiveSessions[source] = nil
        d.streak = 0
        d.last_minigame_at = os.time()
        saveToDb_inline(identifier, d)
        PSSendUpdate(source, identifier)
        cb({ ok = false, reason = 'too_slow' })
        return
    end

    local won = false

    if sess.type == 'memory' then
        local clientSeq = result and result.sequence or {}
        if #clientSeq == #sess.sequence then
            local match = true
            for i = 1, #sess.sequence do
                if tonumber(clientSeq[i]) ~= sess.sequence[i] then match = false; break end
            end
            won = match
        end

    elseif sess.type == 'reaction' then
        local hits = tonumber(result and result.hits) or 0
        won = hits >= cfg.targetsToHit

    elseif sess.type == 'anagram' then
        local answer = tostring(result and result.answer or ''):upper()
        won = answer == sess.word

    elseif sess.type == 'lockpick' then
        local successes = tonumber(result and result.successes) or 0
        won = successes >= cfg.rounds
    end

    PSActiveSessions[source] = nil

    if won then
        d.streak = (d.streak or 0) + 1
        d.last_minigame_at = os.time()

        local removeAmount = cfg.reward
        local streakBonus = false
        if d.streak >= PSConfig.StreakRequired then
            removeAmount = removeAmount + PSConfig.StreakReward
            streakBonus = true
            d.streak = 0
            PSNotify(source, '~y~PASSA! ~w~Bonus +' .. PSConfig.StreakReward .. ' pkt zdjete!')
        end

        saveToDb_inline(identifier, d)
        PSRemovePoints(source, removeAmount, ('mini-gra %s'):format(cfg.label), identifier)

        cb({ ok = true, removed = removeAmount, streakBonus = streakBonus, streak = d.streak })

        PSDiscordLog('🎮 MINI-GRA ZALICZONA',
            ('**Gracz:** %s\n**Mini-gra:** %s\n**Zdjeto:** %d pkt%s'):format(
                d.player_name or 'Unknown', cfg.label, removeAmount,
                streakBonus and ' (BONUS PASSA)' or ''), 65280)
    else
        d.streak = 0
        d.last_minigame_at = os.time()
        saveToDb_inline(identifier, d)
        PSSendUpdate(source, identifier)
        d.last_minigame_at = os.time() - PSConfig.MinigameCooldown + PSConfig.MinigameFailCooldown
        saveToDb_inline(identifier, d)
        cb({ ok = false, reason = 'failed' })
        PSNotify(source, '~r~Nie udalo sie. Sprobuj ponownie po cooldownie.')
    end
end)

function saveToDb_inline(identifier, d)
    PSData[identifier] = d
    MySQL.query.await([[
        UPDATE lunatic_prace_spoleczne
        SET points = ?, total_completed = ?, streak = ?, last_minigame_at = ?
        WHERE identifier = ?
    ]], { d.points, d.total_completed, d.streak, d.last_minigame_at, identifier })
end