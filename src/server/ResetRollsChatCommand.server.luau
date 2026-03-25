-- Server-side chat command handler for /resetrolls and /givecoins (usable by everyone for now; can restrict to admin later)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResetAllRollsEvent = ReplicatedStorage:FindFirstChild("ResetAllRollsEvent")
if not ResetAllRollsEvent then
    ResetAllRollsEvent = Instance.new("RemoteEvent")
    ResetAllRollsEvent.Name = "ResetAllRollsEvent"
    ResetAllRollsEvent.Parent = ReplicatedStorage
end

Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        local msgLower = msg:lower()

        if msgLower == "/resetrolls" then
            local SaveManager = require(script.Parent:WaitForChild("SaveManager"))
            SaveManager.ResetAllPlayers(player)
            print("[ChatCmd] /resetrolls executed by", player.Name)
        end

        if msgLower == "/givecoins" then
            local SaveManager = require(script.Parent:WaitForChild("SaveManager"))
            local ServerStateManager = require(script.Parent.core:WaitForChild("ServerStateManager"))
            local playerData = SaveManager.playerData
            local saveEvent = ReplicatedStorage:WaitForChild("SaveDataEvent")
            if playerData[player.UserId] then
                local data = playerData[player.UserId]
                local grantAmount = 100000
                local delta = grantAmount - math.max(0, math.floor(tonumber(data.coins) or 0))
                data.coins = grantAmount
                -- Keep server-core in sync so subsequent economy deltas use the right base.
                if delta ~= 0 then
                    ServerStateManager.addCoins(player.UserId, delta)
                end
                -- Fire a COMPLETE snapshot so the client does not wipe inventory/items/stats.
                local reconciledStats = ServerStateManager.getStats(player.UserId)
                saveEvent:FireClient(player, {
                    coins        = data.coins,
                    rollCount    = data.rollCount,
                    level        = data.level,
                    inventory    = data.inventory,
                    combat       = data.combat,
                    boosterPacks = data.boosterPacks,
                    items        = data.items,
                    stats        = reconciledStats or data.stats,
                })
                print("[ChatCmd] /givecoins granted " .. grantAmount .. " coins to " .. player.Name)
            else
                warn("[ChatCmd] /givecoins – no player data for " .. player.Name)
            end
        end
    end)
end)
