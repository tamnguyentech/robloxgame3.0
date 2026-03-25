-- Server-side handler for resetting all players' rolls and levels
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResetAllRollsEvent = ReplicatedStorage:FindFirstChild("ResetAllRollsEvent")
if not ResetAllRollsEvent then
    ResetAllRollsEvent = Instance.new("RemoteEvent")
    ResetAllRollsEvent.Name = "ResetAllRollsEvent"
    ResetAllRollsEvent.Parent = ReplicatedStorage
end

-- Reference the actual playerData table from SaveManager
local SaveManager = require(script.Parent:WaitForChild("SaveManager"))

ResetAllRollsEvent.OnServerEvent:Connect(function(sender)
    SaveManager.ResetAllPlayers(sender)
end)
