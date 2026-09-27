# Outpost wait alert

Raises a custom alert on an outpost when any caravan has been stuck on a single supply
action there for longer than a configurable threshold, e.g. an outpost that never receives
the items caravans are waiting to load. The alert icon is the item / fluid being waited on,
so the player can see at a glance what the outpost is short of.

## Functional requirements

- Threshold is the runtime-global mod setting `py-caravan-wait-alert-seconds`
  (default `600`, i.e. 10 minutes; `0` disables the alert).
- A caravan's timer starts when an action begins and resets every time the caravan moves
  on to another action, whether the next action at the same stop or the first action at the
  next stop. Time spent on earlier actions at the same stop does not count.
- A caravan contributes to an outpost alert only when all of the following hold:
  - the current action's target is an outpost (`outpost`, `outpost-fluid`,
    `outpost-aerial`, `outpost-aerial-fluid`);
  - the current action is one that waits for the outpost to supply the caravan:
    `load-caravan`, `unload-target`, `store-food`, `store-specific-food`,
    `fill-tank-until-caravan-has`, `fill-tank-until-target-has`;
  - the action has not completed and the time since it started exceeds the threshold.
- Alerts are placed on the outpost entity, not the caravan, and deduplicated on
  `(outpost, icon)`: many caravans waiting on the same item at the same outpost produce one
  alert; different items at the same outpost produce one alert each.
- Icon per action:
  - item actions (`load-caravan`, `unload-target`, `store-specific-food`): the configured
    item, including quality;
  - fluid actions: the configured fluid;
  - `store-food` (any favourite food): the `py-no-food` signal;
  - an action with no item / fluid configured: the generic `py-caravan-waiting` signal.
- Message: `caravan-warnings.waiting-too-long` with the icon's rich text as `__1__`.
- Active alerts are re-sent every second (same pattern as the out-of-food alert) to all
  connected players on the outpost's force.
- When an `(outpost, icon)` pair stops qualifying (the caravans moved on, were stopped, or
  the threshold changed), its alert is removed within a second.

## Decisions

- Only supply ("requester") actions are watched. Unload-side actions (`empty-inventory`,
  `unload-caravan`, `load-target`, `empty-tank*`) wait for space rather than goods and are
  excluded, as are circuit conditions and `time-passed`.
- `fill-inventory` and `fill-tank` are excluded: they are used for intentionally
  long-running actions (e.g. "fill up whatever is available").
- Non-waiting actions (the "wait" checkbox off, `action.async = true`) complete on the first
  check, so they can never trigger the alert and need no special casing.
- Alerts live on the outpost because the outpost is where the fix is (supply it with the
  missing item); one alert per missing item keeps the alert list short when many caravans
  share an outpost.
- `player.remove_alert` is only reliable with a single criterion, so removal is per entity:
  when any pair on an outpost resolves, all alerts on that outpost are removed and the
  still-active pairs are re-added in the same update.
- The threshold is in seconds to make testing practical. Changing the default does not
  update existing saves, which keep their stored map-setting value.

## State and migration

- `storage.caravans[unit_number].action_started_tick`: tick at which the current action
  began; `nil` while travelling or idle.
- `storage.outpost_wait_alerts`: outpost unit number -> `{entity, alerts}`, where `alerts`
  maps an icon key (`type/name/quality`) to the alert that was sent. Rebuilt from scratch on
  every update and compared with the previous one to find resolved pairs.

Migration: on init / configuration change, `storage.outpost_wait_alerts` is created, and
any caravan already mid-action (`action_id > 0`) without `action_started_tick` gets it set
to the current tick, so caravans stuck in existing saves alert one threshold after loading
the updated mod.

## Code map

Discovery hints only; for behavioural detail re-read the referenced functions.

- Setting: [settings.lua](../../../settings.lua); locale in
  [locale/en/caravan.cfg](../../../locale/en/caravan.cfg).
- Fallback signal prototype `py-caravan-waiting`:
  [prototypes/creatures/caravan.lua](../../../prototypes/creatures/caravan.lua).
- Timer start: `begin_action` in [impl/schedule.lua](../impl/schedule.lua); timer reset in
  `begin_schedule` and `stop_actions` ([impl/control.lua](../impl/control.lua)).
- Watched action list, icon choice, per-caravan check and alert publishing:
  `wait_alert_action_types`, `get_wait_alert_icon`, `check_wait_alert` and
  `publish_outpost_wait_alerts` in [event-handlers/global.lua](../event-handlers/global.lua),
  driven by the `update-caravans` nth-tick handler.
- Alert send / remove helpers: `add_alert` / `remove_alert` in [impl/gui.lua](../impl/gui.lua).
- Outpost predicate: `Utils.entity_name_is_outpost` in [utils.lua](../utils.lua).
- Migration: init handler in [caravan.lua](../caravan.lua).
