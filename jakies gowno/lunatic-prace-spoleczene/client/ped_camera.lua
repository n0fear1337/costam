
PSCam = {
    cam = nil,
    active = false,
    scenarioPlayed = false,
    savedHeading = nil,
    savedCoords = nil,
}

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 50 do
        Wait(20)
        timeout = timeout + 1
    end
    return HasAnimDictLoaded(dict)
end

function PSCam.Start()
    if PSCam.active then return end
    PSCam.active = true

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    PSCam.savedCoords = coords
    PSCam.savedHeading = heading

    if loadAnimDict('random@arrests') then
        TaskPlayAnim(ped, 'random@arrests', 'idle_2_hands_up', 8.0, -8.0, -1, 49, 0, false, false, false)
        PSCam.scenarioPlayed = true
    end

    SetWeaponsNoAutoswap(true)
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)

    local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local forward = GetEntityForwardVector(ped)

    local camCoords = vector3(
        headCoords.x + forward.x * 1.0,
        headCoords.y + forward.y * 1.0,
        headCoords.z + 0.05  -- delikatnie wyzej zeby nie patrzec spod brody
    )

    PSCam.cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        camCoords.x, camCoords.y, camCoords.z,
        0.0, 0.0, heading + 180.0,
        38.0, false, 0  -- mniejszy FOV = portretowe ujecie twarzy
    )
    PointCamAtPedBone(PSCam.cam, ped, 31086, 0.0, 0.0, 0.0, true)
    SetCamActive(PSCam.cam, true)
    RenderScriptCams(true, true, 600, true, true)

    CreateThread(function()
        while PSCam.active do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end

function PSCam.Stop()
    if not PSCam.active then return end
    PSCam.active = false

    if PSCam.cam then
        RenderScriptCams(false, true, 400, true, true)
        SetCamActive(PSCam.cam, false)
        DestroyCam(PSCam.cam, false)
        PSCam.cam = nil
    end

    local ped = PlayerPedId()
    if PSCam.scenarioPlayed then
        ClearPedTasks(ped)
        PSCam.scenarioPlayed = false
    end
    SetWeaponsNoAutoswap(false)
end

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then PSCam.Stop() end
end)