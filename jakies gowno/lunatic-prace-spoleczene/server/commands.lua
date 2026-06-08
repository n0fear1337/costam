
local ESX = exports['es_extended']:getSharedObject()

local function checkAdmin(src)
    if src == 0 then return true end -- konsola
    return PSIsAdmin(src)
end

RegisterCommand(PSConfig.AdminCommands.give, function(source, args, rawCommand)
    local src = source
    if not checkAdmin(src) then
        if src ~= 0 then PSNotify(src, '~r~Brak uprawnien.') end
        return
    end

    if not args[1] or not args[2] then
        if src ~= 0 then PSNotify(src, '~y~Uzycie: /' .. PSConfig.AdminCommands.give .. ' <id> <punkty> [powod]') end
        return
    end

    local targetSrc = tonumber(args[1])
    local pts       = tonumber(args[2])
    if not targetSrc or not pts or pts <= 0 then
        if src ~= 0 then PSNotify(src, '~r~Bledne argumenty. Uzycie: /' .. PSConfig.AdminCommands.give .. ' <id> <punkty> [powod]') end
        return
    end

    local reason = 'brak'
    if #args >= 3 then
        local parts = {}
        for i = 3, #args do parts[#parts + 1] = args[i] end
        reason = table.concat(parts, ' ')
    end

    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        if src ~= 0 then PSNotify(src, '~r~Gracz offline lub bledne ID.') end
        return
    end

    local adminName = (src == 0) and 'Konsola' or (ESX.GetPlayerFromId(src) and ESX.GetPlayerFromId(src).getName() or 'Admin')

    print(('[PRACE] /%s wywolane: target=%d, pts=%d, reason="%s", admin=%s'):format(
        PSConfig.AdminCommands.give, targetSrc, pts, reason, adminName))

    if PSGivePoints(targetSrc, pts, adminName, reason) then
        if src ~= 0 then
            PSNotify(src, ('~g~Nadano ~w~%d ~g~pkt prac dla ~w~%s ~g~(powod: %s)'):format(pts, xTarget.getName(), reason))
        end
    else
        if src ~= 0 then PSNotify(src, '~r~Blad podczas nadawania.') end
    end
end, false)

RegisterCommand(PSConfig.AdminCommands.remove, function(source, args, rawCommand)
    local src = source
    if not checkAdmin(src) then
        if src ~= 0 then PSNotify(src, '~r~Brak uprawnien.') end
        return
    end

    local targetSrc = tonumber(args[1])
    if not targetSrc then
        if src ~= 0 then PSNotify(src, '~y~Uzycie: /' .. PSConfig.AdminCommands.remove .. ' <id>') end
        return
    end
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        if src ~= 0 then PSNotify(src, '~r~Gracz offline.') end
        return
    end

    local byName = (src == 0) and 'Konsola' or (ESX.GetPlayerFromId(src) and ESX.GetPlayerFromId(src).getName() or 'Admin')
    if PSClear(targetSrc, nil, byName) then
        if src ~= 0 then PSNotify(src, ('~g~Skasowano prace dla ~w~%s'):format(xTarget.getName())) end
    else
        if src ~= 0 then PSNotify(src, '~r~Gracz nie ma aktywnych prac.') end
    end
end, false)

RegisterCommand('cs_test_tepa', function(source, args, rawCommand)
    local src = source
    if not checkAdmin(src) then return end
    if src == 0 then return end -- konsola nie ma sensu

    if not PSConfig.Prison or not PSConfig.Prison.enabled then
        PSNotify(src, '~r~PSConfig.Prison.enabled = false. Wlacz najpierw w configu.')
        return
    end

    local pc = PSConfig.Prison.coords
    print(('[PRACE] /cs_test_tepa: testowy imprison dla src=%d'):format(src))
    TriggerClientEvent('ps:client:imprison', src, {
        coords  = { x = pc.x + 0.0, y = pc.y + 0.0, z = pc.z + 0.0 },
        heading = PSConfig.Prison.heading or 0.0,
        radius  = PSConfig.Prison.radius  or 65.0,
    })
    PSNotify(src, '~y~Test: wyslano imprison. Sprawdz F8 w grze.')
end, false)

RegisterCommand('cs_test_free', function(source, args, rawCommand)
    local src = source
    if not checkAdmin(src) then return end
    if src == 0 then return end

    if not PSConfig.Prison or not PSConfig.Prison.enabled then return end

    local fc = PSConfig.Prison.freedomCoords
    print(('[PRACE] /cs_test_free: testowy free dla src=%d'):format(src))
    TriggerClientEvent('ps:client:free', src, {
        coords  = { x = fc.x + 0.0, y = fc.y + 0.0, z = fc.z + 0.0 },
        heading = PSConfig.Prison.freedomHeading or 0.0,
    })
    PSNotify(src, '~y~Test: wyslano free. Sprawdz F8 w grze.')
end, false)

RegisterCommand(PSConfig.AdminCommands.check, function(source, args, rawCommand)
    local src = source
    if not checkAdmin(src) then
        if src ~= 0 then PSNotify(src, '~r~Brak uprawnien.') end
        return
    end

    local targetSrc = tonumber(args[1])
    if not targetSrc then
        if src ~= 0 then PSNotify(src, '~y~Uzycie: /' .. PSConfig.AdminCommands.check .. ' <id>') end
        return
    end
    local xTarget = ESX.GetPlayerFromId(targetSrc)
    if not xTarget then
        if src ~= 0 then PSNotify(src, '~r~Gracz offline.') end
        return
    end
    local id = xTarget.identifier
    PSEnsureLoaded(id, xTarget.getName())
    local d = PSData[id]
    if not d then
        if src ~= 0 then PSNotify(src, ('~g~%s nie ma aktywnych prac.'):format(xTarget.getName())) end
        return
    end
    local msg = ('~b~%s ~w~| ~b~%d~w~ pkt | otrzymal: %d | wykonal: %d | nadal: %s | powod: %s'):format(
        xTarget.getName(), d.points, d.total_received, d.total_completed,
        d.assigned_by or '?', d.reason or '?')
    if src ~= 0 then PSNotify(src, msg) else print(msg) end
end, false)