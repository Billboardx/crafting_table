local vec = {}
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end
function PlayerPedId() return 1 end
local position = vector3(-211.4, -1324.6, 30.9)
function GetEntityCoords() return position end
function SetNuiFocus() end
function SendNUIMessage() end
function RegisterNUICallback() end
function GetCurrentResourceName() return 'crafting_table' end

local function test(provider, startsLate)
    local handlers, added, removed, requests, timers = {}, {}, {}, {}, {}
    local providerState = startsLate and 'stopped' or 'started'
    function GetResourceState(resource) return resource == provider and providerState or 'missing' end
    function AddEventHandler(name, fn) handlers[name] = fn end
    function RegisterNetEvent(name, fn) handlers[name] = fn end
    function SetTimeout(_, fn) timers[#timers + 1] = fn end
    function CreateThread(fn) fn() end
    local core = { Functions = {} }
    function core.Functions.TriggerCallback(name, callback, station)
        requests[#requests + 1] = { name = name, callback = callback, station = station }
    end
    local interact = {}
    function interact:AddInteraction(data) added[data.id] = data; return data.id end
    function interact:RemoveInteraction(id) removed[#removed + 1] = id; added[id] = nil end
    local target = {}
    function target:AddCircleZone(id, coords, radius, options, targetOptions)
        added[id] = { coords = coords, radius = radius, options = options, targetOptions = targetOptions }
        return added[id]
    end
    function target:RemoveZone(id) removed[#removed + 1] = id; added[id] = nil end
    exports = { ['qb-core'] = { GetCoreObject = function() return core end }, interact = interact, ['qb-target'] = target }
    dofile('config.lua')
    Config.Interaction = provider
    Config.Stations.second = { label = 'Second', coords = vector3(0, 0, 0), distance = 1.5 }
    dofile('client/main.lua')

    if startsLate then
        assert(not next(added), 'missing provider must not register points')
        providerState = 'started'
        handlers.onClientResourceStart(provider)
    end
    local first, second = added['crafting_table:workshop'], added['crafting_table:second']
    assert(first and second, provider .. ' must register all workstations')
    local options = provider == 'interact' and first.options or first.targetOptions.options
    assert(options[1].canInteract(), 'interaction should be available near its station')
    if provider == 'interact' then
        assert(first.interactDst == 2 and first.distance >= first.interactDst)
    else
        assert(first.radius == Config.TargetRadius and first.options.useZ and first.targetOptions.distance == 2)
    end
    options[1].action()
    assert(#requests == 1 and requests[1].station == 'workshop', 'interaction must open the selected station')
    assert(not options[1].canInteract(), 'interaction should be unavailable while opening')
    requests[1].callback({ ok = true, data = {} })
    while #timers > 0 do table.remove(timers, 1)() end
    assert(not options[1].canInteract(), 'interaction should be unavailable while open')
    position = vector3(0, 0, 0)
    local secondOptions = provider == 'interact' and second.options or second.targetOptions.options
    assert(not secondOptions[1].canInteract(), 'interaction should be unavailable while another station is open')
    handlers['QBCore:Client:OnPlayerUnload']()
    assert(secondOptions[1].canInteract() and not options[1].canInteract(), 'distance must be checked against the selected station')
    secondOptions[1].action()
    assert(#requests == 2 and requests[2].station == 'second', 'station callbacks must not share loop variables')

    providerState = 'stopped'
    handlers.onClientResourceStop(provider)
    added = {}
    providerState = 'started'
    handlers.onClientResourceStart(provider)
    assert(added['crafting_table:workshop'] and added['crafting_table:second'], 'interactions must return after provider restart')
    handlers.onClientResourceStart(provider)
    local count = 0
    for _ in pairs(added) do count = count + 1 end
    assert(count == 2, 'repeated starts must not register duplicates')
    handlers.onClientResourceStop('crafting_table')
    assert(#removed == 2 and not next(added), 'resource stop must remove only its own interactions')
    position = vector3(-211.4, -1324.6, 30.9)
end

test('interact', true)
test('qb-target')
print('crafting_table interaction tests passed')
