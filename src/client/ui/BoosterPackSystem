local BoosterPackSystem = {}
local BoosterBalanceConfig = require(script.Parent:WaitForChild("BoosterBalanceConfig"))

-- Edit this table to add or tune booster packs.
-- Replace Image with your asset IDs when ready.
local packDefinitions = BoosterBalanceConfig.Packs

local ownedCounts = {}
local changedEvent = Instance.new("BindableEvent")

function BoosterPackSystem.GetPacks()
	return packDefinitions
end

function BoosterPackSystem.GetOwnedCount(packId)
	return ownedCounts[packId] or 0
end

function BoosterPackSystem.GetOwnedSnapshot()
	local snapshot = {}
	for _, pack in ipairs(packDefinitions) do
		snapshot[pack.Id] = ownedCounts[pack.Id] or 0
	end
	return snapshot
end

function BoosterPackSystem.LoadOwnedSnapshot(snapshot)
	ownedCounts = {}
	if type(snapshot) == "table" then
		for _, pack in ipairs(packDefinitions) do
			local count = tonumber(snapshot[pack.Id]) or 0
			ownedCounts[pack.Id] = math.max(0, math.floor(count))
		end
	else
		for _, pack in ipairs(packDefinitions) do
			ownedCounts[pack.Id] = 0
		end
	end

	for _, pack in ipairs(packDefinitions) do
		changedEvent:Fire(pack.Id, ownedCounts[pack.Id] or 0)
	end
end

function BoosterPackSystem.OnChanged(callback)
	return changedEvent.Event:Connect(callback)
end

return BoosterPackSystem
