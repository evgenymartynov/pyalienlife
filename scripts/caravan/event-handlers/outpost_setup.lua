local CaravanUtils = require "__pyalienlife__/scripts/caravan/utils"
local CaravanGuiComponents = require "__pyalienlife__/scripts/caravan/gui/components"

gui_events[defines.events.on_gui_click]["py_caravan_outpost_setup_item_button_."] = function(event)
    if event.button ~= defines.mouse_button_type.left then return end

    if not storage.outpost_setup then return end
    local setup = storage.outpost_setup[event.player_index]
    if not setup then return end

    local item_index = event.element.tags.item_index
    local item = setup.items[item_index]
    if not item then return end

    item.enabled = not item.enabled

    local player = game.get_player(event.player_index)
    CaravanGuiComponents.update_schedule_pane(player)
end

gui_events[defines.events.on_gui_click]["py_caravan_outpost_setup_accept_button"] = function(event)
    local player = game.get_player(event.player_index)
    local setup = storage.outpost_setup and storage.outpost_setup[event.player_index]
    if not setup or not setup.outpost or not setup.outpost.valid then
        player.play_sound {path = "utility/cannot_build"}
        return
    end

    local caravan_data = storage.caravans[setup.caravan_unit_number]
    if not caravan_data or not caravan_data.entity or not caravan_data.entity.valid then
        player.play_sound {path = "utility/cannot_build"}
        return
    end

    local outpost = setup.outpost

    local empty_action = CaravanUtils.ensure_item_count {
        type = "empty-inventory",
        localised_name = {"caravan-actions.empty-inventory", "empty-inventory"},
        async = true,
    }
    local wait_action = CaravanUtils.ensure_item_count {
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

    local existing_interrupts = table.invert(caravan_data.interrupts)
    for _, item in ipairs(setup.items) do
        if item.enabled then
            local name, is_new, station = CaravanUtils.ensure_item_quick_setup_interrupt(player, item.name, "normal", item.count)
            if not existing_interrupts[name] then
                table.insert(caravan_data.interrupts, name)
                existing_interrupts[name] = #caravan_data.interrupts
            end
            if is_new then
                if station and station.valid then
                    player.print {
                        "",
                        "[item=" .. item.name .. "] ",
                        string.format("[gps=%d, %d]", math.floor(station.position.x), math.floor(station.position.y)),
                    }
                else
                    player.print {"", "[item=" .. item.name .. "] (no source outpost found)"}
                end
            end
        end
    end

    if storage.outpost_setup then
        storage.outpost_setup[event.player_index] = nil
    end

    CaravanGuiComponents.update_schedule_pane(player)
end
