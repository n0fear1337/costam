
local ESX = exports['es_extended']:getSharedObject()

PSData = {}
PSSrcToId = {}
PSActiveSessions = {}


function PSNotify(src, msg)
    if not src or src == 0 then return end
    TriggerClientEvent(PSConfig.NotifyEvent, src, msg)
end

function PSGetIdentifier(src)
    if PSSrcToId[src] then return PSSrcToId[src] end
    local x = ESX.GetPlayerFromId(src)
    if not x then return nil end
    PSSrcToId[src] = x.identifier
    return x.identifier
end

function PSGetName(src)
    local x = ESX.GetPlayerFromId(src)
    if x and x.getName then return x.getName() end
    return GetPlayerName(src) or ('Unknown[' .. tostring(src) .. ']')
end

function PSIsAdmin(src)
    local x = ESX.GetPlayerFromId(src)
    if not x then return false end
    local g = x.getGroup()
    for _, allowed in ipairs(PSConfig.AdminGroups) do
        if g == allowed then return true end
    end
    return false
end



local function loadFromDb(identifier)
    local row = MySQL.single.await([[
        SELECT * FROM lunatic_prace_spoleczne WHERE identifier = ? LIMIT 1
    ]], { identifier })
    if not row then return nil end
    row.points          = tonumber(row.points) or 0
    row.total_received  = tonumber(row.total_received) or 0
    row.total_completed = tonumber(row.total_completed) or 0
    row.streak          = tonumber(row.streak) or 0
    row.last_minigame_at = tonumber(row.last_minigame_at) or 0
    row.last_buyout_at   = tonumber(row.last_buyout_at) or 0
    row.last_auto_at     = tonumber(row.last_auto_at) or 0
    row.kill_progress    = tonumber(row.kill_progress) or 0
    return row
end

local function saveToDb(identifier)
    local d = PSData[identifier]
    if not d then return end
    MySQL.query.await([[
        INSERT INTO lunatic_prace_spoleczne
            (identifier, player_name, points, total_received, total_completed,
             streak, assigned_by, reason, assigned_at, last_minigame_at,
             last_buyout_at, last_auto_at, kill_progress)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            player_name      = VALUES(player_name),
            points           = VALUES(points),
            total_received   = VALUES(total_received),
            total_completed  = VALUES(total_completed),
            streak           = VALUES(streak),
            assigned_by      = VALUES(assigned_by),
            reason           = VALUES(reason),
            assigned_at      = VALUES(assigned_at),
            last_minigame_at = VALUES(last_minigame_at),
            last_buyout_at   = VALUES(last_buyout_at),
            last_auto_at     = VALUES(last_auto_at),
            kill_progress    = VALUES(kill_progress)
    ]], {
        identifier, d.player_name or 'Unknown', d.points,
        d.total_received, d.total_completed, d.streak,
        d.assigned_by, d.reason,
        d.assigned_at_unix or os.time(),
        d.last_minigame_at, d.last_buyout_at, d.last_auto_at or 0, d.kill_progress
    })
end

local function deleteFromDb(identifier)
    MySQL.query.await('DELETE FROM lunatic_prace_spoleczne WHERE identifier = ?', { identifier })
end


function PSEnsureLoaded(identifier, playerName)
    if PSData[identifier] then return PSData[identifier] end
    local row = loadFromDb(identifier)
    if not row then return nil end
    if playerName then row.player_name = playerName end
    PSData[identifier] = row
    return row
end

function PSHasActive(identifier)
    local d = PSData[identifier]
    return d and d.points and d.points > 0
end

function PSGetData(identifier)
    return PSData[identifier]
end

function PSBuildClientData(identifier)
    local d = PSData[identifier]
    if not d then return nil end
    local coins = 0
    if PSConfig.BuyoutEnabled then
        pcall(function()
            local row = MySQL.single.await('SELECT coins FROM lunatic_coins WHERE identifier = ? LIMIT 1', { identifier })
            if row then coins = tonumber(row.coins) or 0 end
        end)
    end
    return {
        points          = d.points,
        total_received  = d.total_received,
        total_completed = d.total_completed,
        streak          = d.streak,
        kill_progress   = d.kill_progress,
        kills_per_point = PSConfig.KillsPerPoint,
        duel_reward     = PSConfig.DuelWinReward,
        buyout_enabled  = PSConfig.BuyoutEnabled,
        buyout_base     = PSConfig.BuyoutBasePrice,
        buyout_curve    = PSConfig.BuyoutPriceCurve,
        buyout_max      = PSConfig.BuyoutMaxAtOnce,
        coins_balance   = coins,
        streak_required = PSConfig.StreakRequired,
        streak_reward   = PSConfig.StreakReward,
        assigned_by     = d.assigned_by,
        reason          = d.reason,
        cooldowns = {
            minigame = math.max(0, (d.last_minigame_at or 0) + PSConfig.MinigameCooldown - os.time()),
            buyout   = math.max(0, (d.last_buyout_at   or 0) + PSConfig.BuyoutCooldown   - os.time()),
        },
    }
end

function PSSendUpdate(targetSrc, identifier)
    if not targetSrc or not identifier then return end
    local payload = PSBuildClientData(identifier)
    if payload then
        TriggerClientEvent('ps:client:updateData', targetSrc, payload)
    end
end

function PSGivePoints(targetSrc, points, assignedByName, reason)
    if not targetSrc or not points or points <= 0 then return false end
    local identifier = PSGetIdentifier(targetSrc)
    if not identifier then return false end

    points = math.min(points, PSConfig.MaxAssignAtOnce)

    local d = PSData[identifier] or {
        points = 0, total_received = 0, total_completed = 0,
        streak = 0, last_minigame_at = 0, last_buyout_at = 0, kill_progress = 0,
        player_name = PSGetName(targetSrc)
    }

    d.points          = math.min(d.points + points, PSConfig.MaxTotalPoints)
    d.total_received  = d.total_received + points
    d.assigned_by     = assignedByName or 'Konsola'
    d.reason          = reason or 'brak podanego powodu'
    d.assigned_at_unix = os.time()
    d.player_name     = PSGetName(targetSrc)

    PSData[identifier] = d
    saveToDb(identifier)

    PSNotify(targetSrc, ('~b~PRACE SPOLECZNE: ~w~Otrzymales ~b~%d ~w~punktow karnych. (Powod: %s)'):format(points, d.reason))
    PSNotify(targetSrc, '~b~Otworz panel klawiszem ~y~' .. (PSConfig.PlayerKey or 'F7') .. ' ~b~lub ~y~/' .. PSConfig.PlayerCommand)

    PSSendUpdate(targetSrc, identifier)

    if PSConfig.AutoOpenOnAssign then
        TriggerClientEvent('ps:client:autoOpen', targetSrc)
    end

    if PSConfig.Prison and PSConfig.Prison.enabled then
        sendImprisonTo(targetSrc)
    else
        print('[PRACE] Wiezienie wylaczone w configu — pomijam imprison.')
    end

    PSDiscordLog('🔵 NADANO PRACE SPOLECZNE',
        ('**Gracz:** %s\n**Punkty:** +%d (suma: %d)\n**Nadal:** %s\n**Powod:** %s'):format(
            d.player_name, points, d.points, d.assigned_by, d.reason),
        16753920) -- pomarancz
    return true
end

function PSRemovePoints(targetSrc, points, source, identifier)
    if not points or points <= 0 then return false end

    if not identifier and targetSrc then
        identifier = PSGetIdentifier(targetSrc)
    end
    if not identifier then return false end

    local d = PSData[identifier]
    if not d then return false end

    local removed = math.min(points, d.points)
    d.points = d.points - removed
    d.total_completed = d.total_completed + removed

    if d.points <= 0 then
        PSData[identifier] = nil
        deleteFromDb(identifier)
        if targetSrc then
            PSNotify(targetSrc, '~g~Skonczyles prace spoleczne! Mozesz wracac do gry. ✓')
            TriggerClientEvent('ps:client:cleared', targetSrc)
            if PSConfig.Prison and PSConfig.Prison.enabled then
                local fc = PSConfig.Prison.freedomCoords
                TriggerClientEvent('ps:client:free', targetSrc, {
                    coords  = { x = fc.x + 0.0, y = fc.y + 0.0, z = fc.z + 0.0 },
                    heading = PSConfig.Prison.freedomHeading or 0.0,
                })
            end
        end
        PSDiscordLog('✅ ZAKONCZONE PRACE SPOLECZNE',
            ('**Gracz:** %s\n**Sposob ukonczenia:** %s'):format(d.player_name, source or 'inne'),
            65280) -- zielony
    else
        saveToDb(identifier)
        if targetSrc then
            PSNotify(targetSrc, ('~g~-%d ~w~pkt prac spolecznych (%s). Zostalo: ~b~%d'):format(removed, source or 'akcja', d.points))
            PSSendUpdate(targetSrc, identifier)
        end
    end

    return true
end

function PSClear(targetSrc, identifier, byName)
    if not identifier and targetSrc then
        identifier = PSGetIdentifier(targetSrc)
    end
    if not identifier then return false end
    local d = PSData[identifier]
    if not d then return false end
    PSData[identifier] = nil
    deleteFromDb(identifier)
    if targetSrc then
        PSNotify(targetSrc, '~g~Twoje prace spoleczne zostaly skasowane przez admina.')
        TriggerClientEvent('ps:client:cleared', targetSrc)
        if PSConfig.Prison and PSConfig.Prison.enabled then
            local fc = PSConfig.Prison.freedomCoords
            TriggerClientEvent('ps:client:free', targetSrc, {
                coords  = { x = fc.x + 0.0, y = fc.y + 0.0, z = fc.z + 0.0 },
                heading = PSConfig.Prison.freedomHeading or 0.0,
            })
        end
    end
    PSDiscordLog('🔵 ADMIN SKASOWAL PRACE',
        ('**Gracz:** %s\n**Skasowal:** %s'):format(d.player_name, byName or 'Konsola'),
        2123412) -- niebieski
    return true
end


ESX.RegisterServerCallback('ps:server:getData', function(source, cb)
    local identifier = PSGetIdentifier(source)
    if not identifier then cb(nil) return end
    PSEnsureLoaded(identifier, PSGetName(source))
    local payload = PSBuildClientData(identifier)
    if not payload then cb({ points = 0 }) return end
    cb(payload)
end)


local function getPlayerCoins(identifier)
    local row = MySQL.single.await('SELECT coins FROM lunatic_coins WHERE identifier = ? LIMIT 1', { identifier })
    if not row then return 0 end
    return tonumber(row.coins) or 0
end

local function removePlayerCoins(identifier, amount)
    if amount <= 0 then return true end
    local result = MySQL.update.await(
        'UPDATE lunatic_coins SET coins = coins - ? WHERE identifier = ? AND coins >= ?',
        { amount, identifier, amount })
    return result and result > 0
end

function PSCalcBuyoutPrice(amount)
    if amount <= 0 then return 0 end
    local base  = PSConfig.BuyoutBasePrice or 100
    local curve = PSConfig.BuyoutPriceCurve or 0.15
    return math.floor(base * amount * (1 + (amount - 1) * curve))
end

RegisterNetEvent('ps:server:buyout', function(amountRaw)
    local src = source
    if not PSConfig.BuyoutEnabled then
        PSNotify(src, '~r~Wykup wylaczony przez administracje.')
        return
    end
    local identifier = PSGetIdentifier(src)
    if not identifier then return end
    local d = PSData[identifier]
    if not d or d.points <= 0 then return end

    local amount = tonumber(amountRaw) or 1
    amount = math.max(1, math.floor(amount))
    amount = math.min(amount, PSConfig.BuyoutMaxAtOnce or 10)
    amount = math.min(amount, d.points) -- nie wiecej niz aktualnie pozostalo

    if amount <= 0 then return end

    local now = os.time()
    if (d.last_buyout_at or 0) + (PSConfig.BuyoutCooldown or 60) > now then
        local left = (d.last_buyout_at or 0) + PSConfig.BuyoutCooldown - now
        PSNotify(src, ('~r~Wykup na cooldownie. Poczekaj %d s.'):format(left))
        return
    end

    local price = PSCalcBuyoutPrice(amount)

    local coins = getPlayerCoins(identifier)
    if coins < price then
        PSNotify(src, ('~r~Za malo coinow! Masz: ~y~%d~r~, potrzeba: ~y~%d~r~ za %d pkt.')
            :format(coins, price, amount))
        return
    end

    if not removePlayerCoins(identifier, price) then
        PSNotify(src, '~r~Nie udalo sie odjac coinow (sprawdz saldo).')
        return
    end

    d.last_buyout_at = now
    PSData[identifier] = d
    PSRemovePoints(src, amount, ('wykup za %d coins'):format(price), identifier)

    PSNotify(src, ('~g~Wykupiles ~w~%d ~g~pkt za ~y~%d coins~g~. Saldo: ~y~%d')
        :format(amount, price, coins - price))

    PSDiscordLog('🪙 WYKUP PUNKTOW',
        ('**Gracz:** %s\n**Pkt zdjete:** %d\n**Cena:** %d coins\n**Saldo po:** %d coins\n**Pozostalo prac:** %d')
            :format(d.player_name, amount, price, coins - price, math.max(0, d.points)),
        16766720)
end)

ESX.RegisterServerCallback('ps:server:calcBuyout', function(source, cb, amount)
    amount = tonumber(amount) or 1
    amount = math.max(1, math.min(amount, PSConfig.BuyoutMaxAtOnce or 10))
    local identifier = PSGetIdentifier(source)
    local coins = identifier and getPlayerCoins(identifier) or 0
    cb({
        amount = amount,
        price  = PSCalcBuyoutPrice(amount),
        coins  = coins,
        max    = PSConfig.BuyoutMaxAtOnce or 10,
    })
end)

CreateThread(function()
    Wait(5000)
    while true do
        Wait(2000)
        for src, identifier in pairs(PSSrcToId) do
            local d = PSData[identifier]
            if d and (d.points or 0) > 0 and GetPlayerName(src) then
                local ok, bucket = pcall(function()
                    return GetPlayerRoutingBucket(src)
                end)
                if ok then
                    local bnum = tonumber(bucket) or 0
                    TriggerClientEvent('ps:client:bucketStatus', src, false, bnum)
                end
            end
        end
    end
end)


function sendImprisonTo(targetSrc)
    if not PSConfig.Prison or not PSConfig.Prison.enabled then return end
    local pc = PSConfig.Prison.coords
    print(('[PRACE] -> imprison src=%s coords=(%.1f,%.1f,%.1f) r=%.0f'):format(
        tostring(targetSrc), pc.x, pc.y, pc.z, PSConfig.Prison.radius or 100))
    TriggerClientEvent('ps:client:imprison', targetSrc, {
        coords  = { x = pc.x + 0.0, y = pc.y + 0.0, z = pc.z + 0.0 },
        heading = PSConfig.Prison.heading or 0.0,
        radius  = PSConfig.Prison.radius  or 100.0,
    })
end

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    print('[PRACE] onResourceStart: skanuje online graczy z aktywna kara...')
    CreateThread(function()
        Wait(3000) -- pozwol ESX i innym zasobom sie zaladowac
        local players = GetPlayers()
        print(('[PRACE] %d graczy online do sprawdzenia'):format(#players))
        for _, plyId in ipairs(players) do
            local src = tonumber(plyId)
            if src then
                local xPlayer = ESX.GetPlayerFromId(src)
                if xPlayer then
                    PSSrcToId[src] = xPlayer.identifier
                    local row = loadFromDb(xPlayer.identifier)
                    if row and (row.points or 0) > 0 then
                        row.player_name = xPlayer.getName()
                        PSData[xPlayer.identifier] = row
                        print(('[PRACE] Online %s ma %d pkt - imprison'):format(xPlayer.getName(), row.points))
                        PSNotify(src, ('~b~MASZ AKTYWNE PRACE SPOLECZNE: ~w~%d pkt. /%s aby otworzyc panel.')
                            :format(row.points, PSConfig.PlayerCommand))
                        PSSendUpdate(src, xPlayer.identifier)
                        sendImprisonTo(src)
                    end
                end
            end
        end
        print('[PRACE] onResourceStart: skan zakonczony')
    end)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    PSSrcToId[playerId] = xPlayer.identifier
    CreateThread(function()
        local row = loadFromDb(xPlayer.identifier)
        if row and row.points and row.points > 0 then
            row.player_name = xPlayer.getName()
            PSData[xPlayer.identifier] = row
            Wait(3000)
            if GetPlayerName(playerId) then
                PSNotify(playerId, ('~b~MASZ AKTYWNE PRACE SPOLECZNE: ~w~%d punktow. Wcisnij ~y~%s~w~ aby otworzyc panel.')
                    :format(row.points, PSConfig.PlayerKey))
                PSSendUpdate(playerId, xPlayer.identifier)
                sendImprisonTo(playerId)
            end
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = PSSrcToId[src]
    if identifier then
        if PSData[identifier] then
            saveToDb(identifier)
        end
        PSSrcToId[src] = nil
    end
    PSActiveSessions[src] = nil
end)

if PSConfig.RemindEvery and PSConfig.RemindEvery > 0 then
    CreateThread(function()
        while true do
            Wait(PSConfig.RemindEvery * 1000)
            for src, identifier in pairs(PSSrcToId) do
                local d = PSData[identifier]
                if d and d.points > 0 and GetPlayerName(src) then
                    PSNotify(src, ('~b~Pamietaj o pracach spolecznych: ~w~%d pkt do odrobienia. Otworz: /%s')
                        :format(d.points, PSConfig.PlayerCommand))
                end
            end
        end
    end)
end

CreateThread(function()
    Wait(1000)
    pcall(function()
        local col = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'lunatic_prace_spoleczne'
              AND COLUMN_NAME = 'last_auto_at'
        ]], {})
        if (col or 0) == 0 then
            print('[PRACE-SPOLECZNE] Migracja: dodaje kolumne last_auto_at...')
            MySQL.query.await([[
                ALTER TABLE lunatic_prace_spoleczne
                ADD COLUMN last_auto_at BIGINT NOT NULL DEFAULT 0 AFTER last_buyout_at
            ]], {})
            print('[PRACE-SPOLECZNE] Migracja zakonczona pomyslnie.')
        end
    end)
end)

if PSConfig.AutoDecrement and PSConfig.AutoDecrement.enabled then
    CreateThread(function()
        Wait(15000) -- pozwol serwerowi sie zaladowac
        while true do
            Wait(30000) -- check co 30 sekund
            local now = os.time()
            local onlineInterval  = PSConfig.AutoDecrement.onlineEvery  or 180
            local offlineInterval = PSConfig.AutoDecrement.offlineEvery or 600
            local pointsPerTick   = PSConfig.AutoDecrement.pointsPerTick or 1

            for src, identifier in pairs(PSSrcToId) do
                local d = PSData[identifier]
                if d and d.points and d.points > 0 then
                    if (d.last_auto_at or 0) == 0 then
                        d.last_auto_at = now -- pierwszy odczyt — zaczynamy liczyc
                    elseif (now - d.last_auto_at) >= onlineInterval then
                        d.last_auto_at = now
                        local removed = math.min(pointsPerTick, d.points)
                        d.points = d.points - removed
                        d.total_completed = (d.total_completed or 0) + removed

                        if d.points <= 0 then
                            PSData[identifier] = nil
                            deleteFromDb(identifier)
                            if GetPlayerName(src) then
                                PSNotify(src, '~g~Skonczyles prace spoleczne (czas)! ✓')
                                TriggerClientEvent('ps:client:cleared', src)
                                if PSConfig.Prison and PSConfig.Prison.enabled then
                                    local fc = PSConfig.Prison.freedomCoords
                                    TriggerClientEvent('ps:client:free', src, {
                                        coords  = { x = fc.x + 0.0, y = fc.y + 0.0, z = fc.z + 0.0 },
                                        heading = PSConfig.Prison.freedomHeading or 0.0,
                                    })
                                end
                            end
                        else
                            saveToDb(identifier)
                            if GetPlayerName(src) then
                                PSNotify(src, ('~g~-%d ~w~pkt (odsiadka). Pozostalo: ~b~%d'):format(removed, d.points))
                                PSSendUpdate(src, identifier)
                            end
                        end
                    end
                end
            end

            if (math.floor(now / 60) % 2) == 0 then
                pcall(function()
                    local rows = MySQL.query.await(
                        'SELECT identifier, points, last_auto_at FROM lunatic_prace_spoleczne WHERE points > 0',
                        {})
                    if rows then
                        for _, row in ipairs(rows) do
                            local isOnline = false
                            for _, identCheck in pairs(PSSrcToId) do
                                if identCheck == row.identifier then isOnline = true break end
                            end
                            if not isOnline then
                                local lastAuto = tonumber(row.last_auto_at) or 0
                                if lastAuto == 0 then
                                    MySQL.query.await(
                                        'UPDATE lunatic_prace_spoleczne SET last_auto_at = ? WHERE identifier = ?',
                                        { now, row.identifier })
                                elseif (now - lastAuto) >= offlineInterval then
                                    local newPoints = math.max(0, (tonumber(row.points) or 0) - pointsPerTick)
                                    if newPoints == 0 then
                                        MySQL.query.await('DELETE FROM lunatic_prace_spoleczne WHERE identifier = ?', { row.identifier })
                                    else
                                        MySQL.query.await([[
                                            UPDATE lunatic_prace_spoleczne
                                            SET points = ?, last_auto_at = ?,
                                                total_completed = total_completed + 1
                                            WHERE identifier = ?
                                        ]], { newPoints, now, row.identifier })
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end)
end


function PSDiscordLog(title, message, color)
    if not PSConfig.DiscordWebhook or PSConfig.DiscordWebhook == '' then return end
    local embed = {{
        ['color']       = color or 2123412,
        ['title']       = title,
        ['description'] = message,
        ['footer']      = { ['text'] = ('LunaticGG • Prace Spoleczne • %s'):format(os.date('%Y-%m-%d %H:%M:%S')) },
    }}
    PerformHttpRequest(PSConfig.DiscordWebhook, function() end, 'POST',
        json.encode({ username = 'Prace Spoleczne', embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end


exports('Give',          function(src, pts, by, reason) return PSGivePoints(src, pts, by, reason) end)
exports('Remove',        function(src, pts, source)     return PSRemovePoints(src, pts, source)   end)
exports('HasActive',     function(src)
    local id = PSGetIdentifier(src)
    return id and PSHasActive(id) or false
end)
exports('GetPoints',     function(src)
    local id = PSGetIdentifier(src)
    if not id or not PSData[id] then return 0 end
    return PSData[id].points
end)