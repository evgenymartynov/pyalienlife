local caravan_prototypes = require "caravan-prototypes"
local italian_names = require "italian-names"

local P = {}

---@param caravan_data Caravan
---@param entity LuaEntity
function P.get_valid_actions_for_entity(caravan_entity_name, entity)
    local prototype = caravan_prototypes[caravan_entity_name]
    local all_actions = prototype.actions
    local valid_actions
    if entity and entity.valid then
        if P.entity_name_is_item_outpost(entity.name) then
            valid_actions = all_actions.outpost
        elseif P.entity_name_is_fluid_outpost(entity.name) then
            valid_actions = all_actions["outpost-fluid"]
        else
            valid_actions = all_actions[entity.type]
        end
    end

    return valid_actions or all_actions.default or error()
end

function P.get_all_actions_for_entity(entity)
    local all_actions = Caravan.all_actions
    local valid_actions
    if entity and entity.valid then
        if P.entity_name_is_item_outpost(entity.name) then
            valid_actions = all_actions.outpost
        elseif P.entity_name_is_fluid_outpost(entity.name) then
            valid_actions = all_actions["outpost-fluid"]
        else
            valid_actions = all_actions[entity.type]
        end
    end

    return valid_actions or all_actions.default or error()
end

function P.get_name(caravan_data)
    local name = caravan_data.name
    if name and name ~= "" then return name end
    local random_name = caravan_data.random_name or italian_names[math.random(1, #italian_names)]
    caravan_data.random_name = random_name
    caravan_data.name = random_name
    return random_name
end

function P.entity_name_is_fluid_caravan(entity_name)
    return type(entity_name) == "string" and entity_name:find("^fluidavan") ~= nil
end

function P.entity_name_is_item_outpost(entity_name)
    return entity_name == "outpost" or entity_name == "outpost-aerial"
end

function P.entity_name_is_fluid_outpost(entity_name)
    return entity_name == "outpost-fluid" or entity_name == "outpost-aerial-fluid"
end

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
    if not P.entity_name_is_fluid_outpost(entity.name) then
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

---Accepts a condition or action and returns the relevant label
function P.label_info(schedule_entry)
    if not schedule_entry then return nil, nil, nil end

    local style = schedule_entry.temporary and "black_squashable_label" or "train_schedule_unavailable_stop_label"
    local caption
    local tooltip
    if not schedule_entry.entity and not schedule_entry.position then -- should only be possible with interrupts
        caption = {"caravan-gui.not-specified"}
        tooltip = schedule_entry.temporary and caption or {"caravan-gui.reassign-hint", caption}
    elseif schedule_entry.entity and not schedule_entry.entity.valid then
        caption = schedule_entry.localised_name or {"caravan-gui.destination-unavailable"}
        tooltip = schedule_entry.temporary and {"caravan-gui.interrupt-destination-unavailable"} or {"caravan-gui.reassign-hint", caption}
    else
        style = schedule_entry.temporary and "black_squashable_label" or "clickable_squashable_label"
        caption = schedule_entry.localised_name
        tooltip = schedule_entry.temporary and caption or {"caravan-gui.reassign-hint", caption}
    end
    return style, caption, tooltip
end

function P.is_child_of(c, p, depth)
    if depth == 0 or not c then return false end

    return c.name == p.name or P.is_child_of(c.parent, p, depth - 1)
end

---Returns a table repersenting a caravan's action.
---@param element LuaGuiElement
function P.get_action_from_button(element)
    local tags = element.tags
    local player_index = element.player_index
    local action_list_type = tags.action_list_type

    local action
    if action_list_type == Caravan.action_list_types.standard_schedule then
        action = storage.caravans[tags.unit_number].schedule[tags.schedule_id].actions[tags.action_id]
    elseif action_list_type == Caravan.action_list_types.interrupt_schedule then
        error()
    elseif action_list_type == Caravan.action_list_types.interrupt_condition then
        local interrupt = storage.edited_interrupts[player_index]
        action = interrupt.conditions[tags.condition_id]
    elseif action_list_type == Caravan.action_list_types.interrupt_targets then
        local interrupt = storage.edited_interrupts[player_index]
        action = interrupt.schedule[tags.schedule_id].actions[tags.action_id]
    else
        error("Invalid action_list_type " .. tostring(action_list_type) .. ". GUI tags: " .. serpent.line(tags) .. " elem name: " .. element.name)
    end

    if not action then
        error("Could not find action with action_list_type " .. action_list_type .. ". GUI tags: " .. serpent.line(tags))
    end
    return action
end

---Returns a table repersenting a caravan's schedule.
---@param element LuaGuiElement
function P.get_schedule(element)
    local tags = element.tags
    local action_list_type = tags.action_list_type

    if action_list_type == Caravan.action_list_types.standard_schedule then
        local caravan_data = storage.caravans[tags.unit_number]
        local schedule = caravan_data.schedule
        if tags.action_id then schedule = schedule[tags.schedule_id].actions end
        return schedule
    elseif action_list_type == Caravan.action_list_types.interrupt_schedule then
        local caravan_data = storage.caravans[tags.unit_number]
        return caravan_data.interrupts
    elseif action_list_type == Caravan.action_list_types.interrupt_condition then
        return storage.interrupts[tags.interrupt_name].conditions
    elseif action_list_type == Caravan.action_list_types.interrupt_targets then
        local schedule = storage.interrupts[tags.interrupt_name].schedule
        if tags.action_id then schedule = schedule[tags.schedule_id].actions end
        return schedule
    else
        error("Invalid action_list_type " .. tostring(action_list_type) .. ". GUI tags: " .. serpent.line(tags) .. " elem name: " .. element.name)
    end
end

function P.get_actions_from_tags(tags, player_index)
    local action_list_type = tags.action_list_type

    local action
    if action_list_type == Caravan.action_list_types.standard_schedule then
        return storage.caravans[tags.unit_number].schedule[tags.schedule_id].actions
    elseif action_list_type == Caravan.action_list_types.interrupt_schedule then
        error()
    elseif action_list_type == Caravan.action_list_types.interrupt_condition then
        local interrupt = storage.edited_interrupts[player_index]
        return interrupt.conditions
    elseif action_list_type == Caravan.action_list_types.interrupt_targets then
        local interrupt = storage.edited_interrupts[player_index]
        return interrupt.schedule[tags.schedule_id].actions
    else
        error("Invalid action_list_type " .. tostring(action_list_type) .. ". GUI tags: " .. serpent.line(tags))
    end
end

function P.convert_to_tooltip_row(item)
    local name = item.name
    local count = item.count
    local quality = item.quality or "normal"
    return {"", "\n[item=" .. name .. ",quality=" .. quality .. "] ", " ×", count}
end

local function get_caravan_inventory_tooltip(caravan_data)
    local inventory = caravan_data.inventory
    ---@type (table | string)[]
    local inventory_contents = {"", "\n[img=utility/trash_white] ", {"caravan-gui.the-inventory-is-empty"}}
    if inventory and inventory.valid then
        local sorted_contents = inventory.get_contents()
        table.sort(sorted_contents, function(a, b) return a.count > b.count end)

        local i = 0
        for _, item in pairs(sorted_contents) do
            if i == 0 then inventory_contents = {""} end
            inventory_contents[#inventory_contents + 1] = P.convert_to_tooltip_row(item)
            i = i + 1
            if i == 10 then
                if #sorted_contents > 10 then
                    inventory_contents[#inventory_contents + 1] = {"", "\n[color=255,210,73]", {"caravan-gui.more-items", #sorted_contents - 10}, "[/color]"}
                end
                break
            end
        end
    end
    return {"", "[font=default-semibold]", inventory_contents, "[/font]"}
end

local function get_fluidavan_inventory_tooltip(caravan_data)
    if caravan_data.fluid then
        return {"", "\n[fluid=" .. caravan_data.fluid.name .. "] ", " ×", caravan_data.fluid.amount}
    else
        return {"", "\n[img=utility/fluid_icon] ", {"caravan-gui.tank-is-empty"}}
    end
end

function P.get_inventory_tooltip(caravan_data)
    if caravan_data.entity.name:find("^fluidavan") then
        return get_fluidavan_inventory_tooltip(caravan_data)
    end
    return get_caravan_inventory_tooltip(caravan_data)
end

function P.get_summary_tooltip(caravan_data)
    local entity = caravan_data.entity

    local schedule = caravan_data.schedule[caravan_data.schedule_id]
    ---@type (table | string)[]
    local current_action = {"caravan-gui.current-action", {"entity-status.idle"}}
    if schedule then
        local action_id = caravan_data.action_id
        local action = schedule.actions[action_id]
        current_action = {"", {"caravan-gui.current-action", action and action.localised_name or {"caravan-actions.traveling"}}}

        local destination
        local localised_destination_name
        local destination_entity = schedule.entity
        if destination_entity and destination_entity.valid then
            destination = destination_entity.position
            localised_destination_name = {
                "caravan-gui.entity-position",
                destination_entity.prototype.localised_name,
                math.floor(destination.x),
                math.floor(destination.y)
            }
        elseif schedule.position then
            destination = schedule.position
            localised_destination_name = {"caravan-gui.map-position", math.floor(destination.x), math.floor(destination.y)}
        end

        if localised_destination_name then
            local distance = math.sqrt((entity.position.x - destination.x) ^ 2 + (entity.position.y - destination.y) ^ 2)
            distance = math.floor(distance * 10) / 10
            current_action[#current_action + 1] = {"", "\n", {"caravan-gui.current-destination", distance, localised_destination_name}}
        end
    end

    local fuel_inventory = caravan_data.fuel_inventory
    ---@type (table | string)[]
    local fuel_inventory_contents = {""}
    if fuel_inventory and fuel_inventory.valid then
        local i = 0
        for _, item in pairs(fuel_inventory.get_contents()) do
            fuel_inventory_contents[#fuel_inventory_contents + 1] = P.convert_to_tooltip_row(item)
            i = i + 1
            if i == 10 then break end
        end
    end

    return {"", "[font=default-semibold]", current_action, fuel_inventory_contents, "\n", P.get_inventory_tooltip(caravan_data), "[/font]"}
end

function P.partition(t, pred)
    local a, b = {}, {}

    for _, elem in pairs(t) do
        table.insert(pred(elem) and a or b, elem)
    end
    return a, b
end

function P.filter(t, pred)
    local r = {}
    for _, elem in pairs(t) do
        if pred(elem) then
            table.insert(r, elem)
        end
    end
    return r
end

function P.contains(t, e)
  for i = 1,#t do
    if t[i] == e then return true end
  end
  return false
end

-- takes an action and ensures item_count is set, if relevant. An action can be a condition as well.
function P.ensure_item_count(action)
    if not action or not action.type then
        return action
    end
    if not Caravan.actions_with_item_count[action.type] then
        return action
    end
    if action.type == "time-passed" then
        action.wait_time = action.wait_time or 5
    else
        action.item_count = action.item_count or 0
    end
    return action
end

function P.rename_interrupt(interrupt, new_name)
    local old_name = interrupt.name
    storage.interrupts[old_name] = nil
    interrupt.name = new_name
    storage.interrupts[new_name] = interrupt

    -- far from ideal, it would be better to index caravan interrupts by ID instead of names
    for _, caravan_data in pairs(storage.caravans) do
        for i = 1, #caravan_data.interrupts do
            if caravan_data.interrupts[i] == old_name then
                caravan_data.interrupts[i] = new_name
                break
            end
        end
    end
end

---Parses an `elem_value` from a `choose-elem-button` of type "item" into (name, quality).
---@param elem_value string|table|nil
---@return string?, string?
function P.parse_item_elem_value(elem_value)
    if not elem_value then return nil, nil end
    if type(elem_value) == "string" then
        return elem_value, "normal"
    end
    if type(elem_value) == "table" and elem_value.name then
        return elem_value.name, elem_value.quality or "normal"
    end
    return nil, nil
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

---Looks up or creates the QS interrupt for the given item+quality+count.
---For newly-created interrupts, populates the `caravan-item-count` condition and a `load-caravan`
---schedule entry pointing at the outpost on the player's surface that holds the most of that item.
---@param player LuaPlayer
---@param item_name string
---@param quality string
---@param count number
---@return string name, boolean is_new, LuaEntity? quick_pick_station
function P.ensure_item_quick_setup_interrupt(player, item_name, quality, count)
    local name = P.build_interrupt_name_from_item_and_count(player, item_name, quality, count)
    local is_new = not storage.interrupts[name]

    if is_new then
        storage.interrupts[name] = {
            name = name,
            conditions = {},
            conditions_operators = {},
            schedule = {},
            inside_interrupt = false,
        }
    end

    local interrupt = storage.interrupts[name]
    local quick_pick_station

    if is_new then
        local elem_value = quality == "normal" and item_name or {name = item_name, quality = quality}
        table.insert(
            interrupt.conditions,
            P.ensure_item_count {
                type = "caravan-item-count",
                localised_name = {"caravan-actions.caravan-item-count", "caravan-item-count"},
                elem_value = elem_value,
                item_count = 0,
                operator = 3,
            }
        )

        quick_pick_station = P.find_outpost_with_largest_item_count(player, item_name, quality)
        if quick_pick_station and quick_pick_station.valid then
            local load_action = P.ensure_item_count {
                type = "load-caravan",
                localised_name = {"caravan-actions.load-caravan", "load-caravan"},
                elem_value = elem_value,
                item_count = count,
            }
            table.insert(interrupt.schedule, {
                localised_name = {
                    "caravan-gui.entity-position",
                    quick_pick_station.prototype.localised_name,
                    math.floor(quick_pick_station.position.x),
                    math.floor(quick_pick_station.position.y),
                },
                entity = quick_pick_station,
                position = quick_pick_station.position,
                player_index = nil,
                actions = {load_action},
            })
        end
    end

    return name, is_new, quick_pick_station
end

--TODO: ensure this is the right location for these
function P.store_gui_location(element)
    local player_index = element.player_index
    local locations = storage.gui_locations[player_index]
    if locations then
        locations[element.name] = element.location
    else
        storage.gui_locations[player_index] = {
            [element.name] = element.location
        }
    end
end

---Restores the given GUI element to the stored GUI location (position)
---@param element LuaGuiElement
---@param fallback_location GuiLocation?
function P.restore_gui_location(element, fallback_location)
    local location = (storage.gui_locations[element.player_index] or {})[element.name] or fallback_location
    if location then
        element.location = location
        P.store_gui_location(element)
    end
end

return P
