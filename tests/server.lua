local callbacks, events, timers, notifications, stashes = {}, {}, {}, {}, {}
local unlocked, items, awards, failAdd, failRemove, xpFailure = {}, {}, 0, false, nil, false
local player = { PlayerData = { citizenid = 'character-one' } }
local position, clock, capacity, slotsFull, failCollectAdd, moveOnWithdraw, failReserveAdd = 0, 0, math.huge, false, false, false, nil
local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end
function GetPlayerPed() return player and 1 or 0 end
function GetEntityCoords() return vector3(-211.4 + position, -1324.6, 30.9) end
function GetGameTimer() return clock end
function Wait() error('Unexpected lock contention in synchronous test') end
function SetTimeout(duration, fn) timers[#timers + 1] = { duration = duration, fn = fn } end
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function TriggerClientEvent(name, src, ...)
    if name == 'crafting_table:result' then notifications[#notifications + 1] = { ... } end
end
local core = { Shared = { Items = {} }, Functions = {} }
function core.Functions.GetPlayer() return player end
function core.Functions.CreateCallback(name, fn) callbacks[name] = fn end
for _, name in ipairs({ 'lockpick', 'repairkit', 'advancedlockpick', 'radio', 'copper', 'phone', 'metalscrap', 'plastic', 'steel', 'aluminum' }) do
    core.Shared.Items[name] = { name = name, label = name, image = name .. '.png', unique = name == 'phone' or name == 'radio' }
end
local inventory = {}
function inventory:GetItemCount(_, name)
    local count = 0
    for _, item in pairs(items) do if item.name == name then count = count + item.amount end end
    return count
end
function inventory:GetItemsByName(_, name)
    local matches = {}
    for _, item in pairs(items) do if item.name == name then matches[#matches + 1] = item end end
    table.sort(matches, function(a, b) return a.slot < b.slot end)
    return matches
end
function inventory:RemoveItem(target, name, amount, slot, reason)
    if failRemove == name then return false end
    local targetItems = type(target) == 'string' and assert(stashes[target]).items or items
    local key, item
    for candidate, value in pairs(targetItems) do
        if value.slot == slot then key, item = candidate, value; break end
    end
    assert(item and item.name == name and item.amount >= amount)
    item.amount = item.amount - amount
    if item.amount == 0 then targetItems[key] = nil end
    if reason == 'crafting_table:collect' and moveOnWithdraw then position = 3; moveOnWithdraw = false end
    return true
end
function inventory:CreateInventory(id)
    stashes[id] = stashes[id] or { items = {}, isOpen = false }
end
function inventory:GetInventory(id) return stashes[id] end
function inventory:CanAddItem(_, _, amount)
    if slotsFull then return false, 'slots' end
    local total = 0
    for _, item in pairs(items) do total = total + item.amount end
    if total + amount > capacity then return false, 'weight' end
    return true
end
function inventory:AddItem(target, name, amount, slot, info, reason)
    if failAdd and reason == 'crafting_table:craft' then return false end
    if failCollectAdd and reason == 'crafting_table:collect' then return false end
    if failReserveAdd == name and reason == 'crafting_table:reserve' then return false end
    local targetItems = type(target) == 'string' and assert(stashes[target]).items or items
    if not slot then
        slot = 1
        while targetItems[slot] do slot = slot + 1 end
    end
    if targetItems[slot] then
        assert(targetItems[slot].name == name)
        targetItems[slot].amount = targetItems[slot].amount + amount
    else
        targetItems[slot] = { name = name, amount = amount, slot = slot, info = info }
    end
    return true
end
local skills = {}
local catalog = {
    { id = 'essentials', label = 'Essentials', nodes = {
        { id = 'lockpick', label = 'Lockpick', item = 'lockpick' },
        { id = 'repairkit', label = 'Repair kit', item = 'repairkit' },
        { id = 'advancedlockpick', label = 'Advanced lockpick', item = 'advancedlockpick' },
    } },
    { id = 'electronics', label = 'Electronics', nodes = {
        { id = 'radio', label = 'Radio', item = 'radio' },
        { id = 'wiring', label = 'Wiring recovery', item = 'copper' },
        { id = 'phone', label = 'Phone', item = 'phone' },
        { id = 'new_skill', label = 'New skill', item = 'steel' },
    } },
}
function skills:GetBlueprintCatalog() return catalog end
function skills:GetUnlockedBlueprints()
    local result = {}
    for _, category in ipairs(catalog) do
        local entry = { id = category.id, label = category.label, nodes = {} }
        for _, node in ipairs(category.nodes) do
            if unlocked[node.id] then entry.nodes[#entry.nodes + 1] = node end
        end
        if #entry.nodes > 0 then result[#result + 1] = entry end
    end
    return result, { level = 1, xp = awards, required = 100 }
end
function skills:IsBlueprintUnlocked(_, id) return unlocked[id] == true end
function skills:AddXP(_, amount)
    if xpFailure then error('database unavailable') end
    awards = awards + amount
    return true, 'ok'
end
exports = { ['qb-core'] = { GetCoreObject = function() return core end }, ['qb-inventory'] = inventory, ['skill_tree'] = skills }
dofile('config.lua')
dofile('server/main.lua')

local function call(name, ...)
    local result
    callbacks['crafting_table:' .. name](1, function(value) result = value end, ...)
    assert(result, 'callback did not respond')
    return result
end
local function finish()
    local timer = table.remove(timers, 1)
    assert(timer, 'no craft timer')
    clock = clock + timer.duration
    timer.fn()
    return notifications[#notifications]
end
local function stock()
    for _, stash in pairs(stashes) do stash.items = {}; stash.isOpen = false end
    items = {
        [1] = { name = 'metalscrap', amount = 10, slot = 1, info = { batch = 'first' } },
        [2] = { name = 'metalscrap', amount = 12, slot = 2, info = { batch = 'second' } },
        [3] = { name = 'plastic', amount = 32, slot = 3, info = {} },
    }
end
local function count(name) return inventory:GetItemCount(1, name) end
local function stored(name)
    local stash = stashes['crafting_table:' .. player.PlayerData.citizenid .. ':workshop']
    local total = 0
    if stash then for _, item in pairs(stash.items) do if item.name == name then total = total + item.amount end end end
    return total
end
local function reserved(name)
    local stash = stashes['crafting_table:materials:' .. player.PlayerData.citizenid .. ':workshop']
    local total = 0
    if stash then for _, item in pairs(stash.items) do if item.name == name then total = total + item.amount end end end
    return total
end
local function start() return call('craft', 'workshop', 'lockpick') end

local state = call('state', 'workshop')
assert(state.ok and #state.data.recipes == 0 and #state.data.categories == 0, 'locked skills and empty categories must not be disclosed')
assert(not start().ok, 'locked blueprint must not craft')
unlocked.lockpick = true
stock()
state = call('state', 'workshop')
assert(#state.data.recipes == 1 and state.data.recipes[1].recipeId == 'lockpick' and state.data.recipes[1].ingredients[1].owned == 22 and state.data.level.level == 1 and state.data.level.required == 100, 'state must show learned recipes, level, and split-stack totals')
unlocked.new_skill = true
state = call('state', 'workshop')
assert(#state.data.categories == 2 and #state.data.recipes == 2 and state.data.recipes[2].id == 'skill:new_skill' and state.data.recipes[2].configured == false, 'new unlocked skills must appear automatically without an invented recipe')
assert(not call('craft', 'workshop', 'skill:new_skill').ok, 'unconfigured skills must not craft')
unlocked.new_skill = nil
assert(#call('state', 'workshop').data.recipes == 1, 'revoked skills must disappear')
position = 3
assert(not start().ok and not call('state', 'workshop').ok, 'station distance must be enforced')
position = 0
assert(start().ok and timers[1].duration == Config.Recipes[1].duration, 'craft should start with configured duration')
assert(count('metalscrap') == 0 and count('plastic') == 0 and reserved('metalscrap') == 22 and reserved('plastic') == 32, 'clicking craft must immediately reserve materials')
assert(call('state', 'workshop').data.recipes[1].ingredients[1].owned == 0, 'workshop state must show the deducted materials')
assert(not start().ok and #call('state', 'workshop').data.queue == 1, 'queued crafts must have sufficient combined materials')
local result = finish()
assert(result[1] and stored('lockpick') == 1 and reserved('metalscrap') == 0 and reserved('plastic') == 0 and count('lockpick') == 0 and awards == 15, 'successful craft must consume reserved materials, store output and award XP')
assert(call('state', 'workshop').data.level.xp == 15, 'state must refresh XP after crafting')

stock()
assert(start().ok)
position = 3
result = finish()
assert(result[1] and stored('lockpick') == 1 and count('metalscrap') == 0 and awards == 30, 'leaving station must not cancel a craft')
position = 0
stock()
assert(start().ok)
unlocked.lockpick = false
result = finish()
assert(not result[1] and reserved('plastic') == 32 and reserved('metalscrap') == 22, 'revoking a blueprint must leave reserved materials available')
unlocked.lockpick = true
assert(call('collect', 'workshop').ok and count('plastic') == 32 and count('metalscrap') == 22, 'cancelled craft materials must be collectable')
stock()
items[3].amount = 31
assert(not start().ok, 'insufficient materials must reject start')
stock()
assert(start().ok)
result = finish()
assert(result[1] and stored('lockpick') == 1, 'reserved materials must not need to remain in player inventory')

stock()
failAdd = true
assert(start().ok)
result = finish()
assert(not result[1] and reserved('metalscrap') == 22 and reserved('plastic') == 32, 'failed output must restore reserved materials')
assert(call('collect', 'workshop').ok and count('metalscrap') == 22 and count('plastic') == 32, 'failed output materials must be collectable')
failAdd = false
stock()
assert(start().ok)
failRemove = 'plastic'
result = finish()
assert(not result[1] and reserved('metalscrap') == 22 and reserved('plastic') == 32, 'failed material consumption must restore previously consumed reservations')
failRemove = nil
assert(call('collect', 'workshop').ok and count('metalscrap') == 22 and count('plastic') == 32, 'failed consumption materials must remain recoverable')
stock()
failRemove = 'plastic'
assert(not start().ok and reserved('metalscrap') == 22 and count('plastic') == 32, 'failed material removal must preserve earlier reservations')
failRemove = nil
assert(call('collect', 'workshop').ok and count('metalscrap') == 22, 'materials from a failed reservation must be collectable')
stock()
failReserveAdd = 'plastic'
assert(not start().ok and reserved('metalscrap') == 22 and count('plastic') == 32, 'rejected reservation must return the current stack and preserve earlier reservations')
failReserveAdd = nil
assert(call('collect', 'workshop').ok and count('metalscrap') == 22, 'earlier reservations must be recoverable after a rejected reservation')
stock()
xpFailure = true
assert(start().ok)
result = finish()
assert(result[1] and result[2]:find('XP could not be awarded', 1, true) and stored('lockpick') == 1, 'XP failure must not report a completed craft as cancelled')
xpFailure = false

stock()
assert(start().ok)
source = 1
events.playerDropped()
local savedPlayer = player
player = { PlayerData = { citizenid = 'character-two' } }
local previous = #notifications
finish()
assert(#notifications == previous and stored('lockpick') == 0, 'stale timer must not craft for a replacement player')
player = savedPlayer
assert(reserved('metalscrap') == 22 and call('collect', 'workshop').ok, 'disconnect must leave the original character’s reserved materials collectable')
player = { PlayerData = { citizenid = 'character-two' } }
stock()
assert(start().ok, 'disconnect must release the busy state')
finish()

stock()
assert(start().ok)
events['QBCore:Server:OnPlayerUnload'](1)
local before = #notifications
finish()
assert(#notifications == before and reserved('metalscrap') == 22, 'character unload must preserve the pending materials')
assert(call('collect', 'workshop').ok, 'materials from an unloaded character must be collectable')
assert(start().ok, 'character unload must release the busy state')
finish()
print('crafting_table server tests passed')

stock()
items[1].amount, items[2].amount, items[3].amount = 50, 60, 160
for i = 1, Config.QueueLimit do
    local response = start()
    assert(response.ok and #response.queue == i, 'crafts should enter the bounded queue')
end
local full = start()
assert(not full.ok and full.error == 'Crafting queue is full.' and #timers == 1, 'full queue must reject additions and run only one timer')
clock = clock + 1000
local queued = call('state', 'workshop').data.queue
assert(#queued == Config.QueueLimit and queued[1].remaining == Config.Recipes[1].duration - 1000 and queued[2].remaining == Config.Recipes[1].duration, 'state must expose active time and pending jobs')
for remaining = Config.QueueLimit - 1, 0, -1 do
    local beforeCount = stored('lockpick')
    assert(finish()[1] and stored('lockpick') == beforeCount + 1, 'each queued craft must complete in sequence')
    assert(#call('state', 'workshop').data.queue == remaining, 'queue must advance after each craft')
end

stock()
items[1].amount, items[2].amount, items[3].amount = 20, 24, 64
assert(start().ok and start().ok)
assert(count('metalscrap') == 0 and count('plastic') == 0, 'each queued job must deduct its own materials immediately')
assert(finish()[1] and finish()[1], 'queued crafts must complete using their reserved materials')
assert(#call('state', 'workshop').data.queue == 0 and #timers == 0 and stored('lockpick') == 2, 'queued crafts must complete independently of player inventory')

stock()
items[1].amount, items[2].amount, items[3].amount = 20, 24, 64
assert(start().ok and start().ok)
unlocked.lockpick = false
assert(not finish()[1] and #call('state', 'workshop').data.queue == 0 and #timers == 0, 'revoked skills must cancel queued crafts')
assert(reserved('metalscrap') == 44 and reserved('plastic') == 64, 'cancelled queued crafts must preserve all reserved materials')
unlocked.lockpick = true
assert(call('collect', 'workshop').ok, 'cancelled queued materials must be collectable')
assert(start().ok and start().ok)
position = 3
assert(finish()[1] and finish()[1], 'both crafts must complete while the player is away')
position = 0
assert(#call('state', 'workshop').data.queue == 0 and #timers == 0 and stored('lockpick') == 2, 'completed items must await collection after leaving')

stock()
items[1].amount, items[2].amount, items[3].amount = 20, 24, 64
assert(start().ok and start().ok)
events['QBCore:Server:OnPlayerUnload'](1)
local previousNotifications = #notifications
finish()
assert(#notifications == previousNotifications and #call('state', 'workshop').data.queue == 0, 'unload must clear queued jobs and ignore stale timers')

stock()
items[1].amount, items[2].amount, items[3].amount = 17, 20, 37
unlocked.wiring = true
assert(start().ok and call('craft', 'workshop', 'wiring').ok)
assert(finish()[1] and stored('lockpick') == 1 and stored('copper') == 0, 'first recipe must finish before the next recipe')
assert(finish()[1] and stored('copper') == 2, 'queued recipes must execute in FIFO order')
print('crafting queue tests passed')

stock()
assert(start().ok and reserved('metalscrap') == 22)
timers = {}
dofile('server/main.lua')
assert(call('state', 'workshop').data.collectionCount == 54, 'restart must expose unfinished reserved materials for collection')
assert(call('collect', 'workshop').ok and count('metalscrap') == 22 and count('plastic') == 32, 'unfinished materials must be recoverable after restart')

stock()
call('state', 'workshop')
local oldMaterials = stashes['crafting_table:materials:character-two:workshop']
local oldCollection = stashes['crafting_table:character-two:workshop']
oldMaterials.items = { ['1'] = { name = 'steel', amount = 1, slot = 1, info = {} } }
oldCollection.items = { ['1'] = { name = 'lockpick', amount = 1, slot = 1, info = {} } }
assert(start().ok and oldMaterials.items['1'].name == 'steel', 'new reservations must not reuse string-keyed persisted slots')
assert(finish()[1] and oldCollection.items['1'].amount == 1 and stored('lockpick') == 2, 'new outputs must not overwrite string-keyed persisted slots')

stock()
items[1].amount, items[2].amount, items[3].amount = 50, 60, 160
for _ = 1, 5 do assert(start().ok) end
source = 1
assert(not call('collect', 'workshop').ok)
local originalStash = stashes['crafting_table:character-two:workshop']
assert(not originalStash.isOpen, 'collection must be unavailable during an active queue')
position = 3
for _ = 1, 5 do assert(finish()[1]) end
clock = clock + 300000
assert(stored('lockpick') == 5 and count('lockpick') == 0, 'five crafts must finish and remain in storage while away for ten minutes')
assert(not call('collect', 'workshop').ok and stored('lockpick') == 5, 'collection must be rejected away from the station')
position = 0
player = { PlayerData = { citizenid = 'character-three' } }
assert(call('state', 'workshop').data.collectionCount == 0, 'another character must not see the original collection')
assert(not call('collect', 'workshop').ok and not originalStash.isOpen, 'another character must not collect the original collection')
player = { PlayerData = { citizenid = 'character-two' } }
dofile('server/main.lua')
assert(call('state', 'workshop').data.collectionCount == 5, 'completed collection must survive a crafting resource restart')
slotsFull = true
local full = call('collect', 'workshop')
assert(not full.ok and full.error:find('inventory is full', 1, true) and stored('lockpick') == 5, 'full slots must leave all items in storage')
slotsFull = false
capacity = 2
local partial = call('collect', 'workshop')
assert(partial.ok and partial.collectionCount == 3 and count('lockpick') == 2 and stored('lockpick') == 3, 'partial capacity must collect what fits and retain the rest')
capacity = 10
failCollectAdd = true
local rejected = call('collect', 'workshop')
assert(not rejected.ok and rejected.collectionCount == 3 and stored('lockpick') == 3 and count('lockpick') == 2, 'rejected inventory additions must restore the withdrawn item')
failCollectAdd = false
local collected = call('collect', 'workshop')
assert(collected.ok and collected.collectionCount == 0 and count('lockpick') == 5 and stored('lockpick') == 0, 'remaining items must be delivered exactly once')
assert(not call('collect', 'workshop').ok and count('lockpick') == 5, 'repeated collection must not duplicate items')

items = {}
originalStash.items = { [1] = { name = 'copper', amount = 5, slot = 1, info = { batch = 'saved' } } }
capacity = 2
partial = call('collect', 'workshop')
assert(partial.ok and partial.collectionCount == 3 and count('copper') == 2 and stored('copper') == 3 and items[1].info.batch == 'saved', 'partial stack transfer must preserve metadata')
capacity = 10
collected = call('collect', 'workshop')
assert(collected.ok and collected.collectionCount == 0 and count('copper') == 5, 'remaining stack must be collectable later')
items = {}
originalStash.items = { [1] = { name = 'phone', amount = 1, slot = 1, info = { serie = 'preserved' } } }
moveOnWithdraw = true
local moved = call('collect', 'workshop')
assert(not moved.ok and stored('phone') == 1 and count('phone') == 0, 'leaving during withdrawal must restore the item')
position = 0
collected = call('collect', 'workshop')
assert(collected.ok and count('phone') == 1 and items[1].info.serie == 'preserved', 'unique item metadata must survive collection')
print('crafting collection tests passed')
