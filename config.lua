Config = {}

-- General Settings
Config.HoldUpTime = 10      -- Seconds for the NPC holdup timer
Config.FreezeTime = 15000   -- Milliseconds NPC stays frozen (15 seconds)
Config.TargetDistance = 2.5 -- Distance for the ox_target eye menu
Config.PaperBagTime = 1     -- Minutes the paper bag stays on (e.g., 5 = 5 minutes)

-- Items required for actions
Config.Items = {
    ziptie = "zipties",
    scissors = "scissors",
    paperbag = "paperbag"
}

-- Loot table for robbing NPCs
Config.NPCLoot = {
    { item = 'cash', min = 10, max = 50, chance = 100 }, -- Always get some cash
    { item = 'phone', min = 1, max = 1, chance = 10 },   -- 10% chance for a phone
    { item = 'sandwich', min = 1, max = 1, chance = 20 }, -- 20% chance for food
    { item = 'water', min = 1, max = 1, chance = 25 }
}