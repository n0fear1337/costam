
local ESX = exports['es_extended']:getSharedObject()

print('[PRACE] ============================================================')
print('[PRACE] Klient zaladowany. Wersja: 2.6 (prison-rewrite)')
print('[PRACE] ============================================================')

local panelOpen     = false
local cachedData    = nil
local minigameActive = false  -- gdy gracz jest w trakcie mini-gry, nie zamykaj na ESC

local function nui(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function notify(msg)
    TriggerEvent(PSConfig.NotifyEvent, msg)
    TriggerEvent('chat:addMessage', {
        color = { 80, 130, 255 },
        multiline = true,
        args = { 'PRACE', msg:gsub('~%w~', '') },
    })
    print('[PRACE] notify: ' .. tostring(msg))
end

local function isInGreenzone()
    local pcoords = GetEntityCoords(PlayerPedId())
    for _, zone in ipairs(PSConfig.Greenzones) do
        if #(pcoords - zone.coords) <= zone.radius then return true end
    end
    return false
end


local function openPanel()
    print('[PRACE-SPOLECZNE] openPanel() wywolane, panelOpen=' .. tostring(panelOpen))
    if panelOpen then return end
    if PSConfig.PanelAccess == 'greenzone' and not isInGreenzone() then
        notify('~r~Panel prac spolecznych dostepny tylko w greenzonie.')
        return
    end

    print('[PRACE-SPOLECZNE] Wysylam ESX.TriggerServerCallback...')
    ESX.TriggerServerCallback('ps:server:getData', function(data)
        print('[PRACE-SPOLECZNE] Otrzymalem dane z serwera: ' .. tostring(data ~= nil))
        if data then
            print('[PRACE-SPOLECZNE] points=' .. tostring(data.points) .. ', name=' .. tostring(data.player_name))
        end

        if not data or (data.points or 0) <= 0 then
            notify('~r~Nie masz aktywnych prac spolecznych.')
            cachedData = nil
            return
        end

        cachedData = data
        panelOpen = true
        SetNuiFocus(true, true)
        PSCam.Start()
        nui('open', { data = cachedData })
    end)
end

local function closePanel()
    if not panelOpen then return end
    if minigameActive then return end -- nie zamykaj w srodku mini-gry
    panelOpen = false
    SetNuiFocus(false, false)
    PSCam.Stop()
    nui('close')
end


RegisterCommand(PSConfig.PlayerCommand, function()
    if panelOpen then closePanel() else openPanel() end
end, false)

RegisterCommand('+psOpen', function()
    if panelOpen then closePanel() else openPanel() end
end, false)
RegisterCommand('-psOpen', function() end, false)
RegisterKeyMapping('+psOpen', 'Otworz Prace Spoleczne', 'keyboard', PSConfig.PlayerKey)

CreateThread(function()
    while true do
        if panelOpen then
            Wait(0)
            if IsControlJustPressed(0, 200) and not minigameActive then -- ESC
                closePanel()
            end
        else
            Wait(500)
        end
    end
end)


RegisterNetEvent('ps:client:updateData', function(data)
    cachedData = data
    if panelOpen then
        nui('update', { data = data })
    end
end)

RegisterNetEvent('ps:client:cleared', function()
    cachedData = nil
    if panelOpen then
        nui('cleared')
        SetTimeout(2000, function()
            closePanel()
        end)
    end
end)

RegisterNetEvent('ps:client:autoOpen', function()
    Wait(500)
    openPanel()
end)


local prison = {
    active   = false,
    coords   = nil,
    radius   = 100.0,
    heading  = 0.0,
    inMatch  = false,    -- true gdy matchmaking nas wyciagnal (geo-fence pauza)
    lastPos  = nil,      -- do detekcji teleportu
    blip     = nil,      -- punkt na mapie
    blipArea = nil,      -- czerwone kolo strefy
    bucket   = 0,        -- ostatni znany routing bucket (do debugu)
}

local function setupPrisonBlip()
    if prison.blip     then RemoveBlip(prison.blip);     prison.blip     = nil end
    if prison.blipArea then RemoveBlip(prison.blipArea); prison.blipArea = nil end
    if not prison.coords then return end

    prison.blip = AddBlipForCoord(prison.coords.x, prison.coords.y, prison.coords.z)
    SetBlipSprite(prison.blip, 188)       -- jail/lockup icon
    SetBlipColour(prison.blip, 1)         -- czerwony
    SetBlipScale(prison.blip, 1.0)
    SetBlipAsShortRange(prison.blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Wiezienie (twoja kara)')
    EndTextCommandSetBlipName(prison.blip)

    prison.blipArea = AddBlipForRadius(prison.coords.x, prison.coords.y, prison.coords.z, prison.radius)
    SetBlipColour(prison.blipArea, 1)     -- czerwony
    SetBlipAlpha(prison.blipArea, 96)     -- przezroczystosc
end

local function removePrisonBlip()
    if prison.blip     then RemoveBlip(prison.blip);     prison.blip     = nil end
    if prison.blipArea then RemoveBlip(prison.blipArea); prison.blipArea = nil end
end

local function teleportToPrison()
    if not prison.coords then return end
    local ped = PlayerPedId()
    local cx, cy, cz = prison.coords.x, prison.coords.y, prison.coords.z

    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        TaskLeaveVehicle(ped, veh, 16)
        Wait(150)
        ped = PlayerPedId()
    end

    RequestCollisionAtCoord(cx, cy, cz)

    if IsEntityDead(ped) then
        NetworkResurrectLocalPlayer(cx, cy, cz, 0.0, true, false)
    end

    SetEntityCoords(ped, cx, cy, cz, false, false, false, false)
    SetEntityHeading(ped, prison.heading or 0.0)

    local t = 0
    while not HasCollisionLoadedAroundEntity(ped) and t < 20 do
        Wait(100)
        t = t + 1
    end

    SetEntityCoords(ped, cx, cy, cz, false, false, false, false)

    Wait(100)
    local actualPos = GetEntityCoords(PlayerPedId())
    prison.lastPos = actualPos

    print(('[PRACE] Teleport: cel=(%.1f,%.1f,%.1f) faktyczna=(%.1f,%.1f,%.1f) dist_diff=%.1fm'):format(
        cx, cy, cz, actualPos.x, actualPos.y, actualPos.z,
        #(actualPos - vector3(cx, cy, cz))))
end

local function unpackCoords(c)
    if not c then return nil end
    local x = tonumber(c.x or c[1])
    local y = tonumber(c.y or c[2])
    local z = tonumber(c.z or c[3])
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

RegisterNetEvent('ps:client:imprison')
AddEventHandler('ps:client:imprison', function(data)
    print('[PRACE] >>> ps:client:imprison')
    if not data then
        print('[PRACE] BLAD: data nil')
        return
    end

    local v = unpackCoords(data.coords)
    if not v then
        print('[PRACE] BLAD: nie umiem wyciagnac coords z eventu')
        return
    end

    prison.active  = true
    prison.coords  = v
    prison.radius  = tonumber(data.radius)  or 100.0
    prison.heading = tonumber(data.heading) or 0.0
    prison.inMatch = false
    prison.lastPos = nil

    print(('[PRACE] WIEZIENIE AKTYWNE: (%.1f, %.1f, %.1f) r=%.0fm'):format(v.x, v.y, v.z, prison.radius))

    notify('~b~ODSIADUJESZ KARE. ~r~Nie mozesz opuscic wiezienia.')
    teleportToPrison()
    setupPrisonBlip()
end)

RegisterNetEvent('ps:client:free')
AddEventHandler('ps:client:free', function(data)
    print('[PRACE] >>> ps:client:free')
    prison.active  = false
    prison.coords  = nil
    prison.inMatch = false
    prison.lastPos = nil
    removePrisonBlip()

    if data then
        local v = unpackCoords(data.coords)
        if v then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
                Wait(200)
                ped = PlayerPedId()
            end
            SetEntityCoords(ped, v.x, v.y, v.z, false, false, false, false)
            SetEntityHeading(ped, tonumber(data.heading) or 0.0)
            notify('~g~Wolnosc! Skonczyles odsiadke.')
        end
    end
end)

CreateThread(function()
    local lastDebugAt = 0

    while true do
        Wait(500)
        if not prison.active or not prison.coords then
            goto continue
        end

        local ped     = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local now     = GetGameTimer()
        local dist    = #(pcoords - prison.coords)

        if now - lastDebugAt > 10000 then
            print(('[PRACE] state | active=%s inMatch=%s dist=%.1fm radius=%.0f bucket=%s'):format(
                tostring(prison.active), tostring(prison.inMatch), dist, prison.radius,
                tostring(prison.bucket)))
            lastDebugAt = now
        end

        if not prison.inMatch and dist > prison.radius then
            print(('[PRACE] Wyszles ze strefy (dist=%.1fm > %.0fm) → tepa'):format(dist, prison.radius))
            notify('~r~Nie mozesz opuscic wiezienia!')
            teleportToPrison()
        end

        ::continue::
    end
end)

RegisterNetEvent('ps:client:bucketStatus')
AddEventHandler('ps:client:bucketStatus', function(_, bucketId)
    prison.bucket = tonumber(bucketId) or 0
end)

CreateThread(function()
    while true do
        if prison.active and not prison.inMatch and prison.coords then
            local pcoords = GetEntityCoords(PlayerPedId())
            if #(pcoords - prison.coords) <= prison.radius * 1.2 then
                DisableControlAction(0, 23, true)  -- Enter vehicle
                DisableControlAction(0, 75, true)  -- Exit (wymusza tepa zamiast wyjazdu)
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)


local function endMatchReturn(reason)
    print(('[PRACE] Koniec duelu (%s)'):format(tostring(reason)))
    SetTimeout(1200, function()
        prison.inMatch = false
        if prison.active and prison.coords then
            teleportToPrison()
        end
    end)
end

RegisterNetEvent('mm:client:matchStart')
AddEventHandler('mm:client:matchStart', function(data)
    print('[PRACE] mm:matchStart — pauzuje geo-fence (instant)')
    if prison.active then
        prison.inMatch = true
    end
end)

RegisterNetEvent(PSConfig.MatchResultEvent or 'mm:client:matchResult')
AddEventHandler(PSConfig.MatchResultEvent or 'mm:client:matchResult', function(data)
    print('[PRACE] mm:matchResult, result=' .. tostring(data and data.result))
    if data and data.result then
        if data.result == 'win' or data.result == 'loss' or data.result == 'draw' then
            TriggerServerEvent('ps:server:reportDuelResult', data.result)
        end
    end
    if prison.active then endMatchReturn('matchResult') end
end)

RegisterNetEvent('mm:client:matchEnd')
AddEventHandler('mm:client:matchEnd', function()
    print('[PRACE] mm:matchEnd')
    if prison.active then endMatchReturn('matchEnd') end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        removePrisonBlip()
    end
end)


RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    ESX.TriggerServerCallback('ps:server:getData', function(data)
        cachedData = data
        cb({ data = data })
    end)
end)

RegisterNUICallback('startMinigame', function(payload, cb)
    local gameType = payload and payload.type
    if not gameType then cb({ ok = false }) return end
    ESX.TriggerServerCallback('ps:server:startMinigame', function(res)
        if res.ok then
            minigameActive = true
        end
        cb(res)
    end, gameType)
end)

RegisterNUICallback('endMinigame', function(payload, cb)
    minigameActive = false
    ESX.TriggerServerCallback('ps:server:endMinigame', function(res)
        cb(res)
    end, payload or {})
end)

RegisterNUICallback('cancelMinigame', function(_, cb)
    minigameActive = false
    cb({ ok = true })
end)

RegisterNUICallback('buyout', function(payload, cb)
    local amount = (payload and tonumber(payload.amount)) or 1
    TriggerServerEvent('ps:server:buyout', amount)
    cb({ ok = true })
end)

RegisterNUICallback('openMmMenu', function(_, cb)
    cb({ ok = true })
    if panelOpen then closePanel() end
    SetTimeout(50, function()
        ExecuteCommand('mm_menu')
    end)
end)


AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        if panelOpen then
            SetNuiFocus(false, false)
            PSCam.Stop()
        end
    end
end)