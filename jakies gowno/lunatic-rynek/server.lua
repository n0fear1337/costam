ESX = exports["es_extended"]:getSharedObject()

MySQL.ready(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `lunatic_rynek` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `seller_identifier` VARCHAR(60) NOT NULL,
            `seller_name` VARCHAR(60) NOT NULL,
            `seller_discord` VARCHAR(30) DEFAULT NULL,
            `item_name` VARCHAR(100) NOT NULL,
            `item_label` VARCHAR(100) NOT NULL,
            `item_count` INT(11) NOT NULL DEFAULT 1,
            `price` INT(11) NOT NULL,
            `currency_type` VARCHAR(10) NOT NULL DEFAULT 'money',
            `expires_at` INT(11) NOT NULL,
            `created_at` INT(11) NOT NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_expires` (`expires_at`),
            INDEX `idx_seller` (`seller_identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `lunatic_rynek_vehicles` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `seller_identifier` VARCHAR(60) NOT NULL,
            `seller_name` VARCHAR(60) NOT NULL,
            `seller_discord` VARCHAR(30) DEFAULT NULL,
            `plate` VARCHAR(12) NOT NULL,
            `model` VARCHAR(100) NOT NULL,
            `vehicle_label` VARCHAR(100) NOT NULL DEFAULT '',
            `vehicle_data` LONGTEXT NOT NULL,
            `photo` LONGTEXT DEFAULT NULL,
            `price` INT(11) NOT NULL,
            `currency_type` VARCHAR(10) NOT NULL DEFAULT 'money',
            `expires_at` INT(11) NOT NULL,
            `created_at` INT(11) NOT NULL,
            PRIMARY KEY (`id`),
            INDEX `idx_expires_v` (`expires_at`),
            INDEX `idx_seller_v` (`seller_identifier`),
            UNIQUE INDEX `idx_plate` (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.Async.execute([[
        ALTER TABLE `lunatic_rynek_vehicles` ADD COLUMN IF NOT EXISTS `photo` LONGTEXT DEFAULT NULL AFTER `vehicle_data`;
    ]], {})

    MySQL.Async.execute([[ ALTER TABLE `lunatic_rynek` ADD COLUMN IF NOT EXISTS `seller_discord` VARCHAR(30) DEFAULT NULL AFTER `seller_name`; ]], {})
    MySQL.Async.execute([[ ALTER TABLE `lunatic_rynek_vehicles` ADD COLUMN IF NOT EXISTS `seller_discord` VARCHAR(30) DEFAULT NULL AFTER `seller_name`; ]], {})
    MySQL.Async.execute([[ ALTER TABLE `lunatic_rynek` ADD COLUMN IF NOT EXISTS `currency_type` VARCHAR(10) NOT NULL DEFAULT 'money' AFTER `price`; ]], {})
    MySQL.Async.execute([[ ALTER TABLE `lunatic_rynek_vehicles` ADD COLUMN IF NOT EXISTS `currency_type` VARCHAR(10) NOT NULL DEFAULT 'money' AFTER `price`; ]], {})

    print('^2[lunatic-rynek]^7 System rynku zaladowany.')
end)

local function GetDiscordId(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if string.find(id, "discord:") then
            return string.sub(id, 9)
        end
    end
    return nil
end

local function GetPlayerCoins(identifier)
    local result = MySQL.Sync.fetchAll('SELECT coins FROM lunatic_coins WHERE identifier = @identifier', { ['@identifier'] = identifier })
    if result[1] then return result[1].coins
    else
        MySQL.Async.execute('INSERT INTO lunatic_coins (identifier, coins) VALUES (@identifier, 0)', { ['@identifier'] = identifier })
        return 0
    end
end

local function AddPlayerCoins(identifier, amount)
    GetPlayerCoins(identifier)
    MySQL.Async.execute('UPDATE lunatic_coins SET coins = coins + @amount WHERE identifier = @identifier', { ['@identifier'] = identifier, ['@amount'] = amount })
end

local function RemovePlayerCoins(identifier, amount)
    local current = GetPlayerCoins(identifier)
    if current >= amount then
        MySQL.Async.execute('UPDATE lunatic_coins SET coins = coins - @amount WHERE identifier = @identifier', { ['@identifier'] = identifier, ['@amount'] = amount })
        return true
    end
    return false
end

local function IsBlacklisted(itemName)
    for _, v in ipairs(Config.BlacklistedItems) do
        if v == itemName then return true end
    end
    return false
end

local function IsVehicleBlacklisted(model)
    for _, v in ipairs(Config.BlacklistedVehicles) do
        if v == model then return true end
    end
    return false
end

local function GetValidDuration(seconds)
    for _, d in ipairs(Config.ListingDurations) do
        if d.seconds == seconds then return true end
    end
    return false
end

local function CountPlayerListings(identifier)
    local result = MySQL.Sync.fetchAll(
        'SELECT COUNT(*) as cnt FROM lunatic_rynek WHERE seller_identifier = @id',
        { ['@id'] = identifier }
    )
    return result[1] and result[1].cnt or 0
end

local function CountPlayerVehicleListings(identifier)
    local result = MySQL.Sync.fetchAll(
        'SELECT COUNT(*) as cnt FROM lunatic_rynek_vehicles WHERE seller_identifier = @id AND expires_at > @now',
        { ['@id'] = identifier, ['@now'] = os.time() }
    )
    return result[1] and result[1].cnt or 0
end

local vehicleNameCache = {}
local vehicleCacheLoaded = false

local function NormalizeHash(hash)
    local n = tonumber(hash)
    if not n then return nil, nil end
    local unsigned = n
    local signed = n
    if n < 0 then
        unsigned = n + 0x100000000
    elseif n > 0x7FFFFFFF then
        signed = n - 0x100000000
    end
    return tostring(signed), tostring(unsigned)
end

local function LoadVehicleCache()
    if vehicleCacheLoaded then return end
    local result = MySQL.Sync.fetchAll('SELECT name, model FROM vehicles', {})
    if not result then return end
    for _, v in ipairs(result) do
        local hash = joaat(v.model)
        local signed, unsigned = NormalizeHash(hash)
        if signed then vehicleNameCache[signed] = v.name end
        if unsigned then vehicleNameCache[unsigned] = v.name end
        vehicleNameCache[v.model] = v.name
    end
    vehicleCacheLoaded = true
    print('^2[lunatic-rynek]^7 Zaladowano ' .. #result .. ' nazw pojazdow do cache.')
end

local function GetVehicleLabel(modelHash)
    LoadVehicleCache()
    local hashStr = tostring(modelHash)
    if vehicleNameCache[hashStr] then
        return vehicleNameCache[hashStr]
    end
    local signed, unsigned = NormalizeHash(modelHash)
    if signed and vehicleNameCache[signed] then
        return vehicleNameCache[signed]
    end
    if unsigned and vehicleNameCache[unsigned] then
        return vehicleNameCache[unsigned]
    end
    return hashStr
end

RegisterCommand('rynek_reload', function(source)
    if source ~= 0 then return end
    vehicleCacheLoaded = false
    vehicleNameCache = {}
    LoadVehicleCache()
    print('^2[lunatic-rynek]^7 Cache pojazdow przeladowany.')
end, false)

ESX.RegisterServerCallback('lunatic-rynek:getCoins', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb(0) return end
    cb(GetPlayerCoins(xPlayer.getIdentifier()))
end)

ESX.RegisterServerCallback('lunatic-rynek:getListings', function(source, cb)
    local now = os.time()
    local xPlayer = ESX.GetPlayerFromId(source)
    local myId = xPlayer and xPlayer.getIdentifier() or ''
    local result = MySQL.Sync.fetchAll(
        'SELECT * FROM lunatic_rynek WHERE expires_at > @now AND seller_identifier != @me ORDER BY created_at DESC',
        { ['@now'] = now, ['@me'] = myId }
    )
    local out = {}
    for _, r in ipairs(result) do
        table.insert(out, { id=r.id, sellerName=r.seller_name, sellerDiscord=r.seller_discord, itemName=r.item_name, itemLabel=r.item_label, count=r.item_count, price=r.price, currencyType=r.currency_type or "money", expiresAt=r.expires_at, createdAt=r.created_at, timeLeft=r.expires_at-now })
    end
    cb(out)
end)

ESX.RegisterServerCallback('lunatic-rynek:getMyItems', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({}) return end
    local inv = xPlayer.getInventory()
    local out = {}
    for _, item in ipairs(inv) do
        if item.count > 0 and not IsBlacklisted(item.name) then
            table.insert(out, { name=item.name, label=item.label, count=item.count })
        end
    end
    cb(out)
end)

ESX.RegisterServerCallback('lunatic-rynek:getMyListings', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({}) return end
    local now = os.time()
    local result = MySQL.Sync.fetchAll(
        'SELECT * FROM lunatic_rynek WHERE seller_identifier = @id AND expires_at > @now ORDER BY created_at DESC',
        { ['@id'] = xPlayer.getIdentifier(), ['@now'] = now }
    )
    local out = {}
    for _, r in ipairs(result) do
        table.insert(out, { id=r.id, itemName=r.item_name, itemLabel=r.item_label, count=r.item_count, price=r.price, currencyType=r.currency_type or "money", expiresAt=r.expires_at, createdAt=r.created_at, timeLeft=r.expires_at-now })
    end
    cb(out)
end)

ESX.RegisterServerCallback('lunatic-rynek:buyItem', function(source, cb, listingId)
    local xBuyer = ESX.GetPlayerFromId(source)
    if not xBuyer then cb({ success=false, message='Blad gracza.' }) return end
    local now = os.time()
    local result = MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek WHERE id = @id AND expires_at > @now LIMIT 1', { ['@id']=listingId, ['@now']=now })
    if not result[1] then cb({ success=false, message='Oferta nie istnieje lub wygasla.' }) return end
    local listing = result[1]
    local currency = listing.currency_type or 'money'
    if listing.seller_identifier == xBuyer.getIdentifier() then cb({ success=false, message='Nie mozesz kupic wlasnej oferty!' }) return end

    if currency == 'coins' then
        local coins = GetPlayerCoins(xBuyer.getIdentifier())
        if coins < listing.price then cb({ success=false, message='Nie masz wystarczajaco coinow! Potrzebujesz '..listing.price }) return end
    else
        if xBuyer.getMoney() < listing.price then cb({ success=false, message='Nie masz wystarczajaco pieniedzy!' }) return end
    end

    local deleted = MySQL.Sync.execute('DELETE FROM lunatic_rynek WHERE id = @id AND expires_at > @now', { ['@id']=listingId, ['@now']=now })
    if deleted == 0 then cb({ success=false, message='Oferta juz zostala kupiona.' }) return end

    if currency == 'coins' then
        RemovePlayerCoins(xBuyer.getIdentifier(), listing.price)
    else
        xBuyer.removeMoney(listing.price)
    end

    xBuyer.addInventoryItem(listing.item_name, listing.item_count)
    local tax = math.floor(listing.price * Config.Tax)
    local earnings = listing.price - tax

    local xSeller = ESX.GetPlayerFromIdentifier(listing.seller_identifier)
    if currency == 'coins' then
        AddPlayerCoins(listing.seller_identifier, earnings)
        if xSeller then TriggerClientEvent('lunatic-rynek:itemSold', xSeller.source, listing.item_label, earnings, xBuyer.getName()) end
    else
        if xSeller then
            xSeller.addMoney(earnings)
            TriggerClientEvent('lunatic-rynek:itemSold', xSeller.source, listing.item_label, earnings, xBuyer.getName())
        else
            MySQL.Async.execute('UPDATE users SET money = money + @amount WHERE identifier = @id', { ['@amount']=earnings, ['@id']=listing.seller_identifier })
        end
    end
    print(string.format('^2[lunatic-rynek]^7 %s kupil %dx %s od %s za %d %s', xBuyer.getName(), listing.item_count, listing.item_label, listing.seller_name, listing.price, currency))
    cb({ success=true, itemLabel=listing.item_label, itemCount=listing.item_count, price=listing.price })
end)

ESX.RegisterServerCallback('lunatic-rynek:listItem', function(source, cb, itemName, count, price, duration, currencyType)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({ success=false, message='Blad gracza.' }) return end
    if not itemName or not count or not price or not duration then cb({ success=false, message='Nieprawidlowe dane.' }) return end
    currencyType = (currencyType == 'coins') and 'coins' or 'money'
    count = math.floor(tonumber(count) or 0)
    price = math.floor(tonumber(price) or 0)
    duration = tonumber(duration) or 0
    if count < 1 then cb({ success=false, message='Ilosc musi byc wieksza od 0.' }) return end
    if price < Config.MinPrice then cb({ success=false, message='Minimalna cena to '..Config.MinPrice }) return end
    if price > Config.MaxPrice then cb({ success=false, message='Maksymalna cena to '..Config.MaxPrice }) return end
    if not GetValidDuration(duration) then cb({ success=false, message='Nieprawidlowy czas trwania.' }) return end
    if IsBlacklisted(itemName) then cb({ success=false, message='Ten przedmiot nie moze byc wystawiony.' }) return end
    if CountPlayerListings(xPlayer.getIdentifier()) >= Config.MaxListings then cb({ success=false, message='Masz juz max ofert itemow ('..Config.MaxListings..').' }) return end
    local item = xPlayer.getInventoryItem(itemName)
    if not item or item.count < count then cb({ success=false, message='Nie masz wystarczajaco tego przedmiotu.' }) return end
    xPlayer.removeInventoryItem(itemName, count)
    local now = os.time()
    local discordId = GetDiscordId(source)
    MySQL.Async.execute('INSERT INTO lunatic_rynek (seller_identifier, seller_name, seller_discord, item_name, item_label, item_count, price, currency_type, expires_at, created_at) VALUES (@sid,@sname,@sdisc,@iname,@ilabel,@icount,@price,@curr,@exp,@cre)', {
        ['@sid']=xPlayer.getIdentifier(), ['@sname']=xPlayer.getName(), ['@sdisc']=discordId, ['@iname']=itemName, ['@ilabel']=item.label or itemName, ['@icount']=count, ['@price']=price, ['@curr']=currencyType, ['@exp']=now+duration, ['@cre']=now
    })
    print(string.format('^2[lunatic-rynek]^7 %s wystawil %dx %s za $%d', xPlayer.getName(), count, item.label or itemName, price))
    cb({ success=true })
end)

ESX.RegisterServerCallback('lunatic-rynek:cancelListing', function(source, cb, listingId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({ success=false, message='Blad gracza.' }) return end
    local result = MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek WHERE id = @id AND seller_identifier = @sid LIMIT 1', { ['@id']=listingId, ['@sid']=xPlayer.getIdentifier() })
    if not result[1] then cb({ success=false, message='Oferta nie istnieje.' }) return end
    MySQL.Async.execute('DELETE FROM lunatic_rynek WHERE id = @id', { ['@id']=listingId })
    xPlayer.addInventoryItem(result[1].item_name, result[1].item_count)
    cb({ success=true })
end)

ESX.RegisterServerCallback('lunatic-rynek:getMyVehicles', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({}) return end
    local result = MySQL.Sync.fetchAll(
        'SELECT ov.plate, ov.vehicle FROM owned_vehicles ov WHERE ov.owner = @owner AND ov.plate NOT IN (SELECT plate FROM lunatic_rynek_vehicles WHERE expires_at > @now)',
        { ['@owner']=xPlayer.getIdentifier(), ['@now']=os.time() }
    )
    local out = {}
    for _, row in ipairs(result) do
        local vd = json.decode(row.vehicle)
        local modelRaw = vd and tostring(vd.model) or 'unknown'
        local label = GetVehicleLabel(modelRaw)
        if not IsVehicleBlacklisted(modelRaw) then
            table.insert(out, { plate=row.plate, model=modelRaw, label=label, data=row.vehicle })
        end
    end
    cb(out)
end)

ESX.RegisterServerCallback('lunatic-rynek:getVehicleListings', function(source, cb)
    local now = os.time()
    local xPlayer = ESX.GetPlayerFromId(source)
    local myId = xPlayer and xPlayer.getIdentifier() or ''
    local result = MySQL.Sync.fetchAll(
        'SELECT * FROM lunatic_rynek_vehicles WHERE expires_at > @now AND seller_identifier != @me ORDER BY created_at DESC',
        { ['@now']=now, ['@me']=myId }
    )
    local out = {}
    for _, r in ipairs(result) do
        local label = r.vehicle_label
        if tonumber(label) then label = GetVehicleLabel(label) end
        table.insert(out, { id=r.id, sellerName=r.seller_name, sellerDiscord=r.seller_discord, plate=r.plate, model=r.model, vehicleLabel=label, photo=r.photo, price=r.price, currencyType=r.currency_type or "money", expiresAt=r.expires_at, createdAt=r.created_at, timeLeft=r.expires_at-now })
    end
    cb(out)
end)

ESX.RegisterServerCallback('lunatic-rynek:getMyVehicleListings', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({}) return end
    local now = os.time()
    local result = MySQL.Sync.fetchAll(
        'SELECT * FROM lunatic_rynek_vehicles WHERE seller_identifier = @id AND expires_at > @now ORDER BY created_at DESC',
        { ['@id']=xPlayer.getIdentifier(), ['@now']=now }
    )
    local out = {}
    for _, r in ipairs(result) do
        local label = r.vehicle_label
        if tonumber(label) then label = GetVehicleLabel(label) end
        table.insert(out, { id=r.id, plate=r.plate, model=r.model, vehicleLabel=label, photo=r.photo, price=r.price, currencyType=r.currency_type or "money", expiresAt=r.expires_at, createdAt=r.created_at, timeLeft=r.expires_at-now })
    end
    cb(out)
end)

local pendingPhotos = {}

RegisterNetEvent('lunatic-rynek:uploadPhoto')
AddEventHandler('lunatic-rynek:uploadPhoto', function(photoData)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    pendingPhotos[xPlayer.getIdentifier()] = photoData
    Citizen.SetTimeout(60000, function()
        pendingPhotos[xPlayer.getIdentifier()] = nil
    end)
end)

ESX.RegisterServerCallback('lunatic-rynek:listVehicle', function(source, cb, plate, price, duration, currencyType)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({ success=false, message='Blad gracza.' }) return end
    if not plate or not price or not duration then cb({ success=false, message='Nieprawidlowe dane.' }) return end
    currencyType = (currencyType == "coins") and "coins" or "money"
    price = math.floor(tonumber(price) or 0)
    duration = tonumber(duration) or 0
    if price < Config.VehicleMinPrice then cb({ success=false, message='Min. cena pojazdu to $'..Config.VehicleMinPrice }) return end
    if price > Config.VehicleMaxPrice then cb({ success=false, message='Max. cena pojazdu to $'..Config.VehicleMaxPrice }) return end
    if not GetValidDuration(duration) then cb({ success=false, message='Nieprawidlowy czas trwania.' }) return end
    if CountPlayerVehicleListings(xPlayer.getIdentifier()) >= Config.MaxVehicleListings then
        cb({ success=false, message='Masz juz max ofert pojazdow ('..Config.MaxVehicleListings..').' }) return
    end
    local vehResult = MySQL.Sync.fetchAll('SELECT * FROM owned_vehicles WHERE owner = @o AND plate = @p LIMIT 1', { ['@o']=xPlayer.getIdentifier(), ['@p']=plate })
    if not vehResult[1] then cb({ success=false, message='Nie posiadasz tego pojazdu!' }) return end
    local alreadyListed = MySQL.Sync.fetchAll('SELECT id FROM lunatic_rynek_vehicles WHERE plate = @p AND expires_at > @now LIMIT 1', { ['@p']=plate, ['@now']=os.time() })
    if alreadyListed[1] then cb({ success=false, message='Ten pojazd jest juz na rynku!' }) return end
    local vehicleData = vehResult[1].vehicle
    local vd = json.decode(vehicleData)
    local modelRaw = vd and tostring(vd.model) or 'unknown'
    local vehicleLabel = GetVehicleLabel(modelRaw)
    if IsVehicleBlacklisted(modelRaw) then cb({ success=false, message='Ten pojazd nie moze byc wystawiony.' }) return end

    local photo = pendingPhotos[xPlayer.getIdentifier()]
    pendingPhotos[xPlayer.getIdentifier()] = nil

    local now = os.time()
    local discordId = GetDiscordId(source)
    MySQL.Async.execute('INSERT INTO lunatic_rynek_vehicles (seller_identifier,seller_name,seller_discord,plate,model,vehicle_label,vehicle_data,photo,price,currency_type,expires_at,created_at) VALUES (@sid,@sn,@sdisc,@pl,@mo,@vl,@vd,@ph,@pr,@curr,@ex,@cr)', {
        ['@sid']=xPlayer.getIdentifier(), ['@sn']=xPlayer.getName(), ['@sdisc']=discordId, ['@pl']=plate, ['@mo']=modelRaw, ['@vl']=vehicleLabel, ['@vd']=vehicleData, ['@ph']=photo, ['@pr']=price, ['@curr']=currencyType, ['@ex']=now+duration, ['@cr']=now
    })
    MySQL.Async.execute('DELETE FROM owned_vehicles WHERE owner = @o AND plate = @p', { ['@o']=xPlayer.getIdentifier(), ['@p']=plate })
    print(string.format('^2[lunatic-rynek]^7 %s wystawil pojazd %s [%s] za $%d', xPlayer.getName(), vehicleLabel, plate, price))
    cb({ success=true })
end)

ESX.RegisterServerCallback('lunatic-rynek:buyVehicle', function(source, cb, listingId)
    local xBuyer = ESX.GetPlayerFromId(source)
    if not xBuyer then cb({ success=false, message='Blad gracza.' }) return end
    local now = os.time()
    local result = MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek_vehicles WHERE id = @id AND expires_at > @now LIMIT 1', { ['@id']=listingId, ['@now']=now })
    if not result[1] then cb({ success=false, message='Oferta nie istnieje lub wygasla.' }) return end
    local listing = result[1]
    local currency = listing.currency_type or 'money'
    if listing.seller_identifier == xBuyer.getIdentifier() then cb({ success=false, message='Nie mozesz kupic wlasnej oferty!' }) return end

    if currency == 'coins' then
        if GetPlayerCoins(xBuyer.getIdentifier()) < listing.price then cb({ success=false, message='Nie masz wystarczajaco coinow!' }) return end
    else
        if xBuyer.getMoney() < listing.price then cb({ success=false, message='Nie masz wystarczajaco pieniedzy!' }) return end
    end

    local deleted = MySQL.Sync.execute('DELETE FROM lunatic_rynek_vehicles WHERE id = @id AND expires_at > @now', { ['@id']=listingId, ['@now']=now })
    if deleted == 0 then cb({ success=false, message='Oferta juz zostala kupiona.' }) return end

    if currency == 'coins' then
        RemovePlayerCoins(xBuyer.getIdentifier(), listing.price)
    else
        xBuyer.removeMoney(listing.price)
    end

    MySQL.Async.execute('INSERT INTO owned_vehicles (owner,plate,vehicle) VALUES (@o,@p,@v)', { ['@o']=xBuyer.getIdentifier(), ['@p']=listing.plate, ['@v']=listing.vehicle_data })
    local tax = math.floor(listing.price * Config.VehicleTax)
    local earnings = listing.price - tax
    local xSeller = ESX.GetPlayerFromIdentifier(listing.seller_identifier)

    if currency == 'coins' then
        AddPlayerCoins(listing.seller_identifier, earnings)
        if xSeller then TriggerClientEvent('lunatic-rynek:itemSold', xSeller.source, listing.vehicle_label..' ['..listing.plate..']', earnings, xBuyer.getName()) end
    else
        if xSeller then
            xSeller.addMoney(earnings)
            TriggerClientEvent('lunatic-rynek:itemSold', xSeller.source, listing.vehicle_label..' ['..listing.plate..']', earnings, xBuyer.getName())
        else
            MySQL.Async.execute('UPDATE users SET money = money + @a WHERE identifier = @id', { ['@a']=earnings, ['@id']=listing.seller_identifier })
        end
    end
    print(string.format('^2[lunatic-rynek]^7 %s kupil pojazd %s [%s] od %s za %d %s', xBuyer.getName(), listing.vehicle_label, listing.plate, listing.seller_name, listing.price, currency))
    cb({ success=true, vehicleLabel=listing.vehicle_label, plate=listing.plate, price=listing.price })
end)

ESX.RegisterServerCallback('lunatic-rynek:cancelVehicleListing', function(source, cb, listingId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then cb({ success=false, message='Blad gracza.' }) return end
    local result = MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek_vehicles WHERE id = @id AND seller_identifier = @sid LIMIT 1', { ['@id']=listingId, ['@sid']=xPlayer.getIdentifier() })
    if not result[1] then cb({ success=false, message='Oferta nie istnieje.' }) return end
    local listing = result[1]
    MySQL.Async.execute('DELETE FROM lunatic_rynek_vehicles WHERE id = @id', { ['@id']=listingId })
    MySQL.Async.execute('INSERT INTO owned_vehicles (owner,plate,vehicle) VALUES (@o,@p,@v)', { ['@o']=xPlayer.getIdentifier(), ['@p']=listing.plate, ['@v']=listing.vehicle_data })
    print(string.format('^2[lunatic-rynek]^7 %s anulowal oferte pojazdu: %s [%s]', xPlayer.getName(), listing.vehicle_label, listing.plate))
    cb({ success=true })
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.ExpiredCheckInterval * 1000)
        local now = os.time()

        local ei = MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek WHERE expires_at <= @now', { ['@now']=now })
        for _, l in ipairs(ei) do
            local xs = ESX.GetPlayerFromIdentifier(l.seller_identifier)
            if xs then
                xs.addInventoryItem(l.item_name, l.item_count)
                TriggerClientEvent('lunatic-rynek:listingExpired', xs.source, l.item_label, l.item_count)
            end
            MySQL.Async.execute('DELETE FROM lunatic_rynek WHERE id = @id', { ['@id']=l.id })
        end

        local ev = MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek_vehicles WHERE expires_at <= @now', { ['@now']=now })
        for _, l in ipairs(ev) do
            MySQL.Async.execute('INSERT INTO owned_vehicles (owner,plate,vehicle) VALUES (@o,@p,@v)', { ['@o']=l.seller_identifier, ['@p']=l.plate, ['@v']=l.vehicle_data })
            local xs = ESX.GetPlayerFromIdentifier(l.seller_identifier)
            if xs then TriggerClientEvent('lunatic-rynek:listingExpired', xs.source, l.vehicle_label..' ['..l.plate..']', 1) end
            MySQL.Async.execute('DELETE FROM lunatic_rynek_vehicles WHERE id = @id', { ['@id']=l.id })
        end

        if #ei + #ev > 0 then print(string.format('^2[lunatic-rynek]^7 Wyczyszczono %d wygaslych ofert.', #ei + #ev)) end
    end
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    Citizen.Wait(5000)
    local now = os.time()
    local id = xPlayer.getIdentifier()

    for _, l in ipairs(MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek WHERE seller_identifier = @id AND expires_at <= @now', { ['@id']=id, ['@now']=now })) do
        xPlayer.addInventoryItem(l.item_name, l.item_count)
        TriggerClientEvent('lunatic-rynek:listingExpired', playerId, l.item_label, l.item_count)
        MySQL.Async.execute('DELETE FROM lunatic_rynek WHERE id = @id', { ['@id']=l.id })
    end

    for _, l in ipairs(MySQL.Sync.fetchAll('SELECT * FROM lunatic_rynek_vehicles WHERE seller_identifier = @id AND expires_at <= @now', { ['@id']=id, ['@now']=now })) do
        MySQL.Async.execute('INSERT INTO owned_vehicles (owner,plate,vehicle) VALUES (@o,@p,@v)', { ['@o']=id, ['@p']=l.plate, ['@v']=l.vehicle_data })
        TriggerClientEvent('lunatic-rynek:listingExpired', playerId, l.vehicle_label..' ['..l.plate..']', 1)
        MySQL.Async.execute('DELETE FROM lunatic_rynek_vehicles WHERE id = @id', { ['@id']=l.id })
    end
end)

print('^2[lunatic-rynek]^7 Rynek zaladowany. Uzyj /' .. Config.Command .. ' aby otworzyc.')