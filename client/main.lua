local QBCore = exports['qb-core']:GetCoreObject()
local opened, stationId, requesting, requestId = false, nil, false, 0
local stateRequests, statePending = {}, false

local function requestState(id, callback)
    stateRequests[#stateRequests + 1] = { id = id, callback = callback }
    if statePending then return end
    local function nextRequest()
        local request = table.remove(stateRequests, 1)
        if not request then statePending = false; return end
        statePending = true
        QBCore.Functions.TriggerCallback('crafting_table:state', function(result)
            request.callback(result)
            SetTimeout(0, nextRequest)
        end, request.id)
    end
    nextRequest()
end

local function close()
    opened, stationId = false, nil
    requesting, requestId = false, requestId + 1
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function open(id)
    if opened or requesting then return end
    requesting = true
    requestId = requestId + 1
    local currentRequest = requestId
    requestState(id, function(result)
        if currentRequest ~= requestId then return end
        requesting = false
        if not result.ok then QBCore.Functions.Notify(result.error, 'error'); return end
        opened, stationId = true, id
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', data = result.data })
    end)
end

assert(Config.Interaction == 'marker' or Config.Interaction == 'interact' or Config.Interaction == 'qb-target',
    "Config.Interaction must be 'marker', 'interact', or 'qb-target'")
if Config.Interaction == 'qb-target' then
    assert(type(Config.TargetRadius) == 'number' and Config.TargetRadius > 0 and Config.TargetRadius < math.huge,
        'Config.TargetRadius must be a positive number')
elseif Config.Interaction == 'interact' then
    assert(type(Config.DrawDistance) == 'number' and Config.DrawDistance > 0 and Config.DrawDistance < math.huge,
        'Config.DrawDistance must be a positive number')
end
local registered = {}

local function registerInteractions()
    local provider = Config.Interaction
    if provider == 'marker' then return end
    if GetResourceState(provider) ~= 'started' then
        print(('[crafting_table] %s is not started; workstation interactions will register when it starts.'):format(provider))
        return
    end
    for id, station in pairs(Config.Stations) do
        if not registered[id] then
            local interactionId = ('crafting_table:%s'):format(id)
            local function available()
                return not opened and not requesting and #(GetEntityCoords(PlayerPedId()) - station.coords) <= station.distance
            end
            if provider == 'interact' then
                local added = exports.interact:AddInteraction({
                    id = interactionId,
                    coords = station.coords,
                    distance = math.max(Config.DrawDistance, station.distance),
                    interactDst = station.distance,
                    options = { { label = 'Open crafting table', canInteract = available, action = function() open(id) end } },
                })
                assert(added, 'Unable to register interaction ' .. interactionId)
            else
                local added = exports['qb-target']:AddCircleZone(interactionId, station.coords, Config.TargetRadius,
                    { name = interactionId, useZ = true, debugPoly = false },
                    { options = { { icon = 'fas fa-hammer', label = 'Open crafting table', canInteract = available, action = function() open(id) end } },
                        distance = station.distance })
                assert(added, 'Unable to register target zone ' .. interactionId)
            end
            registered[id] = interactionId
        end
    end
end

if Config.Interaction == 'marker' then
    CreateThread(function()
        while true do
            local wait = 1000
            local coords = GetEntityCoords(PlayerPedId())
            for id, station in pairs(Config.Stations) do
                local distance = #(coords - station.coords)
                if distance < Config.DrawDistance then
                    wait = 0
                    DrawMarker(2, station.coords.x, station.coords.y, station.coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.18, 0.18, 0.18, 220, 220, 220, 180, false, false, 2, false, nil, nil, false)
                    if distance <= station.distance and not opened then
                        QBCore.Functions.DrawText3D(station.coords.x, station.coords.y, station.coords.z + 0.4, '[E] Crafting table')
                        if IsControlJustReleased(0, Config.InteractKey) then open(id) end
                    end
                end
            end
            Wait(wait)
        end
    end)
else
    CreateThread(registerInteractions)
    AddEventHandler('onClientResourceStart', function(resource)
        if resource == Config.Interaction then registerInteractions() end
    end)
    AddEventHandler('onClientResourceStop', function(resource)
        if resource == Config.Interaction then
            registered = {}
            print(('[crafting_table] %s stopped; workstation interactions are unavailable until it restarts.'):format(resource))
        elseif resource == GetCurrentResourceName() and GetResourceState(Config.Interaction) == 'started' then
            for _, interactionId in pairs(registered) do
                if Config.Interaction == 'interact' then exports.interact:RemoveInteraction(interactionId)
                else exports['qb-target']:RemoveZone(interactionId) end
            end
        end
    end)
end

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('skills', function(_, cb)
    close()
    TriggerEvent('skill_tree:client:Open')
    cb({ ok = true })
end)
RegisterNUICallback('refresh', function(_, cb)
    if not stationId then cb({ ok = false, error = 'Workshop closed.' }); return end
    requestState(stationId, cb)
end)
RegisterNUICallback('craft', function(data, cb)
    if not stationId then cb({ ok = false, error = 'Workshop closed.' }); return end
    local currentRequest = requestId
    QBCore.Functions.TriggerCallback('crafting_table:craft', function(result)
        cb(result)
        if opened and currentRequest == requestId then
            requestState(stationId, function(stateResult)
                if opened and currentRequest == requestId and stateResult.ok then SendNUIMessage({ action = 'update', data = stateResult.data }) end
            end)
        end
    end, stationId, type(data) == 'table' and data.id)
end)
RegisterNUICallback('collect', function(_, cb)
    if not stationId then cb({ ok = false, error = 'Workshop closed.' }); return end
    local currentRequest = requestId
    QBCore.Functions.TriggerCallback('crafting_table:collect', function(result)
        cb(result)
        if opened and currentRequest == requestId then
            requestState(stationId, function(stateResult)
                if opened and currentRequest == requestId and stateResult.ok then SendNUIMessage({ action = 'update', data = stateResult.data }) end
            end)
        end
    end, stationId)
end)

RegisterNetEvent('crafting_table:result', function(ok, message)
    QBCore.Functions.Notify(message, ok and 'success' or 'error')
    if opened then
        SendNUIMessage({ action = 'result', ok = ok, message = message })
        local currentRequest = requestId
        requestState(stationId, function(result)
            if opened and currentRequest == requestId and result.ok then SendNUIMessage({ action = 'update', data = result.data }) end
        end)
    end
end)
RegisterNetEvent('crafting_table:queue', function(queue)
    if opened then SendNUIMessage({ action = 'queue', queue = queue }) end
end)
RegisterNetEvent('skill_tree:update', function(data)
    if opened and type(data) == 'table' and type(data.levelProgress) == 'table' then
        SendNUIMessage({ action = 'level', level = data.levelProgress })
    end
end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', close)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then close() end
end)
