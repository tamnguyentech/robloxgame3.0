local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IdleRollProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IdleRollProtocol"))

local idleEvent = ReplicatedStorage:FindFirstChild("IdleCardEvent")
if not (idleEvent and idleEvent:IsA("BindableEvent")) then
	if idleEvent then
		idleEvent:Destroy()
	end
	idleEvent = Instance.new("BindableEvent")
	idleEvent.Name = "IdleCardEvent"
	idleEvent.Parent = ReplicatedStorage
end

local remotesFolder = ReplicatedStorage:WaitForChild(IdleRollProtocol.Remotes.FolderName)
local rewardEvent = remotesFolder:WaitForChild(IdleRollProtocol.Remotes.RewardEvent)

rewardEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.cardId) ~= "string" or payload.cardId == "" then
		return
	end

	idleEvent:Fire({
		cardId = payload.cardId,
		rollCount = payload.rollCount,
		level = payload.level,
	})
end)
