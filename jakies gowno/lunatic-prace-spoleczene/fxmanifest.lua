fx_version 'cerulean'
game 'gta5'

lua54 'yes'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/minigames.lua',
    'server/integrations.lua',
    'server/commands.lua',
}

client_scripts {
    'client/main.lua',
    'client/ped_camera.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'es_extended',
    'oxmysql',
}