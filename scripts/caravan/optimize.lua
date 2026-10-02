local CaravanUtils = require "__pyalienlife__/scripts/caravan/utils"

local P = {}

local LOAD_ACTIONS = {["load-caravan"] = true, ["fill-tank-until-caravan-has"] = true}
local OPTIMISE_RESTARTS = 64

---@param schedule_entry table
---@return MapPosition?
local function schedule_entry_position(schedule_entry)
    if schedule_entry.entity and schedule_entry.entity.valid then return schedule_entry.entity.position end
    return schedule_entry.position
end

---Position of the interrupt's first load (or fill) target; falls back to its first target with a position.
---@param interrupt table
---@return MapPosition?
local function interrupt_load_position(interrupt)
    local fallback
    for _, entry in ipairs(interrupt.schedule or {}) do
        local pos = schedule_entry_position(entry)
        if pos then
            for _, action in ipairs(entry.actions or {}) do
                if LOAD_ACTIONS[action.type] then return pos end
            end
            fallback = fallback or pos
        end
    end
    return fallback
end

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

---Length of visiting `points` in `order`. With an anchor, the tour starts and ends there (closed loop).
local function tour_length(points, order, anchor)
    local total, prev = 0, anchor
    for i = 1, #order do
        local p = points[order[i]]
        if prev then total = total + dist(prev, p) end
        prev = p
    end
    if anchor and prev then total = total + dist(prev, anchor) end
    return total
end

---Improves `order` in place with 2-opt segment reversals until no reversal shortens the tour.
local function two_opt(points, order, anchor)
    local n = #order
    local function edge(a, b)
        if not a or not b then return 0 end
        return dist(a, b)
    end
    local improved = true
    while improved do
        improved = false
        for i = 1, n - 1 do
            for j = i + 1, n do
                local prev = i == 1 and anchor or points[order[i - 1]]
                local nxt = j == n and anchor or points[order[j + 1]]
                local pi, pj = points[order[i]], points[order[j]]
                local delta = edge(prev, pj) + edge(pi, nxt) - edge(prev, pi) - edge(pj, nxt)
                if delta < -1e-6 then
                    local a, b = i, j
                    while a < b do
                        order[a], order[b] = order[b], order[a]
                        a, b = a + 1, b - 1
                    end
                    improved = true
                end
            end
        end
    end
    return tour_length(points, order, anchor)
end

---Reorders the caravan's interrupts to minimise the straight-line distance travelled between their load
---stations. Interrupts allowed to interrupt other interrupts (`inside_interrupt`) and interrupts without
---any target position keep their slots; the rest are permuted among the remaining slots. The tour is
---anchored at the caravan's first regular schedule stop (usually the drop-off) when there is one.
---Uses random-restart 2-opt.
---@param caravan_data table
---@return number? old_length nil if there was nothing to optimise
---@return number? new_length
function P.optimise_interrupt_order(caravan_data)
    local slots, names, points = {}, {}, {}
    for i, name in ipairs(caravan_data.interrupts) do
        local interrupt = storage.interrupts[name]
        local pos = interrupt and not interrupt.inside_interrupt and interrupt_load_position(interrupt)
        if pos then
            slots[#slots + 1] = i
            names[#names + 1] = name
            points[#points + 1] = pos
        end
    end
    if #slots < 2 then return nil end

    local anchor
    for _, entry in ipairs(caravan_data.schedule) do
        anchor = schedule_entry_position(entry)
        if anchor then break end
    end

    local current = {}
    for i = 1, #points do current[i] = i end
    local old_length = tour_length(points, current, anchor)

    local best_order, best_length = table.deepcopy(current), old_length
    local rng = game.create_random_generator()
    for restart = 0, OPTIMISE_RESTARTS do
        local order = table.deepcopy(current)
        if restart > 0 then
            for i = #order, 2, -1 do
                local j = rng(i)
                order[i], order[j] = order[j], order[i]
            end
        end
        local len = two_opt(points, order, anchor)
        if len < best_length - 1e-6 then
            best_order, best_length = order, len
        end
    end

    for k, slot in ipairs(slots) do
        caravan_data.interrupts[slot] = names[best_order[k]]
    end
    return old_length, best_length
end

gui_events[defines.events.on_gui_click]["py_caravan_optimise_interrupt_order_button"] = function(event)
    local player = game.get_player(event.player_index)
    local caravan_data = storage.caravans[event.element.tags.unit_number]
    if not caravan_data then return end

    local old_length, new_length = P.optimise_interrupt_order(caravan_data)
    if not old_length or new_length >= old_length then
        player.play_sound {path = "utility/cannot_build"}
        return
    end

    player.print {"caravan-gui.optimise-interrupt-order-result", math.floor(old_length), math.floor(new_length)}
    CaravanGuiComponents.update_schedule_pane(player)
end

gui_events[defines.events.on_gui_click]["py_caravan_optimise_all_interrupt_orders_button"] = function(event)
    local player = game.get_player(event.player_index)

    local improved = 0
    for _, caravan_data in pairs(storage.caravans) do
        if caravan_data.entity and caravan_data.entity.valid
            and not CaravanUtils.entity_name_is_fluid_caravan(caravan_data.entity.name) then
            local old_length, new_length = P.optimise_interrupt_order(caravan_data)
            if old_length and new_length < old_length then
                improved = improved + 1
            end
        end
    end

    if improved == 0 then
        player.play_sound {path = "utility/cannot_build"}
        return
    end

    player.print {"caravan-gui.optimise-all-interrupt-orders-result", improved}
    CaravanGuiComponents.update_schedule_pane(player)
end

return P
