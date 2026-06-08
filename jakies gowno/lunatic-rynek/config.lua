Config = {}

Config.Command = 'rynek'

Config.MaxListings = 5

Config.Tax = 0.05

Config.MinPrice = 10

Config.MaxPrice = 10000000

Config.ListingDurations = {
    { label = '1 godzina',  seconds = 3600 },
    { label = '6 godzin',   seconds = 21600 },
    { label = '12 godzin',  seconds = 43200 },
    { label = '24 godziny', seconds = 86400 },
    { label = '3 dni',      seconds = 259200 },
    { label = '7 dni',      seconds = 604800 },
}

Config.BlacklistedItems = {
    'money',
    'black_money',
}

Config.ExpiredCheckInterval = 60

Config.MaxVehicleListings = 3

Config.VehicleTax = 0.05

Config.VehicleMinPrice = 1000

Config.VehicleMaxPrice = 50000000

Config.BlacklistedVehicles = {
}