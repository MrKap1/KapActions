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

    -- 2. Check Bone Height (Fail-safe)
    -- If the hands (bones 60309 or 57005) are higher than the head (bone 31086), 
    -- they definitely have their hands up.
    local headPos = GetPedBoneCoords(targetPed, 31086, 0, 0, 0)
    local leftHandPos = GetPedBoneCoords(targetPed, 60309, 0, 0, 0)
    local rightHandPos = GetPedBoneCoords(targetPed, 57005, 0, 0, 0)

    if leftHandPos.z > headPos.z or rightHandPos.z > headPos.z then
        return true
    end

    -- 3. Check for common Scenarios
    if IsPedUsingAnyScenario(targetPed) or IsEntityPlayingAnim(targetPed, "nm", "handsup_fall", 3) then
        return true
    end

    -- 4. Standard Animation List (Existing list)
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
                            duration = 5000,
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
                local timer = (Config.PaperBagTime or 5) * 60 
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
    distance = 2.0,
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
    distance = 2.0,
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

RegisterCommand('checkanim', function()
    local player, distance = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
    if player then
        local targetPed = GetPlayerPed(player)
        local dict = "Unknown"
        local anim = "Unknown"
        
        -- This checks every common dictionary to see what is currently playing
        local commonDicts = {"random@mugging0", "missminuteman_1ig_2", "mp_player_intupperhands_up", "nm", "random@arrests", "random@arrests@busted"}
        
        for _, d in ipairs(commonDicts) do
            if IsEntityPlayingAnim(targetPed, d, "", 3) then -- Check if any anim in dict is playing
                dict = d
            end
        end

        print("--- ANIMATION DEBUG ---")
        print("Native Task 134 (Hands Up):", GetIsTaskActive(targetPed, 134))
        print("Detected Dictionary:", dict)
        lib.notify({title = "Debug", description = "Check F8 Console", type = "inform"})
    else
        print("No player nearby to check.")
    end
end)