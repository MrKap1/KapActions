fx_version 'cerulean'
game 'gta5'

author 'Kap'
description 'KapActions for QBox - Interactive Player Actions'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'qbx_core',
    'ox_target',
    'ox_inventory',
    'ox_lib'
}