

RegisterNetEvent('ps:server:reportDuelResult', function(result)
    local src = source
    local identifier = PSGetIdentifier(src)
    if not identifier then return end
    local d = PSData[identifier]
    if not d or d.points <= 0 then return end

    if result == 'win' and PSConfig.DuelWinReward and PSConfig.DuelWinReward > 0 then
        PSRemovePoints(src, PSConfig.DuelWinReward, 'wygrany duel', identifier)
    end
end)


RegisterNetEvent('kd:reportDeath')
AddEventHandler('kd:reportDeath', function(killerServerId)
    local victimSrc = source
    print(('[PRACE-SPOLECZNE] kd:reportDeath otrzymany | ofiara=%s killer=%s'):format(
        tostring(victimSrc), tostring(killerServerId)))

    if not killerServerId or killerServerId == 0 then return end
    if killerServerId == victimSrc then return end -- selfkill nie liczymy

    local killerIdent = PSGetIdentifier(killerServerId)
    if not killerIdent then
        print('[PRACE-SPOLECZNE] killer ' .. killerServerId .. ' bez identyfikatora')
        return
    end
    local d = PSData[killerIdent]
    if not d or d.points <= 0 then
        return
    end

    d.kill_progress = (d.kill_progress or 0) + 1
    print(('[PRACE-SPOLECZNE] killer %s ma kare, kill_progress=%d/%d'):format(
        killerIdent, d.kill_progress, PSConfig.KillsPerPoint))

    if d.kill_progress >= PSConfig.KillsPerPoint then
        d.kill_progress = 0
        saveToDb_inline(killerIdent, d) -- z minigames.lua (globalny)
        PSRemovePoints(killerServerId, 1, ('%d killi'):format(PSConfig.KillsPerPoint), killerIdent)
    else
        saveToDb_inline(killerIdent, d)
        PSSendUpdate(killerServerId, killerIdent)
        PSNotify(killerServerId, ('~b~Kill: %d/%d ~w~do nastepnego punktu zdjetego'):format(
            d.kill_progress, PSConfig.KillsPerPoint))
    end
end)