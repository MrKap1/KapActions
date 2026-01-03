local qbx = exports.qbx_core

--------------------------------------------------------------------------------
-- OX_INVENTORY HOOK (FORCE ALLOW ROBBING)
--------------------------------------------------------------------------------
exports.ox_inventory:registerHook('openInventory', function(payload)
    local targetId = payload.inventoryId 

    if type(targetId) == 'number' then
        local targetPed = GetPlayerPed(targetId)
        if targetPed ~= 0 then
            local state = Entity(targetPed).state
            -- Only allow opening the inventory if they are restrained
            if state.isZiptied or state.isKneeling then
                return true 
            end
        end
    end
end, {
    inventoryFilter = {
        '^player'
    }
})

--------------------------------------------------------------------------------
-- ROBBERY HANDLERS
--------------------------------------------------------------------------------

-- Player Robbery (Opens Inventory)
RegisterNetEvent('KapActions:server:startRobbery', function(targetId)
    local src = source
    local targetPed = GetPlayerPed(targetId)
    
    if targetPed ~= 0 then
        local state = Entity(targetPed).state
        if state.isZiptied or state.isKneeling then
            exports.ox_inventory:forceOpenInventory(src, 'player', targetId)
        else
            TriggerClientEvent('ox_lib:notify', src, {type = 'error', description = 'Target is not restrained!'})
        end
    end
end)

-- NPC Robbery (Gives Loot from Config)
RegisterNetEvent('KapActions:server:robNPC', function(netId)
    local src = source
    local entity = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(entity) then
        local state = Entity(entity).state
        
        if state.isRobbed then 
            return TriggerClientEvent('ox_lib:notify', src, {type = 'error', description = 'This person has already been searched.'}) 
        end

        if state.isZiptied or state.isKneeling then
            local itemsFound = false
            for _, loot in pairs(Config.NPCLoot) do
                if math.random(1, 100) <= loot.chance then
                    local amount = math.random(loot.min, loot.max)
                    if exports.ox_inventory:CanCarryItem(src, loot.item, amount) then
                        exports.ox_inventory:AddItem(src, loot.item, amount)
                        itemsFound = true
                    end
                end
            end

            state:set('isRobbed', true, true)

            if itemsFound then
                TriggerClientEvent('ox_lib:notify', src, {type = 'success', description = 'You found some items.'})
            else
                TriggerClientEvent('ox_lib:notify', src, {type = 'inform', description = 'They had nothing of value.'})
            end
        else
            TriggerClientEvent('ox_lib:notify', src, {type = 'error', description = 'They need to be restrained first!'})
        end
    end
end)

--------------------------------------------------------------------------------
-- PERMISSION BRIDGE
--------------------------------------------------------------------------------
RegisterNetEvent('KapActions:server:requestPermission', function(targetId, action, isPlayer)
    local src = source
    
    -- If it's an NPC, we don't ask for permission, just do it
    if not isPlayer or targetId == 0 then
        TriggerEvent('KapActions:server:handleAction', targetId, action, false, src)
        return
    end

    -- If it's a player, send the dialog box
    lib.callback('KapActions:client:getPermission', targetId, function(accepted)
        if accepted then
            TriggerEvent('KapActions:server:handleAction', targetId, action, true, src)
        else
            TriggerClientEvent('ox_lib:notify', src, {type = 'error', description = 'Action declined.'})
        end
    end, action, src)
end)

--------------------------------------------------------------------------------
-- MAIN ACTION HANDLER
--------------------------------------------------------------------------------
RegisterNetEvent('KapActions:server:handleAction', function(targetId, actionType, isPlayer, actorOverride)
    local src = actorOverride or source
    local targetEntity = isPlayer and GetPlayerPed(targetId) or NetworkGetEntityFromNetworkId(targetId)
    
    if not DoesEntityExist(targetEntity) then return end
    local entState = Entity(targetEntity).state

    -- 1. ZIP TIE LOGIC
    if actionType == 'ziptie' then
        local itemNeeded = entState.isZiptied and Config.Items.scissors or Config.Items.ziptie
        if exports.ox_inventory:GetItemCount(src, itemNeeded) < 1 then
            return TriggerClientEvent('ox_lib:notify', src, {type='error', description='Missing item: '..itemNeeded})
        end
        
        local newState = not entState.isZiptied
        entState:set('isZiptied', newState, true)
        if newState then exports.ox_inventory:RemoveItem(src, Config.Items.ziptie, 1) end
        if not newState then actionType = 'untie' end

    -- 2. PAPER BAG LOGIC
    elseif actionType == 'paperbag' then
        if not entState.hasPaperBag then
            if exports.ox_inventory:GetItemCount(src, Config.Items.paperbag) < 1 then
                return TriggerClientEvent('ox_lib:notify', src, {type='error', description='You need a paper bag!'})
            end
            exports.ox_inventory:RemoveItem(src, Config.Items.paperbag, 1)
        end
        local newState = not entState.hasPaperBag
        entState:set('hasPaperBag', newState, true)
        if not newState then actionType = 'free' end

    -- 3. MOVEMENT/KNEEL LOGIC
    elseif actionType == 'carry' or actionType == 'drop' then
        if actionType == 'drop' or entState.isBeingCarried then
            actionType = 'drop'
            entState:set('isBeingCarried', false, true)
        else
            actionType = 'beingCarried'
            entState:set('isBeingCarried', true, true)
        end
    elseif actionType == 'kneel' then
        local newState = not entState.isKneeling
        entState:set('isKneeling', newState, true)
        if not newState then actionType = 'free' end
    elseif actionType == 'free' then
        entState:set('isZiptied', false, true)
        entState:set('isBeingCarried', false, true)
        entState:set('isKneeling', false, true)
        entState:set('hasPaperBag', false, true)
    end

    -- 4. SYNCING TO CLIENTS
    if isPlayer then
        TriggerClientEvent('KapActions:client:syncAction', targetId, actionType, src, false)
        
        if actionType == 'beingCarried' then 
            TriggerClientEvent('KapActions:client:syncAction', src, 'carrierAnim', src, false)
        elseif actionType == 'drop' or actionType == 'free' or actionType == 'untie' then 
            TriggerClientEvent('KapActions:client:syncAction', src, 'drop', src, false) 
        end
    else
        TriggerClientEvent('KapActions:client:syncAction', -1, {npcNetId = targetId, actualAction = actionType}, src, true)
        
        if actionType == 'beingCarried' then 
            TriggerClientEvent('KapActions:client:syncAction', src, 'carrierAnim', src, false) 
        elseif actionType == 'drop' or actionType == 'free' or actionType == 'untie' then 
            TriggerClientEvent('KapActions:client:syncAction', src, 'drop', src, false) 
        end
    end
end)