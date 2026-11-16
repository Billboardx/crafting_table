fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Crafting Skills'
description 'Skill-tree linked crafting workstations'
version '1.0.0'

shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'
ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/app.js' }
dependencies { 'qb-core', 'qb-inventory', 'skill_tree' }
