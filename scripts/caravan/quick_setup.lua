local Utils = require "__pyalienlife__/scripts/caravan/utils"

local P = {}

---Caravan land/aerial outpost chest inventory only.
---@param entity LuaEntity
---@return LuaInventory?
function P.try_get_outpost_item_inventory(entity)
    if not entity or not entity.valid then return nil end
    if entity.type == "container" then
        return entity.get_inventory(defines.inventory.chest)
    end
    return nil
end

---Item land / aerial outpost on the player's surface and force with the highest amount of the item.
---@param player LuaPlayer
---@param item_name string
---@param quality string
---@return LuaEntity?
function P.find_outpost_with_largest_item_count(player, item_name, quality)
    local item_filter = quality == "normal" and item_name or {name = item_name, quality = quality}
    local best_entity, best_count = nil, 0
    for _, ent in pairs(player.surface.find_entities_filtered {
        name = {"outpost", "outpost-aerial"},
        force = player.force,
    }) do
        local inv = P.try_get_outpost_item_inventory(ent)
        if inv then
            local count = inv.get_item_count(item_filter)
            if count > best_count then
                best_count = count
                best_entity = ent
            end
        end
    end
    return best_entity
end

---@param entity LuaEntity
---@param fluid_name string
---@return number
function P.try_get_outpost_fluid_amount(entity, fluid_name)
    if not entity or not entity.valid then return 0 end
    if not Utils.entity_name_is_fluid_outpost(entity.name) then
        return 0
    end
    return entity.get_fluid_count(fluid_name)
end

---Fluid land / aerial outpost on the player's surface and force with the most of that fluid (nil if none hold any).
---@param player LuaPlayer
---@param fluid_name string
---@return LuaEntity?
function P.find_fluid_outpost_with_largest_fluid_amount(player, fluid_name)
    local best_entity, best_amount = nil, 0
    for _, ent in pairs(player.surface.find_entities_filtered {
        name = {"outpost-fluid", "outpost-aerial-fluid"},
        force = player.force,
    }) do
        local amount = P.try_get_outpost_fluid_amount(ent, fluid_name)
        if amount > best_amount then
            best_amount = amount
            best_entity = ent
        end
    end
    return best_entity
end

---Nearest fluid land / aerial outpost to the given entity (nil if none exist).
---@param caravan_entity LuaEntity
---@param player LuaPlayer
---@return LuaEntity?
function P.find_nearest_fluid_outpost(caravan_entity, player)
    local pos = caravan_entity.position
    local best_entity, best_dist_sq = nil, math.huge
    for _, ent in pairs(player.surface.find_entities_filtered {
        name = {"outpost-fluid", "outpost-aerial-fluid"},
        force = player.force,
    }) do
        local dx = ent.position.x - pos.x
        local dy = ent.position.y - pos.y
        local dist_sq = dx * dx + dy * dy
        if dist_sq < best_dist_sq then
            best_dist_sq = dist_sq
            best_entity = ent
        end
    end
    return best_entity
end

---Translates an item or fluid name using the cached locale store, falling back to the raw name.
---@param player LuaPlayer
---@param name string
---@return string
function P.translate_item_and_fluid_name(player, name)
    if py.get_localised_item_or_fluid_name then
        return py.get_localised_item_or_fluid_name(player, name)
    end
    local locale_store = (storage.item_and_fluid_locale or {})[player.locale] or {}
    return locale_store[name] or name
end

---Builds the QS interrupt name for an item: "[item=X] LocalizedName count" (with quality if non-normal).
---@param player LuaPlayer
---@param item_name string
---@param quality string
---@param count number
---@return string
function P.build_interrupt_name_from_item_and_count(player, item_name, quality, count)
    local translated_name = P.translate_item_and_fluid_name(player, item_name)
    if quality == "normal" then
        return string.format("[item=%s] %s %d", item_name, translated_name, count)
    end
    return string.format("[item=%s,quality=%s] %s %d", item_name, quality, translated_name, count)
end

---Builds the QS interrupt name for a fluid: "[fluid=X] LocalizedName count".
---@param player LuaPlayer
---@param fluid_name string
---@param count number
---@return string
function P.build_interrupt_name_from_fluid_and_count(player, fluid_name, count)
    local translated_name = P.translate_item_and_fluid_name(player, fluid_name)
    return string.format("[fluid=%s] %s %d", fluid_name, translated_name, count)
end

local ITEM_KIND = {condition = "caravan-item-count", action = "load-caravan"}
local FLUID_KIND = {condition = "caravan-fluid-count", action = "fill-tank-until-caravan-has"}

---Looks up or creates a QS interrupt. Existing interrupts are reused as-is. New interrupts are only
---created when `find_station` returns a source outpost; they get a "caravan has 0" condition and a
---single schedule entry pointing at that outpost with a load action for `count`.
---@param name string
---@param kind table ITEM_KIND or FLUID_KIND
---@param elem_value string|table
---@param count number
---@param find_station fun(): LuaEntity?
---@return string? name nil if the interrupt didn't exist and no source outpost was found
---@return boolean is_new
---@return LuaEntity? quick_pick_station
local function ensure_interrupt(name, kind, elem_value, count, find_station)
    if storage.interrupts[name] then
        return name, false, nil
    end

    local quick_pick_station = find_station()
    if not quick_pick_station or not quick_pick_station.valid then
        return nil, false, nil
    end

    storage.interrupts[name] = {
        name = name,
        conditions = {
            Utils.ensure_item_count {
                type = kind.condition,
                localised_name = {"caravan-actions." .. kind.condition, kind.condition},
                elem_value = elem_value,
                item_count = 0,
                operator = 3,
            },
        },
        conditions_operators = {},
        schedule = {
            {
                localised_name = {
                    "caravan-gui.entity-position",
                    quick_pick_station.prototype.localised_name,
                    math.floor(quick_pick_station.position.x),
                    math.floor(quick_pick_station.position.y),
                },
                entity = quick_pick_station,
                position = quick_pick_station.position,
                player_index = nil,
                actions = {
                    Utils.ensure_item_count {
                        type = kind.action,
                        localised_name = {"caravan-actions." .. kind.action, kind.action},
                        elem_value = elem_value,
                        item_count = count,
                    },
                },
            },
        },
        inside_interrupt = false,
    }

    return name, true, quick_pick_station
end

---Looks up or creates the QS interrupt for the given item+quality+count, sourced from the outpost
---on the player's surface that holds the most of that item.
---@param player LuaPlayer
---@param item_name string
---@param quality string
---@param count number
---@return string? name, boolean is_new, LuaEntity? quick_pick_station
function P.ensure_item_interrupt(player, item_name, quality, count)
    local name = P.build_interrupt_name_from_item_and_count(player, item_name, quality, count)
    local elem_value = quality == "normal" and item_name or {name = item_name, quality = quality}
    return ensure_interrupt(name, ITEM_KIND, elem_value, count, function()
        return P.find_outpost_with_largest_item_count(player, item_name, quality)
    end)
end

---Looks up or creates the QS interrupt for the given fluid+count, sourced from the fluid outpost
---on the player's surface that holds the most of that fluid.
---@param player LuaPlayer
---@param fluid_name string
---@param count number
---@return string? name, boolean is_new, LuaEntity? quick_pick_station
function P.ensure_fluid_interrupt(player, fluid_name, count)
    local name = P.build_interrupt_name_from_fluid_and_count(player, fluid_name, count)
    return ensure_interrupt(name, FLUID_KIND, fluid_name, count, function()
        return P.find_fluid_outpost_with_largest_fluid_amount(player, fluid_name)
    end)
end

---Appends a schedule entry to the caravan that empties `count` of the fluid into `outpost`, then waits 120s.
---@param caravan_data table
---@param outpost LuaEntity
---@param fluid_name string
---@param count number
function P.add_fluid_dropoff(caravan_data, outpost, fluid_name, count)
    local empty_action = Utils.ensure_item_count {
        type = "empty-tank-until-target-has",
        localised_name = {"caravan-actions.empty-tank-until-target-has", "empty-tank-until-target-has"},
        elem_value = fluid_name,
        item_count = count,
    }
    local wait_action = Utils.ensure_item_count {
        type = "time-passed",
        localised_name = {"caravan-actions.time-passed", "time-passed"},
        wait_time = 120,
    }
    table.insert(caravan_data.schedule, {
        localised_name = {
            "caravan-gui.entity-position",
            outpost.prototype.localised_name,
            math.floor(outpost.position.x),
            math.floor(outpost.position.y),
        },
        entity = outpost,
        position = outpost.position,
        player_index = nil,
        actions = {empty_action, wait_action},
    })
end

return P
