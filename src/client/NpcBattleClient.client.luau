local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")

local BattleProtocol     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BattleProtocol"))
local cardArtFolder      = ReplicatedStorage:WaitForChild("CardArt")
local CardDatabase       = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local CardVisualResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardVisualResolver"))
local HoloFoilController = require(script.Parent.ui.effects:WaitForChild("HoloFoilController"))
local RainbowBorderStroke = require(script.Parent.ui.effects:WaitForChild("RainbowBorderStroke"))
local ClientStateManager = require(script.Parent.core:WaitForChild("ClientStateManager"))
local DeviceContext = require(script.Parent.core:WaitForChild("DeviceContext"))
local DamagePopupManager = require(script.Parent.ui:WaitForChild("DamagePopupManager"))
-- PvE enemy card (NPC) hit feedback
-- Removed unused cardArtFolder assignment

local function waitForRemote(folder, remoteName)
	local remote = folder:WaitForChild(remoteName)
	while not remote:IsA("RemoteEvent") do
		remote = folder:WaitForChild(remoteName)
	end
	return remote
end

local remotesFolder = ReplicatedStorage:WaitForChild(BattleProtocol.Remotes.FolderName)
local requestBattleEvent = waitForRemote(remotesFolder, BattleProtocol.Remotes.RequestBattle)
local battleInviteEvent = waitForRemote(remotesFolder, BattleProtocol.Remotes.BattleInvite)
local battleStateEvent = waitForRemote(remotesFolder, BattleProtocol.Remotes.BattleState)
local battleActionEvent = waitForRemote(remotesFolder, BattleProtocol.Remotes.BattleAction)

local bridgeEvent = ReplicatedStorage:FindFirstChild("NpcBattleClientBridge")
if not (bridgeEvent and bridgeEvent:IsA("BindableEvent")) then
	if bridgeEvent then
		bridgeEvent:Destroy()
	end
	bridgeEvent = Instance.new("BindableEvent")
	bridgeEvent.Name = "NpcBattleClientBridge"
	bridgeEvent.Parent = ReplicatedStorage
end

local AUTO_REQUEST_BATTLE_ON_INVITE = true
local player = Players.LocalPlayer
local MAX_DECK_SYNC_RETRIES = 10
local DECK_SYNC_RETRY_DELAY = 0.25
local BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS = 1.0
local trackedBattleVideoFrames = {}
local preloadedBattleVideoAssets = {}
local lastBattleVideoTimePosition = {}
local BATTLE_FX_TIME_SCALE = 1.35
local BATTLE_FX_LIFETIME_SCALE = 1.45
local ABILITY_WORLD_BURST_COOLDOWN_SECONDS = 0.16
local abilityWorldBurstCooldownByEffect = {}

local function fxTime(seconds)
	return math.max(0.01, (tonumber(seconds) or 0) * BATTLE_FX_TIME_SCALE)
end

local function fxLife(seconds)
	return math.max(0.05, (tonumber(seconds) or 0) * BATTLE_FX_LIFETIME_SCALE)
end

local function ensureBattleVideoFramePlayback(videoFrame, videoAssetId)
	if not (videoFrame and videoFrame:IsA("VideoFrame")) then
		return
	end

	local function forcePlay()
		videoFrame.Playing = true
		pcall(function()
			videoFrame:Play()
		end)
	end

	trackedBattleVideoFrames[videoFrame] = true
	if not preloadedBattleVideoAssets[videoAssetId] then
		preloadedBattleVideoAssets[videoAssetId] = true
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({videoAssetId})
			end)
		end)
	end

	local shouldRestart = (videoFrame.Video ~= videoAssetId)
	videoFrame.Looped = true
	videoFrame.Video = videoAssetId
	if shouldRestart then
		videoFrame.TimePosition = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
	end
	forcePlay()

	task.defer(function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId then
			forcePlay()
		end
	end)
	task.delay(0.15, function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId then
			forcePlay()
		end
	end)
	task.delay(0.4, function()
		if not (videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId) then
			return
		end
		local pos = tonumber(videoFrame.TimePosition) or 0
		if pos <= 0.02 then
			videoFrame.Video = ""
			task.wait()
			if not (videoFrame.Parent and videoFrame.Visible) then
				return
			end
			videoFrame.Video = videoAssetId
			videoFrame.TimePosition = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
			forcePlay()
		end
	end)
end

local battleVideoGuardAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	battleVideoGuardAccumulator += dt
	if battleVideoGuardAccumulator < 0.2 then
		return
	end
	battleVideoGuardAccumulator = 0

	for videoFrame in pairs(trackedBattleVideoFrames) do
		if not videoFrame.Parent then
			trackedBattleVideoFrames[videoFrame] = nil
			lastBattleVideoTimePosition[videoFrame] = nil
		elseif videoFrame.Visible and videoFrame.Video ~= "" and videoFrame.Video ~= "rbxassetid://0" then
			videoFrame.Looped = true
			if not videoFrame.Playing then
				videoFrame.Playing = true
				pcall(function()
					videoFrame:Play()
				end)
			end

			local currentPos = tonumber(videoFrame.TimePosition) or 0
			local lastPos = lastBattleVideoTimePosition[videoFrame]
			if lastPos and currentPos + 0.03 < lastPos and currentPos < BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS then
				videoFrame.TimePosition = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
				currentPos = BATTLE_VIDEO_LOOP_START_OFFSET_SECONDS
			end
			lastBattleVideoTimePosition[videoFrame] = currentPos
		end
	end
end)

local function findCardArtDecal(cardId)
	if type(cardId) ~= "string" or cardId == "" then
		return nil
	end

	local exact = cardArtFolder:FindFirstChild(cardId)
	if exact and exact:IsA("Decal") then
		return exact
	end

	local target = string.lower(cardId)
	for _, obj in ipairs(cardArtFolder:GetChildren()) do
		if obj:IsA("Decal") and string.lower(obj.Name) == target then
			return obj
		end
	end

	return nil
end

local function emitWorldParticleBurst(color, burstCount, distanceFromCamera)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local fxPart = Instance.new("Part")
	fxPart.Name = "BattleParticleBurst"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CanTouch = false
	fxPart.Transparency = 1
	fxPart.Size = Vector3.new(0.2, 0.2, 0.2)
	fxPart.CFrame = camera.CFrame * CFrame.new(0, 0, -(tonumber(distanceFromCamera) or 12))
	fxPart.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = fxPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CardAttackEmitter"
	emitter.Rate = 0
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.fromRGB(255, 184, 90), 0.35)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 122, 36)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(84, 18, 8)),
	})
	emitter.LightEmission = 0.9
	emitter.LightInfluence = 0
	emitter.Lifetime = NumberRange.new(0.45, 0.95)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.Drag = 2
	emitter.SpreadAngle = Vector2.new(95, 95)
	emitter.Acceleration = Vector3.new(0, 8, 0)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(0.35, 0.44),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(0.6, 0.36),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Parent = attachment

	emitter:Emit(math.max(4, math.floor(tonumber(burstCount) or 20)))
	Debris:AddItem(fxPart, fxLife(1.2))
end

local function emitAbilityWorldParticleBurst(effectType, color)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local effect = tostring(effectType or "")
	local burstColor = color or Color3.fromRGB(230, 230, 230)
	local texture = "rbxasset://textures/particles/fire_main.dds"
	local speed = NumberRange.new(9, 18)
	local lifetime = NumberRange.new(0.45, 0.95)
	local spread = Vector2.new(90, 90)
	local acceleration = Vector3.new(0, 8, 0)
	local burstCount = 28

	if effect == "TeamAttackSpeedBoost" then
		texture = "rbxasset://textures/particles/sparkles_main.dds"
		burstColor = Color3.fromRGB(130, 210, 255)
		speed = NumberRange.new(18, 34)
		lifetime = NumberRange.new(0.38, 0.8)
		spread = Vector2.new(45, 45)
		acceleration = Vector3.new(0, -4, 0)
		burstCount = 34
	elseif effect == "HealLowestAlly" then
		texture = "rbxasset://textures/particles/sparkles_main.dds"
		burstColor = Color3.fromRGB(126, 255, 180)
		speed = NumberRange.new(7, 16)
		lifetime = NumberRange.new(0.7, 1.25)
		spread = Vector2.new(55, 55)
		acceleration = Vector3.new(0, 10, 0)
		burstCount = 30
	end

	local fxPart = Instance.new("Part")
	fxPart.Name = "AbilityParticleBurst"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.CanTouch = false
	fxPart.Transparency = 1
	fxPart.Size = Vector3.new(0.2, 0.2, 0.2)
	fxPart.CFrame = camera.CFrame * CFrame.new(0, 0, -8)
	fxPart.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = fxPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AbilityBuffEmitter"
	emitter.Rate = 0
	emitter.Texture = texture
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, burstColor:Lerp(Color3.fromRGB(255, 255, 255), 0.22)),
		ColorSequenceKeypoint.new(1, burstColor:Lerp(Color3.fromRGB(30, 30, 30), 0.25)),
	})
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Lifetime = lifetime
	emitter.Speed = speed
	emitter.Drag = 2
	emitter.SpreadAngle = spread
	emitter.Acceleration = acceleration
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.35, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment

	emitter:Emit(burstCount)
	Debris:AddItem(fxPart, fxLife(1.4))
end

local function resolveArtScaleType(data, imageObj)
	if data and data.ArtFitMode == "Stretch" then
		return Enum.ScaleType.Stretch
	end
	if data and data.ArtFitMode == "Crop" then
		return Enum.ScaleType.Crop
	end
	if data and data.ArtFitMode == "Fit" then
		return Enum.ScaleType.Fit
	end

	if imageObj then
		local modeAttr = imageObj:GetAttribute("ArtFitMode")
		if type(modeAttr) == "string" then
			local normalized = string.lower(modeAttr)
			if normalized == "stretch" then
				return Enum.ScaleType.Stretch
			end
			if normalized == "crop" then
				return Enum.ScaleType.Crop
			end
			return Enum.ScaleType.Fit
		end
		if imageObj:GetAttribute("ForceStretch") == true or imageObj:GetAttribute("SquareArt") == true then
			return Enum.ScaleType.Stretch
		end
	end

	return Enum.ScaleType.Fit
end
local HIT_SOUND_ASSET = "rbxassetid://9118828568"
local PLAYER_ATTACK_SOUND_ASSET = "rbxassetid://12222242"
local BOSS_HIT_SOUND_ASSET = "rbxassetid://91078784560732" -- Public explosion sound
local ABILITY_SPEED_SOUND_ASSET = "rbxassetid://9113420775"
local ABILITY_DAMAGE_SOUND_ASSET = "rbxassetid://9118828568"
local ABILITY_HEAL_SOUND_ASSET = "rbxassetid://9048375035"
local BOSS_ATTACK_SOUND_TIME_OFFSET = 0.07

local ABILITY_SOUND_PROFILE_BY_EFFECT = {
	TeamAttackSpeedBoost = {
		assetId = ABILITY_SPEED_SOUND_ASSET,
		volume = 0.22,
		speedMin = 1.04,
		speedMax = 1.18,
		layerAssetId = ABILITY_SPEED_SOUND_ASSET,
		layerVolume = 0.1,
		layerSpeedMin = 1.2,
		layerSpeedMax = 1.34,
	},
	TeamAttackDamageBoost = {
		assetId = ABILITY_DAMAGE_SOUND_ASSET,
		volume = 0.26,
		speedMin = 0.9,
		speedMax = 1.0,
		layerAssetId = HIT_SOUND_ASSET,
		layerVolume = 0.15,
		layerSpeedMin = 0.68,
		layerSpeedMax = 0.78,
	},
	HealLowestAlly = {
		assetId = ABILITY_HEAL_SOUND_ASSET,
		volume = 0.2,
		speedMin = 1.02,
		speedMax = 1.14,
		layerAssetId = ABILITY_HEAL_SOUND_ASSET,
		layerVolume = 0.09,
		layerSpeedMin = 1.24,
		layerSpeedMax = 1.38,
	},
}

local function playOneShotAbilitySound(parentGui, assetId, volume, speedMin, speedMax)
	if not (parentGui and assetId) then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "AbilityBuffSound"
	sound.SoundId = assetId
	sound.Volume = math.max(0, tonumber(volume) or 0.2)
	sound.RollOffMaxDistance = 44
	sound.PlaybackSpeed = (tonumber(speedMin) or 1) + (math.random() * math.max(0, (tonumber(speedMax) or 1) - (tonumber(speedMin) or 1)))
	sound.PlayOnRemove = false
	sound.Parent = parentGui
	sound:Play()
	Debris:AddItem(sound, 2)
end

local function playAbilitySound(effectType)
	local profile = ABILITY_SOUND_PROFILE_BY_EFFECT[tostring(effectType or "")]
	if not profile then
		return
	end

	local playerGui = player and player:FindFirstChild("PlayerGui")
	local parentGui = playerGui and playerGui:FindFirstChild("NpcBattleGui")
	if not parentGui then
		return
	end

	playOneShotAbilitySound(parentGui, profile.assetId, profile.volume, profile.speedMin, profile.speedMax)
	if profile.layerAssetId then
		playOneShotAbilitySound(parentGui, profile.layerAssetId, profile.layerVolume, profile.layerSpeedMin, profile.layerSpeedMax)
	end
end

local uiState = {
	sessionId = nil,
	deckSnapshot = {},
	gui = nil,
	npcEnemyHpLabel = nil,
	npcEnemyNameLabel = nil,
	npcEnemyCardFrame = nil,
	rootFrame = nil,
	deckRowFrame = nil,
	exitButton = nil,
	deckCardsById = {},
	deckCardBySlot = {},
	npcDrDebuffEndClock = nil,
	npcDrDebuffPercent = nil,
	npcDrDebuffHbConn = nil,
	speedBoostEndBySlot = {},
	speedBoostMagBySlot = {},
	speedBoostHbConn = nil,
}

local function clearDeckCardMappings()
	uiState.deckCardsById = {}
	uiState.deckCardBySlot = {}
end

local function removeCardViewFromMappings(cardView)
	if not cardView then
		return
	end

	for cardId, views in pairs(uiState.deckCardsById) do
		for i = #views, 1, -1 do
			if views[i] == cardView then
				table.remove(views, i)
			end
		end
		if #views == 0 then
			uiState.deckCardsById[cardId] = nil
		end
	end

	for slotIndex, mapped in pairs(uiState.deckCardBySlot) do
		if mapped == cardView then
			uiState.deckCardBySlot[slotIndex] = nil
		end
	end
end

local function createBattleGui(payload)
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("NpcBattleGui")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "NpcBattleGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 420
	gui.Parent = playerGui

	-- Create transparent animation layer
	local animLayer = Instance.new("ScreenGui")
	animLayer.Name = "BattleAnimLayer"
	animLayer.ResetOnSpawn = false
	animLayer.DisplayOrder = 421 -- Above NpcBattleGui
	animLayer.Parent = playerGui
	animLayer.IgnoreGuiInset = true
	-- Transparent full-screen frame for effects
	local animFrame = Instance.new("Frame")
	animFrame.Name = "AnimRoot"
	animFrame.Size = UDim2.fromScale(1, 1)
	animFrame.BackgroundTransparency = 1
	animFrame.BorderSizePixel = 0
    animFrame.ClipsDescendants = true
	animFrame.Parent = animLayer

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1) -- Make the battle UI row even taller for more room
	root.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
	root.BackgroundTransparency = 0.28
	root.BorderSizePixel = 0
	root.Parent = gui

	local npcEnemyCard = Instance.new("Frame")
	npcEnemyCard.Name = "NpcEnemyCard"
	npcEnemyCard.AnchorPoint = Vector2.new(0.5, 0)
	npcEnemyCard.Size = UDim2.fromOffset(200, 240) -- Make the NPC card frame smaller
	npcEnemyCard.Position = UDim2.new(0.5, 0, 0, 40) -- Move the NPC card further down
	npcEnemyCard.BackgroundColor3 = Color3.fromRGB(28, 20, 20)
	npcEnemyCard.BorderSizePixel = 0
	npcEnemyCard.ClipsDescendants = false
	npcEnemyCard.Parent = root
	npcEnemyCard:SetAttribute("IsNpcCard", true)

	local npcCorner = Instance.new("UICorner")
	npcCorner.CornerRadius = UDim.new(0, 12)
	npcCorner.Parent = npcEnemyCard

	local npcStroke = Instance.new("UIStroke")
	npcStroke.Thickness = 2
	npcStroke.Color = Color3.fromRGB(186, 70, 70)
	npcStroke.Transparency = 0.1
	npcStroke.Parent = npcEnemyCard

	local npcArt = Instance.new("ImageLabel")
	npcArt.Name = "NpcEnemyArt"
	npcArt.Size = UDim2.fromScale(1, 1)
	npcArt.Position = UDim2.new(0, 0, 0, 0)
	npcArt.BackgroundTransparency = 1
	npcArt.BorderSizePixel = 0
	npcArt.ScaleType = Enum.ScaleType.Stretch
	npcArt.ClipsDescendants = true -- Only clip card art, not the card frame
	npcArt.Image = "" -- will be set below
	npcArt.Parent = npcEnemyCard

	local npcTitle = Instance.new("TextLabel")
	npcTitle.Name = "NpcEnemyTitle"
	npcTitle.Size = UDim2.new(1, -20, 0, 52)
	npcTitle.Position = UDim2.fromOffset(10, 8)
	npcTitle.BackgroundTransparency = 1
	npcTitle.Text = "Foe"
	npcTitle.TextColor3 = Color3.fromRGB(245, 245, 245)
	npcTitle.Font = Enum.Font.Fantasy
	npcTitle.TextSize = 30
	npcTitle.TextWrapped = true
	npcTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	npcTitle.TextStrokeTransparency = 0.2
	npcTitle.Parent = npcEnemyCard

	local cardDatabaseModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
	local npcCardId = payload and payload.npcCardId or "PerfectCell"
	local npcRow = cardDatabaseModule.GetCardData and cardDatabaseModule.GetCardData(npcCardId)
	if npcRow and type(npcRow.ArtAssetId) == "string" and npcRow.ArtAssetId ~= "" then
		npcArt.Image = npcRow.ArtAssetId
	end
	npcEnemyCard:SetAttribute("CardId", npcCardId)

	local npcHp = Instance.new("TextLabel")
	npcHp.Name = "NpcEnemyHp"
	npcHp.Size = UDim2.new(1, -20, 0, 36)
	npcHp.Position = UDim2.fromOffset(10, 68)
	npcHp.BackgroundTransparency = 1
	npcHp.Text = "HP: 0 / 0"
	npcHp.TextColor3 = Color3.fromRGB(255, 130, 130)
	npcHp.Font = Enum.Font.SourceSansBold
	npcHp.TextSize = 24
	npcHp.TextXAlignment = Enum.TextXAlignment.Center
	npcHp.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	npcHp.TextStrokeTransparency = 0.25
	npcHp.Parent = npcEnemyCard

	local npcHint = Instance.new("TextLabel")
	npcHint.Name = "NpcEnemyHint"
	npcHint.Size = UDim2.new(1, -20, 0, 28)
	npcHint.Position = UDim2.new(0, 10, 1, -36)
	npcHint.BackgroundTransparency = 1
	npcHint.Text = "Your card attack speeds vary"
	npcHint.TextColor3 = Color3.fromRGB(220, 220, 220)
	npcHint.Font = Enum.Font.SourceSans
	npcHint.TextSize = 20
	npcHint.TextXAlignment = Enum.TextXAlignment.Center
	npcHint.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	npcHint.TextStrokeTransparency = 0.3
	npcHint.Parent = npcEnemyCard

	local npcDrBar = Instance.new("Frame")
	npcDrBar.Name = "NpcOutgoingDrDebuffBar"
	npcDrBar.Visible = false
	npcDrBar.Size = UDim2.new(1, -16, 0, 30)
	npcDrBar.Position = UDim2.new(0, 8, 0, 102)
	npcDrBar.BackgroundColor3 = Color3.fromRGB(48, 26, 68)
	npcDrBar.BackgroundTransparency = 0.1
	npcDrBar.BorderSizePixel = 0
	npcDrBar.ZIndex = 18
	npcDrBar.Parent = npcEnemyCard
	local npcDrCorner = Instance.new("UICorner")
	npcDrCorner.CornerRadius = UDim.new(0, 8)
	npcDrCorner.Parent = npcDrBar
	local npcDrStroke = Instance.new("UIStroke")
	npcDrStroke.Thickness = 1.5
	npcDrStroke.Color = Color3.fromRGB(190, 140, 255)
	npcDrStroke.Transparency = 0.25
	npcDrStroke.Parent = npcDrBar
	local npcDrText = Instance.new("TextLabel")
	npcDrText.Name = "DrText"
	npcDrText.Size = UDim2.fromScale(1, 1)
	npcDrText.BackgroundTransparency = 1
	npcDrText.Font = Enum.Font.GothamBold
	npcDrText.TextSize = 16
	npcDrText.TextColor3 = Color3.fromRGB(245, 210, 255)
	npcDrText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	npcDrText.TextStrokeTransparency = 0.35
	npcDrText.Text = "DR 10% · 0.0s"
	npcDrText.Parent = npcDrBar

	local deckRow = Instance.new("Frame")
	deckRow.Name = "DeckRow"
	deckRow.AnchorPoint = Vector2.new(0.5, 1)
	deckRow.Size = UDim2.new(1, -64, 0, 274)
	deckRow.Position = UDim2.new(0.5, 0, 1, -16)
	deckRow.BackgroundColor3 = Color3.fromRGB(15, 19, 28)
	deckRow.BackgroundTransparency = 0.16
	deckRow.BorderSizePixel = 0
	deckRow.Parent = root

	local deckCorner = Instance.new("UICorner")
	deckCorner.CornerRadius = UDim.new(0, 12)
	deckCorner.Parent = deckRow

	local deckStroke = Instance.new("UIStroke")
	deckStroke.Thickness = 1
	deckStroke.Color = Color3.fromRGB(95, 120, 180)
	deckStroke.Transparency = 0.2
	deckStroke.Parent = deckRow

	local deckLayout = Instance.new("UIListLayout")
	deckLayout.FillDirection = Enum.FillDirection.Horizontal
	deckLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	deckLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	deckLayout.Padding = UDim.new(0, 14)
	deckLayout.Parent = deckRow

	local deckPadding = Instance.new("UIPadding")
	deckPadding.PaddingLeft = UDim.new(0, 16)
	deckPadding.PaddingRight = UDim.new(0, 16)
	deckPadding.PaddingTop = UDim.new(0, 12)
	deckPadding.PaddingBottom = UDim.new(0, 12)
	deckPadding.Parent = deckRow

	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitBattleButton"
	exitButton.AnchorPoint = Vector2.new(1, 0.5)
	exitButton.Size = UDim2.fromOffset(136, math.max(44, DeviceContext.getTouchTargetMin()))
	exitButton.Position = UDim2.new(1, -18, 0.5, 0)
	exitButton.BackgroundColor3 = Color3.fromRGB(172, 42, 42)
	exitButton.BackgroundTransparency = 0.08
	exitButton.BorderSizePixel = 0
	exitButton.Font = Enum.Font.SourceSansBold
	exitButton.TextSize = 24
	exitButton.TextColor3 = Color3.fromRGB(245, 245, 245)
	exitButton.Text = "Exit Battle"
	exitButton.ZIndex = 35
	exitButton.Parent = root

	local exitCorner = Instance.new("UICorner")
	exitCorner.CornerRadius = UDim.new(0, 8)
	exitCorner.Parent = exitButton

	local exitStroke = Instance.new("UIStroke")
	exitStroke.Thickness = 1
	exitStroke.Color = Color3.fromRGB(94, 14, 14)
	exitStroke.Transparency = 0.12
	exitStroke.Parent = exitButton

	uiState.gui = gui
	uiState.rootFrame = root
	uiState.deckRowFrame = deckRow
	uiState.npcEnemyHpLabel = npcHp
	uiState.npcEnemyNameLabel = npcTitle
	uiState.npcEnemyCardFrame = npcEnemyCard
	uiState.exitButton = exitButton

	local hitSound = Instance.new("Sound")
	hitSound.Name = "BattleHitSound"
	hitSound.SoundId = HIT_SOUND_ASSET
	hitSound.Volume = 0.225
	hitSound.RollOffMaxDistance = 40
	hitSound.Parent = gui

	local playerAttackSound = Instance.new("Sound")
	playerAttackSound.Name = "PlayerAttackSound"
	playerAttackSound.SoundId = PLAYER_ATTACK_SOUND_ASSET
	playerAttackSound.Volume = 0.25
	playerAttackSound.RollOffMaxDistance = 40
	playerAttackSound.Parent = gui

	local npcEnemyAttackSound = Instance.new("Sound")
	npcEnemyAttackSound.Name = "NpcEnemyAttackSound"
	npcEnemyAttackSound.SoundId = BOSS_HIT_SOUND_ASSET
	npcEnemyAttackSound.Volume = 0.3
	npcEnemyAttackSound.RollOffMaxDistance = 44
	npcEnemyAttackSound.Parent = gui

	exitButton.MouseButton1Click:Connect(function()
		if not uiState.sessionId then
			gui.Enabled = false
			return
		end

		battleActionEvent:FireServer({
			actionType = BattleProtocol.ActionType.Surrender,
			sessionId = uiState.sessionId,
		})
		gui.Enabled = false
	end)

	return gui
end

local function createDeckCardView(cardId)
	   local data = CardDatabase.GetCardData(cardId)
	   local frame = Instance.new("Frame")
	   frame.Name = "DeckCard_" .. tostring(cardId)
	   frame.Size = UDim2.fromOffset(168, 234)
	   frame.BackgroundColor3 = Color3.fromRGB(24, 28, 42)
	   frame.BorderSizePixel = 0
	   frame:SetAttribute("CardId", cardId)
	   -- Mark NPC cards for shake effect
	   if data and data.IsNpcCard == true then
		   frame:SetAttribute("IsNpcCard", true)
	   else
		   frame:SetAttribute("IsNpcCard", false)
	   end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.Size = UDim2.new(1, -8, 1, -8)
	art.Position = UDim2.fromOffset(4, 4)
	art.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	art.BackgroundTransparency = 0.05
	art.BorderSizePixel = 0
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = frame
	-- (Removed blood VFX overlay for TestBattleCard)

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 8)
	artCorner.Parent = art

	local artStroke = Instance.new("UIStroke")
	artStroke.Thickness = 1
	artStroke.Color = Color3.fromRGB(58, 68, 96)
	artStroke.Transparency = 0.35
	artStroke.Parent = art

	local videoAssetId = data and data.VideoAssetId
	if type(videoAssetId) == "string" and videoAssetId ~= "" and videoAssetId ~= "rbxassetid://0" then
		local artVideo = Instance.new("VideoFrame")
		artVideo.Name = "ArtVideo"
		artVideo.Size = UDim2.fromScale(1, 1)
		artVideo.Position = UDim2.fromOffset(0, 0)
		artVideo.BackgroundTransparency = 1
		artVideo.BorderSizePixel = 0
		artVideo.ZIndex = art.ZIndex + 1
		artVideo.Visible = true
		artVideo.Parent = art
		ensureBattleVideoFramePlayback(artVideo, videoAssetId)
		art.Image = ""
	else
		local decal = findCardArtDecal(cardId)
		if decal and decal.Texture then
			art.Image = decal.Texture
		elseif data and type(data.ArtAssetId) == "string" and data.ArtAssetId ~= "" and data.ArtAssetId ~= "rbxassetid://0" then
			art.Image = data.ArtAssetId
		end
	end
	art.ScaleType = resolveArtScaleType(data, nil)

	local stroke = Instance.new("UIStroke")
	stroke.Name = "CardBorderStroke"
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(130, 154, 214)
	stroke.Transparency = 0.24
	stroke.Parent = frame

	local spdBar = Instance.new("Frame")
	spdBar.Name = "AtkSpeedBuffBar"
	spdBar.Visible = false
	spdBar.Size = UDim2.new(1, -12, 0, 22)
	spdBar.Position = UDim2.new(0, 6, 0, 4)
	spdBar.BackgroundColor3 = Color3.fromRGB(22, 48, 72)
	spdBar.BackgroundTransparency = 0.08
	spdBar.BorderSizePixel = 0
	spdBar.ZIndex = 6
	spdBar.Parent = frame
	local spdCorner = Instance.new("UICorner")
	spdCorner.CornerRadius = UDim.new(0, 7)
	spdCorner.Parent = spdBar
	local spdStroke = Instance.new("UIStroke")
	spdStroke.Thickness = 1
	spdStroke.Color = Color3.fromRGB(100, 190, 255)
	spdStroke.Transparency = 0.25
	spdStroke.Parent = spdBar
	local spdText = Instance.new("TextLabel")
	spdText.Name = "SpdText"
	spdText.Size = UDim2.fromScale(1, 1)
	spdText.BackgroundTransparency = 1
	spdText.Font = Enum.Font.GothamBold
	spdText.TextSize = 13
	spdText.TextColor3 = Color3.fromRGB(160, 225, 255)
	spdText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	spdText.TextStrokeTransparency = 0.35
	spdText.Text = "ATK SPD +0% · 0.0s"
	spdText.Parent = spdBar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 66)
	nameLabel.Position = UDim2.fromOffset(5, 28)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextWrapped = true
	nameLabel.Text = data and data.Name or tostring(cardId)
	nameLabel.TextColor3 = Color3.fromRGB(242, 246, 255)
	nameLabel.Font = Enum.Font.Fantasy
	nameLabel.TextSize = 20
	nameLabel.ZIndex = 4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(10, 10, 16)
	nameLabel.TextStrokeTransparency = 0.15
	nameLabel.Parent = frame

	local atkLabel = Instance.new("TextLabel")
	atkLabel.Name = "AtkLabel"
	atkLabel.Size = UDim2.new(1, -10, 0, 40)
	atkLabel.AnchorPoint = Vector2.new(0.5, 1)
	atkLabel.Position = UDim2.new(0.5, 0, 1, -10)
	atkLabel.BackgroundColor3 = Color3.fromRGB(78, 24, 19)
	atkLabel.BackgroundTransparency = 1
	atkLabel.Text = "ATK " .. CardDatabase.FormatAttack((data and data.Attack) or 0)
	atkLabel.TextColor3 = Color3.fromRGB(255, 115, 98)
	atkLabel.Font = Enum.Font.Arcade
	atkLabel.TextSize = 22
	atkLabel.ZIndex = 4
	atkLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	atkLabel.TextStrokeTransparency = 0.05
	atkLabel.Parent = frame

	local atkCorner = Instance.new("UICorner")
	atkCorner.CornerRadius = UDim.new(0, 8)
	atkCorner.Parent = atkLabel

	local atkStroke = Instance.new("UIStroke")
	atkStroke.Thickness = 1
	atkStroke.Color = Color3.fromRGB(0, 0, 0)
	atkStroke.Transparency = 0.32
	atkStroke.Parent = atkLabel

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HpLabel"
	hpLabel.Size = UDim2.new(1, -10, 0, 34)
	hpLabel.AnchorPoint = Vector2.new(0.5, 1)
	hpLabel.Position = UDim2.new(0.5, 0, 1, -52)
	hpLabel.BackgroundColor3 = Color3.fromRGB(18, 74, 28)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text = "HP " .. CardDatabase.FormatAttack((data and data.Health) or 0)
	hpLabel.TextColor3 = Color3.fromRGB(108, 255, 145)
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextSize = 22
	hpLabel.ZIndex = 4
	hpLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0.05
	hpLabel.Parent = frame

	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 8)
	hpCorner.Parent = hpLabel

	local hpStroke = Instance.new("UIStroke")
	hpStroke.Thickness = 1
	hpStroke.Color = Color3.fromRGB(0, 0, 0)
	hpStroke.Transparency = 0.32
	hpStroke.Parent = hpLabel

	return frame
end

local function playCardDeathAnimation(cardView)
	if not cardView or not cardView.Parent then
		if cardView then
			cardView:Destroy()
		end
		return
	end
	if cardView:GetAttribute("IsDying") then
		return
	end
	cardView:SetAttribute("IsDying", true)

	local root = uiState.rootFrame
	if root and root.Parent then
		local centerAbs = cardView.AbsolutePosition + (cardView.AbsoluteSize * 0.5)
		local rootAbs = root.AbsolutePosition
		for i = 1, 10 do
			local shard = Instance.new("Frame")
			shard.Name = "CardDeathShard"
			shard.AnchorPoint = Vector2.new(0.5, 0.5)
			shard.BorderSizePixel = 0
			shard.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(250, 85, 85) or Color3.fromRGB(24, 20, 28)
			shard.BackgroundTransparency = 0.12
			shard.Size = UDim2.fromOffset(math.random(4, 10), math.random(10, 18))
			shard.Position = UDim2.fromOffset(centerAbs.X - rootAbs.X + math.random(-12, 12), centerAbs.Y - rootAbs.Y + math.random(-12, 12))
			shard.Rotation = math.random(0, 180)
			shard.ZIndex = 95
			shard.Parent = root

			local angle = math.rad(math.random(0, 359))
			local radius = math.random(38, 72)
			local ex = (centerAbs.X - rootAbs.X) + (math.cos(angle) * radius)
			local ey = (centerAbs.Y - rootAbs.Y) + (math.sin(angle) * radius)

			TweenService:Create(
				shard,
				TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromOffset(ex, ey),
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(2, 2),
				}
			):Play()
			Debris:AddItem(shard, 0.32)
		end
	end

	local deathFlash = Instance.new("Frame")
	deathFlash.Name = "CardDeathFlash"
	deathFlash.Size = UDim2.fromScale(1, 1)
	deathFlash.Position = UDim2.fromOffset(0, 0)
	deathFlash.BackgroundColor3 = Color3.fromRGB(255, 95, 95)
	deathFlash.BackgroundTransparency = 0.4
	deathFlash.BorderSizePixel = 0
	deathFlash.ZIndex = 98
	deathFlash.Parent = cardView

	local deathCorner = Instance.new("UICorner")
	deathCorner.CornerRadius = UDim.new(0, 10)
	deathCorner.Parent = deathFlash

	TweenService:Create(
		deathFlash,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	):Play()
	Debris:AddItem(deathFlash, 0.24)

	for _, obj in ipairs(cardView:GetDescendants()) do
		if obj:IsA("TextLabel") then
			TweenService:Create(
				obj,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{TextTransparency = 1, TextStrokeTransparency = 1}
			):Play()
		elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			TweenService:Create(
				obj,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ImageTransparency = 1, BackgroundTransparency = 1}
			):Play()
		elseif obj:IsA("Frame") or obj:IsA("TextButton") then
			TweenService:Create(
				obj,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundTransparency = 1}
			):Play()
		elseif obj:IsA("UIStroke") then
			TweenService:Create(
				obj,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Transparency = 1}
			):Play()
		end
	end

	TweenService:Create(
		cardView,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{
			Size = UDim2.fromOffset(math.max(20, math.floor(cardView.AbsoluteSize.X * 0.68)), math.max(20, math.floor(cardView.AbsoluteSize.Y * 0.68))),
			Rotation = 12,
			BackgroundTransparency = 1,
		}
	):Play()

	task.delay(0.28, function()
		if cardView and cardView.Parent then
			cardView:Destroy()
		end
	end)
end

local function stopDeckSpeedBuffUi()
	if uiState.speedBoostHbConn then
		uiState.speedBoostHbConn:Disconnect()
		uiState.speedBoostHbConn = nil
	end
	uiState.speedBoostEndBySlot = {}
	uiState.speedBoostMagBySlot = {}
	for s = 1, 5 do
		local cv = uiState.deckCardBySlot[s]
		local b = cv and cv:FindFirstChild("AtkSpeedBuffBar")
		if b then
			b.Visible = false
		end
	end
end

local function tickDeckSpeedBuffLabels()
	for slotIndex, endClock in pairs(uiState.speedBoostEndBySlot) do
		local cardView = uiState.deckCardBySlot[slotIndex]
		local bar = cardView and cardView:FindFirstChild("AtkSpeedBuffBar")
		local txt = bar and bar:FindFirstChild("SpdText")
		if not (bar and txt and bar.Parent) then
			uiState.speedBoostEndBySlot[slotIndex] = nil
			uiState.speedBoostMagBySlot[slotIndex] = nil
		else
			local left = math.max(0, (tonumber(endClock) or 0) - os.clock())
			local mag = tonumber(uiState.speedBoostMagBySlot[slotIndex]) or 0
			if left <= 0.05 or mag <= 0 then
				bar.Visible = false
				uiState.speedBoostEndBySlot[slotIndex] = nil
				uiState.speedBoostMagBySlot[slotIndex] = nil
			else
				local pct = math.floor(mag * 100 + 0.5)
				txt.Text = string.format("ATK SPD +%d%% · %.1fs", pct, left)
			end
		end
	end
end

local function ensureDeckSpeedBuffHeartbeat()
	if uiState.speedBoostHbConn then
		return
	end
	uiState.speedBoostHbConn = RunService.Heartbeat:Connect(function()
		tickDeckSpeedBuffLabels()
	end)
end

local function syncDeckSpeedBuffFromCardState(state, slotIndex, cardView)
	local spdBar = cardView:FindFirstChild("AtkSpeedBuffBar")
	local spdText = spdBar and spdBar:FindFirstChild("SpdText")
	if not (spdBar and spdText) then
		return
	end
	local rem = tonumber(state.speedBoostRemainingSec) or 0
	local mag = tonumber(state.speedBoostMagnitude) or 0
	if rem > 0 and mag > 0 then
		uiState.speedBoostEndBySlot[slotIndex] = os.clock() + rem
		uiState.speedBoostMagBySlot[slotIndex] = mag
		spdBar.Visible = true
		local pct = math.floor(mag * 100 + 0.5)
		spdText.Text = string.format("ATK SPD +%d%% · %.1fs", pct, rem)
		ensureDeckSpeedBuffHeartbeat()
	else
		uiState.speedBoostEndBySlot[slotIndex] = nil
		uiState.speedBoostMagBySlot[slotIndex] = nil
		spdBar.Visible = false
	end
end

local function applyPlayerCardStates(playerCardStates)
	if type(playerCardStates) ~= "table" then
		return
	end

	for _, state in ipairs(playerCardStates) do
		local slotIndex = state.slotIndex
		local cardView = (type(slotIndex) == "number") and uiState.deckCardBySlot[slotIndex] or nil
		if cardView and cardView.Parent then
			local hp = math.max(0, math.floor(tonumber(state.health) or 0))
			local maxHp = math.max(1, math.floor(tonumber(state.maxHealth) or 1))
			local alive = state.isAlive ~= false and hp > 0
			local attack = math.max(1, math.floor(tonumber(state.attack) or 1))

			local atkLabel = cardView:FindFirstChild("AtkLabel")
			if atkLabel and atkLabel:IsA("TextLabel") then
				atkLabel.Text = "ATK " .. CardDatabase.FormatAttack(attack)
			end

			local hpLabel = cardView:FindFirstChild("HpLabel")
			if hpLabel and hpLabel:IsA("TextLabel") then
				hpLabel.Text = string.format("HP %s/%s", CardDatabase.FormatAttack(hp), CardDatabase.FormatAttack(maxHp))
			end

			if type(slotIndex) == "number" then
				syncDeckSpeedBuffFromCardState(state, slotIndex, cardView)
			end

			if not alive then
				if type(slotIndex) == "number" then
					uiState.speedBoostEndBySlot[slotIndex] = nil
					uiState.speedBoostMagBySlot[slotIndex] = nil
					local sb = cardView:FindFirstChild("AtkSpeedBuffBar")
					if sb then
						sb.Visible = false
					end
				end
				removeCardViewFromMappings(cardView)
				if cardView:GetAttribute("IsAnimatingAttack") then
					cardView:SetAttribute("PendingDeath", true)
				else
					playCardDeathAnimation(cardView)
				end
			end
		end
	end
end

local function renderDeckRow(deckSnapshot)
	local gui = createBattleGui()
	local root = gui:FindFirstChild("Root")
	local deckRow = root and root:FindFirstChild("DeckRow")
	if not deckRow then
		return
	end

	clearDeckCardMappings()
	for _, child in ipairs(deckRow:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^DeckCard_") then
			child:Destroy()
		end
	end

	-- Resolve player FoilChance once for the whole deck build rather than per card.
	local _stats = ClientStateManager.getStats and ClientStateManager.getStats() or {}
	local _battleFoilChance = _stats.FoilChance or _stats.BorderChance or 0

	for _, entry in ipairs(deckSnapshot) do
		local cardId = entry.cardId
		local slotIndex = entry.slotIndex
		local cardView = createDeckCardView(cardId)
		cardView.Parent = deckRow
		if not uiState.deckCardsById[cardId] then
			uiState.deckCardsById[cardId] = {}
		end
		table.insert(uiState.deckCardsById[cardId], cardView)
		if type(slotIndex) == "number" then
			uiState.deckCardBySlot[slotIndex] = cardView
		end

		-- Apply holographic foil to bordered cards so the battle deck surface
		-- matches what the player sees in Inventory.
		local visualStyle = CardVisualResolver.resolve(cardId, _battleFoilChance, nil)
		if visualStyle.isBordered then
			local outerStroke = cardView:FindFirstChild("CardBorderStroke")
				or cardView:FindFirstChildOfClass("UIStroke")
			if outerStroke and outerStroke:IsA("UIStroke") then
				if visualStyle.tierKey == "Rainbow" then
					RainbowBorderStroke.attach(outerStroke)
				else
					RainbowBorderStroke.detach(outerStroke)
					outerStroke.Color = visualStyle.strokeColor
				end
			end
			local foilCtrl = HoloFoilController.Attach(cardView, visualStyle.foilOpts)
			cardView.Destroying:Connect(function()
				if outerStroke and outerStroke.Parent then
					RainbowBorderStroke.detach(outerStroke)
				end
				foilCtrl:Destroy()
			end)
		end
	end
end

local function animateSingleDeckAttack(attackerSlotIndex, attackerCardId)
	local cardView = nil
	if type(attackerSlotIndex) == "number" then
		cardView = uiState.deckCardBySlot[attackerSlotIndex]
	end

	if not cardView and type(attackerCardId) == "string" then
		local views = uiState.deckCardsById[attackerCardId]
		if views and #views > 0 then
			cardView = views[1]
		end
	end

	if not (cardView and cardView.Parent) then
		return
	end

	local root = uiState.rootFrame
	local npcEnemyCard = uiState.npcEnemyCardFrame
	local deckRow = uiState.deckRowFrame
	if not (root and root.Parent and npcEnemyCard and npcEnemyCard.Parent and deckRow and deckRow.Parent) then
		return
	end

	if cardView:GetAttribute("IsAnimatingAttack") then
		return
	end
	cardView:SetAttribute("IsAnimatingAttack", true)

	local startAbs = cardView.AbsolutePosition + (cardView.AbsoluteSize * 0.5)
	local npcAbs = npcEnemyCard.AbsolutePosition + (npcEnemyCard.AbsoluteSize * 0.5)
	local rootAbs = root.AbsolutePosition
	local startLocal = startAbs - rootAbs
	local targetLocal = Vector2.new(npcAbs.X - rootAbs.X, npcAbs.Y - rootAbs.Y + 42)

	local originalLayoutOrder = cardView.LayoutOrder
	local originalSize = cardView.Size
	cardView.AnchorPoint = Vector2.new(0.5, 0.5)
	cardView.Size = UDim2.fromOffset(cardView.AbsoluteSize.X, cardView.AbsoluteSize.Y)
	cardView.Position = UDim2.fromOffset(startLocal.X, startLocal.Y)
	cardView.Parent = root
	cardView.ZIndex = 50

	for _, obj in ipairs(cardView:GetDescendants()) do
		if obj:IsA("GuiObject") then
			obj.ZIndex = math.max(51, obj.ZIndex + 20)
		end
	end

	local function playHitEffects()
		-- ...existing code...
			-- Trigger flame animation on card hit
			emitAbilityWorldParticleBurst("Flame", Color3.fromRGB(255, 120, 62))

		for i = 1, 8 do
			local spark = Instance.new("Frame")
			spark.Name = "HitSpark"
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.BorderSizePixel = 0
			spark.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 145, 115) or Color3.fromRGB(255, 235, 195)
			spark.BackgroundTransparency = 0.1
			spark.Size = UDim2.fromOffset(math.random(8, 14), math.random(8, 14))
			spark.Position = UDim2.fromOffset(targetLocal.X + math.random(-10, 10), targetLocal.Y + math.random(-8, 8))
			spark.ZIndex = 80
			spark.Parent = root

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = spark

			local angle = math.rad(math.random(0, 359))
			local radius = math.random(30, 62)
			local ex = targetLocal.X + (math.cos(angle) * radius)
			local ey = targetLocal.Y + (math.sin(angle) * radius)

			TweenService:Create(
				spark,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromOffset(ex, ey),
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(2, 2),
				}
			):Play()

			Debris:AddItem(spark, 0.28)
		end

		local flash = Instance.new("Frame")
		flash.Name = "NpcHitFlash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.Position = UDim2.fromOffset(0, 0)
		flash.BackgroundColor3 = Color3.fromRGB(255, 160, 160)
		flash.BackgroundTransparency = 0.5
		flash.BorderSizePixel = 0
		flash.ZIndex = 90
		flash.Parent = npcEnemyCard

		local flashCorner = Instance.new("UICorner")
		flashCorner.CornerRadius = UDim.new(0, 12)
		flashCorner.Parent = flash

		local fade = TweenService:Create(
			flash,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}
		)
		fade:Play()
		Debris:AddItem(flash, 0.2)

		emitWorldParticleBurst(Color3.fromRGB(255, 158, 112), 24, 12)
	end

	local launch = TweenService:Create(
		cardView,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(targetLocal.X, targetLocal.Y),
			Size = UDim2.fromOffset(math.floor(cardView.AbsoluteSize.X * 0.92), math.floor(cardView.AbsoluteSize.Y * 0.92)),
		}
	)
	   -- Play PlayerAttackSound for all combat deck card attacks except NPC cards
	   if not cardView:GetAttribute("IsNpcCard") then
		   local attackSoundTemplate = uiState.gui and uiState.gui:FindFirstChild("PlayerAttackSound")
		   if attackSoundTemplate and attackSoundTemplate:IsA("Sound") then
			   local attackSound = attackSoundTemplate:Clone()
			   attackSound.Parent = uiState.gui
			   attackSound:Play()
			   Debris:AddItem(attackSound, 2)
		   end
	   end
	launch:Play()
	launch.Completed:Connect(function()
		   if not (cardView and cardView.Parent) then
			   return
		   end

		   playHitEffects()

		   -- Shake effect for NPC card hit by combat deck card
		   local function doShakeEffectIfNpcCard(onComplete)
			   if cardView:GetAttribute("IsNpcCard") then
				   print("[DEBUG] NPC card hit, moving up:", cardView.Name)
				   cardView.AnchorPoint = Vector2.new(0.5, 0.5)
				   cardView.ZIndex = 100
				   local upAmount = -40
				   local upTween = TweenService:Create(
					   cardView,
					   TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					   {Position = UDim2.fromOffset(startLocal.X, startLocal.Y + upAmount)}
				   )
				   upTween.Completed:Connect(function()
					   local downTween = TweenService:Create(
						   cardView,
						   TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						   {Position = UDim2.fromOffset(startLocal.X, startLocal.Y)}
					   )
					   downTween.Completed:Connect(function()
						   cardView.ZIndex = 50
						   if onComplete then
							   onComplete()
						   end
					   end)
					   downTween:Play()
				   end)
				   upTween:Play()
			   else
				   print("[DEBUG] Not an NPC card, skipping move for:", cardView.Name)
				   if onComplete then
					   onComplete()
				   end
			   end
		   end

		   doShakeEffectIfNpcCard(function()
			   -- (Removed boss card hit movement call)
			   local retreat = TweenService:Create(
				   cardView,
				   TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				   {
					   Position = UDim2.fromOffset(startLocal.X, startLocal.Y),
					   Size = originalSize,
				   }
			   )
			   retreat:Play()
			   retreat.Completed:Connect(function()
				   if cardView and cardView.Parent then
					   local pendingDeath = cardView:GetAttribute("PendingDeath") == true
					   cardView.AnchorPoint = Vector2.new(0, 0)
					   cardView.Size = originalSize
					   cardView.Position = UDim2.fromOffset(0, 0)
					   cardView.LayoutOrder = originalLayoutOrder
					   cardView.Parent = deckRow
					   cardView:SetAttribute("IsAnimatingAttack", false)
					   if pendingDeath then
						   cardView:SetAttribute("PendingDeath", false)
						   playCardDeathAnimation(cardView)
					   end
				   end
			   end)
		   end)

		   local retreat = TweenService:Create(
			   cardView,
			   TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			   {
				   Position = UDim2.fromOffset(startLocal.X, startLocal.Y),
				   Size = originalSize,
			   }
		   )
		   retreat:Play()
		   retreat.Completed:Connect(function()
			   if cardView and cardView.Parent then
				   -- TEST: Try to move the cardView in place after attack
				   local testTween = TweenService:Create(
					   cardView,
					   TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
					   {Position = UDim2.fromOffset(startLocal.X + 100, startLocal.Y)}
				   )
				   testTween:Play()
				   testTween.Completed:Connect(function()
					   local pendingDeath = cardView:GetAttribute("PendingDeath") == true
					   cardView.AnchorPoint = Vector2.new(0, 0)
					   cardView.Size = originalSize
					   cardView.Position = UDim2.fromOffset(0, 0)
					   cardView.LayoutOrder = originalLayoutOrder
					   cardView.Parent = deckRow
					   cardView:SetAttribute("IsAnimatingAttack", false)
					   if pendingDeath then
						   cardView:SetAttribute("PendingDeath", false)
						   playCardDeathAnimation(cardView)
					   end
				   end)
			   end
		   end)
	end)
end

local function playNpcHitEffects(targetCard)
	local root = uiState.rootFrame
	if not (targetCard and targetCard.Parent and root and root.Parent) then
		return
	end

	local centerAbs = targetCard.AbsolutePosition + (targetCard.AbsoluteSize * 0.5)
	local rootAbs = root.AbsolutePosition
	local localCenter = Vector2.new(centerAbs.X - rootAbs.X, centerAbs.Y - rootAbs.Y)

	for i = 1, 24 do -- double the spikes
		local spike = Instance.new("Frame")
		spike.Name = "NpcHitSpike"
		spike.AnchorPoint = Vector2.new(0.5, 0.5)
		spike.BorderSizePixel = 0
		spike.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(94, 0, 0)
		spike.BackgroundTransparency = 0
		spike.Size = UDim2.fromOffset(math.random(8, 16), math.random(32, 60))
		spike.Position = UDim2.fromOffset(localCenter.X + math.random(-10, 10), localCenter.Y + math.random(-10, 10))
		spike.Rotation = math.random(0, 360)
		spike.ZIndex = 121
		spike.Parent = root

		local angle = math.rad(math.random(0, 359))
		local radius = math.random(80, 140)
		local ex = localCenter.X + (math.cos(angle) * radius)
		local ey = localCenter.Y + (math.sin(angle) * radius)

		TweenService:Create(
			spike,
			TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(ex, ey),
				Size = UDim2.fromOffset(4, 18),
				BackgroundTransparency = 1,
			}
		):Play()
		Debris:AddItem(spike, 0.85)
	end

	local hitFlash = Instance.new("Frame")
	hitFlash.Name = "CardHitFlash"
	hitFlash.Size = UDim2.fromScale(1.2, 1.2) -- larger flash
	hitFlash.Position = UDim2.fromOffset(-0.1 * targetCard.AbsoluteSize.X, -0.1 * targetCard.AbsoluteSize.Y)
	hitFlash.BackgroundColor3 = Color3.fromRGB(255, 30, 30) -- more intense red
	hitFlash.BackgroundTransparency = 0.18
	hitFlash.BorderSizePixel = 0
	hitFlash.ZIndex = 120
	hitFlash.Parent = targetCard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = hitFlash

	TweenService:Create(
		hitFlash,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 0)}
	):Play()
	Debris:AddItem(hitFlash, 1.1)

	emitWorldParticleBurst(Color3.fromRGB(255, 30, 30), 48, 6) -- more, closer particles
end

local function playNpcEnemyAttackSound()
	local soundTemplate = uiState.gui and uiState.gui:FindFirstChild("NpcEnemyAttackSound")
	if soundTemplate and soundTemplate:IsA("Sound") then
		if soundTemplate.IsPlaying then
			soundTemplate:Stop()
		end
		soundTemplate.TimePosition = BOSS_ATTACK_SOUND_TIME_OFFSET
		soundTemplate:Play()
	end
end

local function animateNpcEnemyAttack(targetSlotIndex, targetCardId)
	local npcEnemyCard = uiState.npcEnemyCardFrame
	local root = uiState.rootFrame
	if not (npcEnemyCard and npcEnemyCard.Parent and root and root.Parent) then
		return
	end

	if npcEnemyCard:GetAttribute("IsAnimatingAttack") then
		return
	end
	npcEnemyCard:SetAttribute("IsAnimatingAttack", true)

	local npcArt = npcEnemyCard:FindFirstChild("NpcEnemyArt")
	print("[DEBUG] animateNpcEnemyAttack called for NPC card.")
	if npcArt then
		print("[DEBUG] NpcEnemyArt found.")
	else
		print("[DEBUG] NpcEnemyArt not found.")
	end
	if uiState.npcEnemyNameLabel then
		print("[DEBUG] NPC name label text:", uiState.npcEnemyNameLabel.Text)
	end

	local targetCard = nil
	if type(targetSlotIndex) == "number" then
		targetCard = uiState.deckCardBySlot[targetSlotIndex]
	end
	if not targetCard and type(targetCardId) == "string" then
		local list = uiState.deckCardsById[targetCardId]
		if list and #list > 0 then
			targetCard = list[1]
		end
	end

	local originalPos = npcEnemyCard.Position
	local targetPos = nil
	if targetCard and targetCard.Parent then
		local rootAbs = root.AbsolutePosition
		local targetAbs = targetCard.AbsolutePosition + (targetCard.AbsoluteSize * 0.5)
		targetPos = UDim2.fromOffset(targetAbs.X - rootAbs.X, targetAbs.Y - rootAbs.Y - 70)
	else
		targetPos = UDim2.new(0.5, 0, 0, 84)
	end

	print("[DEBUG] NpcEnemyCard original position:", tostring(originalPos))
	print("[DEBUG] NpcEnemyCard target position:", tostring(targetPos))
	local dash = TweenService:Create(
		npcEnemyCard,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), -- slowed by half
		{Position = targetPos}
	)
	playNpcEnemyAttackSound()
	dash:Play()
	dash.Completed:Connect(function()
		print("[DEBUG] NpcEnemyCard reached target position:", tostring(npcEnemyCard.Position))
		local playerGui = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
		local animLayer = playerGui and playerGui:FindFirstChild("BattleAnimLayer")
		local animRoot = animLayer and animLayer:FindFirstChild("AnimRoot")
		if animRoot then
			local VFXController = require(script.Parent.vfx.VFXController)
			print("[DEBUG] npcEnemyCardFrame CardId attribute:", uiState.npcEnemyCardFrame and uiState.npcEnemyCardFrame:GetAttribute("CardId"))

			local npcCardAnimations = {
				Aokoji = function()
					print("[DEBUG] Triggering ice animation for Aokoji")
					VFXController.playMultiSpriteSequenceOnce(animRoot, {
						{imageId = "rbxassetid://120564438202500", gridCols = 5, gridRows = 7, totalFrames = 35, frameSize = 128}
					}, 1/12)
					local sound = Instance.new("Sound")
					sound.SoundId = "rbxassetid://75443362172608"
					sound.Volume = 0.7
					sound.Parent = animRoot
					sound:Play()
					sound.Ended:Connect(function()
						sound:Destroy()
					end)
				end,
				PerfectCell = function()
					if targetCard and targetCard.Parent then
						print("[DEBUG] Triggering flame animation for PerfectCell on hit card")
						local VFXTemplates = ReplicatedStorage:FindFirstChild("VFXTemplates")
						local flameTemplate = VFXTemplates and VFXTemplates:FindFirstChild("FlameAnimation")
						local flameImageId = (flameTemplate and flameTemplate.Image ~= "") and flameTemplate.Image or "rbxassetid://110838461690103"
						VFXController.playMultiSpriteSequenceOnce(targetCard, {
							{imageId = flameImageId, gridCols = 8, gridRows = 8, totalFrames = 64, frameSize = 128}
						}, 1/50)
					end
				end
			}

			local animCardId = uiState.npcEnemyCardFrame and uiState.npcEnemyCardFrame:GetAttribute("CardId")
			if animCardId and npcCardAnimations[animCardId] then
				npcCardAnimations[animCardId]()
			end
		end
		if targetCard and targetCard.Parent then
			playNpcHitEffects(targetCard)
		end

		local retreat = TweenService:Create(
			npcEnemyCard,
			TweenInfo.new(0.48, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), -- slowed by half
			{Position = originalPos}
		)
		retreat:Play()
		retreat.Completed:Connect(function()
			print("[DEBUG] NpcEnemyCard retreated to original position:", tostring(npcEnemyCard.Position))
			npcEnemyCard:SetAttribute("IsAnimatingAttack", false)
			print("[DEBUG] IsAnimatingAttack reset to false.")
		end)
		-- Safety: forcibly reset IsAnimatingAttack after 1s in case tween fails
		task.delay(1, function()
			if npcEnemyCard:GetAttribute("IsAnimatingAttack") then
				npcEnemyCard:SetAttribute("IsAnimatingAttack", false)
				print("[DEBUG] IsAnimatingAttack forcibly reset after delay.")
			end
		end)
	end)
end

local function getAbilityEffectStyle(effectType)
	if effectType == "HealLowestAlly" then
		return Color3.fromRGB(86, 214, 122), "RECOVERY+"
	end
	if effectType == "TeamAttackSpeedBoost" then
		return Color3.fromRGB(90, 184, 255), "ATK SPD+"
	end
	if effectType == "TeamAttackDamageBoost" then
		return Color3.fromRGB(255, 154, 76), "ATK DMG+"
	end
	if effectType == "EnemyPartyAttackDown" then
		return Color3.fromRGB(190, 130, 255), "ATK DOWN"
	end
	return Color3.fromRGB(220, 220, 220), "BUFF"
end

local function playBuffScreenPulse(color)
	local root = uiState.rootFrame
	if not (root and root.Parent) then
		return
	end

	local pulse = Instance.new("Frame")
	pulse.Name = "BuffScreenPulse"
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.Position = UDim2.fromOffset(0, 0)
	pulse.BackgroundColor3 = color
	pulse.BackgroundTransparency = 0.97
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 65
	pulse.Parent = root

	TweenService:Create(
		pulse,
		TweenInfo.new(fxTime(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.9}
	):Play()

	task.delay(fxTime(0.14), function()
		if pulse and pulse.Parent then
			TweenService:Create(
				pulse,
				TweenInfo.new(fxTime(0.36), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{BackgroundTransparency = 1}
			):Play()
		end
	end)

	Debris:AddItem(pulse, fxLife(0.58))
end

local function playAbilityThemeFx(cardView, color, effectType)
	local effect = tostring(effectType or "")
	local burstNow = os.clock()
	if (abilityWorldBurstCooldownByEffect[effect] or 0) <= burstNow then
		emitAbilityWorldParticleBurst(effect, color)
		abilityWorldBurstCooldownByEffect[effect] = burstNow + ABILITY_WORLD_BURST_COOLDOWN_SECONDS
	end

	if effect == "TeamAttackSpeedBoost" then
		for _ = 1, 10 do
			local arc = Instance.new("Frame")
			arc.Name = "SpeedArc"
			arc.AnchorPoint = Vector2.new(0.5, 0.5)
			arc.Size = UDim2.fromOffset(math.random(18, 34), math.random(2, 3))
			arc.Position = UDim2.fromScale(math.random(20, 80) / 100, math.random(20, 80) / 100)
			arc.Rotation = math.random(-70, 70)
			arc.BackgroundColor3 = color
			arc.BackgroundTransparency = 0.12
			arc.BorderSizePixel = 0
			arc.ZIndex = 105
			arc.Parent = cardView

			TweenService:Create(
				arc,
				TweenInfo.new(fxTime(0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Position = UDim2.fromScale(math.random(10, 90) / 100, math.random(10, 90) / 100), BackgroundTransparency = 1}
			):Play()
			Debris:AddItem(arc, fxLife(0.38))
		end
	elseif effect == "TeamAttackDamageBoost" then
		local shock = Instance.new("Frame")
		shock.Name = "DamageShock"
		shock.AnchorPoint = Vector2.new(0.5, 0.5)
		shock.Size = UDim2.fromOffset(20, 20)
		shock.Position = UDim2.fromScale(0.5, 0.5)
		shock.BackgroundTransparency = 1
		shock.BorderSizePixel = 0
		shock.ZIndex = 105
		shock.Parent = cardView

		local shockStroke = Instance.new("UIStroke")
		shockStroke.Thickness = 2.5
		shockStroke.Color = Color3.fromRGB(255, 108, 56)
		shockStroke.Transparency = 0.06
		shockStroke.Parent = shock

		local shockCorner = Instance.new("UICorner")
		shockCorner.CornerRadius = UDim.new(1, 0)
		shockCorner.Parent = shock

		TweenService:Create(
			shock,
			TweenInfo.new(fxTime(0.38), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = UDim2.fromOffset(cardView.AbsoluteSize.X + 30, cardView.AbsoluteSize.Y + 30), Rotation = -140}
		):Play()
		TweenService:Create(
			shockStroke,
			TweenInfo.new(fxTime(0.38), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		):Play()
		Debris:AddItem(shock, fxLife(0.46))

		for i = 1, 14 do
			local ember = Instance.new("Frame")
			ember.Name = "DamageEmber"
			ember.AnchorPoint = Vector2.new(0.5, 0.5)
			ember.Size = UDim2.fromOffset(math.random(2, 5), math.random(2, 5))
			ember.Position = UDim2.fromScale(0.5, 0.5)
			ember.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 120, 62) or Color3.fromRGB(255, 214, 146)
			ember.BackgroundTransparency = 0.08
			ember.BorderSizePixel = 0
			ember.ZIndex = 106
			ember.Parent = cardView

			local angle = math.rad(math.random(0, 359))
			local radius = math.random(26, 60)
			local tx = 0.5 + (math.cos(angle) * radius / math.max(1, cardView.AbsoluteSize.X))
			local ty = 0.5 + (math.sin(angle) * radius / math.max(1, cardView.AbsoluteSize.Y))

			TweenService:Create(
				ember,
				TweenInfo.new(fxTime(0.34), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Position = UDim2.fromScale(tx, ty), BackgroundTransparency = 1}
			):Play()
			Debris:AddItem(ember, fxLife(0.42))
		end
	elseif effect == "HealLowestAlly" then
		local glyph = Instance.new("Frame")
		glyph.Name = "HealGlyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Size = UDim2.fromOffset(24, 24)
		glyph.Position = UDim2.fromScale(0.5, 0.56)
		glyph.BackgroundTransparency = 1
		glyph.BorderSizePixel = 0
		glyph.ZIndex = 105
		glyph.Parent = cardView

		local glyphStroke = Instance.new("UIStroke")
		glyphStroke.Thickness = 2
		glyphStroke.Color = Color3.fromRGB(130, 255, 176)
		glyphStroke.Transparency = 0.08
		glyphStroke.Parent = glyph

		local glyphCorner = Instance.new("UICorner")
		glyphCorner.CornerRadius = UDim.new(1, 0)
		glyphCorner.Parent = glyph

		TweenService:Create(
			glyph,
			TweenInfo.new(fxTime(0.46), Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Size = UDim2.fromOffset(cardView.AbsoluteSize.X + 20, cardView.AbsoluteSize.Y + 20), Position = UDim2.fromScale(0.5, 0.5)}
		):Play()
		TweenService:Create(
			glyphStroke,
			TweenInfo.new(fxTime(0.46), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		):Play()
		Debris:AddItem(glyph, fxLife(0.56))

		for _ = 1, 12 do
			local mote = Instance.new("Frame")
			mote.Name = "HealMote"
			mote.AnchorPoint = Vector2.new(0.5, 0.5)
			mote.Size = UDim2.fromOffset(math.random(2, 4), math.random(2, 4))
			mote.Position = UDim2.fromScale(math.random(25, 75) / 100, math.random(45, 80) / 100)
			mote.BackgroundColor3 = Color3.fromRGB(180, 255, 210)
			mote.BackgroundTransparency = 0.05
			mote.BorderSizePixel = 0
			mote.ZIndex = 106
			mote.Parent = cardView

			TweenService:Create(
				mote,
				TweenInfo.new(fxTime(0.5), Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromScale(math.random(20, 80) / 100, math.random(10, 35) / 100),
					BackgroundTransparency = 1,
				}
			):Play()
			Debris:AddItem(mote, fxLife(0.58))
		end
	end
end

local function playAbilityPulse(cardView, color, effectType)
	if not (cardView and cardView.Parent) then
		return
	end

	local fx = Instance.new("Frame")
	fx.Name = "AbilityPulse"
	fx.Size = UDim2.fromScale(1, 1)
	fx.Position = UDim2.fromOffset(0, 0)
	fx.BackgroundColor3 = color
	fx.BackgroundTransparency = 0.92
	fx.BorderSizePixel = 0
	fx.ZIndex = 100
	fx.Parent = cardView

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = fx

	TweenService:Create(
		fx,
		TweenInfo.new(fxTime(0.24), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.72}
	):Play()

	task.delay(fxTime(0.24), function()
		if not (fx and fx.Parent) then
			return
		end
		TweenService:Create(
			fx,
			TweenInfo.new(fxTime(0.34), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{BackgroundTransparency = 1}
		):Play()
	end)

	Debris:AddItem(fx, fxLife(0.68))

	local rune = Instance.new("Frame")
	rune.Name = "AbilityRune"
	rune.AnchorPoint = Vector2.new(0.5, 0.5)
	rune.Size = UDim2.fromOffset(26, 26)
	rune.Position = UDim2.fromScale(0.5, 0.5)
	rune.BackgroundTransparency = 1
	rune.BorderSizePixel = 0
	rune.ZIndex = 102
	rune.Parent = cardView

	local runeStroke = Instance.new("UIStroke")
	runeStroke.Thickness = 2
	runeStroke.Color = color
	runeStroke.Transparency = 0.15
	runeStroke.Parent = rune

	local runeCorner = Instance.new("UICorner")
	runeCorner.CornerRadius = UDim.new(1, 0)
	runeCorner.Parent = rune

	TweenService:Create(
		rune,
		TweenInfo.new(fxTime(0.5), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.fromOffset(cardView.AbsoluteSize.X + 18, cardView.AbsoluteSize.Y + 18), Rotation = 120}
	):Play()
	TweenService:Create(
		runeStroke,
		TweenInfo.new(fxTime(0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 1}
	):Play()
	Debris:AddItem(rune, fxLife(0.58))

	for i = 1, 12 do
		local shard = Instance.new("Frame")
		shard.Name = "BuffShard"
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Size = UDim2.fromOffset(math.random(3, 7), math.random(10, 20))
		shard.Position = UDim2.fromScale(0.5, 0.5)
		shard.Rotation = math.random(0, 180)
		shard.BackgroundColor3 = (i % 2 == 0) and color or Color3.fromRGB(255, 245, 210)
		shard.BackgroundTransparency = 0.05
		shard.BorderSizePixel = 0
		shard.ZIndex = 103
		shard.Parent = cardView

		local angle = math.rad((360 / 12) * i + math.random(-8, 8))
		local radius = math.random(30, 52)
		local tx = 0.5 + (math.cos(angle) * radius / math.max(1, cardView.AbsoluteSize.X))
		local ty = 0.5 + (math.sin(angle) * radius / math.max(1, cardView.AbsoluteSize.Y))

		TweenService:Create(
			shard,
			TweenInfo.new(fxTime(0.38), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(tx, ty),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(1, 1),
			}
		):Play()
		Debris:AddItem(shard, fxLife(0.46))
	end

	for i = 1, 4 do
		local streak = Instance.new("Frame")
		streak.Name = "BuffStreak"
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Size = UDim2.fromOffset(math.random(34, 58), math.random(2, 4))
		streak.Position = UDim2.fromScale(0.5, 0.5)
		streak.Rotation = (i - 1) * 45 + math.random(-6, 6)
		streak.BackgroundColor3 = color
		streak.BackgroundTransparency = 0.18
		streak.BorderSizePixel = 0
		streak.ZIndex = 104
		streak.Parent = cardView

		TweenService:Create(
			streak,
			TweenInfo.new(fxTime(0.34), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.fromOffset(math.random(70, 96), 1), BackgroundTransparency = 1}
		):Play()
		Debris:AddItem(streak, fxLife(0.42))
	end

	playAbilityThemeFx(cardView, color, effectType)
end

local function showAbilityPopup(cardView, color, text)
	if not (cardView and cardView.Parent) then
		return
	end

	local popup = Instance.new("TextLabel")
	popup.Name = "AbilityPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Size = UDim2.fromOffset(156, 40)
	popup.Position = UDim2.fromScale(0.5, -0.05)
	popup.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	popup.BackgroundTransparency = 1
	popup.Text = text
	popup.Font = Enum.Font.GothamBold
	popup.TextSize = 21
	popup.TextColor3 = color
	popup.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	popup.TextStrokeTransparency = 0.05
	popup.ZIndex = 101
	popup.Parent = cardView

	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, 8)
	popupCorner.Parent = popup

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Thickness = 2
	popupStroke.Color = Color3.fromRGB(0, 0, 0)
	popupStroke.Transparency = 0
	popupStroke.Parent = popup

	TweenService:Create(
		popup,
		TweenInfo.new(fxTime(0.3), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.fromScale(0.5, -0.14)}
	):Play()

	task.delay(fxTime(2.1), function()
		if not (popup and popup.Parent) then
			return
		end
		TweenService:Create(
			popup,
			TweenInfo.new(fxTime(0.42), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = UDim2.fromScale(0.5, -0.2), TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1}
		):Play()
		if popupStroke and popupStroke.Parent then
			TweenService:Create(
				popupStroke,
				TweenInfo.new(fxTime(0.42), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{Transparency = 1}
			):Play()
		end
	end)

	Debris:AddItem(popup, fxLife(2.9))
end

local function playAbilityEvents(payload)
	if type(payload.abilityEvents) ~= "table" then
		return
	end

	for _, abilityEvent in ipairs(payload.abilityEvents) do
		if type(abilityEvent) == "table" then
			local color, text = getAbilityEffectStyle(abilityEvent.effectType)
			local caster = uiState.deckCardBySlot[tonumber(abilityEvent.casterSlotIndex) or -1]
			playAbilitySound(abilityEvent.effectType)
			if caster then
				playAbilityPulse(caster, color, abilityEvent.effectType)
				showAbilityPopup(caster, color, text)
			end
			if abilityEvent.effectType == "EnemyPartyAttackDown" then
				local npc = uiState.npcEnemyCardFrame
				if npc and npc.Parent then
					playAbilityPulse(npc, color, abilityEvent.effectType)
				end
			end
			if caster then
				-- Blood animation sequence for TestBattleCard
				if abilityEvent.effectType == "Fireball" and caster:GetAttribute("CardId") == "TestBattleCard" then
					local VFXController = require(script.Parent.vfx.VFXController)
					VFXController.playMultiSpriteSequence(caster, {
						{imageId = "rbxassetid://77570709327719", gridCols = 8, gridRows = 1, totalFrames = 8, frameSize = 128},
						{imageId = "rbxassetid://94246830328231", gridCols = 5, gridRows = 1, totalFrames = 5, frameSize = 128},
						{imageId = "rbxassetid://117080686747829", gridCols = 6, gridRows = 1, totalFrames = 6, frameSize = 128}
					})
				end
			end
			playBuffScreenPulse(color)

			for _, slotIndex in ipairs(abilityEvent.targetSlotIndices or {}) do
				local target = uiState.deckCardBySlot[tonumber(slotIndex) or -1]
				if target then
					playAbilityPulse(target, color, abilityEvent.effectType)
				end
			end
		end
	end
end

local function setNpcEnemyHeader(payload)
	if not uiState.npcEnemyNameLabel then
		return
	end
	uiState.npcEnemyNameLabel.Text = tostring(payload.npcCardName or "Foe")
end

local function setNpcEnemyHp(payload)
	if not uiState.npcEnemyHpLabel then
		return
	end
	local hp = math.max(0, math.floor(tonumber(payload.npcHealth) or 0))
	local maxHp = math.max(1, math.floor(tonumber(payload.npcMaxHealth) or 1))
	uiState.npcEnemyHpLabel.Text = string.format("HP: %s / %s", CardDatabase.FormatAttack(hp), CardDatabase.FormatAttack(maxHp))
end

local function setNpcEnemyHint(payload)
	local hint = uiState.npcEnemyCardFrame and uiState.npcEnemyCardFrame:FindFirstChild("NpcEnemyHint")
	if not (hint and hint:IsA("TextLabel")) then
		return
	end
	local displayedAttack = tonumber(payload and payload.npcAttack)
	if not displayedAttack then
		displayedAttack = 1500000
	end
	hint.Text = string.format("NPC ATK: %s | Auto battle", CardDatabase.FormatAttack(displayedAttack))
end

local function showBattleUi(payload)
	local gui = createBattleGui(payload)
	if uiState.npcEnemyCardFrame and payload and payload.npcCardId then
		uiState.npcEnemyCardFrame:SetAttribute("CardId", payload.npcCardId)
		local cardDatabaseModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
		local npcArt = uiState.npcEnemyCardFrame:FindFirstChild("NpcEnemyArt")
		local npcRow = cardDatabaseModule.GetCardData and cardDatabaseModule.GetCardData(payload.npcCardId)
		if npcArt and npcRow and type(npcRow.ArtAssetId) == "string" and npcRow.ArtAssetId ~= "" then
			npcArt.Image = npcRow.ArtAssetId
		end
	end
	gui.Enabled = true
	uiState.sessionId = payload.sessionId
	setNpcEnemyHeader(payload)
	setNpcEnemyHp(payload)
	setNpcEnemyHint(payload)
end

local function showBattleUiLoading(invitePayload)
	local gui = createBattleGui()
	gui.Enabled = true
	uiState.sessionId = nil
	if uiState.npcEnemyNameLabel then
		uiState.npcEnemyNameLabel.Text = tostring(invitePayload and invitePayload.npcName or "Foe")
	end
	if uiState.npcEnemyHpLabel then
		uiState.npcEnemyHpLabel.Text = "Preparing battle..."
	end
end

local function stopNpcOutgoingDrDebuffUi()
	if uiState.npcDrDebuffHbConn then
		uiState.npcDrDebuffHbConn:Disconnect()
		uiState.npcDrDebuffHbConn = nil
	end
	uiState.npcDrDebuffEndClock = nil
	uiState.npcDrDebuffPercent = nil
	local card = uiState.npcEnemyCardFrame
	local bar = card and card:FindFirstChild("NpcOutgoingDrDebuffBar")
	if bar then
		bar.Visible = false
	end
end

local function syncNpcOutgoingDrDebuffFromPayload(payload)
	local bar = uiState.npcEnemyCardFrame and uiState.npcEnemyCardFrame:FindFirstChild("NpcOutgoingDrDebuffBar")
	local lbl = bar and bar:FindFirstChild("DrText")
	if not (bar and lbl) then
		return
	end
	local rem = tonumber(payload and payload.npcOutgoingAttackDebuffRemainingSec) or 0
	local pct = tonumber(payload and payload.npcOutgoingAttackDebuffPercent) or 0
	if rem > 0 and pct > 0 then
		uiState.npcDrDebuffEndClock = os.clock() + rem
		uiState.npcDrDebuffPercent = pct
		bar.Visible = true
		local pctDisp = math.floor(pct * 100 + 0.5)
		lbl.Text = string.format("DR %d%% · %.1fs", pctDisp, rem)
		if not uiState.npcDrDebuffHbConn then
			uiState.npcDrDebuffHbConn = RunService.Heartbeat:Connect(function()
				if not bar.Parent then
					return
				end
				if not uiState.npcDrDebuffEndClock or not uiState.npcDrDebuffPercent then
					bar.Visible = false
					return
				end
				local left = math.max(0, uiState.npcDrDebuffEndClock - os.clock())
				if left <= 0.05 then
					bar.Visible = false
					uiState.npcDrDebuffEndClock = nil
					return
				end
				local p = math.floor(uiState.npcDrDebuffPercent * 100 + 0.5)
				lbl.Text = string.format("DR %d%% · %.1fs", p, left)
			end)
		end
	else
		stopNpcOutgoingDrDebuffUi()
	end
end

local function hideBattleUi()
	stopNpcOutgoingDrDebuffUi()
	stopDeckSpeedBuffUi()
	if uiState.sessionId then
		DamagePopupManager.ClearSession(uiState.sessionId)
	end
	if uiState.gui then
		uiState.gui.Enabled = false
	end
	uiState.sessionId = nil
	uiState.deckSnapshot = {}
	clearDeckCardMappings()
end

local function buildCombatDeckSnapshot()
	local deck = {}
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local mainUI = playerGui and playerGui:FindFirstChild("MainUI")
	local combatDeckFrame = mainUI and mainUI:FindFirstChild("CombatDeckFrame")
	if not (combatDeckFrame and combatDeckFrame:IsA("GuiObject")) then
		return deck
	end

	for i = 1, 5 do
		local slot = combatDeckFrame:FindFirstChild("CombatSlot" .. tostring(i))
		if slot then
			for _, child in ipairs(slot:GetChildren()) do
				if child:IsA("GuiButton") then
					local cardId = child:GetAttribute("CardId") or child.Name
					if type(cardId) == "string" and cardId ~= "" then
						table.insert(deck, {
							slotIndex = i,
							cardId = cardId,
						})
					end
					break
				end
			end
		end
	end

	return deck
end

local function requestBattle(npcId)
	requestBattleEvent:FireServer({npcId = npcId})
end

local function submitDeckSnapshotWithRetry(expectedSessionId, attempt)
	if uiState.sessionId ~= expectedSessionId then
		return
	end

	attempt = attempt or 1
	uiState.deckSnapshot = buildCombatDeckSnapshot()
	renderDeckRow(uiState.deckSnapshot)

	if #uiState.deckSnapshot == 0 and attempt < MAX_DECK_SYNC_RETRIES then
		if uiState.npcEnemyHpLabel then
			uiState.npcEnemyHpLabel.Text = "Syncing combat deck..."
		end
		task.delay(DECK_SYNC_RETRY_DELAY, function()
			submitDeckSnapshotWithRetry(expectedSessionId, attempt + 1)
		end)
		return
	end

	battleActionEvent:FireServer({
		actionType = BattleProtocol.ActionType.SubmitDeckSnapshot,
		deck = uiState.deckSnapshot,
	})
end

battleInviteEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	-- Open the battle screen immediately on interaction for a snappy transition.
	showBattleUiLoading(payload)

	bridgeEvent:Fire({
		eventType = "BattleInvite",
		payload = payload,
	})

	if AUTO_REQUEST_BATTLE_ON_INVITE and type(payload.npcId) == "string" then
		requestBattle(payload.npcId)
	end
end)

battleStateEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	bridgeEvent:Fire({
		eventType = "BattleState",
		payload = payload,
	})

	if payload.eventType == BattleProtocol.EventType.SessionStarted then
		showBattleUi(payload)
		submitDeckSnapshotWithRetry(payload.sessionId, 1)
	end

	if payload.eventType == BattleProtocol.EventType.NpcState then
		setNpcEnemyHp(payload)
		setNpcEnemyHint(payload)
		syncNpcOutgoingDrDebuffFromPayload(payload)
		local dealtToNpc = tonumber(payload.dealtDamage) or 0
		if dealtToNpc > 0 then
			animateSingleDeckAttack(payload.attackerSlotIndex, payload.attackerCardId)
			local root = uiState.rootFrame
			local npcCard = uiState.npcEnemyCardFrame
			if root and root.Parent and npcCard and npcCard.Parent then
				local cat = DamagePopupManager.MapCategory(dealtToNpc, payload.isCrit, payload.isDodged, payload.absorbed)
				DamagePopupManager.EnqueueFloating({
					sessionId = payload.sessionId,
					targetKey = "pve_npc",
					rootFrame = root,
					targetGui = npcCard,
					amount = dealtToNpc,
					absorbed = payload.absorbed,
					category = cat,
					contextKind = "PlayerToNpc",
					sequence = tonumber(payload.hitSeq) or 0,
				})
			end
		end
		local dealtFromNpc = tonumber(payload.npcAttackDealtDamage) or 0
		local npcCat = DamagePopupManager.MapCategory(
			dealtFromNpc,
			payload.npcAttackIsCrit,
			payload.npcAttackIsDodged,
			payload.npcAttackAbsorbed
		)
		local showNpcHit = npcCat == "Dodge"
			or npcCat == "ShieldAbsorb"
			or dealtFromNpc > 0
		if showNpcHit then
			animateNpcEnemyAttack(payload.npcAttackTargetSlotIndex, payload.npcAttackTargetCardId)
			local targetCard = nil
			if type(payload.npcAttackTargetSlotIndex) == "number" then
				targetCard = uiState.deckCardBySlot[payload.npcAttackTargetSlotIndex]
			end
			if not targetCard and type(payload.npcAttackTargetCardId) == "string" then
				local list = uiState.deckCardsById[payload.npcAttackTargetCardId]
				if list and #list > 0 then
					targetCard = list[1]
				end
			end
			if targetCard then
				local root = uiState.rootFrame
				if root and root.Parent and targetCard.Parent then
					local slotKey = type(payload.npcAttackTargetSlotIndex) == "number" and payload.npcAttackTargetSlotIndex or 0
					DamagePopupManager.EnqueueFloating({
						sessionId = payload.sessionId,
						targetKey = "pve_slot_" .. tostring(slotKey),
						rootFrame = root,
						targetGui = targetCard,
						amount = dealtFromNpc,
						absorbed = payload.npcAttackAbsorbed,
						category = npcCat,
						contextKind = "NpcToPlayer",
						sequence = tonumber(payload.hitSeq) or 0,
					})
				end
			end
		end
		applyPlayerCardStates(payload.playerCardStates)
		playAbilityEvents(payload)
	end

	if payload.eventType == BattleProtocol.EventType.SessionEnded then
		hideBattleUi()
	end

	if payload.eventType == BattleProtocol.EventType.Error then
		warn(string.format("[NpcBattle] %s", tostring(payload.reason)))
	end
end)

-- Future UI systems can fire this bridge to submit battle actions.
bridgeEvent.Event:Connect(function(message)
	if type(message) ~= "table" then
		return
	end
	if message.eventType ~= "SubmitAction" then
		return
	end
	if type(message.payload) ~= "table" then
		return
	end
	battleActionEvent:FireServer(message.payload)
end)
