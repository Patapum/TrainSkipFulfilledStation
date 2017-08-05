script.on_load(
    function()
        script.on_event(
            {defines.events.on_train_changed_state},
            function(e)
                local train = e.train
                if train.manual_mode == false then
                    UpdateNextTrainStation(train)
                end
            end
        )
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
    local result = nil
    if wait_conditions ~= nil then
        for _, wait_condition in pairs(wait_conditions) do
            if result == nil then
                result = IsFulfilled(train, wait_condition)
            elseif wait_condition.compare_type == "and" then
                result = result and IsFulfilled(train, wait_condition)
            else
                result = result or IsFulfilled(train, wait_condition)
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
