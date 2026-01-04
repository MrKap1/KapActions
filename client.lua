local currentBagProp = nil
local isCarrying = false
local bagTimerActive = false

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function isLocalPlayerArmed()
    local ped = cache.ped
    return IsPedArmed(ped, 7)
end

local function isTargetCompliant(targetPed)
    -- 1. Check Native Task
    if GetIsTaskActive(targetPed, 134) then return true end

    -- 2. Bone Height Fail-safe (Hands above head check)
    local headPos = GetPedBoneCoords(targetPed, 31086, 0, 0, 0)
    local leftHandPos = GetPedBoneCoords(targetPed, 60309, 0, 0, 0)
    local rightHandPos = GetPedBoneCoords(targetPed, 57005, 0, 0, 0)

    if leftHandPos.z > headPos.z or rightHandPos.z > headPos.z then
        return true
    end

    -- 3. Check Animation Dictionaries
    local animations = {
        {dict = "random@mugging0", anim = "handsup_standing_base"},
        {dict = "missminuteman_1ig_2", anim = "handsup_base"},
        {dict = "mp_player_intupperhands_up", anim = "idle_a"},
        {dict = "nm", anim = "handsup_enter"},
        {dict = "random@arrests", anim = "idle_2_l_arrest_idle"},
        {dict = "random@arrests@busted", anim = "idle_a"}
    }

    for _, v in ipairs(animations) do
        if IsEntityPlayingAnim(targetPed, v.dict, v.anim, 3) then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- NPC THREAT LOGIC (FREEZE & HANDS UP)
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = 1000
        local playerPed = cache.ped

        -- Detect if aiming or "locking on" with a weapon
        if IsPlayerFreeAiming(PlayerId()) or IsControlPressed(0, 25) then
            sleep = 250
            local found, target = GetEntityPlayerIsFreeAimingAt(PlayerId())
            
            if found and DoesEntityExist(target) and not IsPedAPlayer(target) and IsEntityAPed(target) then
                if not IsPedDeadOrDying(target, true) then
                    -- 1. Make them freeze and put hands up
                    if not GetIsTaskActive(target, 134) then
                        ClearPedTasks(target)
                        TaskHandsUp(target, Config.FreezeTime or 15000, playerPed, -1, false)
                        SetEntityAsMissionEntity(target, true, true)
                        SetBlockingOfNonTemporaryEvents(target, true) -- Stops them from running away
                    end

                    -- 2. Force them to drop weapon if they have one
                    if IsPedArmed(target, 7) then
                        SetPedDropsInventoryWeapon(target, GetSelectedPedWeapon(target), 0.0, 0.6, -1.0, 0)
                        SetCurrentPedWeapon(target, `WEAPON_UNARMED`, true)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

--------------------------------------------------------------------------------
-- CORE FUNCTIONS
--------------------------------------------------------------------------------

function OpenActionMenu(targetId, isPlayer)
    local targetEntity = isPlayer and GetPlayerPed(GetPlayerFromServerId(targetId)) or NetToPed(targetId)
    
    if not DoesEntityExist(targetEntity) then return end
    
    local entState = Entity(targetEntity).state
    local isTied = entState.isZiptied
    local isKneeling = entState.isKneeling

    if not isTargetCompliant(targetEntity) and not isTied and not isKneeling then
        lib.notify({
            type = 'error', 
            description = 'Target is not complying! (Hands must be up)',
            position = 'top'
        })
        return
    end

    lib.registerContext({
        id = 'kap_actions_menu',
        title = isPlayer and 'Player Actions' or 'NPC Actions',
        options = {
            { 
                title = 'Carry / Drop', icon = 'person-walking-arrow-right', 
                onSelect = function() TriggerServerEvent('KapActions:server:requestPermission', targetId, 'carry', isPlayer) end 
            },
            { 
                title = 'Force Kneel', icon = 'person-falling', 
                onSelect = function() TriggerServerEvent('KapActions:server:requestPermission', targetId, 'kneel', isPlayer) end 
            },
            { 
                title = 'Rob', icon = 'mask', 
                onSelect = function() 
                    if isPlayer then
                        if isTied or isKneeling then
                            TriggerServerEvent('KapActions:server:startRobbery', targetId)
                        else
                            lib.notify({type = 'error', description = 'Target must be tied or kneeling!'})
                        end
                    else 
                        if lib.progressBar({
                            duration = (Config.HoldUpTime or 10) * 1000,
                            label = 'Searching...',
                            useWhileDead = false,
                            canCancel = true,
                            anim = { dict = 'anim@heists@prison_heiststation@cop_reactions', clip = 'cop_b_idle' },
                        }) then
                            TriggerServerEvent('KapActions:server:robNPC', targetId)
                        end
                    end 
                end 
            },
            { 
                title = isTied and 'Cut Zipties' or 'Tie Up', icon = isTied and 'scissors' or 'link', 
                onSelect = function() 
                    if isTied then TriggerServerEvent('KapActions:server:handleAction', targetId, 'ziptie', isPlayer)
                    else TriggerServerEvent('KapActions:server:requestPermission', targetId, 'ziptie', isPlayer) end
                end 
            },
            { 
                title = 'Paper Bag', icon = 'box', 
                onSelect = function() TriggerServerEvent('KapActions:server:requestPermission', targetId, 'paperbag', isPlayer) end 
            },
            { 
                title = 'Release Everything', icon = 'person-walking', 
                onSelect = function() TriggerServerEvent('KapActions:server:handleAction', targetId, 'free', isPlayer) end 
            },
        }
    })
    lib.showContext('kap_actions_menu')
end

local function togglePaperBag(targetPed, status)
    if status then
        local model = `prop_food_bs_bag_03`
        lib.requestModel(model)
        currentBagProp = CreateObject(model, 0, 0, 0, true, true, true)
        AttachEntityToEntity(currentBagProp, targetPed, GetPedBoneIndex(targetPed, 31086), 0.22, -0.02, 0.0, -90.0, 0.0, 90.0, true, true, false, true, 1, true)
        
        if targetPed == cache.ped then
            DoScreenFadeOut(500) 
            DisplayRadar(false) 
            bagTimerActive = true
            CreateThread(function()
                local timer = (Config.PaperBagTime or 1) * 60 
                while DoesEntityExist(currentBagProp) and bagTimerActive do
                    if not IsScreenFadedOut() then DoScreenFadeOut(0) end
                    Wait(1000)
                    timer = timer - 1
                    if timer <= 0 then
                        bagTimerActive = false
                        TriggerServerEvent('KapActions:server:handleAction', GetPlayerServerId(PlayerId()), 'free', true)
                        break
                    end
                end
            end)
        end
    else
        bagTimerActive = false
        if DoesEntityExist(currentBagProp) then DeleteEntity(currentBagProp) currentBagProp = nil end
        if targetPed == cache.ped then 
            DoScreenFadeIn(1000) 
            DisplayRadar(true) 
        end
    end
end

--------------------------------------------------------------------------------
-- SYNCING
--------------------------------------------------------------------------------

RegisterNetEvent('KapActions:client:syncAction', function(data, actorId, isNpcAction)
    local targetPed = cache.ped
    local actionType = data
    local actorPed = GetPlayerPed(GetPlayerFromServerId(actorId))

    if isNpcAction then
        targetPed = NetToPed(data.npcNetId)
        actionType = data.actualAction
    end

    if not DoesEntityExist(targetPed) then return end

    if actionType == 'kneel' then
        lib.requestAnimDict("random@arrests")
        TaskPlayAnim(targetPed, "random@arrests", "kneeling_arrest_idle", 8.0, -8.0, -1, 1, 0, false, false, false)
    elseif actionType == 'ziptie' then
        if not isNpcAction and targetPed == cache.ped then LocalPlayer.state:set('invBusy', true, true) end
        lib.requestAnimDict("mp_arresting")
        TaskPlayAnim(targetPed, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
    elseif actionType == 'paperbag' then
        togglePaperBag(targetPed, true)
    elseif actionType == 'beingCarried' then
        lib.requestAnimDict("nm")
        SetEntityCollision(targetPed, false, false)
        AttachEntityToEntity(targetPed, actorPed, 0, 0.27, 0.15, 0.63, 0.5, 0.5, 180.0, false, false, false, false, 2, true)
        TaskPlayAnim(targetPed, "nm", "firemans_carry", 8.0, -8.0, -1, 33, 0, false, false, false)
    elseif actionType == 'carrierAnim' then
        lib.requestAnimDict("missfinale_c2mcs_1")
        TaskPlayAnim(cache.ped, "missfinale_c2mcs_1", "fin_c2_mcs_1_camman", 8.0, -8.0, -1, 49, 0, false, false, false)
        isCarrying = true 
    elseif actionType == 'drop' or actionType == 'free' or actionType == 'untie' then
        isCarrying = false
        if targetPed == cache.ped then 
            bagTimerActive = false
            LocalPlayer.state:set('invBusy', false, true) 
        end
        togglePaperBag(targetPed, false)
        DetachEntity(targetPed, true, true)
        SetEntityCollision(targetPed, true, true)
        ClearPedTasksImmediately(targetPed)
        if actorPed == cache.ped then 
            ClearPedTasksImmediately(cache.ped) 
            lib.hideTextUI() 
        end
        local coords = GetEntityCoords(actorPed)
        local forward = GetEntityForwardVector(actorPed)
        SetEntityCoords(targetPed, coords.x + forward.x * 0.8, coords.y + forward.y * 0.8, coords.z - 1.0)
    end
end)

--------------------------------------------------------------------------------
-- TARGETING & CALLBACKS
--------------------------------------------------------------------------------

exports.ox_target:addGlobalPlayer({{
    name = 'kapactions:interact_player', 
    icon = 'fa-solid fa-user-tag', 
    label = 'Interact', 
    distance = Config.TargetDistance or 2.0,
    canInteract = function(entity) 
        return isLocalPlayerArmed() 
    end,
    onSelect = function(data) 
        local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))
        OpenActionMenu(targetServerId, true) 
    end
}})

exports.ox_target:addGlobalPed({{
    name = 'kapactions:interact_npc', 
    icon = 'fa-solid fa-person-rays', 
    label = 'Interact', 
    distance = Config.TargetDistance or 2.0,
    canInteract = function(entity) 
        return not IsPedAPlayer(entity) and isLocalPlayerArmed() 
    end,
    onSelect = function(data) 
        local netId = NetworkGetNetworkIdFromEntity(data.entity)
        OpenActionMenu(netId, false) 
    end
}})

lib.callback.register('KapActions:client:getPermission', function(actionType, requesterId)
    local alert = lib.alertDialog({
        header = 'Action Request',
        content = 'Player [' .. requesterId .. '] wants to ' .. actionType .. ' you. Accept?',
        centered = true, cancel = true
    })
    return alert == 'confirm'
end)

--------------------------------------------------------------------------------
-- DROP LOGIC (PRESS E)
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = 1000
        if isCarrying then
            sleep = 0
            lib.showTextUI('[E] - Drop Person', {position = "left-center"})
            
            if IsControlJustPressed(0, 38) then
                local playerPed = cache.ped
                local attachedEntity = nil
                
                local nearbyPlayers = lib.getNearbyPlayers(GetEntityCoords(playerPed), 2.0)
                for _, v in pairs(nearbyPlayers) do
                    if IsEntityAttachedToEntity(v.ped, playerPed) then
                        attachedEntity = v.ped
                        local tId = GetPlayerServerId(v.id)
                        TriggerServerEvent('KapActions:server:handleAction', tId, 'drop', true)
                        break
                    end
                end
                
                if not attachedEntity then
                    local nearbyPeds = lib.getNearbyPeds(GetEntityCoords(playerPed), 2.0)
                    for _, v in pairs(nearbyPeds) do
                        if IsEntityAttachedToEntity(v.ped, playerPed) then
                            attachedEntity = v.ped
                            local netId = NetworkGetNetworkIdFromEntity(v.ped)
                            TriggerServerEvent('KapActions:server:handleAction', netId, 'drop', false)
                            break
                        end
                    end
                end

                if not attachedEntity then
                    isCarrying = false
                    lib.hideTextUI()
                    ClearPedTasksImmediately(playerPed)
                end
                Wait(500)
            end
        end
        Wait(sleep)
    end
end)