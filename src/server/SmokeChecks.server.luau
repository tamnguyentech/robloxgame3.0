local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoosterBalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoosterBalanceConfig"))
local EconomyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyCatalog"))
local EconomyProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyProtocol"))
local IdleRollProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IdleRollProtocol"))

local function warnCheck(msg)
	warn("[SmokeChecks] " .. msg)

	-- Ensure StatsHandler (which creates AllocatePointsRemote) is loaded so handler is connected
	require(script.Parent:WaitForChild("StatsHandler"))
	print("[SmokeChecks] Required StatsHandler, AllocatePointsRemote handler should be connected.")
end

local function checkBoosterConfig()
	local seenIds = {}
	for _, pack in ipairs(BoosterBalanceConfig.Packs or {}) do
		if type(pack.Id) ~= "string" or pack.Id == "" then
			warnCheck("Pack has invalid Id")
		elseif seenIds[pack.Id] then
			warnCheck("Duplicate pack Id: " .. pack.Id)
		else
			seenIds[pack.Id] = true
		end

		if (tonumber(pack.Price) or 0) <= 0 then
			warnCheck("Pack has non-positive price: " .. tostring(pack.Id))
		end
		if (tonumber(pack.CardsPerOpen) or 0) <= 0 then
			warnCheck("Pack has non-positive CardsPerOpen: " .. tostring(pack.Id))
		end
	end
end

local function checkEconomyCatalog()
	for itemId, offer in pairs(EconomyCatalog.Items or {}) do
		if (tonumber(offer.Price) or 0) <= 0 then
			warnCheck("Item offer has non-positive price: " .. tostring(itemId))
		end
		if (tonumber(offer.GrantAmount) or 0) <= 0 then
			warnCheck("Item offer has non-positive grant amount: " .. tostring(itemId))
		end
	end

	for cardId, offer in pairs(EconomyCatalog.DirectCards or {}) do
		if (tonumber(offer.Price) or 0) <= 0 then
			warnCheck("Direct card offer has non-positive price: " .. tostring(cardId))
		end
		if (tonumber(offer.GrantAmount) or 0) <= 0 then
			warnCheck("Direct card offer has non-positive grant amount: " .. tostring(cardId))
		end
	end
end

local function checkProtocol()
	if type(EconomyProtocol.Remotes.FolderName) ~= "string" or EconomyProtocol.Remotes.FolderName == "" then
		warnCheck("EconomyProtocol.Remotes.FolderName is invalid")
	end
	if type(EconomyProtocol.Remotes.Request) ~= "string" or EconomyProtocol.Remotes.Request == "" then
		warnCheck("EconomyProtocol.Remotes.Request is invalid")
	end

	for actionName, actionValue in pairs(EconomyProtocol.ActionType or {}) do
		if type(actionValue) ~= "string" or actionValue == "" then
			warnCheck("Economy action is invalid: " .. tostring(actionName))
		end
	end

	if type(IdleRollProtocol.Remotes.FolderName) ~= "string" or IdleRollProtocol.Remotes.FolderName == "" then
		warnCheck("IdleRollProtocol.Remotes.FolderName is invalid")
	end
	if type(IdleRollProtocol.Remotes.RewardEvent) ~= "string" or IdleRollProtocol.Remotes.RewardEvent == "" then
		warnCheck("IdleRollProtocol.Remotes.RewardEvent is invalid")
	end
	if type(IdleRollProtocol.Remotes.ControlEvent) ~= "string" or IdleRollProtocol.Remotes.ControlEvent == "" then
		warnCheck("IdleRollProtocol.Remotes.ControlEvent is invalid")
	end
end

checkBoosterConfig()
checkEconomyCatalog()
checkProtocol()
