local callbacks, events, nui, timers, messages = {}, {}, {}, {}, {}
local active, thread, press = {}, nil, true
local vec = {}
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end
function CreateThread(fn) thread = coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetEntityCoords() return vector3(-211.4, -1324.6, 30.9) end
function PlayerPedId() return 1 end
function DrawMarker() end
function IsControlJustReleased() local value = press; press = false; return value end
function SetNuiFocus() end
function SendNUIMessage(message) messages[#messages + 1] = message end
function SetTimeout(_, fn) timers[#timers + 1] = fn end
function RegisterNUICallback(name, fn) nui[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function TriggerEvent() end
local core = { Functions = {} }
function core.Functions.DrawText3D() end
function core.Functions.Notify() end
function core.Functions.TriggerCallback(name, callback)
    assert(not active[name], 'same callback name must not overlap')
    active[name] = true
    callbacks[#callbacks + 1] = { name = name, callback = callback }
end
exports = { ['qb-core'] = { GetCoreObject = function() return core end } }
dofile('config.lua')
Config.Interaction = 'marker'
dofile('client/main.lua')

local function respond(data)
    local request = table.remove(callbacks, 1)
    assert(request)
    request.callback(data or { ok = true, data = {} })
    active[request.name] = nil -- QBCore clears its callback after invoking it.
    while #timers > 0 do table.remove(timers, 1)() end
end
assert(coroutine.resume(thread))
assert(active['crafting_table:state'], 'opening should request state')
respond()
assert(messages[#messages].action == 'open')
local refreshed = false
nui.refresh({}, function(result) refreshed = result.ok end)
events['crafting_table:result'](true, 'done')
assert(#callbacks == 1, 'result refresh should wait for the first state request')
respond()
assert(refreshed and #callbacks == 1, 'queued state request should start after QBCore clears the previous callback')
respond()
assert(messages[#messages].action == 'update')
events['skill_tree:update']({ levelProgress = { level = 2, xp = 5, required = 125 } })
assert(messages[#messages].action == 'level' and messages[#messages].level.level == 2, 'open workshop must receive live level updates')
events['crafting_table:queue']({ { label = 'Lockpick', duration = 5000, remaining = 4000 } })
assert(messages[#messages].action == 'queue' and messages[#messages].queue[1].remaining == 4000, 'open workshop must receive live queue updates')
local crafted
nui.craft({ id = 'lockpick' }, function(result) crafted = result.ok end)
assert(callbacks[1].name == 'crafting_table:craft', 'craft must request the server reservation')
respond({ ok = true, queue = {} })
assert(crafted and callbacks[1].name == 'crafting_table:state', 'craft must refresh inventory amounts')
respond()
local collected
nui.collect({}, function(result) collected = result.ok end)
assert(callbacks[1].name == 'crafting_table:collect', 'collection must request a server transfer')
respond({ ok = true, collectionCount = 0 })
assert(collected and callbacks[1].name == 'crafting_table:state', 'collection must keep the workshop open and refresh state')
respond()
assert(messages[#messages].action == 'update', 'collection should refresh the workshop')
print('crafting_table client tests passed')
