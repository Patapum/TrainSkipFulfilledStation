script.on_event(
    {defines.events.on_train_changed_state, defines.events.on_train_schedule_changed},
    function(e)
        local train = e.train
        if train.manual_mode == false and train.state ~= defines.train_state.wait_station and train.state ~= defines.train_state.arrive_station then
            UpdateNextTrainStation(train)
        end
    end
)

local SkipEmpty = settings.global["TrainSkipFulfilledStation-SkipEmpty"].value
local CheckCircuitConditions = settings.global["TrainSkipFulfilledStation-CheckCircuitConditions"].value

script.on_event(
    defines.events.on_runtime_mod_setting_changed,
    function(event)
        SkipEmpty = settings.global["TrainSkipFulfilledStation-SkipEmpty"].value
        CheckCircuitConditions = settings.global["TrainSkipFulfilledStation-CheckCircuitConditions"].value
    end
)

local UpdateNextTrainStationLock = true
function UpdateNextTrainStation(train)
    if UpdateNextTrainStationLock and train.schedule ~= nil then
        local next = GetNextNotFulfilled(train)
        if train.schedule.current ~= next then
            UpdateNextTrainStationLock = false
            train.schedule = {current = next, records = train.schedule.records}
            UpdateNextTrainStationLock = true
        end
    end
end

function GetNextNotFulfilled(train)
    local index = train.schedule.current
    if SkipEmpty == false and train.state == defines.train_state.arrive_station and train.schedule.records[index].wait_conditions == nil then
        index = NextScheduleIndex(index, #train.schedule.records)
    end
    repeat
        if IsAllFulfilled(train, train.schedule.records[index]) == false and
          AnyStationEnabled(train.schedule.records[index].station) then
            break
        end
        index = NextScheduleIndex(index, #train.schedule.records)
    until index == train.schedule.current
    return index
end

function NextScheduleIndex(current, recordsCount)
    current = current + 1
    if current > recordsCount then
        current = 1
    end
    return current
end

function IsAllFulfilled(train, schedule_record)
    local result = SkipEmpty
    local and_result = true
    local wait_conditions = schedule_record.wait_conditions
    if wait_conditions ~= nil then
        local station = nil
        if train.path_end_stop ~= nil and train.path_end_stop.backer_name == schedule_record.station then
            station = train.path_end_stop
        end
        for i = #wait_conditions, 1, -1 do
            local wait_condition = wait_conditions[i]
            and_result = and_result and IsFulfilled(train, station, wait_condition)
            if i == 1 or wait_condition.compare_type == "or" then
                if and_result then
                    return true
                else
                    result = false
                end
                and_result = true
            else
            end
        end
    end
    return result
end

function IsFulfilled(train, station, wait_condition)
    if wait_condition.type == "full" then
        return CheckFull(train)
    elseif wait_condition.type == "empty" then
        return CheckEmpty(train)
    elseif wait_condition.type == "item_count" then
        return CheckCondition(wait_condition.condition, function(signal_id) return train.get_item_count(signal_id.name) end)
    elseif wait_condition.type == "fluid_count" then
        return CheckCondition(wait_condition.condition, function(signal_id) return train.get_fluid_count(signal_id.name) end)
    elseif wait_condition.type == "circuit" then
        if CheckCircuitConditions then
            if station ~= nil then
                return CheckCondition(wait_condition.condition, station.get_merged_signal)
            else
                return false
            end
        else
            return CheckCondition(wait_condition.condition, function(signal_id) return 0 end)
        end
    elseif wait_condition.type == "passenger_present" then
        return CheckPassengerPresent(train)
    elseif wait_condition.type == "passenger_not_present" then
        return CheckPassengerPresent(train) == false
    else
        return false
    end
end

function CheckFull(train)
    for _, wagon in pairs(train.cargo_wagons) do
        local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)

        for index = #inventory, 1, -1 do
            local stack = inventory[index]
            if stack.valid_for_read == false then
                return false
            end
        end

        for item, _ in pairs(inventory.get_contents()) do
            if inventory.can_insert(item) then
                return false
            end
        end
    end

    for _, wagon in pairs(train.fluid_wagons) do
        for index = 1, #wagon.fluidbox do
            local fluidbox = wagon.fluidbox[index]
            if fluidbox == nil or wagon.fluidbox.get_capacity(index) > fluidbox.amount then
                return false
            end
        end
    end

    return true
end

function CheckEmpty(train)
    return train.get_item_count() == 0 and train.get_fluid_count() == 0
end

local NaN = 0/0

function CheckCondition(condition, get_count)
    if condition == nil then
        return false
    end

    local count_first =
        condition.first_signal == nil and NaN or get_count(condition.first_signal)
    local count_second =
        condition.second_signal == nil and (condition.constant or NaN) or
        get_count(condition.second_signal)

    if condition.comparator == "<" then
        return count_first < count_second
    elseif condition.comparator == "=" then
        return count_first == count_second
    elseif condition.comparator == "≥" then
        return count_first >= count_second
    elseif condition.comparator == "≤" then
        return count_first <= count_second
    elseif condition.comparator == "≠" then
        return count_first ~= count_second
    else
        return count_first > count_second
    end
end

function CheckPassengerPresent(train)
    return #train.passengers > 0
end

function AnyStationEnabled(station_name)
    local stations = game.get_train_stops({name = station_name})
    
    for _, station in pairs(stations) do
        local control = station.get_control_behavior()
        if control == nil or control.disabled == false then
            return true
        end
    end
    
    return false
end
