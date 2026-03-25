-- BuffBridge.luau
-- Centralized get-or-create for Luck/FoilChance buff events and IntValue bridges.
-- IdleCardGainer writes IntValues; ItemsTab fires events; ProfileUIController reads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffBridge = {}

local _luckBuffEvent = nil
local _foilChanceBuffEvent = nil
local _luckBuffBonusValue = nil
local _foilChanceBuffBonusValue = nil
local _borderChanceBuffBonusValue = nil

function BuffBridge.GetLuckBuffEvent()
	if not _luckBuffEvent then
		local ev = ReplicatedStorage:FindFirstChild("LuckBuffEvent")
		if not (ev and ev:IsA("BindableEvent")) then
			if ev then ev:Destroy() end
			ev = Instance.new("BindableEvent")
			ev.Name = "LuckBuffEvent"
			ev.Parent = ReplicatedStorage
		end
		_luckBuffEvent = ev
	end
	return _luckBuffEvent
end

function BuffBridge.GetFoilChanceBuffEvent()
	if not _foilChanceBuffEvent then
		local ev = ReplicatedStorage:FindFirstChild("FoilChanceBuffEvent")
		if not (ev and ev:IsA("BindableEvent")) then
			if ev then ev:Destroy() end
			ev = Instance.new("BindableEvent")
			ev.Name = "FoilChanceBuffEvent"
			ev.Parent = ReplicatedStorage
		end
		_foilChanceBuffEvent = ev
	end
	return _foilChanceBuffEvent
end

function BuffBridge.GetLuckBuffBonusValue()
	if not _luckBuffBonusValue then
		local v = ReplicatedStorage:FindFirstChild("LuckBuffBonus")
		if not (v and v:IsA("IntValue")) then
			if v then v:Destroy() end
			v = Instance.new("IntValue")
			v.Name = "LuckBuffBonus"
			v.Value = 0
			v.Parent = ReplicatedStorage
		end
		_luckBuffBonusValue = v
	end
	return _luckBuffBonusValue
end

function BuffBridge.GetFoilChanceBuffBonusValue()
	if not _foilChanceBuffBonusValue then
		local v = ReplicatedStorage:FindFirstChild("FoilChanceBuffBonus")
		if not (v and v:IsA("IntValue")) then
			if v then v:Destroy() end
			v = Instance.new("IntValue")
			v.Name = "FoilChanceBuffBonus"
			v.Value = 0
			v.Parent = ReplicatedStorage
		end
		_foilChanceBuffBonusValue = v
	end
	return _foilChanceBuffBonusValue
end

return BuffBridge
