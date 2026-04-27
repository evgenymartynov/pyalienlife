# Outpost setup (item-caravan schedule tab)

A quick way to populate an item-caravan's schedule and interrupts based on the inventory
filters of an existing outpost: pick the outpost, toggle which item types you want, and
press Accept to create a drop-off schedule plus one matching restock interrupt per item.

## Functional requirements

- Available only for non-fluid (item-carrying) caravans, on the schedule tab's quick-setup row.
- The "read outpost filters" button enters the destination-selection mode (carrot-on-stick).
  Only `outpost` and `outpost-aerial` are valid targets; clicking anything else plays
  `utility/cannot_build` and bails. An empty filter set also plays `utility/cannot_build`.
- After a valid pick, an items row appears in the schedule tab with one button per filtered
  item type. Each button shows the item icon, with the aggregate count
  (`stack_size * filtered_slot_count`) as a subscript number.
- Left-clicking an item button toggles its enabled state. Enabled buttons use
  `slot_sized_button`; disabled buttons use `slot_sized_button_red` (darker / red tint), to
  match the existing QS picker visual language while remaining clickable.
- The row also includes an Accept button at the right.
- Accept does the following, in order:
  1. Appends a schedule entry pointed at the picked outpost with two actions:
     a single `empty-inventory` action (`async = true`, no waiting) followed by a
     `time-passed` action with `wait_time = 120`.
  2. For each enabled item, calls the shared QS interrupt-creation helper to
     look up or create the matching `[item=X] LocalisedName count` interrupt
     (and, when newly created, populates its `caravan-item-count` condition and a
     `load-caravan` schedule entry pointing at the outpost on the same surface that
     stocks the most of that item).
  3. Adds the interrupt name to the caravan's `interrupts` list if not already present.
  4. For each newly-created interrupt, prints to the player a line containing the item
     icon and a GPS marker for the auto-picked source outpost (or a "no source outpost
     found" message if none was found).
- After Accept, the items row is cleared so the player can immediately run the flow again
  with another outpost.

## Lifecycle

The items row is ephemeral. Per-player state lives at `storage.outpost_setup[player_index]`
and is cleared on:

- Accept.
- Closing the caravan GUI.
- Switching tabs in the caravan GUI.
- Re-clicking the read-outpost-filters button (a new selection resets prior state).
- Detection of a stale entry (mismatched caravan, invalid outpost) when the schedule pane
  rebuilds.

## Decisions

- Storage key: `storage.outpost_setup` (per-player, ephemeral).
- Toggle: left-click only.
- Unload: single `empty-inventory` action (`async = true`) plus a single `time-passed`
  120s wait. We intentionally do not iterate per-item unload-caravan actions.
- Interrupt deduplication: if the interrupt name is already in the caravan's list, skip
  silently. The player-print only fires for newly-created entries in `storage.interrupts`.
- GPS format: `[gps=x, y]`, matching existing usage in the codebase.
- Quality: outpost inventory filters expose only `name` for vanilla `with_filters_and_bar`,
  so all items are treated as `quality = "normal"` for interrupt-name building.

## Code map

Discovery hints only; for behavioural detail re-read the referenced functions.

- Read-outpost-filters button click: [event-handlers/destination.lua](../event-handlers/destination.lua),
  handler `py_caravan_quick_setup_read_outpost_filters_button`.
- Selection-mode entry/exit: `CaravanImpl.select_destination` in
  [impl/control.lua](../impl/control.lua); the carrot click is handled by
  `on_carrot_used` in [event-handlers/global.lua](../event-handlers/global.lua).
- Aggregation and state population: `start_outpost_setup` in
  [event-handlers/global.lua](../event-handlers/global.lua).
- Items row rendering: `build_outpost_setup_row` in
  [gui/schedule_tab.lua](../gui/schedule_tab.lua), called from `build_schedule_flow`.
- Toggle and Accept handlers, schedule + interrupt creation: 
  [event-handlers/outpost_setup.lua](../event-handlers/outpost_setup.lua).
- Shared QS helpers used by Accept and the existing single-item QS path: see
  `Utils.parse_item_elem_value`, `Utils.build_interrupt_name_from_item_and_count`,
  `Utils.ensure_item_quick_setup_interrupt`, and the outpost-name helpers in
  [utils.lua](../utils.lua).
