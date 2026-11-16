# Crafting Table

A separate QBCore workstation for the `skill_tree` resource. Players interact with a configured location, choose an unlocked blueprint, and craft using `qb-inventory` materials. The workshop uses the same dark style and inventory images as the skill tree.

## Setup

1. Start `qb-core`, `qb-inventory`, `oxmysql`, and `skill_tree` first, then `ensure crafting_table`. For `interact`, start `ox_lib` and the installed `interact` resource; for `qb-target`, start `PolyZone` and `qb-target`.
2. Move the example workstation in [config.lua](./config.lua) to your preferred location and choose `Config.Interaction`:
   - `marker` (default): draw a marker and press E; `DrawDistance` and `InteractKey` control the marker.
   - `interact`: use the standalone `interact` resource; `DrawDistance` controls how far its point is shown.
   - `qb-target`: aim at a target zone; `TargetRadius` controls the zone size.

   All modes use each station's `distance` as the maximum player distance, also checked on the server. No mode spawns a physical prop. Place the point on a targetable surface for `qb-target`, and avoid overlapping another crafting resource. If the selected interaction resource starts later or restarts, its workstation points are registered again.
3. Categories, icons, labels, and output items come automatically from `skill_tree/config.lua`. Only unlocked skills appear; discovered but unlearned skills remain hidden. Empty categories are hidden too. Restart `skill_tree` and then `crafting_table` after changing the skill-tree configuration.
4. Configure crafting recipes in [config.lua](./config.lua). `blueprint` must be the exact skill-tree node ID, not its blueprint inventory item. The output item comes from that node. Set the ingredients, output amount, duration, and XP for each recipe; the included amounts are examples. An unlocked skill without a configured recipe is visible but cannot be crafted. This includes the example weapon skills until you configure their recipes. All items must exist in `QBCore.Shared.Items`.
5. Change the color variables at the top of [web/style.css](./web/style.css) to customize the workshop.

Each recipe produces its configured amount per craft, after its duration in milliseconds, and awards its configured skill XP after success. Unique outputs must have an amount of one. Legacy recipe `item` and `category` fields may be omitted; if present, they must match the skill-tree node.

The top-right level and XP bar use `skill_tree` progression. Every level grants one skill point, and the XP needed increases each level; configure the curve in `skill_tree/config.lua`.

Admins can manage an online player's shared crafting progression with `/skilladdxp <playerId> <amount>`, `/skillremovexp <playerId> <amount>`, and `/skillreset <playerId>`. XP removal can lower the player's level and available points. **Reset also clears points, discovered blueprints, and unlocked skills.** See the skill tree's admin tools documentation for details.

Players can queue crafts at the same workstation. `Config.QueueLimit` limits the number of crafts, including the active one. Crafts run one at a time and continue while the player is away; return to the same workstation and select **Collect Items** after the queue finishes. Items are transferred directly into the player's inventory; items that do not fit remain available for later collection. Completed items are stored in a private character-and-workstation `qb-inventory` stash, including across resource restarts and reconnects. The stash has 100 slots and a 10,000,000 weight limit. Collection is unavailable while that workstation's queue is active.

The server checks location, learned blueprints and materials when adding a job. Materials are removed immediately and held in a private `qb-inventory` reservation until the craft completes. Closing the UI or leaving the station does not cancel the queue. Disconnecting, changing character, or restarting the crafting resource cancels unfinished jobs; their reserved materials can be collected at the original workstation after the queue ends. Completed items also remain available. Cancelled crafts and failed output storage leave their reserved materials available for collection. Collection is unavailable while that workstation's queue is active. Failed refunds, collection restorations, and XP awards are logged for administrator intervention. Inventory operations are not database transactions: inventory hooks or resource failures can prevent a refund or make a transfer's outcome uncertain.

This resource does not disable `qb-crafting` or other item sources. If all crafting must require skill-tree unlocks, disable or separately configure other crafting systems. Its example marker is not a security boundary against other resources.

## Validation

From this directory:

```shell
node --check web/app.js
npx --yes --package fengari-node-cli fengari tests/server.lua
npx --yes --package fengari-node-cli fengari tests/client.lua
npx --yes --package fengari-node-cli fengari tests/interactions.lua
```

The Lua test mocks QBCore, inventory, and FiveM; verify interaction, inventory hooks, and visuals on a development server as well. For a static UI preview, open `web/index.html?preview` in a browser.
