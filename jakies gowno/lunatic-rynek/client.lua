ESX = exports["es_extended"]:getSharedObject()

local menuOpen = false
local cameraActive = false
local cam = nil
local pendingVehicle = nil

local function ResolveVehicleName(modelHash, fallback)
    local hash = tonumber(modelHash)
    if not hash then return fallback or tostring(modelHash) end
    local displayName = GetDisplayNameFromVehicleModel(hash)
    if displayName and displayName ~= '' and displayName ~= 'CARNOTFOUND' then
        local label = GetLabelText(displayName)
        if label and label ~= 'NULL' and label ~= '' then
            return label
        end
        return displayName
    end
    return fallback or tostring(modelHash)
end

local function ResolveVehicleLabels(vehicleList, labelKey)
    labelKey = labelKey or 'label'
    for _, veh in ipairs(vehicleList) do
        local currentLabel = veh[labelKey]
        if currentLabel and tonumber(currentLabel) then
            veh[labelKey] = ResolveVehicleName(currentLabel, currentLabel)
        end
        if veh.model and currentLabel and tonumber(currentLabel) then
            veh[labelKey] = ResolveVehicleName(veh.model, veh[labelKey])
        end
    end
    return vehicleList
end

local camAngleH = 0.0
local camAngleV = 20.0
local camDist = 6.0
local camTarget = nil
local photoVehicle = nil

local function GetClosestOwnedVehicle(plate)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicles = ESX.Game.GetVehiclesInArea(coords, 30.0)
    for _, veh in ipairs(vehicles) do
        if DoesEntityExist(veh) then
            local vehPlate = string.gsub(GetVehicleNumberPlateText(veh), "^%s+", "")
            vehPlate = string.gsub(vehPlate, "%s+$", "")
            local checkPlate = string.gsub(plate, "^%s+", "")
            checkPlate = string.gsub(checkPlate, "%s+$", "")
            if string.upper(vehPlate) == string.upper(checkPlate) then
                return veh
            end
        end
    end
    return nil
end

local function UpdateCameraPosition()
    if not cam or not camTarget then return end
    local angleH = math.rad(camAngleH)
    local angleV = math.rad(camAngleV)
    local x = camTarget.x + camDist * math.cos(angleH) * math.cos(angleV)
    local y = camTarget.y + camDist * math.sin(angleH) * math.cos(angleV)
    local z = camTarget.z + camDist * math.sin(angleV) + 0.5
    SetCamCoord(cam, x, y, z)
    PointCamAtCoord(cam, camTarget.x, camTarget.y, camTarget.z + 0.3)
end

function StartPhotoMode(vehicleData)
    local vehicle = GetClosestOwnedVehicle(vehicleData.plate)
    if not vehicle then
        TriggerEvent('erkamon_notify:Send', '~r~Podjedz blizej swojego pojazdu! (max 30m)')
        return
    end

    pendingVehicle = vehicleData
    photoVehicle = vehicle
    cameraActive = true

    SendNUIMessage({ type = 'hideForPhoto' })
    SetNuiFocus(false, false)
    menuOpen = false

    local vehCoords = GetEntityCoords(vehicle)
    camTarget = vehCoords
    camAngleH = GetEntityHeading(vehicle) + 135.0
    camAngleV = 15.0
    camDist = 6.0

    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    UpdateCameraPosition()
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, false)

    DisplayHud(false)
    DisplayRadar(false)

    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'showPhotoHud' })

    Citizen.CreateThread(function()
        while cameraActive do
            Citizen.Wait(0)

            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)

            local mx = GetDisabledControlNormal(0, 1) * 3.0  -- mouse X
            local my = GetDisabledControlNormal(0, 2) * 3.0  -- mouse Y
            camAngleH = camAngleH - mx
            camAngleV = math.max(-5.0, math.min(60.0, camAngleV + my))

            if IsDisabledControlJustPressed(0, 241) then -- scroll up
                camDist = math.max(3.0, camDist - 0.5)
            end
            if IsDisabledControlJustPressed(0, 242) then -- scroll down
                camDist = math.min(15.0, camDist + 0.5)
            end

            UpdateCameraPosition()

            if IsDisabledControlJustPressed(0, 191) then
                TakeVehiclePhoto()
            end

            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then
                CancelPhotoMode()
            end
        end
    end)
end

function TakeVehiclePhoto()
    if not cameraActive then return end

    SendNUIMessage({ type = 'hidePhotoHud' })
    Citizen.Wait(100)

    exports['screenshot-basic']:requestScreenshot(function(data)
        local photoBase64 = data

        ExitPhotoMode()

        Citizen.Wait(300)
        menuOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            type = 'openSellVehicleWithPhoto',
            vehicle = pendingVehicle,
            photo = photoBase64
        })
    end)
end

function CancelPhotoMode()
    ExitPhotoMode()
    Citizen.Wait(300)
    OpenMarket()
end

function ExitPhotoMode()
    cameraActive = false
    SendNUIMessage({ type = 'hidePhotoHud' })

    if cam then
        RenderScriptCams(false, true, 500, true, false)
        SetCamActive(cam, false)
        DestroyCam(cam, false)
        cam = nil
    end

    DisplayHud(true)
    DisplayRadar(true)
    EnableAllControlActions(0)
end

RegisterCommand(Config.Command, function()
    OpenMarket()
end, false)

function OpenMarket()
    if menuOpen then return end
    if cameraActive then return end

    ESX.TriggerServerCallback('lunatic-rynek:getListings', function(listings)
        ESX.TriggerServerCallback('lunatic-rynek:getMyItems', function(myItems)
            ESX.TriggerServerCallback('lunatic-rynek:getMyListings', function(myListings)
                ESX.TriggerServerCallback('lunatic-rynek:getVehicleListings', function(vehListings)
                    ESX.TriggerServerCallback('lunatic-rynek:getMyVehicles', function(myVehicles)
                        ESX.TriggerServerCallback('lunatic-rynek:getMyVehicleListings', function(myVehListings)
                            ESX.TriggerServerCallback('lunatic-rynek:getCoins', function(coins)
                                ResolveVehicleLabels(vehListings, 'vehicleLabel')
                                ResolveVehicleLabels(myVehicles, 'label')
                                ResolveVehicleLabels(myVehListings, 'vehicleLabel')

                                menuOpen = true
                                SetNuiFocus(true, true)
                                SendNUIMessage({
                                    type = 'openMenu',
                                    listings = listings,
                                    myItems = myItems,
                                    myListings = myListings,
                                    vehicleListings = vehListings,
                                    myVehicles = myVehicles,
                                    myVehicleListings = myVehListings,
                                    coins = coins,
                                    durations = Config.ListingDurations,
                                    tax = Config.Tax,
                                    vehicleTax = Config.VehicleTax,
                                    maxListings = Config.MaxListings,
                                    maxVehicleListings = Config.MaxVehicleListings,
                                    minPrice = Config.MinPrice,
                                    maxPrice = Config.MaxPrice,
                                    vehicleMinPrice = Config.VehicleMinPrice,
                                    vehicleMaxPrice = Config.VehicleMaxPrice
                                })
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end

RegisterNUICallback('closeMenu', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buyItem', function(data, cb)
    ESX.TriggerServerCallback('lunatic-rynek:buyItem', function(result)
        if result.success then
            TriggerEvent('erkamon_notify:Send', '~g~Kupiono: ' .. result.itemLabel)
        else
            TriggerEvent('erkamon_notify:Send', '~r~' .. result.message)
        end
        cb(result)
    end, data.listingId)
end)

RegisterNUICallback('listItem', function(data, cb)
    ESX.TriggerServerCallback('lunatic-rynek:listItem', function(result)
        if result.success then
            TriggerEvent('erkamon_notify:Send', '~g~Wystawiono przedmiot na rynek!')
        else
            TriggerEvent('erkamon_notify:Send', '~r~' .. result.message)
        end
        cb(result)
    end, data.itemName, data.count, data.price, data.duration, data.currencyType)
end)

RegisterNUICallback('cancelListing', function(data, cb)
    ESX.TriggerServerCallback('lunatic-rynek:cancelListing', function(result)
        if result.success then
            TriggerEvent('erkamon_notify:Send', '~y~Oferta anulowana, item zwrocony.')
        else
            TriggerEvent('erkamon_notify:Send', '~r~' .. result.message)
        end
        cb(result)
    end, data.listingId)
end)

RegisterNUICallback('startPhotoMode', function(data, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'hideForPhoto' })
    Citizen.Wait(200)
    StartPhotoMode(data.vehicle)
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(data, cb)
    ESX.TriggerServerCallback('lunatic-rynek:buyVehicle', function(result)
        if result.success then
            TriggerEvent('erkamon_notify:Send', '~g~Kupiono pojazd: ' .. result.vehicleLabel .. ' [' .. result.plate .. ']')
        else
            TriggerEvent('erkamon_notify:Send', '~r~' .. result.message)
        end
        cb(result)
    end, data.listingId)
end)

RegisterNUICallback('uploadVehiclePhoto', function(data, cb)
    if data.photo then
        TriggerServerEvent('lunatic-rynek:uploadPhoto', data.photo)
    end
    cb('ok')
end)

RegisterNUICallback('listVehicle', function(data, cb)
    ESX.TriggerServerCallback('lunatic-rynek:listVehicle', function(result)
        if result.success then
            TriggerEvent('erkamon_notify:Send', '~g~Wystawiono pojazd na rynek!')
            if photoVehicle and DoesEntityExist(photoVehicle) then
                SetEntityAsMissionEntity(photoVehicle, true, true)
                DeleteVehicle(photoVehicle)
            end
            photoVehicle = nil
        else
            TriggerEvent('erkamon_notify:Send', '~r~' .. result.message)
        end
        cb(result)
    end, data.plate, data.price, data.duration, data.currencyType)
end)

RegisterNUICallback('cancelVehicleListing', function(data, cb)
    ESX.TriggerServerCallback('lunatic-rynek:cancelVehicleListing', function(result)
        if result.success then
            TriggerEvent('erkamon_notify:Send', '~y~Oferta pojazdu anulowana, pojazd zwrocony.')
        else
            TriggerEvent('erkamon_notify:Send', '~r~' .. result.message)
        end
        cb(result)
    end, data.listingId)
end)

RegisterNUICallback('refreshListings', function(_, cb)
    ESX.TriggerServerCallback('lunatic-rynek:getListings', function(listings)
        ESX.TriggerServerCallback('lunatic-rynek:getMyListings', function(myListings)
            ESX.TriggerServerCallback('lunatic-rynek:getMyItems', function(myItems)
                ESX.TriggerServerCallback('lunatic-rynek:getVehicleListings', function(vehListings)
                    ESX.TriggerServerCallback('lunatic-rynek:getMyVehicles', function(myVehicles)
                        ESX.TriggerServerCallback('lunatic-rynek:getMyVehicleListings', function(myVehListings)
                            ESX.TriggerServerCallback('lunatic-rynek:getCoins', function(coins)
                                ResolveVehicleLabels(vehListings, 'vehicleLabel')
                                ResolveVehicleLabels(myVehicles, 'label')
                                ResolveVehicleLabels(myVehListings, 'vehicleLabel')
                                cb({
                                    listings = listings,
                                    myListings = myListings,
                                    myItems = myItems,
                                    vehicleListings = vehListings,
                                    myVehicles = myVehicles,
                                    myVehicleListings = myVehListings,
                                    coins = coins
                                })
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)

RegisterNetEvent('lunatic-rynek:itemSold')
AddEventHandler('lunatic-rynek:itemSold', function(itemLabel, price, buyerName)
    TriggerEvent('erkamon_notify:Send', '~g~Sprzedano ' .. itemLabel .. ' za $' .. price .. ' graczowi ' .. buyerName)
end)

RegisterNetEvent('lunatic-rynek:listingExpired')
AddEventHandler('lunatic-rynek:listingExpired', function(itemLabel, count)
    TriggerEvent('erkamon_notify:Send', '~y~Oferta wygasla: ' .. count .. 'x ' .. itemLabel .. ' - zwrocono.')
end)