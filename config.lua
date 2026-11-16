Config = {}

-- Move or add workstations to suit your server. Coordinates are also checked server-side.
Config.Stations = {
    workshop = { label = 'Workshop', coords = vector3(-211.4, -1324.6, 30.9), distance = 2.0 },
}
Config.Interaction = 'interact' -- 'marker', 'interact', or 'qb-target'
Config.DrawDistance = 15.0 -- Marker drawing distance or interact display distance.
Config.InteractKey = 38 -- E
Config.TargetRadius = 0.6 -- qb-target zone radius; station.distance still limits use.
Config.QueueLimit = 5 -- Maximum crafts per player, including the active craft.

-- Categories and output items come from skill_tree. Add a recipe for a blueprint
-- to make it craftable. Unlocked skills without a recipe remain visible but disabled.
-- Materials are consumed and XP is granted only after a successful craft.
Config.Recipes = {
    { id = 'lockpick', blueprint = 'lockpick', amount = 1, duration = 1 * 60 * 1000, xp = 15,
        ingredients = { { item = 'metalscrap', amount = 22 }, { item = 'plastic', amount = 32 } } },
    { id = 'repairkit', blueprint = 'repairkit', amount = 1, duration = 8000, xp = 25,
        ingredients = { { item = 'metalscrap', amount = 32 }, { item = 'steel', amount = 43 }, { item = 'plastic', amount = 61 } } },
    { id = 'advancedlockpick', blueprint = 'advancedlockpick', amount = 1, duration = 8000, xp = 25,
        ingredients = { { item = 'metalscrap', amount = 30 }, { item = 'steel', amount = 20 }, { item = 'plastic', amount = 20 } } },
    { id = 'radio', blueprint = 'radio', amount = 1, duration = 1 * 60 * 1000, xp = 20,
        ingredients = { { item = 'plastic', amount = 25 }, { item = 'copper', amount = 20 }, { item = 'aluminum', amount = 10 } } },
    { id = 'wiring', blueprint = 'wiring', amount = 2, duration = 5000, xp = 15,
        ingredients = { { item = 'metalscrap', amount = 15 }, { item = 'plastic', amount = 5 } } },
    { id = 'phone', blueprint = 'phone', amount = 1, duration = 10000, xp = 30,
        ingredients = { { item = 'plastic', amount = 30 }, { item = 'copper', amount = 25 }, { item = 'aluminum', amount = 15 } } },
}
