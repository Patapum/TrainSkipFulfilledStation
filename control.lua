script.on_event(
    {defines.events.on_train_changed_state},
    function(e)
        local train = e.train
        if train.manual_mode == false then
            UpdateNextTrainStation(train)
        end
    end
)

local SkipEmpty = settings.global["TrainSkipFulfilledStation-SkipEmpty"].value

script.on_event(
    defines.events.on_runtime_mod_setting_changed,
    function(event)
        SkipEmpty = settings.global["TrainSkipFulfilledStation-SkipEmpty"].value
    end
)

function UpdateNextTrainStation(train)
    if train.schedule ~= nil then
        local next = GetNextNotFulfilled(train)
        if train.schedule.current ~= next then
            train.schedule = {current = next, records = train.schedule.records}
        end
    end
end

function GetNextNotFulfilled(train)
    local index = train.schedule.current
    if SkipEmpty == false and train.state == defines.train_state.arrive_station and train.schedule.records[index].wait_conditions == nil then
        index = NextScheduleIndex(index, #train.schedule.records)
    end
    repeat
        if IsAllFulfilled(train, train.schedule.records[index].wait_conditions) == false then
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

function IsAllFulfilled(train, wait_conditions)
    local result = SkipEmpty
    local and_result = true
    if wait_conditions ~= nil then
        for i = #wait_conditions, 1, -1 do
            local wait_condition = wait_conditions[i]
            and_result = and_result and IsFulfilled(train, wait_condition)
            if wait_condition.compare_type == "or" then
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

function IsFulfilled(train, wait_condition)
    if wait_condition.type == "full" then
        return CheckFull(train)
    elseif wait_condition.type == "empty" then
        return CheckEmpty(train)
    elseif wait_condition.type == "item_count" then
        return CheckCondition(wait_condition.condition, train.get_item_count)
    elseif wait_condition.type == "fluid_count" then
        return CheckCondition(wait_condition.condition, train.get_fluid_count)
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

function CheckCondition(condition, get_count)
    if condition == nil then
        return false
    end

    local count_first =
        condition.first_signal == nil and 0 or get_count(condition.first_signal.name)
    local count_second =
        condition.second_signal == nil and (condition.constant or 0) or
        get_count(condition.second_signal.name)

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
