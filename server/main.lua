local QBCore = exports['qb-core']:GetCoreObject()
local inventory = exports['qb-inventory']
local recipes, recipesByBlueprint, blueprints, queues, locks = {}, {}, {}, {}, {}

local function integer(value, minimum)
    return type(value) == 'number' and value == math.floor(value) and value >= minimum and value < math.huge
end

assert(integer(Config.QueueLimit, 1) and Config.QueueLimit <= 100, 'QueueLimit must be a whole number from 1 to 100')

for _, category in ipairs(exports['skill_tree']:GetBlueprintCatalog()) do
    for _, node in ipairs(category.nodes) do
        blueprints[node.id] = { item = node.item, category = category.id, label = node.label }
    end
end
for id, station in pairs(Config.Stations) do
    assert(type(id) == 'string' and type(station.label) == 'string' and station.coords and type(station.distance) == 'number' and station.distance > 0, 'Invalid crafting station')
end
for _, recipe in ipairs(Config.Recipes) do
    assert(type(recipe.id) == 'string' and recipe.id ~= '' and not recipes[recipe.id], 'Invalid or duplicate recipe ID')
    local blueprint = type(recipe.blueprint) == 'string' and blueprints[recipe.blueprint]
    assert(blueprint, 'Unknown blueprint for ' .. recipe.id)
    assert(not recipe.item or recipe.item == blueprint.item, 'Recipe output must match skill_tree item for ' .. recipe.id)
    assert(not recipe.category or recipe.category == blueprint.category, 'Recipe category must match skill_tree category for ' .. recipe.id)
    recipe.item = blueprint.item
    assert(QBCore.Shared.Items[recipe.item], 'Unknown output for ' .. recipe.id)
    assert(integer(recipe.amount, 1) and integer(recipe.duration, 1) and recipe.duration <= 600000 and integer(recipe.xp, 0) and recipe.xp <= 1000000, 'Invalid amounts or duration for ' .. recipe.id)
    assert(not QBCore.Shared.Items[recipe.item].unique or recipe.amount == 1, 'Unique outputs must have amount 1: ' .. recipe.id)
    assert(type(recipe.ingredients) == 'table' and #recipe.ingredients > 0, 'Missing ingredients for ' .. recipe.id)
    local seen = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        assert(type(ingredient.item) == 'string' and QBCore.Shared.Items[ingredient.item] and not seen[ingredient.item], 'Unknown or duplicate ingredient for ' .. recipe.id)
        assert(integer(ingredient.amount, 1), 'Invalid ingredient amount for ' .. recipe.id)
        seen[ingredient.item] = true
    end
    recipes[recipe.id] = recipe
    recipesByBlueprint[recipe.blueprint] = recipesByBlueprint[recipe.blueprint] or {}
    table.insert(recipesByBlueprint[recipe.blueprint], recipe)
end

local function nearStation(src, id)
    local station = type(id) == 'string' and Config.Stations[id]
    local ped = GetPlayerPed(src)
    if not station or not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - station.coords) <= station.distance
end

local function samePlayer(src, citizenid)
    local player = QBCore.Functions.GetPlayer(src)
    return player and player.PlayerData.citizenid == citizenid
end

local function itemCount(src, name)
    local count = inventory:GetItemCount(src, name)
    assert(type(count) == 'number', 'Unable to read inventory for player ' .. tostring(src))
    return count
end

local function collection(citizenid, stationId)
    local id = ('crafting_table:%s:%s'):format(citizenid, stationId)
    inventory:CreateInventory(id, { label = Config.Stations[stationId].label .. ' - Crafted Items', maxweight = 10000000, slots = 100 })
    return id, assert(inventory:GetInventory(id), 'Unable to load crafting collection')
end

local function escrow(citizenid, stationId)
    local id = ('crafting_table:materials:%s:%s'):format(citizenid, stationId)
    inventory:CreateInventory(id, { label = Config.Stations[stationId].label .. ' - Reserved Materials', maxweight = 100000000, slots = 1000 })
    return id, assert(inventory:GetInventory(id), 'Unable to load reserved materials')
end

local function collectionCount(stash)
    local count = 0
    for _, item in pairs(stash.items) do count = count + item.amount end
    return count
end

local function availableSlot(stash, limit)
    local occupied = {}
    for _, item in pairs(stash.items) do occupied[item.slot] = true end
    for slot = 1, limit do if not occupied[slot] then return slot end end
end

local function queueState(src)
    local queue = queues[src]
    local result = {}
    if not queue then return result end
    for index, job in ipairs(queue.jobs) do
        local remaining = job.recipe.duration
        if index == 1 and job.started then
            local elapsed = (GetGameTimer() - job.started) & 0xffffffff
            remaining = math.max(0, job.recipe.duration - elapsed)
        end
        result[#result + 1] = {
            label = blueprints[job.recipe.blueprint].label,
            duration = job.recipe.duration,
            remaining = remaining,
        }
    end
    return result
end

local function state(src, stationId)
    local player = assert(QBCore.Functions.GetPlayer(src), 'Player unavailable')
    local citizenid = player.PlayerData.citizenid
    local categories, level = exports['skill_tree']:GetUnlockedBlueprints(src)
    assert(type(categories) == 'table' and type(level) == 'table', 'Unable to load skill progress for player ' .. tostring(src))
    assert(samePlayer(src, citizenid) and nearStation(src, stationId), 'Player or station changed while loading blueprints')
    local _, stash = collection(citizenid, stationId)
    local _, reserved = escrow(citizenid, stationId)
    local active = queues[src] and queues[src].station == stationId
    local result = { station = Config.Stations[stationId].label, categories = {}, recipes = {}, queue = queueState(src), queueLimit = Config.QueueLimit, collectionCount = collectionCount(stash) + (active and 0 or collectionCount(reserved)), level = level }
    for _, category in ipairs(categories) do
        result.categories[#result.categories + 1] = { id = category.id, label = category.label, subtitle = category.subtitle, icon = category.icon }
        for _, node in ipairs(category.nodes) do
            local item = assert(QBCore.Shared.Items[node.item], 'Unknown skill_tree item ' .. node.item)
            local matches = recipesByBlueprint[node.id]
            if not matches then
                result.recipes[#result.recipes + 1] = { id = 'skill:' .. node.id, category = category.id, label = node.label, image = item.image, configured = false }
            else
                for _, recipe in ipairs(matches) do
                    local entry = { id = 'recipe:' .. recipe.id, recipeId = recipe.id, category = category.id, label = node.label, image = item.image, configured = true, amount = recipe.amount, duration = recipe.duration, xp = recipe.xp, ingredients = {} }
                    for _, ingredient in ipairs(recipe.ingredients) do
                        local info = QBCore.Shared.Items[ingredient.item]
                        entry.ingredients[#entry.ingredients + 1] = { label = info.label, image = info.image, amount = ingredient.amount, owned = itemCount(src, ingredient.item) }
                    end
                    result.recipes[#result.recipes + 1] = entry
                end
            end
        end
    end
    return result
end

local function protected(src, fn)
    local result = table.pack(xpcall(fn, debug.traceback))
    if not result[1] then
        print(('[crafting_table] Player %s: %s'):format(src, result[2]))
        return false, 'Crafting service unavailable. Please try again.'
    end
    return table.unpack(result, 2, result.n)
end

local function withLock(src, fn)
    while locks[src] do Wait(0) end
    locks[src] = true
    local result = table.pack(xpcall(fn, debug.traceback))
    locks[src] = nil
    if not result[1] then error(result[2]) end
    return table.unpack(result, 2, result.n)
end

QBCore.Functions.CreateCallback('crafting_table:state', function(src, cb, stationId)
    if not QBCore.Functions.GetPlayer(src) or not nearStation(src, stationId) then
        cb({ ok = false, error = 'You must be at a crafting table.' }); return
    end
    local ok, result = protected(src, function() return true, state(src, stationId) end)
    cb(ok and { ok = true, data = result } or { ok = false, error = result })
end)

local function rollback(src, removed)
    for i = #removed, 1, -1 do
        local item = removed[i]
        local callOk, added = xpcall(function()
            return inventory:AddItem(src, item.name, item.amount, item.slot, item.info, 'crafting_table:rollback')
        end, debug.traceback)
        if not callOk or not added then
            print(('[crafting_table] REFUND FAILED player=%s item=%s amount=%s slot=%s error=%s; manual restoration required'):format(src, item.name, item.amount, item.slot, callOk and 'rejected' or tostring(added)))
            TriggerClientEvent('QBCore:Notify', src, 'A material refund failed. Contact an administrator.', 'error')
        end
    end
end

local startNext
local function complete(src, queue, job)
    if queues[src] ~= queue or queue.jobs[1] ~= job then return end
    local lockedOk, lockedMessage = protected(src, function() return withLock(src, function()
      local ok, message = protected(src, function()
        if queues[src] ~= queue or queue.jobs[1] ~= job then return false, 'Craft cancelled.' end
        if not samePlayer(src, job.citizenid) then return false, 'Player unavailable.' end
        local recipe = job.recipe
        if not exports['skill_tree']:IsBlueprintUnlocked(src, recipe.blueprint) then return false, 'Craft cancelled: blueprint no longer unlocked. Collect your reserved materials at the workstation.' end
        if not samePlayer(src, job.citizenid) or queues[src] ~= queue or queue.jobs[1] ~= job then return false, 'Craft cancelled: player changed.' end
        local stashId, stash = collection(job.citizenid, job.station)
        if stash.isOpen then return false, 'Close your crafting collection before crafting completes.' end
        local outputSlot = availableSlot(stash, 100)
        if not outputSlot then return false, 'Crafting collection is full. Collect your reserved materials at the workstation.' end
        local escrowId = escrow(job.citizenid, job.station)
        local consumed = {}
        local function restoreConsumed()
            local restored = true
            for _, item in ipairs(consumed) do
                local callOk, added = xpcall(function()
                    return inventory:AddItem(escrowId, item.name, item.amount, item.slot, item.info, 'crafting_table:materials_rollback')
                end, debug.traceback)
                if not callOk or not added then
                    restored = false
                    print(('[crafting_table] MATERIAL RESTORE FAILED player=%s citizenid=%s item=%s amount=%s slot=%s error=%s; manual restoration required'):format(src, job.citizenid, item.name, item.amount, item.slot, callOk and 'rejected' or tostring(added)))
                end
            end
            return restored
        end
        for _, item in ipairs(job.materials) do
            local callOk, removed = xpcall(function()
                return inventory:RemoveItem(escrowId, item.name, item.amount, item.slot, 'crafting_table:consume')
            end, debug.traceback)
            if not callOk or not removed then
                local restored = restoreConsumed()
                if not callOk then
                    print(('[crafting_table] Material consumption outcome unknown player=%s citizenid=%s item=%s amount=%s slot=%s error=%s; manual investigation required'):format(src, job.citizenid, item.name, item.amount, item.slot, removed))
                end
                if not callOk or not restored then return false, 'Crafting failed. Contact an administrator.' end
                return false, 'Craft cancelled. Collect your reserved materials at the workstation.'
            end
            consumed[#consumed + 1] = item
        end
        local addOk, added = xpcall(function()
            return inventory:AddItem(stashId, recipe.item, recipe.amount, outputSlot, false, 'crafting_table:craft')
        end, debug.traceback)
        if not addOk then
            print(('[crafting_table] Craft output outcome unknown player=%s citizenid=%s recipe=%s error=%s; manual investigation required'):format(src, job.citizenid, recipe.id, added))
            return false, 'Crafting failed. Contact an administrator.'
        end
        if not added then
            if not restoreConsumed() then return false, 'Material restoration failed. Contact an administrator.' end
            return false, 'Crafting collection is full. Collect your reserved materials at the workstation.'
        end
        if recipe.xp > 0 then
            local xpCallOk, xpOk, xpMessage = xpcall(function() return exports['skill_tree']:AddXP(src, recipe.xp) end, debug.traceback)
            if not xpCallOk or not xpOk then
                if not xpCallOk then xpMessage = xpOk end
                print(('[crafting_table] XP award failed player=%s recipe=%s: %s'):format(src, recipe.id, tostring(xpMessage)))
                return true, 'Craft complete, but skill XP could not be awarded. Contact an administrator.'
            end
        end
        return true, ('%s is ready to collect at the workstation.'):format(QBCore.Shared.Items[recipe.item].label)
      end)
        if queues[src] ~= queue or queue.jobs[1] ~= job then return true end
        table.remove(queue.jobs, 1)
        if not samePlayer(src, job.citizenid) then
            queues[src] = nil
            return true
        end
        TriggerClientEvent('crafting_table:result', src, ok, message)
        startNext(src, queue)
        return true
    end) end)
    if not lockedOk and queues[src] == queue then
        queues[src] = nil
        if samePlayer(src, job.citizenid) then
            TriggerClientEvent('crafting_table:result', src, false, lockedMessage)
            TriggerClientEvent('crafting_table:queue', src, {})
        end
    end
end

startNext = function(src, queue)
    while queues[src] == queue and #queue.jobs > 0 do
        local job = queue.jobs[1]
        local ok, message = protected(src, function()
            if not samePlayer(src, job.citizenid) then return false, 'Crafting queue cancelled: player changed.' end
            if not exports['skill_tree']:IsBlueprintUnlocked(src, job.recipe.blueprint) then return false, 'Craft cancelled: blueprint no longer unlocked. Collect your reserved materials at the workstation.' end
            if queues[src] ~= queue or not samePlayer(src, job.citizenid) then return false, 'Crafting queue cancelled: player changed.' end
            return true
        end)
        if queues[src] ~= queue then return end
        if ok then
            job.started = GetGameTimer()
            SetTimeout(job.recipe.duration, function() complete(src, queue, job) end)
            TriggerClientEvent('crafting_table:queue', src, queueState(src))
            return
        end
        table.remove(queue.jobs, 1)
        if samePlayer(src, job.citizenid) then TriggerClientEvent('crafting_table:result', src, false, message) end
        if not samePlayer(src, job.citizenid) then break end
    end
    if queues[src] == queue then
        queues[src] = nil
        if samePlayer(src, queue.citizenid) then TriggerClientEvent('crafting_table:queue', src, {}) end
    end
end

local function reserveMaterials(src, job)
    local id = escrow(job.citizenid, job.station)
    job.materials = {}
    for _, ingredient in ipairs(job.recipe.ingredients) do
        local remaining = ingredient.amount
        for _, item in ipairs(inventory:GetItemsByName(src, ingredient.item)) do
            if remaining <= 0 then break end
            if not samePlayer(src, job.citizenid) or not nearStation(src, job.station) then return false, 'Player or station changed.' end
            local stash = assert(inventory:GetInventory(id), 'Reserved materials unavailable')
            local slot = availableSlot(stash, 1000)
            if not slot or stash.isOpen then return false, 'Reserved materials storage is unavailable or full.' end
            local amount = math.min(remaining, item.amount)
            local saved = { name = item.name, amount = amount, slot = slot, info = item.info }
            local playerSlot = item.slot
            local callOk, removed = xpcall(function()
                return inventory:RemoveItem(src, item.name, amount, playerSlot, 'crafting_table:reserve')
            end, debug.traceback)
            if not callOk then
                print(('[crafting_table] Material withdrawal outcome unknown player=%s citizenid=%s item=%s amount=%s slot=%s error=%s; manual investigation required'):format(src, job.citizenid, item.name, amount, playerSlot, removed))
                return false, 'Material withdrawal failed. Contact an administrator.'
            end
            if not removed then return false, 'Unable to remove materials.' end
            local addOk, added = xpcall(function()
                return inventory:AddItem(id, saved.name, saved.amount, saved.slot, saved.info, 'crafting_table:reserve')
            end, debug.traceback)
            if not addOk then
                print(('[crafting_table] Material reservation outcome unknown player=%s citizenid=%s item=%s amount=%s slot=%s error=%s; manual investigation required'):format(src, job.citizenid, saved.name, saved.amount, saved.slot, added))
                return false, 'Material reservation failed. Contact an administrator.'
            end
            if not added then
                if samePlayer(src, job.citizenid) then
                    rollback(src, { { name = saved.name, amount = saved.amount, slot = playerSlot, info = saved.info } })
                else
                    print(('[crafting_table] REFUND FAILED player=%s citizenid=%s item=%s amount=%s; player changed, manual restoration required'):format(src, job.citizenid, saved.name, saved.amount))
                end
                return false, 'Unable to reserve materials; check your collection and contact an administrator if anything is missing.'
            end
            job.materials[#job.materials + 1] = saved
            remaining = remaining - amount
        end
        if remaining > 0 then return false, 'Materials changed while queuing.' end
    end
    return true
end

QBCore.Functions.CreateCallback('crafting_table:craft', function(src, cb, stationId, recipeId)
    local player = QBCore.Functions.GetPlayer(src)
    local recipe = type(recipeId) == 'string' and recipes[recipeId]
    if not player or not nearStation(src, stationId) then cb({ ok = false, error = 'You must be at a crafting table.' }); return end
    if not recipe then cb({ ok = false, error = 'Unknown recipe.' }); return end
    local job = { citizenid = player.PlayerData.citizenid, station = stationId, recipe = recipe }
    local ok, message, snapshot = protected(src, function() return withLock(src, function()
        local queue = queues[src]
        if not samePlayer(src, job.citizenid) or not nearStation(src, stationId) then return false, 'Player or station changed.' end
        if queue and (queue.citizenid ~= job.citizenid or queue.station ~= stationId) then return false, 'Finish the current queue at its workstation first.' end
        if queue and #queue.jobs >= Config.QueueLimit then return false, 'Crafting queue is full.' end
        local _, stash = collection(job.citizenid, stationId)
        if stash.isOpen then return false, 'Close your crafting collection first.' end
        if not exports['skill_tree']:IsBlueprintUnlocked(src, recipe.blueprint) then return false, 'Learn this blueprint in the skill tree first.' end
        if not samePlayer(src, job.citizenid) or queues[src] ~= queue or not nearStation(src, stationId) then return false, 'Player or station changed.' end
        for _, ingredient in ipairs(recipe.ingredients) do
            if itemCount(src, ingredient.item) < ingredient.amount then return false, 'Not enough materials for this craft.' end
        end
        if not samePlayer(src, job.citizenid) or queues[src] ~= queue or not nearStation(src, stationId) then return false, 'Player or station changed.' end
        local reserved, reserveError = reserveMaterials(src, job)
        if not reserved then return false, reserveError .. ' Any reserved materials can be collected when the queue ends.' end
        if not samePlayer(src, job.citizenid) or queues[src] ~= queue or not nearStation(src, stationId) then
            return false, 'Player or station changed. Collect the reserved materials at the workstation.'
        end
        if not queue then
            queue = { citizenid = job.citizenid, station = stationId, jobs = {} }
            queues[src] = queue
        end
        queue.jobs[#queue.jobs + 1] = job
        if #queue.jobs == 1 then startNext(src, queue) end
        if queues[src] ~= queue then return false, 'Unable to start crafting.' end
        return true, #queue.jobs == 1 and 'Crafting started.' or 'Added to crafting queue.', queueState(src)
    end) end)
    if not ok then
        cb({ ok = false, error = message }); return
    end
    cb({ ok = true, message = message, queue = snapshot })
end)

QBCore.Functions.CreateCallback('crafting_table:collect', function(src, cb, stationId)
    local player = QBCore.Functions.GetPlayer(src)
    if not player or not nearStation(src, stationId) then
        cb({ ok = false, error = 'You must be at a crafting table.' }); return
    end
    local citizenid = player.PlayerData.citizenid
    local ok, message, remaining = protected(src, function() return withLock(src, function()
        if not samePlayer(src, citizenid) or not nearStation(src, stationId) then return false, 'Player or station changed.' end
        local queue = queues[src]
        if queue and queue.station == stationId then return false, 'Wait for the crafting queue to finish before collecting.' end
        local id, stash = collection(citizenid, stationId)
        local materialsId, materials = escrow(citizenid, stationId)
        if stash.isOpen or materials.isOpen then return false, 'Crafting collection is already open.' end
        if collectionCount(stash) + collectionCount(materials) == 0 then return false, 'No items to collect.' end
        local function remainingCount()
            return collectionCount(assert(inventory:GetInventory(id), 'Crafting collection unavailable'))
                + collectionCount(assert(inventory:GetInventory(materialsId), 'Reserved materials unavailable'))
        end
        local function restore(item, amount)
            local restoreOk, restored = xpcall(function()
                return inventory:AddItem(item.storage, item.name, amount, item.slot, item.info, 'crafting_table:collect_rollback')
            end, debug.traceback)
            if not restoreOk or not restored then
                print(('[crafting_table] COLLECTION RESTORE FAILED player=%s citizenid=%s item=%s amount=%s slot=%s error=%s; manual restoration required'):format(src, citizenid, item.name, amount, item.slot, restoreOk and 'rejected' or tostring(restored)))
                return false
            end
            return true
        end
        local entries = {}
        for _, storage in ipairs({ { id = id, items = stash.items }, { id = materialsId, items = materials.items } }) do
            for _, item in pairs(storage.items) do
                entries[#entries + 1] = { storage = storage.id, name = item.name, amount = item.amount, slot = item.slot, info = item.info }
            end
        end
        table.sort(entries, function(a, b)
            if a.storage == b.storage then return a.slot < b.slot end
            return a.storage == id
        end)
        local collected = 0
        for _, item in ipairs(entries) do
            local left = item.amount
            while left > 0 do
                if not samePlayer(src, citizenid) or not nearStation(src, stationId) then
                    return false, 'Player or station changed; uncollected items remain in storage.', remainingCount()
                end
                local definition = QBCore.Shared.Items[item.name]
                if not definition then
                    print(('[crafting_table] Unknown collection item player=%s item=%s slot=%s'):format(src, item.name, item.slot))
                    return false, 'An item in your collection is unavailable. Contact an administrator.', remainingCount()
                end
                local low, high = 0, definition.unique and 1 or left
                while low < high do
                    local amount = math.floor((low + high + 1) / 2)
                    local fits, reason = inventory:CanAddItem(src, item.name, amount)
                    if fits then low = amount
                    elseif reason == 'weight' or reason == 'slots' then high = amount - 1
                    else
                        print(('[crafting_table] Cannot check collection capacity player=%s item=%s reason=%s'):format(src, item.name, tostring(reason)))
                        return false, 'Unable to check inventory space. Please try again.', remainingCount()
                    end
                end
                if low == 0 then break end
                local removeOk, removed = xpcall(function()
                    return inventory:RemoveItem(item.storage, item.name, low, item.slot, 'crafting_table:collect')
                end, debug.traceback)
                if not removeOk then
                    print(('[crafting_table] Collection removal error player=%s item=%s amount=%s slot=%s: %s'):format(src, item.name, low, item.slot, removed))
                    return false, 'Collection transfer failed. Contact an administrator.', remainingCount()
                end
                if not removed then return false, 'Unable to withdraw an item from the collection.', remainingCount() end
                if not samePlayer(src, citizenid) or not nearStation(src, stationId) then
                    if not restore(item, low) then return false, 'Collection restoration failed. Contact an administrator.', remainingCount() end
                    return false, 'Player or station changed; uncollected items remain in storage.', remainingCount()
                end
                local addOk, added = xpcall(function()
                    return inventory:AddItem(src, item.name, low, false, item.info, 'crafting_table:collect')
                end, debug.traceback)
                if not addOk then
                    print(('[crafting_table] Collection transfer outcome unknown player=%s citizenid=%s item=%s amount=%s slot=%s error=%s; manual investigation required'):format(src, citizenid, item.name, low, item.slot, added))
                    return false, 'Collection transfer failed. Contact an administrator.', remainingCount()
                end
                if not added then
                    if not restore(item, low) then return false, 'Collection restoration failed. Contact an administrator.', remainingCount() end
                    return false, 'Unable to add an item to your inventory; it remains in your collection.', remainingCount()
                end
                collected = collected + low
                left = left - low
            end
        end
        local remaining = remainingCount()
        if collected == 0 then return false, 'Your inventory is full; items remain in your collection.', remaining end
        if remaining > 0 then return true, ('Collected %s item(s). %s remain because your inventory is full.'):format(collected, remaining), remaining end
        return true, ('Collected %s item(s).'):format(collected), remaining
    end) end)
    cb({ ok = ok, message = ok and message or nil, error = not ok and message or nil, collectionCount = remaining })
end)

AddEventHandler('playerDropped', function() queues[source] = nil end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) queues[src] = nil end)
