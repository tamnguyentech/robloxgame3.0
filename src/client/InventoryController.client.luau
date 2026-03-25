
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResetAllRollsEvent = ReplicatedStorage:FindFirstChild("ResetAllRollsEvent")
if not ResetAllRollsEvent then
	ResetAllRollsEvent = Instance.new("RemoteEvent")
	ResetAllRollsEvent.Name = "ResetAllRollsEvent"
	ResetAllRollsEvent.Parent = ReplicatedStorage
end
local ClientSettingsChangedEvent = ReplicatedStorage:FindFirstChild("ClientSettingsChangedEvent")
if not (ClientSettingsChangedEvent and ClientSettingsChangedEvent:IsA("BindableEvent")) then
	if ClientSettingsChangedEvent then ClientSettingsChangedEvent:Destroy() end
	ClientSettingsChangedEvent = Instance.new("BindableEvent")
	ClientSettingsChangedEvent.Name = "ClientSettingsChangedEvent"
	ClientSettingsChangedEvent.Parent = ReplicatedStorage
end

-- selene: allow(unused_variable)
function ResetAllRolls()
	ResetAllRollsEvent:FireServer()
end
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Player = game.Players.LocalPlayer
local CardDatabase      = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local BalanceConfig     = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local EconomyCatalog    = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyCatalog"))
local CardVisualResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardVisualResolver"))
local RarityConfig      = require(script.Parent:WaitForChild("RarityConfig"))
local ClientStateManager = require(script.Parent.core:WaitForChild("ClientStateManager"))
local DeviceContext = require(script.Parent.core:WaitForChild("DeviceContext"))
local Spring            = require(script.Parent:WaitForChild("Spring"))
local SettingsUIController = require(script.Parent.ui.controllers.SettingsUIController)

local AddCardToInventory -- forward declaration; defined below

-- ── Shared spring driver for card hover-zoom ──────────────────────────────────
-- Why: one Heartbeat for all active card springs is cheaper than N connections.
-- Each card registers its Spring + UIScale reference here on creation.
local activeScaleSprings = {}  -- { [Spring] = UIScale }
local springDriverConn   = nil

local function ensureSpringDriver()
	if springDriverConn then return end
	springDriverConn = RunService.Heartbeat:Connect(function(dt)
		local anyActive = false
		for spring, scaleObj in pairs(activeScaleSprings) do
			if scaleObj and scaleObj.Parent then
				scaleObj.Scale = spring:step(dt)
				anyActive = true
			else
				activeScaleSprings[spring] = nil
			end
		end
		if not anyActive and springDriverConn then
			springDriverConn:Disconnect()
			springDriverConn = nil
		end
	end)
end

local artFolder = ReplicatedStorage:WaitForChild("CardArt")
local mainUI = Player.PlayerGui:WaitForChild("MainUI")  -- Adjust "MainUI" to your ScreenGui name

local function getOrCreateHoverVideoPreviewActiveValue()
	local valueObj = ReplicatedStorage:FindFirstChild("HoverVideoPreviewActive")
	if not (valueObj and valueObj:IsA("BoolValue")) then
		if valueObj then
			valueObj:Destroy()
		end
		valueObj = Instance.new("BoolValue")
		valueObj.Name = "HoverVideoPreviewActive"
		valueObj.Value = false
		valueObj.Parent = ReplicatedStorage
	end
	return valueObj
end

local hoverVideoPreviewActiveValue = getOrCreateHoverVideoPreviewActiveValue()

local function getOrCreateDeckFrame(frameName, fallbackPosition)
	local existing = mainUI:FindFirstChild(frameName)
	if existing and existing:IsA("ScrollingFrame") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local frame = Instance.new("ScrollingFrame")
	frame.Name = frameName
	frame.Size = UDim2.fromOffset(760, 320)
	frame.Position = fallbackPosition
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 8
	frame.CanvasSize = UDim2.fromOffset(0, 0)
	frame.Visible = false
	frame.ZIndex = 2
	frame.ClipsDescendants = true
	frame.Parent = mainUI

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Color = Color3.fromRGB(85, 85, 85)
	stroke.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	return frame
end

-- Move frames further right to avoid overlap with left-side toggles
local inventoryFrame = getOrCreateDeckFrame("InventoryFrame", UDim2.fromOffset(260, 20))
local combatDeckFrame = getOrCreateDeckFrame("CombatDeckFrame", UDim2.fromOffset(260, 360))

local COMBAT_MAX_UNIQUE = 5
local COMBAT_SLOT_PADDING = 10
local COMBAT_SLOT_GAP = 10
local COMBAT_CARD_WIDTH = 140
local COMBAT_CARD_HEIGHT = 210
local COMBAT_SLOT_PREFIX = "CombatSlot"

combatDeckFrame.Size = UDim2.fromOffset(760, 230)
combatDeckFrame.Position = UDim2.fromOffset(260, 360)

local currentRollCount = 0
local currentLevel = 1
local hasLoadedSaveData = false
local pendingSaveAfterLoad = false
local saveEvent = ReplicatedStorage:WaitForChild("SaveDataEvent")
local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CardTemplate"):WaitForChild("Card")
local updateProgressStatsDisplay = nil
local getOrCreateIntValue
local getOrCreateBoolValue
local getOrCreateBindableEvent
local getCurrencyValueObject
local getAutoRollOwnedValueObject
local findCardArtDecal
-- Forward-declared so the sell confirm handler (set up before line ~1400) can
-- reference it; the actual require happens after helper functions are defined.
local EconomyClient

local CARD_NAME_FONT = Enum.Font.Fantasy
local CARD_STAT_FONT = Enum.Font.Arcade
local CARD_META_FONT = Enum.Font.SciFi

-- Replace these placeholders with your own image asset IDs later.
local INVENTORY_BG_IMAGE = "rbxassetid://0"
local COMBAT_BG_IMAGE = "rbxassetid://0"

local function hasUsableBackgroundImage(imageId)
	return type(imageId) == "string" and imageId ~= "" and imageId ~= "rbxassetid://0"
end

-- BindableEvent for card gains from idle roll and booster openings
local idleEvent = ReplicatedStorage:FindFirstChild("IdleCardEvent")
if not idleEvent then
	idleEvent = Instance.new("BindableEvent")
	idleEvent.Name = "IdleCardEvent"
	idleEvent.Parent = ReplicatedStorage
end

local tabsFolder = script.Parent:WaitForChild("tabs")
local uiFolder = script.Parent:WaitForChild("ui")
local TabController = require(tabsFolder:WaitForChild("TabController"))
local ItemsTab = require(tabsFolder:WaitForChild("ItemsTab"))
local BoosterPacksTab = require(tabsFolder:WaitForChild("BoosterPacksTab"))
local HoverPreview = require(uiFolder:WaitForChild("HoverPreview"))
local HoverPreviewBridge = require(uiFolder:WaitForChild("HoverPreviewBridge"))
-- Why: HoloFoilController owns all holographic shimmer tween logic; importing here
-- avoids duplicating UIGradient animation code inside InventoryController.
local HoloFoilController = require(uiFolder:WaitForChild("effects"):WaitForChild("HoloFoilController"))
local ParallaxNameLabel   = require(uiFolder:WaitForChild("ParallaxNameLabel"))
local RainbowBorderStroke = require(uiFolder:WaitForChild("effects"):WaitForChild("RainbowBorderStroke"))
local BoosterPackSystem = require(script.Parent:WaitForChild("BoosterPackSystem"))

-- Backpack tab bar anchor (positioned by RPGHUDController when Backpack modal opens)
local backpackContentAnchor = Instance.new("Frame")
backpackContentAnchor.Name = "BackpackContentAnchor"
backpackContentAnchor.Size = UDim2.fromOffset(700, 500)
backpackContentAnchor.Position = UDim2.fromOffset(150, 90)
backpackContentAnchor.AnchorPoint = Vector2.new(0, 0)
backpackContentAnchor.BackgroundTransparency = 1
backpackContentAnchor.Parent = mainUI

local tabController = TabController.Init(mainUI, backpackContentAnchor, {
	ItemsTab,
	BoosterPacksTab,
})
tabController.SetActive("Items")

local function getPreviewRarityColor(rarity)
	return RarityConfig.GetPreviewRarityColor(rarity)
end

local function getBorderPulseScale(rarity)
	return RarityConfig.GetBorderPulseScale(rarity)
end

local hoverPreview = HoverPreview.Init(mainUI, artFolder, {
	stripImage = "rbxassetid://137460001724797",
	stripThickness = 20,
	stripOverdraw = 8,
	stripTileSize = 26,
	stripTransparency = 0.2,
	stripScrollSpeed = 0.6,
})
-- Publish the initialized API so other client modules (e.g. ShopUIController)
-- can show the shared preview panel without a circular require dependency.
HoverPreviewBridge.set(hoverPreview)

local function buildBorderGradient(baseColor)
	return RarityConfig.BuildBorderGradient(baseColor)
end

local function applyBeliodusShadowParticles(card)
	if not card or card:GetAttribute("HasBeliodusShadowAura") then
		return
	end
	card:SetAttribute("HasBeliodusShadowAura", true)

	local aura = card:FindFirstChild("BeliodusShadowAura")
	if not aura then
		aura = Instance.new("Frame")
		aura.Name = "BeliodusShadowAura"
		aura.Size = UDim2.new(1, 36, 1, 36)
		aura.Position = UDim2.fromOffset(-18, -18)
		aura.BackgroundTransparency = 1
		aura.BorderSizePixel = 0
		aura.ClipsDescendants = false
		aura.ZIndex = math.max(10, card.ZIndex + 4)
		aura.Parent = card
	end
	aura.Active = false
	aura.Selectable = false
	pcall(function()
		aura.Interactable = false
	end)

	task.spawn(function()
		while aura.Parent and card.Parent do
			for _ = 1, 2 do
				local particle = Instance.new("Frame")
				particle.Name = "ShadowParticle"
				particle.AnchorPoint = Vector2.new(0.5, 0.5)
				local startX = math.random(4, math.max(5, aura.AbsoluteSize.X - 4))
				local startY = math.random(4, math.max(5, aura.AbsoluteSize.Y - 4))
				local sizePx = math.random(4, 10)
				particle.Size = UDim2.fromOffset(sizePx, sizePx)
				particle.Position = UDim2.fromOffset(startX, startY)
				particle.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
				particle.BackgroundTransparency = 0.2 + (math.random() * 0.25)
				particle.BorderSizePixel = 0
				particle.ZIndex = aura.ZIndex
				particle.Parent = aura
				particle.Active = false
				particle.Selectable = false
				pcall(function()
					particle.Interactable = false
				end)

				local particleCorner = Instance.new("UICorner")
				particleCorner.CornerRadius = UDim.new(1, 0)
				particleCorner.Parent = particle

				local rise = math.random(20, 44)
				local drift = math.random(-26, 26)
				local t = 0.65 + (math.random() * 0.55)
				TweenService:Create(
					particle,
					TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromOffset(startX + drift, startY - rise),
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(sizePx + 2, sizePx + 2),
					}
				):Play()

				task.delay(t + 0.05, function()
					if particle and particle.Parent then
						particle:Destroy()
					end
				end)
			end

			task.wait(0.055)
		end
	end)
end

local function applyAnimatedCardBorder(card, rarity, cardId)
	if not card or card:GetAttribute("HasAnimatedBorder") then
		return
	end
	card:SetAttribute("HasAnimatedBorder", true)

	local isBeliodus = (cardId == "BeliodusX") or (card and card.Name == "BeliodusX")
	local isAstraEclipse = (cardId == "AstraEclipse") or (card and card.Name == "AstraEclipse")
	local isGodRarity = rarity == "God" or rarity == "Transcendent"
	-- Astra Eclipse and Beliodus both use a deep black border color.
	local borderColor = (isBeliodus or isAstraEclipse) and Color3.fromRGB(8, 8, 8) or getPreviewRarityColor(rarity)
	local pulseScale = getBorderPulseScale(rarity)
	if isBeliodus then
		pulseScale = math.max(pulseScale, 1.7)
	elseif isGodRarity then
		pulseScale = math.max(pulseScale, 1.5)
	end

	local borderStroke = card:FindFirstChild("CardBorderStroke")
	if not borderStroke then
		borderStroke = Instance.new("UIStroke")
		borderStroke.Name = "CardBorderStroke"
		borderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		borderStroke.Thickness = 3.4
		borderStroke.Transparency = 0.18
		borderStroke.Parent = card
	end
	borderStroke.Color = borderColor

	local borderGradient = borderStroke:FindFirstChild("CardBorderGradient")
	if not borderGradient then
		borderGradient = Instance.new("UIGradient")
		borderGradient.Name = "CardBorderGradient"
		borderGradient.Parent = borderStroke
	end
	borderGradient.Color = buildBorderGradient(borderColor)
	borderGradient.Rotation = 0

	local glowFrame = card:FindFirstChild("CardBorderGlow")
	if not glowFrame then
		glowFrame = Instance.new("Frame")
		glowFrame.Name = "CardBorderGlow"
		glowFrame.BackgroundTransparency = 1
		glowFrame.BorderSizePixel = 0
		glowFrame.Size = UDim2.new(1, 10, 1, 10)
		glowFrame.Position = UDim2.fromOffset(-5, -5)
		glowFrame.ZIndex = card.ZIndex
		glowFrame.Parent = card

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0, 10)
		glowCorner.Parent = glowFrame
	end

	local glowStroke = glowFrame:FindFirstChild("GlowStroke")
	if not glowStroke then
		glowStroke = Instance.new("UIStroke")
		glowStroke.Name = "GlowStroke"
		glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glowStroke.Thickness = 6.6
		glowStroke.Transparency = 0.72
		glowStroke.Parent = glowFrame
	end
	glowStroke.Color = borderColor

	local glowGradient = glowStroke:FindFirstChild("GlowGradient")
	if not glowGradient then
		glowGradient = Instance.new("UIGradient")
		glowGradient.Name = "GlowGradient"
		glowGradient.Parent = glowStroke
	end
	glowGradient.Color = buildBorderGradient(borderColor)
	glowGradient.Rotation = 0

	TweenService:Create(
		borderStroke,
		TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Thickness = 4.2 * pulseScale,
			Transparency = 0.03,
		}
	):Play()

	TweenService:Create(
		glowStroke,
		TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Thickness = 7.8 * pulseScale,
			Transparency = 0.84,
		}
	):Play()

	TweenService:Create(
		borderGradient,
		TweenInfo.new(2.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
		{Rotation = 360}
	):Play()

	TweenService:Create(
		glowGradient,
		TweenInfo.new(3.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
		{Rotation = -360}
	):Play()

	if isBeliodus or isGodRarity then
		applyBeliodusShadowParticles(card)
	end
end

local function parseCardReference(cardRef)
	return CardDatabase.ParseCardReference(cardRef)
end

local function normalizeCardReference(cardRef)
	local parsed = parseCardReference(cardRef)
	return parsed and parsed.CardRef or nil
end

local function getBaseCardId(cardRef)
	local parsed = parseCardReference(cardRef)
	return parsed and parsed.BaseCardId or nil
end

-- Why: Returns a HoloFoilController so CreateCard can toggle shimmer intensity
-- on mouse-enter/leave without re-querying the child hierarchy each frame.
-- tier: "Silver" | "Gold" | "Diamond" | "Rainbow" — explicit from the card ref,
-- or derived from the player's FoilChance stat as a fallback.
local function applyBorderedVariantVisual(card, tier)
	-- Guard against double-application; HoloFoilMask is the presence sentinel.
	if not card or card:FindFirstChild("HoloFoilMask") then
		return nil
	end

	-- Use CardVisualResolver so stroke colours are always consistent with what the
	-- HoverPreview and battle surfaces show for the same tier.
	local style = CardVisualResolver.resolveFromTier(tier or "Silver")

	local foil = HoloFoilController.Attach(card, style.foilOpts)

	local borderStroke = card:FindFirstChild("CardBorderStroke")
	if borderStroke and borderStroke:IsA("UIStroke") then
		local tierKey = tier or "Silver"
		if tierKey == "Rainbow" then
			-- Rainbow tier: rotating spectrum on the outline (not solid pink).
			local cardGrad = borderStroke:FindFirstChild("CardBorderGradient")
			if cardGrad then
				cardGrad:Destroy()
			end
			RainbowBorderStroke.attach(borderStroke)
		else
			RainbowBorderStroke.detach(borderStroke)
			borderStroke.Color = style.strokeColor
		end
	end

	local glowFrame = card:FindFirstChild("CardBorderGlow")
	local glowStroke = glowFrame and glowFrame:FindFirstChild("GlowStroke")
	if glowStroke and glowStroke:IsA("UIStroke") then
		glowStroke.Color = BalanceConfig.GetFoilVisuals().GlowColor
	end

	return foil
end

local function showHoverPreview(cardId)
	local parsed = parseCardReference(cardId)
	local cardRef = parsed and parsed.CardRef or cardId
	local baseCardId = parsed and parsed.BaseCardId or cardId
	local data = CardDatabase.GetCardData(baseCardId)
	if not data then
		return
	end
	-- Use CardVisualResolver so the hover preview stroke colour always matches
	-- the foil tier shown on the small card (single source of truth).
	local borderChancePoints = ClientStateManager.getStats and
		(ClientStateManager.getStats().FoilChance or ClientStateManager.getStats().BorderChance or 0) or 0
	local style = CardVisualResolver.resolve(
		cardRef,
		borderChancePoints,
		getPreviewRarityColor(data.Rarity)
	)
	hoverPreview.Show(cardRef, data, style.strokeColor)
end

local function hideHoverPreview(delaySeconds)
	hoverPreview.Hide(delaySeconds)
end

local function ensureDeckBackground(frame, decorName, imageId, tintColor)
	local bg = mainUI:FindFirstChild(decorName)
	if not bg then
		bg = Instance.new("ImageLabel")
		bg.Name = decorName
		bg.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		bg.BackgroundTransparency = 0.12
		bg.BorderSizePixel = 0
		bg.ScaleType = Enum.ScaleType.Crop
		bg.ImageTransparency = 1
		bg.Parent = mainUI

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = bg

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = tintColor
		stroke.Transparency = 0.15
		stroke.Parent = bg

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 55, 55)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20)),
		})
		gradient.Rotation = 90
		gradient.Parent = bg
	end

	local useImage = hasUsableBackgroundImage(imageId)
	bg.Image = useImage and imageId or ""
	bg.ImageTransparency = useImage and 0.2 or 1
	bg.ZIndex = math.max(0, frame.ZIndex - 1)
	bg.Size = frame.Size
	bg.Position = frame.Position
	bg.AnchorPoint = frame.AnchorPoint
	bg.Visible = frame.Visible

	return bg
end

local function setupDeckBackgroundSync(frame, decorName, imageId, tintColor)
	local function sync()
		-- Keep deck frame above decorative background layer.
		if frame.ZIndex < 2 then
			frame.ZIndex = 2
		end
		ensureDeckBackground(frame, decorName, imageId, tintColor)
		if frame == combatDeckFrame then
			local overlay = mainUI:FindFirstChild("CombatSlotOverlay")
			if not (overlay and overlay:IsA("Frame")) then
				overlay = Instance.new("Frame")
				overlay.Name = "CombatSlotOverlay"
				overlay.BackgroundTransparency = 1
				overlay.BorderSizePixel = 0
				overlay.Parent = mainUI

				for i = 1, COMBAT_MAX_UNIQUE - 1 do
					local slotA = combatDeckFrame:FindFirstChild("CombatSlot" .. tostring(i))
					local slotB = combatDeckFrame:FindFirstChild("CombatSlot" .. tostring(i+1))
					if slotA and slotB then
						local line = Instance.new("Frame")
						line.Name = "SlotLine" .. tostring(i)
						line.AnchorPoint = Vector2.new(0.5, 0)
						line.Size = UDim2.new(0, 2, 1, -18)
						line.BackgroundColor3 = Color3.fromRGB(230, 125, 125)
						line.BackgroundTransparency = 0.45
						line.BorderSizePixel = 0
						line.Parent = overlay
						-- Position line between slotA and slotB
						local xA = slotA.Position.X.Offset + slotA.Size.X.Offset
						local xB = slotB.Position.X.Offset
						line.Position = UDim2.fromOffset(math.floor((xA + xB) / 2), 9)
						line.ZIndex = overlay.ZIndex + 1
					end
				end
			end

			overlay.Size = frame.Size
			overlay.Position = frame.Position
			overlay.AnchorPoint = frame.AnchorPoint
			overlay.ZIndex = frame.ZIndex + 1
			overlay.Visible = frame.Visible

			for i = 1, COMBAT_MAX_UNIQUE - 1 do
				local line = overlay:FindFirstChild("SlotLine" .. tostring(i))
				if line and line:IsA("Frame") then
					local x = COMBAT_SLOT_PADDING + (COMBAT_CARD_WIDTH * i) + (COMBAT_SLOT_GAP * (i - 1)) + math.floor(COMBAT_SLOT_GAP * 0.5)
					line.Position = UDim2.fromOffset(x, 9)
					line.ZIndex = overlay.ZIndex + 1
				end
			end
		end
	end

	frame:GetPropertyChangedSignal("Visible"):Connect(sync)
	frame:GetPropertyChangedSignal("Position"):Connect(sync)
	frame:GetPropertyChangedSignal("Size"):Connect(sync)
	frame:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	sync()
end

setupDeckBackgroundSync(inventoryFrame, "InventoryDeckBackground", INVENTORY_BG_IMAGE, Color3.fromRGB(74, 130, 225))
setupDeckBackgroundSync(combatDeckFrame, "CombatDeckBackground", COMBAT_BG_IMAGE, Color3.fromRGB(225, 88, 88))

local function SyncTabsWithBackpackToggle()
	local itemsFrame = mainUI:FindFirstChild("ItemsFrame")
	local boosterPacksFrame = mainUI:FindFirstChild("BoosterPacksFrame")
	local isOpen = (itemsFrame and itemsFrame.Visible) or (boosterPacksFrame and boosterPacksFrame.Visible)
	tabController.SetVisible(isOpen)
end

local itemsFrameRef = mainUI:FindFirstChild("ItemsFrame")
local boosterPacksFrameRef = mainUI:FindFirstChild("BoosterPacksFrame")
if itemsFrameRef then
	itemsFrameRef:GetPropertyChangedSignal("Visible"):Connect(SyncTabsWithBackpackToggle)
end
if boosterPacksFrameRef then
	boosterPacksFrameRef:GetPropertyChangedSignal("Visible"):Connect(SyncTabsWithBackpackToggle)
end
task.defer(SyncTabsWithBackpackToggle)

local function SetCardStackVisual(card, parentFrame)
	if not card or not card:FindFirstChild("NumberLabel") then
		return
	end
	card.NumberLabel.Visible = (parentFrame == inventoryFrame)
end

-- For inventory/backpack: prefer Stretch over Fit so card art fills the frame
-- and avoids white gaps when aspect ratios differ.
local function resolveArtScaleType(cardId, data)
	if type(cardId) ~= "string" or cardId == "" then
		return Enum.ScaleType.Stretch
	end

	local cardData = data or CardDatabase.GetCardData(cardId)
	if cardData and cardData.ArtFitMode == "Stretch" then
		return Enum.ScaleType.Stretch
	end
	if cardData and cardData.ArtFitMode == "Crop" then
		return Enum.ScaleType.Crop
	end
	if cardData and cardData.ArtFitMode == "Fit" then
		-- Override Fit to Stretch for inventory view: fill frame, no white gaps
		return Enum.ScaleType.Stretch
	end

	local imageObj = findCardArtDecal(cardId)
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
			return Enum.ScaleType.Stretch  -- Fit -> Stretch for clean fill
		end
		if imageObj:GetAttribute("ForceStretch") == true then
			return Enum.ScaleType.Stretch
		end
		if imageObj:GetAttribute("SquareArt") == true then
			return Enum.ScaleType.Stretch
		end
	end

	return Enum.ScaleType.Stretch
end

local function applyCardArtScale(card, cardId, data)
	if not (card and card:FindFirstChild("ArtLabel")) then
		return
	end
	card.ArtLabel.ScaleType = resolveArtScaleType(cardId, data)
end

local preloadedVideoAssets = {}
local trackedVideoFrames = {}
local lastVideoTimePosition = {}
local VIDEO_LOOP_START_OFFSET_SECONDS = 1.0

local function ensureVideoFramePlayback(videoFrame, videoAssetId)
	if not (videoFrame and videoFrame:IsA("VideoFrame")) then
		return
	end
	trackedVideoFrames[videoFrame] = true

	if not preloadedVideoAssets[videoAssetId] then
		preloadedVideoAssets[videoAssetId] = true
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({videoAssetId})
			end)
		end)
	end

	local shouldRestart = (videoFrame.Video ~= videoAssetId)
	videoFrame.Looped = true
	videoFrame.Video = videoAssetId
	videoFrame.Visible = true
	if shouldRestart then
		videoFrame.TimePosition = VIDEO_LOOP_START_OFFSET_SECONDS
	end
	videoFrame.Playing = (hoverVideoPreviewActiveValue.Value ~= true)

	-- Re-assert playback after layout/content settle; bursts of UI creation can otherwise stall autoplay.
	task.defer(function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId and hoverVideoPreviewActiveValue.Value ~= true then
			videoFrame.Playing = true
		end
	end)
	task.delay(0.15, function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId and hoverVideoPreviewActiveValue.Value ~= true then
			videoFrame.Playing = true
		end
	end)
end

local playbackGuardAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	playbackGuardAccumulator += dt
	if playbackGuardAccumulator < 0.2 then
		return
	end
	playbackGuardAccumulator = 0

	for videoFrame in pairs(trackedVideoFrames) do
		if not videoFrame.Parent then
			trackedVideoFrames[videoFrame] = nil
			lastVideoTimePosition[videoFrame] = nil
		elseif videoFrame.Visible and videoFrame.Video ~= "" and videoFrame.Video ~= "rbxassetid://0" then
			videoFrame.Looped = true
			if hoverVideoPreviewActiveValue.Value == true then
				if videoFrame.Playing then
					videoFrame.Playing = false
				end
			elseif not videoFrame.Playing then
				videoFrame.Playing = true
			end

			local currentPos = tonumber(videoFrame.TimePosition) or 0
			local lastPos = lastVideoTimePosition[videoFrame]
			if lastPos and currentPos + 0.03 < lastPos and currentPos < VIDEO_LOOP_START_OFFSET_SECONDS then
				videoFrame.TimePosition = VIDEO_LOOP_START_OFFSET_SECONDS
				currentPos = VIDEO_LOOP_START_OFFSET_SECONDS
			end
			lastVideoTimePosition[videoFrame] = currentPos
		end
	end
end)

hoverVideoPreviewActiveValue:GetPropertyChangedSignal("Value"):Connect(function()
	local shouldPlay = hoverVideoPreviewActiveValue.Value ~= true
	for videoFrame in pairs(trackedVideoFrames) do
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video ~= "" and videoFrame.Video ~= "rbxassetid://0" then
			videoFrame.Playing = shouldPlay
		end
	end
end)

local function applyCardArtVisual(card, cardId, data)
	if not (card and card:FindFirstChild("ArtLabel")) then
		return
	end

	local baseCardId = getBaseCardId(cardId) or cardId
	local artLabel = card.ArtLabel
	local videoAssetId = data and data.VideoAssetId
	if type(videoAssetId) == "string" and videoAssetId ~= "" and videoAssetId ~= "rbxassetid://0" then
		local video = card:FindFirstChild("ArtVideo")
		if not (video and video:IsA("VideoFrame")) then
			if video then
				video:Destroy()
			end
			video = Instance.new("VideoFrame")
			video.Name = "ArtVideo"
			video.Size = UDim2.fromScale(1, 1)
			video.Position = UDim2.fromOffset(0, 0)
			video.BackgroundTransparency = 1
			video.BorderSizePixel = 0
			video.Parent = card
		end

		video.ZIndex = artLabel.ZIndex
		ensureVideoFramePlayback(video, videoAssetId)
		artLabel.Image = ""
		artLabel.Visible = false
		return
	end

	local video = card:FindFirstChild("ArtVideo")
	if video and video:IsA("VideoFrame") then
		video.Visible = false
		video.Playing = false
	end

	artLabel.Visible = true
	artLabel.Image = ""
	local imageObj = findCardArtDecal(baseCardId)
	if imageObj then
		artLabel.Image = imageObj.Texture
	elseif data and type(data.ArtAssetId) == "string" and data.ArtAssetId ~= "" and data.ArtAssetId ~= "rbxassetid://0" then
		artLabel.Image = data.ArtAssetId
	end
	applyCardArtScale(card, baseCardId, data)
end

local function getCombatSlotName(slotIndex)
	return COMBAT_SLOT_PREFIX .. tostring(slotIndex)
end

local function getCombatSlot(slotIndex)
	local slot = combatDeckFrame:FindFirstChild(getCombatSlotName(slotIndex))
	if slot and slot:IsA("Frame") then
		return slot
	end
	return nil
end

local function ensureCombatSlots()
	for i = 1, COMBAT_MAX_UNIQUE do
		local slot = getCombatSlot(i)
		if not slot then
			slot = Instance.new("Frame")
			slot.Name = getCombatSlotName(i)
			slot.BackgroundColor3 = Color3.fromRGB(28, 18, 18)
			slot.BackgroundTransparency = 0.5
			slot.BorderSizePixel = 0
			slot.ZIndex = combatDeckFrame.ZIndex + 1
			slot.Parent = combatDeckFrame

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = slot

			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Transparency = 0.35
			stroke.Color = Color3.fromRGB(235, 125, 125)
			stroke.Parent = slot
		end

		slot.Size = UDim2.fromOffset(COMBAT_CARD_WIDTH, COMBAT_CARD_HEIGHT)
		slot.Position = UDim2.fromOffset(
			COMBAT_SLOT_PADDING + ((i - 1) * (COMBAT_CARD_WIDTH + COMBAT_SLOT_GAP)),
			COMBAT_SLOT_PADDING
		)
		slot.ZIndex = combatDeckFrame.ZIndex + 1
	end

	combatDeckFrame.CanvasSize = UDim2.fromOffset(
		(COMBAT_SLOT_PADDING * 2) + (COMBAT_CARD_WIDTH * COMBAT_MAX_UNIQUE) + (COMBAT_SLOT_GAP * (COMBAT_MAX_UNIQUE - 1)),
		0
	)
end

local function getCardDeckContainer(card)
	if not card then
		return nil
	end
	if card.Parent == inventoryFrame then
		return inventoryFrame
	end
	if card.Parent == combatDeckFrame then
		return combatDeckFrame
	end
	local parent = card.Parent
	if parent and parent.Parent == combatDeckFrame and parent.Name:match("^" .. COMBAT_SLOT_PREFIX .. "%d+$") then
		return combatDeckFrame
	end
	return nil
end

local function getCardCombatSlotIndex(card)
	if not card or not card.Parent then
		return nil
	end
	if card.Parent == combatDeckFrame then
		return nil
	end
	if card.Parent.Parent ~= combatDeckFrame then
		return nil
	end
	local idx = tonumber(card.Parent.Name:match("^" .. COMBAT_SLOT_PREFIX .. "(%d+)$"))
	if idx and idx >= 1 and idx <= COMBAT_MAX_UNIQUE then
		return idx
	end
	return nil
end

local function getFirstEmptyCombatSlotIndex()
	for i = 1, COMBAT_MAX_UNIQUE do
		local slot = getCombatSlot(i)
		if slot and not slot:FindFirstChildWhichIsA("GuiButton") then
			return i
		end
	end
	return nil
end

local function getCombatCardsInSlot(slot)
	local cards = {}
	if not slot then
		return cards
	end
	for _, child in ipairs(slot:GetChildren()) do
		if child:IsA("GuiButton") then
			table.insert(cards, child)
		end
	end
	return cards
end

local function getCardIdFromGuiCard(guiCard)
	local candidateId = guiCard and guiCard:GetAttribute("CardId") or nil
	if type(candidateId) ~= "string" or candidateId == "" then
		candidateId = guiCard and guiCard.Name or nil
	end
	if type(candidateId) ~= "string" or candidateId == "" then
		return nil
	end
	return normalizeCardReference(candidateId)
end

local function choosePrimaryCombatSlotCard(cards)
	if #cards == 0 then
		return nil
	end
	-- Prefer non-darkmonarch when legacy duplicate cards exist in same slot.
	for _, card in ipairs(cards) do
		if getCardIdFromGuiCard(card) ~= "darkmonarch" then
			return card
		end
	end
	return cards[1]
end

local function enforceCombatDeckIntegrity()
	local changed = false
	ensureCombatSlots()

	-- Keep at most one card per slot.
	for i = 1, COMBAT_MAX_UNIQUE do
		local slot = getCombatSlot(i)
		if slot then
			local cards = getCombatCardsInSlot(slot)
			if #cards > 1 then
				local keep = choosePrimaryCombatSlotCard(cards)
				for _, extra in ipairs(cards) do
					if extra ~= keep then
						local extraId = getCardIdFromGuiCard(extra)
						extra:Destroy()
						if type(extraId) == "string" and extraId ~= "" then
							AddCardToInventory(extraId, false)
						end
						changed = true
					end
				end
			end

			local primary = choosePrimaryCombatSlotCard(getCombatCardsInSlot(slot))
			if primary then
				if not getCardIdFromGuiCard(primary) then
					primary:Destroy()
					changed = true
					continue
				end
				primary.Parent = slot
				primary.Size = UDim2.fromScale(1, 1)
				primary.Position = UDim2.fromOffset(0, 0)
				SetCardStackVisual(primary, combatDeckFrame)
			end
		end
	end

	-- Any card directly under combat frame (not inside slots) is invalid; return it to inventory.
	for _, child in ipairs(combatDeckFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			local cardId = getCardIdFromGuiCard(child)
			child:Destroy()
			if type(cardId) == "string" and cardId ~= "" then
				AddCardToInventory(cardId, false)
			end
			changed = true
		end
	end

	return changed
end

local deckDirtySinceLastSave = false
local clientSettingsDirtySinceLastSave = false
-- Block saves briefly after RequestLoad (e.g. after sell) so we don't send stale
-- inventory before the snapshot arrives. Prevents "Card ownership inflation" rejects.
local saveBlockedUntil = 0

local function SaveDeckState()
	if not hasLoadedSaveData then
		pendingSaveAfterLoad = true
		return
	end
	if os.clock() < saveBlockedUntil then
		return -- Suppress stale save during post-RequestLoad window
	end

	ensureCombatSlots()
	local hasAnySlot = false
	for i = 1, COMBAT_MAX_UNIQUE do
		if getCombatSlot(i) then
			hasAnySlot = true
			break
		end
	end
	if not hasAnySlot then
		return -- Slots not ready; do not send empty combat
	end

	enforceCombatDeckIntegrity()

	local invList = {}
	for _, c in pairs(inventoryFrame:GetChildren()) do
		if c:IsA("GuiButton") then
			local cardId = getCardIdFromGuiCard(c)
			if not cardId then
				c:Destroy()
				continue
			end
			local count = tonumber(c.NumberLabel.Text) or 1
			for _ = 1, count do
				table.insert(invList, cardId)
			end
		end
	end

	local deckList = {}
	for i = 1, COMBAT_MAX_UNIQUE do
		local slot = getCombatSlot(i)
		if slot then
			local slotCards = getCombatCardsInSlot(slot)
			local c = choosePrimaryCombatSlotCard(slotCards)
			local cardId = getCardIdFromGuiCard(c)
			-- Keep fixed slot indexes so rejoin rebuild is exact.
			deckList[i] = cardId or ""
		else
			deckList[i] = ""
		end
	end

	local settingsState = SettingsUIController.GetState()
	local payload = {
		inventory = invList,
		combat = deckList,
		rollCount = currentRollCount,
		level = currentLevel,
		coins = getCurrencyValueObject().Value,
		clientSettings = {
			ShowIdleRollCardNotifications = settingsState and settingsState.ShowIdleRollCardNotifications,
		},
	}
	saveEvent:FireServer(payload)
	deckDirtySinceLastSave = false
	clientSettingsDirtySinceLastSave = false
end

-- Save deck when Deck modal closes (combat deck was visible)
local wasCombatVisible = false
combatDeckFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	local nowVisible = combatDeckFrame.Visible
	if wasCombatVisible and not nowVisible then
		deckDirtySinceLastSave = true
		task.defer(SaveDeckState)
	end
	wasCombatVisible = nowVisible
end)

ClientSettingsChangedEvent.Event:Connect(function()
	clientSettingsDirtySinceLastSave = true
end)

-- Periodic save when deck or client settings are dirty (backup for disconnect/flake)
task.spawn(function()
	while true do
		task.wait(2)
		if (deckDirtySinceLastSave or clientSettingsDirtySinceLastSave) and hasLoadedSaveData then
			task.defer(SaveDeckState)
		end
	end
end)

local function SetProgress(rollCount, level)
	-- Server is authoritative on both rollCount and level.
	-- Store the raw cumulative rollCount; level is derived server-side by the same
	-- floor(rollCount / ROLLS_PER_LEVEL) + 1 formula so we trust it directly.
	if type(level) == "number" then
		currentLevel = math.max(1, math.floor(level))
	end
	if type(rollCount) == "number" then
		currentRollCount = math.max(0, math.floor(rollCount))
		-- Derive level from rollCount if level was not supplied, using the same
		-- flat formula the server uses so client and server always agree.
		if type(level) ~= "number" then
			currentLevel = math.floor(currentRollCount / BalanceConfig.ROLLS_PER_LEVEL) + 1
		end
	end
	if updateProgressStatsDisplay then
		updateProgressStatsDisplay()
	end
end

getOrCreateIntValue = function(name, defaultValue)
	local valueObj = ReplicatedStorage:FindFirstChild(name)
	if not (valueObj and valueObj:IsA("IntValue")) then
		if valueObj then
			valueObj:Destroy()
		end
		valueObj = Instance.new("IntValue")
		valueObj.Name = name
		valueObj.Value = defaultValue or 0
		valueObj.Parent = ReplicatedStorage
	end
	return valueObj
end

getOrCreateBoolValue = function(name, defaultValue)
	local valueObj = ReplicatedStorage:FindFirstChild(name)
	if not (valueObj and valueObj:IsA("BoolValue")) then
		if valueObj then
			valueObj:Destroy()
		end
		valueObj = Instance.new("BoolValue")
		valueObj.Name = name
		valueObj.Value = defaultValue == true
		valueObj.Parent = ReplicatedStorage
	end
	return valueObj
end

getOrCreateBindableEvent = function(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if not (ev and ev:IsA("BindableEvent")) then
		if ev then
			ev:Destroy()
		end
		ev = Instance.new("BindableEvent")
		ev.Name = name
		ev.Parent = ReplicatedStorage
	end
	return ev
end

getCurrencyValueObject = function()
	local valueObj = ReplicatedStorage:FindFirstChild("PlayerCurrencyValue")
	if not (valueObj and valueObj:IsA("IntValue")) then
		if valueObj then
			valueObj:Destroy()
		end
		valueObj = Instance.new("IntValue")
		valueObj.Name = "PlayerCurrencyValue"
		valueObj.Value = 0
		valueObj.Parent = ReplicatedStorage
	end
	return valueObj
end

getAutoRollOwnedValueObject = function()
	return getOrCreateIntValue("ItemOwned_AutoRoll2x20s", 0)
end

local sellModeEnabledValue = getOrCreateBoolValue("ShopSellModeEnabled", false)
local selectedSellCountValue = getOrCreateIntValue("ShopSellSelectedCount", 0)
local selectedSellCoinsValue = getOrCreateIntValue("ShopSellSelectedCoins", 0)
local confirmSellSelectionEvent = getOrCreateBindableEvent("ConfirmSellSelectionEvent")
local inventoryRebuiltEvent = getOrCreateBindableEvent("InventoryRebuiltEvent")

local selectedSellCountByCard = {}

local function getCardSellValue(cardId)
	local baseCardId = getBaseCardId(cardId) or cardId
	return math.max(0, math.floor(EconomyCatalog.GetCardSellValue(baseCardId) or 0))
end

local function applySellSelectionVisual(card, selectedCount)
	if not card then
		return
	end

	local glow = card:FindFirstChild("SellSelectGlow")
	if not (glow and glow:IsA("UIStroke")) then
		glow = Instance.new("UIStroke")
		glow.Name = "SellSelectGlow"
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glow.Thickness = 4
		glow.Color = Color3.fromRGB(255, 215, 95)
		glow.Transparency = 1
		glow.Parent = card
	end
	-- Set high ZIndex for glow if possible
	pcall(function()
		if card:IsA("GuiObject") then
			card.ZIndex = math.max(card.ZIndex, 50)
		end
	end)

	local badge = card:FindFirstChild("SellSelectBadge")
	if not (badge and badge:IsA("TextLabel")) then
		badge = Instance.new("TextLabel")
		badge.Name = "SellSelectBadge"
		badge.AnchorPoint = Vector2.new(0, 0)
		badge.Size = UDim2.fromOffset(56, 18)
		badge.Position = UDim2.fromOffset(4, 4)
		badge.BackgroundColor3 = Color3.fromRGB(34, 94, 52)
		badge.BackgroundTransparency = 0.12
		badge.BorderSizePixel = 0
		badge.Font = Enum.Font.SourceSansBold
		badge.TextColor3 = Color3.fromRGB(229, 255, 214)
		badge.TextScaled = true
		badge.Visible = false
		badge.ZIndex = 100
		badge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 4)
		badgeCorner.Parent = badge
	else
		badge.ZIndex = 100
	end

	if selectedCount > 0 then
		glow.Transparency = 0.05
		badge.Visible = true
		badge.Text = "SELL x" .. tostring(selectedCount)
	else
		glow.Transparency = 1
		badge.Visible = false
	end
end

local function refreshSellSelectionTotals()
	local totalCount = 0
	local totalCoins = 0
	for card, count in pairs(selectedSellCountByCard) do
		if not (card and card.Parent == inventoryFrame and count > 0) then
			selectedSellCountByCard[card] = nil
			if card then
				applySellSelectionVisual(card, 0)
			end
		else
			local stackCount = tonumber(card.NumberLabel.Text) or 1
			local clamped = math.max(0, math.min(count, stackCount))
			selectedSellCountByCard[card] = clamped
			applySellSelectionVisual(card, clamped)
			local cardId = getCardIdFromGuiCard(card) or card.Name
			totalCount += clamped
			totalCoins += clamped * getCardSellValue(cardId)
		end
	end

	selectedSellCountValue.Value = totalCount
	selectedSellCoinsValue.Value = totalCoins
end

local function clearSellSelections()
	for card in pairs(selectedSellCountByCard) do
		if card then
			applySellSelectionVisual(card, 0)
		end
	end
	table.clear(selectedSellCountByCard)
	selectedSellCountValue.Value = 0
	selectedSellCoinsValue.Value = 0
end

sellModeEnabledValue:GetPropertyChangedSignal("Value"):Connect(function()
	if not sellModeEnabledValue.Value then
		clearSellSelections()
	else
		refreshSellSelectionTotals()
	end
end)

confirmSellSelectionEvent.Event:Connect(function()
	if not sellModeEnabledValue.Value then
		return
	end
	if not EconomyClient then
		warn("[Sell] EconomyClient not yet loaded; try again in a moment.")
		return
	end

	-- Build { [cardRef] = count } dict for the server request.
	local selectionDict = {}
	for card, count in pairs(selectedSellCountByCard) do
		if card and card.Parent == inventoryFrame and count > 0 then
			local cardId = getCardIdFromGuiCard(card) or card.Name
			selectionDict[cardId] = (selectionDict[cardId] or 0) + count
		end
	end

	if next(selectionDict) == nil then
		return
	end

	-- Disable further sells mid-flight.
	sellModeEnabledValue.Value = false
	clearSellSelections()

		task.spawn(function()
			local ok, response = EconomyClient.SellCards(selectionDict)
			if ok then
				-- Block SaveDeckState for 2.5s so we don't send stale inventory
				-- before the snapshot arrives (prevents merge rejection).
				saveBlockedUntil = os.clock() + 2.5
				-- Request a fresh data snapshot so the inventory grid rebuilds
				-- from authoritative server state (same mechanism used at startup).
				saveEvent:FireServer("RequestLoad")
			else
			warn("[Sell] Server rejected sell:", tostring(response))
			-- Re-enable sell mode so the player can retry.
			sellModeEnabledValue.Value = true
		end
	end)
end)

-- ── Inventory Sell-Mode Side Panel ────────────────────────────────────────────
-- Compact vertical panel docked to the RIGHT of inventoryFrame so it never
-- touches the tab bar above or the combat deck frame below.
-- Why a sibling of inventoryFrame (not a child): inventoryFrame is a
-- ClipsDescendants ScrollingFrame — its children cannot overflow its bounds.

local SELL_PANEL_W = 128

local function ensureSellToolbar()
	local existing = mainUI:FindFirstChild("InventorySellPanel")
	if existing and existing:IsA("Frame") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	-- Panel shell — height will be kept in sync with inventoryFrame via reposition
	local panel = Instance.new("Frame")
	panel.Name                  = "InventorySellPanel"
	panel.AnchorPoint           = Vector2.new(0, 0)
	panel.Size                  = UDim2.fromOffset(SELL_PANEL_W, 320)
	panel.Position              = UDim2.fromOffset(0, 0)   -- overwritten by repositionPanel
	panel.BackgroundColor3      = Color3.fromRGB(18, 20, 28)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel       = 0
	panel.ZIndex                = 110
	panel.Visible               = false
	panel.Parent                = mainUI

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Thickness    = 1.5
	stroke.Transparency = 0.45
	stroke.Color        = Color3.fromRGB(70, 100, 160)
	stroke.Parent       = panel

	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(30, 34, 48)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 20, 28)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(14, 16, 22)),
	})
	bg.Rotation = 90
	bg.Parent = panel

	-- ── Toggle button (always visible while panel is showing) ─────────────────
	local sellToggle = Instance.new("TextButton")
	sellToggle.Name             = "SellToggle"
	sellToggle.Size             = UDim2.new(1, -16, 0, 36)
	sellToggle.AnchorPoint      = Vector2.new(0.5, 0)
	sellToggle.Position         = UDim2.new(0.5, 0, 0, 10)
	sellToggle.BackgroundColor3 = Color3.fromRGB(55, 120, 75)
	sellToggle.BorderSizePixel  = 0
	sellToggle.AutoButtonColor  = false
	sellToggle.Font             = Enum.Font.GothamBold
	sellToggle.TextSize         = 13
	sellToggle.TextColor3       = Color3.fromRGB(220, 255, 230)
	sellToggle.Text             = "SELL"
	sellToggle.ZIndex           = 111
	sellToggle.Parent           = panel

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 8)
	toggleCorner.Parent = sellToggle

	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Thickness    = 1
	toggleStroke.Transparency = 0.45
	toggleStroke.Color        = Color3.fromRGB(90, 200, 120)
	toggleStroke.Parent       = sellToggle

	-- ── Divider ───────────────────────────────────────────────────────────────
	local divider = Instance.new("Frame")
	divider.Name                 = "Divider"
	divider.Size                 = UDim2.new(1, -20, 0, 1)
	divider.AnchorPoint          = Vector2.new(0.5, 0)
	divider.Position             = UDim2.new(0.5, 0, 0, 54)
	divider.BackgroundColor3     = Color3.fromRGB(60, 75, 110)
	divider.BackgroundTransparency = 0.3
	divider.BorderSizePixel      = 0
	divider.ZIndex               = 111
	divider.Visible              = false
	divider.Parent               = panel

	-- ── Totals label — 2-line compact display ─────────────────────────────────
	local totalsLabel = Instance.new("TextLabel")
	totalsLabel.Name               = "TotalsLabel"
	totalsLabel.Size               = UDim2.new(1, -8, 0, 46)
	totalsLabel.AnchorPoint        = Vector2.new(0.5, 0)
	totalsLabel.Position           = UDim2.new(0.5, 0, 0, 60)
	totalsLabel.BackgroundTransparency = 1
	totalsLabel.Font               = Enum.Font.GothamMedium
	totalsLabel.TextSize           = 12
	totalsLabel.TextColor3         = Color3.fromRGB(190, 210, 245)
	totalsLabel.TextXAlignment     = Enum.TextXAlignment.Center
	totalsLabel.TextWrapped        = true
	totalsLabel.Text               = ""
	totalsLabel.Visible            = false
	totalsLabel.ZIndex             = 111
	totalsLabel.Parent             = panel

	-- ── Confirm button ────────────────────────────────────────────────────────
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name             = "ConfirmBtn"
	confirmBtn.Size             = UDim2.new(1, -16, 0, 34)
	confirmBtn.AnchorPoint      = Vector2.new(0.5, 0)
	confirmBtn.Position         = UDim2.new(0.5, 0, 0, 112)
	confirmBtn.BackgroundColor3 = Color3.fromRGB(55, 150, 80)
	confirmBtn.BorderSizePixel  = 0
	confirmBtn.AutoButtonColor  = false
	confirmBtn.Font             = Enum.Font.GothamBold
	confirmBtn.TextSize         = 13
	confirmBtn.TextColor3       = Color3.new(1, 1, 1)
	confirmBtn.Text             = "CONFIRM"
	confirmBtn.Visible          = false
	confirmBtn.ZIndex           = 111
	confirmBtn.Parent           = panel

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 8)
	confirmCorner.Parent = confirmBtn

	-- ── Cancel button ─────────────────────────────────────────────────────────
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name             = "CancelBtn"
	cancelBtn.Size             = UDim2.new(1, -16, 0, 30)
	cancelBtn.AnchorPoint      = Vector2.new(0.5, 0)
	cancelBtn.Position         = UDim2.new(0.5, 0, 0, 154)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(130, 50, 50)
	cancelBtn.BorderSizePixel  = 0
	cancelBtn.AutoButtonColor  = false
	cancelBtn.Font             = Enum.Font.GothamBold
	cancelBtn.TextSize         = 13
	cancelBtn.TextColor3       = Color3.new(1, 1, 1)
	cancelBtn.Text             = "CANCEL"
	cancelBtn.Visible          = false
	cancelBtn.ZIndex           = 111
	cancelBtn.Parent           = panel

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 8)
	cancelCorner.Parent = cancelBtn

	-- ── State sync ────────────────────────────────────────────────────────────
	local function refreshSellBar()
		local isOn  = sellModeEnabledValue.Value
		local count = selectedSellCountValue.Value
		local coins = selectedSellCoinsValue.Value

		if isOn then
			sellToggle.Text             = "EXIT SELL"
			sellToggle.BackgroundColor3 = Color3.fromRGB(130, 50, 50)
			sellToggle.TextColor3       = Color3.fromRGB(255, 200, 200)
			toggleStroke.Color          = Color3.fromRGB(200, 90, 90)
		else
			sellToggle.Text             = "SELL"
			sellToggle.BackgroundColor3 = Color3.fromRGB(55, 120, 75)
			sellToggle.TextColor3       = Color3.fromRGB(220, 255, 230)
			toggleStroke.Color          = Color3.fromRGB(90, 200, 120)
		end

		divider.Visible    = isOn
		totalsLabel.Visible = isOn
		confirmBtn.Visible  = isOn
		cancelBtn.Visible   = isOn

		if isOn then
			if count > 0 then
				local suffix = count == 1 and "" or "s"
				totalsLabel.Text = string.format("%d card%s\n+%d coins", count, suffix, coins)
			else
				totalsLabel.Text = "Tap cards\nto select"
			end
			local hasSelection = count > 0
			confirmBtn.BackgroundColor3 = hasSelection
				and Color3.fromRGB(55, 150, 80)
				or  Color3.fromRGB(35, 45, 35)
			confirmBtn.TextColor3 = hasSelection
				and Color3.new(1, 1, 1)
				or  Color3.fromRGB(100, 120, 100)
		end
	end

	-- Keep the panel pinned to the right edge of inventoryFrame, matching its height.
	local function repositionPanel()
		if not (panel and panel.Parent) then return end
		local absPos  = inventoryFrame.AbsolutePosition
		local absSize = inventoryFrame.AbsoluteSize
		panel.Size     = UDim2.fromOffset(SELL_PANEL_W, absSize.Y)
		panel.Position = UDim2.fromOffset(absPos.X + absSize.X + 8, absPos.Y)
	end

	inventoryFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionPanel)
	inventoryFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionPanel)
	task.defer(repositionPanel)

	-- Mirror visibility; auto-exit sell mode when the inventory closes.
	inventoryFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		panel.Visible = inventoryFrame.Visible
		if not inventoryFrame.Visible then
			if sellModeEnabledValue.Value then
				clearSellSelections()
				sellModeEnabledValue.Value = false
			end
		end
		refreshSellBar()
	end)

	sellModeEnabledValue:GetPropertyChangedSignal("Value"):Connect(refreshSellBar)
	selectedSellCountValue:GetPropertyChangedSignal("Value"):Connect(refreshSellBar)
	selectedSellCoinsValue:GetPropertyChangedSignal("Value"):Connect(refreshSellBar)

	-- Button wiring
	sellToggle.MouseButton1Click:Connect(function()
		if sellModeEnabledValue.Value then
			clearSellSelections()
			sellModeEnabledValue.Value = false
		else
			sellModeEnabledValue.Value = true
		end
		refreshSellBar()
	end)

	confirmBtn.MouseButton1Click:Connect(function()
		if selectedSellCountValue.Value > 0 then
			confirmSellSelectionEvent:Fire()
		end
	end)

	cancelBtn.MouseButton1Click:Connect(function()
		clearSellSelections()
		sellModeEnabledValue.Value = false
		refreshSellBar()
	end)

	-- Subtle hover tint on toggle
	sellToggle.MouseEnter:Connect(function()
		TweenService:Create(sellToggle, TweenInfo.new(0.12), {
			BackgroundTransparency = 0.25,
		}):Play()
	end)
	sellToggle.MouseLeave:Connect(function()
		TweenService:Create(sellToggle, TweenInfo.new(0.12), {
			BackgroundTransparency = 0,
		}):Play()
	end)

	refreshSellBar()
	return panel
end

-- ── Bottom Stats HUD ──────────────────────────────────────────────────────────
-- Centered glass panel matching the RPG HUD visual language.
-- Layout: [LEVEL stat] | [ROLLS label + progress bar + count] | [COINS stat]
-- Why centered: AnchorPoint (0.5,1) + Position (0.5,0,1,-14) adapts to any
-- viewport width without needing a per-frame resize connection.

local HUD_HEIGHT    = 72
local HUD_MAX_WIDTH = 620
local HUD_PAD_SIDE  = 16

-- Builds one stat block (left or right side): a muted label above a bold value.
local function makeStatBlock(parent, blockName, labelText, accentColor, xAlignEnum)
	local block = parent:FindFirstChild(blockName)
	if block and block:IsA("Frame") then
		return block
	end
	if block then
		block:Destroy()
	end

	block = Instance.new("Frame")
	block.Name = blockName
	block.Size = UDim2.new(0, 90, 1, 0)
	block.BackgroundTransparency = 1
	block.BorderSizePixel = 0
	block.Parent = parent

	-- Thin accent stripe along the inner edge
	-- xEdge: 0 for left-aligned blocks, 1 for right-aligned (stripe hugs the
	-- inner boundary so it visually separates sections inside the panel).
	local xEdge = (xAlignEnum == Enum.TextXAlignment.Left) and 0 or 1
	local stripe = Instance.new("Frame")
	stripe.Name            = "Stripe"
	stripe.Size            = UDim2.new(0, 3, 0.55, 0)
	stripe.AnchorPoint     = Vector2.new(xEdge, 0.5)
	stripe.Position        = UDim2.new(xEdge, 0, 0.5, 0)
	stripe.BackgroundColor3 = accentColor
	stripe.BorderSizePixel = 0
	stripe.Parent          = block

	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 2)
	stripeCorner.Parent = stripe

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.new(1, 0, 0, 18)
	lbl.Position = UDim2.fromOffset(0, 8)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 12
	lbl.TextColor3 = accentColor
	lbl.TextXAlignment = xAlignEnum
	lbl.Parent = block

	local val = Instance.new("TextLabel")
	val.Name = "Value"
	val.Size = UDim2.new(1, 0, 0, 30)
	val.Position = UDim2.fromOffset(0, 26)
	val.BackgroundTransparency = 1
	val.Text = "0"
	val.Font = Enum.Font.GothamBold
	val.TextSize = 26
	val.TextColor3 = Color3.fromRGB(240, 245, 255)
	val.TextXAlignment = xAlignEnum
	val.Parent = block

	return block
end

-- Builds the center rolls section: label + progress bar + count text.
local function makeRollsSection(parent)
	local section = parent:FindFirstChild("RollsSection")
	if section and section:IsA("Frame") then
		return section
	end
	if section then
		section:Destroy()
	end

	section = Instance.new("Frame")
	section.Name = "RollsSection"
	section.Size = UDim2.new(1, -(90 + 90 + HUD_PAD_SIDE * 4), 1, 0)
	section.AnchorPoint = Vector2.new(0.5, 0)
	section.Position = UDim2.new(0.5, 0, 0, 0)
	section.BackgroundTransparency = 1
	section.BorderSizePixel = 0
	section.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.new(1, 0, 0, 16)
	lbl.Position = UDim2.fromOffset(0, 7)
	lbl.BackgroundTransparency = 1
	lbl.Text = "ROLLS TO NEXT LEVEL"
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 11
	lbl.TextColor3 = Color3.fromRGB(130, 160, 210)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Parent = section

	-- Progress bar track
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 10)
	track.Position = UDim2.fromOffset(0, 26)
	track.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = section

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 5)
	trackCorner.Parent = track

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 148, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	-- Subtle gloss highlight on the fill
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, 0, 0.6, 0)
	gloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	gloss.BackgroundTransparency = 0.82
	gloss.BorderSizePixel = 0
	gloss.Parent = fill

	local glossCorner = Instance.new("UICorner")
	glossCorner.CornerRadius = UDim.new(0, 4)
	glossCorner.Parent = gloss

	-- Fill gradient (lighter left edge)
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(120, 185, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80,  148, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(55,  110, 220)),
	})
	fillGrad.Rotation = 0
	fillGrad.Parent = fill

	-- Compact count label below bar
	local countLbl = Instance.new("TextLabel")
	countLbl.Name = "CountLabel"
	countLbl.Size = UDim2.new(1, 0, 0, 16)
	countLbl.Position = UDim2.fromOffset(0, 39)
	countLbl.BackgroundTransparency = 1
	countLbl.Text = "0 / 10"
	countLbl.Font = Enum.Font.GothamMedium
	countLbl.TextSize = 12
	countLbl.TextColor3 = Color3.fromRGB(165, 185, 220)
	countLbl.TextXAlignment = Enum.TextXAlignment.Center
	countLbl.Parent = section

	return section
end

local function ensureBottomStatsBar()
	local statsBar = mainUI:FindFirstChild("BottomStatsBar")
	if not (statsBar and statsBar:IsA("Frame")) then
		if statsBar then
			statsBar:Destroy()
		end

		-- Soft drop shadow (same technique as RPG HUD modals)
		local shadow = Instance.new("ImageLabel")
		shadow.Name = "BottomStatsBarShadow"
		shadow.AnchorPoint = Vector2.new(0.5, 1)
		shadow.Size = UDim2.new(0, HUD_MAX_WIDTH + 48, 0, HUD_HEIGHT + 32)
		shadow.Position = UDim2.new(0.5, 0, 1, -6)
		shadow.BackgroundTransparency = 1
		shadow.Image = "rbxassetid://466659280"
		shadow.ImageColor3 = Color3.new(0, 0, 0)
		shadow.ImageTransparency = 0.55
		shadow.ZIndex = 38
		shadow.Parent = mainUI

		-- Main glass panel
		statsBar = Instance.new("Frame")
		statsBar.Name = "BottomStatsBar"
		-- Centered, anchored to bottom of screen
		statsBar.AnchorPoint = Vector2.new(0.5, 1)
		statsBar.Position = UDim2.new(0.5, 0, 1, -14)
		statsBar.Size = UDim2.fromOffset(HUD_MAX_WIDTH, HUD_HEIGHT)
		statsBar.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
		statsBar.BackgroundTransparency = 0.08
		statsBar.BorderSizePixel = 0
		statsBar.ZIndex = 40
		statsBar.Parent = mainUI

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 16)
		corner.Parent = statsBar

		-- Subtle outer stroke
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Transparency = 0.45
		stroke.Color = Color3.fromRGB(70, 100, 160)
		stroke.Parent = statsBar

		-- Background gradient (top brighter, bottom darker — glass depth)
		local bg = Instance.new("UIGradient")
		bg.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(30, 34, 48)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 20, 28)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(14, 16, 22)),
		})
		bg.Rotation = 90
		bg.Parent = statsBar

		-- Horizontal dividers to visually separate the three sections
		local divLeft = Instance.new("Frame")
		divLeft.Name = "DivLeft"
		divLeft.AnchorPoint = Vector2.new(0, 0.5)
		divLeft.Size = UDim2.new(0, 1, 0.6, 0)
		divLeft.Position = UDim2.new(0, 90 + HUD_PAD_SIDE * 2, 0.5, 0)
		divLeft.BackgroundColor3 = Color3.fromRGB(60, 75, 110)
		divLeft.BackgroundTransparency = 0.3
		divLeft.BorderSizePixel = 0
		divLeft.ZIndex = 41
		divLeft.Parent = statsBar

		local divRight = Instance.new("Frame")
		divRight.Name = "DivRight"
		divRight.AnchorPoint = Vector2.new(1, 0.5)
		divRight.Size = UDim2.new(0, 1, 0.6, 0)
		divRight.Position = UDim2.new(1, -(90 + HUD_PAD_SIDE * 2), 0.5, 0)
		divRight.BackgroundColor3 = Color3.fromRGB(60, 75, 110)
		divRight.BackgroundTransparency = 0.3
		divRight.BorderSizePixel = 0
		divRight.ZIndex = 41
		divRight.Parent = statsBar

		-- Padding wrapper so children sit inside the panel edges
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft  = UDim.new(0, HUD_PAD_SIDE)
		pad.PaddingRight = UDim.new(0, HUD_PAD_SIDE)
		pad.Parent = statsBar
	end

	-- Left section: LEVEL
	local levelBlock = makeStatBlock(
		statsBar, "LevelBlock",
		"LEVEL", Color3.fromRGB(128, 210, 138),
		Enum.TextXAlignment.Left
	)
	levelBlock.AnchorPoint = Vector2.new(0, 0)
	levelBlock.Position    = UDim2.fromOffset(0, 0)

	-- Right section: COINS
	local coinsBlock = makeStatBlock(
		statsBar, "CoinsBlock",
		"COINS", Color3.fromRGB(255, 200, 92),
		Enum.TextXAlignment.Right
	)
	coinsBlock.AnchorPoint = Vector2.new(1, 0)
	coinsBlock.Position    = UDim2.new(1, 0, 0, 0)

	-- Center section: ROLLS progress bar
	makeRollsSection(statsBar)

	return statsBar
end

local currencyValue = getCurrencyValueObject()

updateProgressStatsDisplay = function()
	local statsBar = ensureBottomStatsBar()
	if not statsBar then
		return
	end

	-- Level
	local levelBlock = statsBar:FindFirstChild("LevelBlock")
	if levelBlock and levelBlock:FindFirstChild("Value") then
		levelBlock.Value.Text = tostring(currentLevel)
	end

	-- Coins
	local coinsBlock = statsBar:FindFirstChild("CoinsBlock")
	if coinsBlock and coinsBlock:FindFirstChild("Value") then
		coinsBlock.Value.Text = tostring(currencyValue.Value)
	end

	-- Rolls progress bar + count label.
	-- Server uses flat formula: level = floor(totalRolls / ROLLS_PER_LEVEL) + 1.
	-- Progress within the current level = totalRolls mod ROLLS_PER_LEVEL.
	local rollsSection = statsBar:FindFirstChild("RollsSection")
	if rollsSection then
		local rollsPerLevel = BalanceConfig.ROLLS_PER_LEVEL
		local rollsInLevel = currentRollCount % rollsPerLevel
		local pct = math.clamp(rollsInLevel / rollsPerLevel, 0, 1)

		local track = rollsSection:FindFirstChild("Track")
		if track then
			local fill = track:FindFirstChild("Fill")
			if fill then
				TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(pct, 1)
				}):Play()
			end
		end

		local countLbl = rollsSection:FindFirstChild("CountLabel")
		if countLbl then
			countLbl.Text = string.format("%d / %d", rollsInLevel, rollsPerLevel)
		end
	end
end

currencyValue:GetPropertyChangedSignal("Value"):Connect(function()
	if updateProgressStatsDisplay then
		updateProgressStatsDisplay()
	end
end)

local economySnapshotEvent = ReplicatedStorage:FindFirstChild("EconomySnapshotEvent")
local function handleEconomySnapshot(payload)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.boosterPacks) == "table" then
		BoosterPackSystem.LoadOwnedSnapshot(payload.boosterPacks)
	end
end

if economySnapshotEvent and economySnapshotEvent:IsA("RemoteEvent") then
	economySnapshotEvent.OnClientEvent:Connect(handleEconomySnapshot)
else
	if economySnapshotEvent and not economySnapshotEvent:IsA("BindableEvent") then
		economySnapshotEvent:Destroy()
		economySnapshotEvent = nil
	end
	if not economySnapshotEvent then
		economySnapshotEvent = Instance.new("BindableEvent")
		economySnapshotEvent.Name = "EconomySnapshotEvent"
		economySnapshotEvent.Parent = ReplicatedStorage
	end
	economySnapshotEvent.Event:Connect(handleEconomySnapshot)
end

updateProgressStatsDisplay()

-- Fulfill the forward declaration so the sell confirm handler can use it.
EconomyClient = require(script.Parent:WaitForChild("services"):WaitForChild("EconomyClient"))
task.spawn(function()
	local ok, err = EconomyClient.SyncState()
	if not ok then
		warn("[InventoryController] Failed to sync economy state:", err)
	end
end)

findCardArtDecal = function(cardId)
	if type(cardId) ~= "string" or cardId == "" then
		return nil
	end

	local baseCardId = getBaseCardId(cardId) or cardId
	local exact = artFolder:FindFirstChild(baseCardId)
	if exact and exact:IsA("Decal") then
		return exact
	end

	local target = string.lower(baseCardId)
	for _, obj in ipairs(artFolder:GetChildren()) do
		if obj:IsA("Decal") and string.lower(obj.Name) == target then
			return obj
		end
	end

	return nil
end

local function isPointInsideGui(point, guiObject)
	if not (guiObject and guiObject.Visible) then
		return false
	end
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return point.X >= pos.X and point.X <= (pos.X + size.X)
		and point.Y >= pos.Y and point.Y <= (pos.Y + size.Y)
end

local function getDropTargetAtPoint(point)
	local inventoryBg = mainUI:FindFirstChild("InventoryDeckBackground")
	local combatBg = mainUI:FindFirstChild("CombatDeckBackground")

	if isPointInsideGui(point, inventoryFrame) then
		return {kind = "frame", frame = inventoryFrame}
	end
	if inventoryBg and isPointInsideGui(point, inventoryBg) then
		return {kind = "frame", frame = inventoryFrame}
	end
	if isPointInsideGui(point, combatDeckFrame) then
		ensureCombatSlots()
		for i = 1, COMBAT_MAX_UNIQUE do
			local slot = getCombatSlot(i)
			if slot and isPointInsideGui(point, slot) then
				return {kind = "frame", frame = combatDeckFrame, slotIndex = i}
			end
		end
		return {kind = "frame", frame = combatDeckFrame, slotIndex = getFirstEmptyCombatSlotIndex()}
	end
	if combatBg and isPointInsideGui(point, combatBg) then
		return {kind = "frame", frame = combatDeckFrame, slotIndex = getFirstEmptyCombatSlotIndex()}
	end
	return nil
end

local function moveOneCardToFrame(card, targetParent, targetSlotIndex)
	if not (card and targetParent and (targetParent == inventoryFrame or targetParent == combatDeckFrame)) then
		return false
	end

	local sourceParent = getCardDeckContainer(card)
	if not (sourceParent == inventoryFrame or sourceParent == combatDeckFrame) then
		return false
	end
	local cardId = getCardIdFromGuiCard(card)
	if type(cardId) ~= "string" or cardId == "" then
		return false
	end

	-- Combat to combat: swap/reposition inside fixed slots.
	if sourceParent == combatDeckFrame and targetParent == combatDeckFrame then
		ensureCombatSlots()
		local fromSlotIndex = getCardCombatSlotIndex(card)
		local toSlotIndex = targetSlotIndex or fromSlotIndex
		if not (fromSlotIndex and toSlotIndex) or fromSlotIndex == toSlotIndex then
			return false
		end

		local fromSlot = getCombatSlot(fromSlotIndex)
		local toSlot = getCombatSlot(toSlotIndex)
		if not (fromSlot and toSlot) then
			return false
		end

		local occupying = toSlot:FindFirstChildWhichIsA("GuiButton")
		if occupying and occupying ~= card then
			occupying.Parent = fromSlot
			occupying.Size = UDim2.fromScale(1, 1)
			occupying.Position = UDim2.fromOffset(0, 0)
			SetCardStackVisual(occupying, combatDeckFrame)
		end

		card.Parent = toSlot
		card.Size = UDim2.fromScale(1, 1)
		card.Position = UDim2.fromOffset(0, 0)
		SetCardStackVisual(card, combatDeckFrame)
		deckDirtySinceLastSave = true
		SaveDeckState()
		return true
	end

	if sourceParent == targetParent then
		return false
	end

	-- Combat to inventory: remove from slot and add one stack in inventory.
	if sourceParent == combatDeckFrame and targetParent == inventoryFrame then
		card:Destroy()
		AddCardToInventory(cardId, false)
		deckDirtySinceLastSave = true
		SaveDeckState()
		return true
	end

	-- Inventory to combat: consume one stack and place into target slot.
	if sourceParent == inventoryFrame and targetParent == combatDeckFrame then
		ensureCombatSlots()
		local chosenSlotIndex = targetSlotIndex
		if not chosenSlotIndex then
			chosenSlotIndex = getFirstEmptyCombatSlotIndex()
		end
		if not chosenSlotIndex then
			return false
		end

		local chosenSlot = getCombatSlot(chosenSlotIndex)
		if not chosenSlot then
			return false
		end

		local replacedCards = getCombatCardsInSlot(chosenSlot)

		-- Consume one from inventory stack.
		local num = tonumber(card.NumberLabel.Text) or 1
		if num > 1 then
			card.NumberLabel.Text = tostring(num - 1)
		else
			card:Destroy()
		end

		if #replacedCards > 0 then
			for _, replaced in ipairs(replacedCards) do
				local replacedId = getCardIdFromGuiCard(replaced)
				replaced:Destroy()
				if type(replacedId) == "string" and replacedId ~= "" then
					AddCardToInventory(replacedId, false)
				end
			end
		end

		local placed = CreateCard(cardId)
		if not placed then
			-- Roll back consumed card if placement fails.
			AddCardToInventory(cardId, false)
			deckDirtySinceLastSave = true
			SaveDeckState()
			return false
		end

		placed.NumberLabel.Text = "1"
		placed.Parent = chosenSlot
		placed.Size = UDim2.fromScale(1, 1)
		placed.Position = UDim2.fromOffset(0, 0)
		SetCardStackVisual(placed, combatDeckFrame)
		deckDirtySinceLastSave = true
		SaveDeckState()
		return true
	end

	return false
end

-- Card management
function CreateCard(cardId)
	local parsed = parseCardReference(cardId)
	if not parsed then
		return nil
	end
	local resolvedCardId = parsed.BaseCardId
	local normalizedCardRef = parsed.CardRef

	local data = CardDatabase.GetCardData(resolvedCardId)
	if not data then
		return nil
	end

	local newCard = template:Clone()
	newCard.Name = normalizedCardRef
	newCard:SetAttribute("CardId", normalizedCardRef)
	newCard:SetAttribute("BaseCardId", resolvedCardId)
	newCard:SetAttribute("IsBordered", parsed.IsBordered == true)

	local currentStats = ClientStateManager.getStats()
	local foilChancePoints = currentStats and (currentStats.FoilChance or currentStats.BorderChance) or 0
	local foilTier = parsed.BorderTier or BalanceConfig.GetFoilTier(foilChancePoints)
	-- Foil tier letter for name prefix: (S)ilver, (G)old, (D)iamond, (R)ainbow, (C)orrupted
	local FOIL_LETTER = { Silver = "S", Gold = "G", Diamond = "D", Rainbow = "R", Corrupted = "C" }
	local foilLetter = FOIL_LETTER[foilTier] or "B"

	newCard.Size = UDim2.fromScale(1, 1)  -- Fill grid cell
	newCard.BackgroundTransparency = 1  -- Remove button background
	newCard.ZIndex = 6

	-- Replace template NameLabel with 3-layer parallax
	local nameContainer = newCard:FindFirstChild("NameLabel")
	if nameContainer then
		nameContainer:Destroy()
	end
	nameContainer = ParallaxNameLabel.create(newCard, {
		size = UDim2.new(1, -8, 0.25, 0),
		position = UDim2.fromOffset(4, 2),
		font = CARD_NAME_FONT,
		textSize = 14,
		textColor = Color3.new(1, 1, 1),
		zIndex = 7,
		baseName = "NameLabel",
		textXAlignment = Enum.TextXAlignment.Left,
		textYAlignment = Enum.TextYAlignment.Top,
		textWrapped = true,
	})
	ParallaxNameLabel.setText(nameContainer, parsed.IsBordered and ("(" .. foilLetter .. ") " .. data.Name) or data.Name)

	newCard.AttackLabel.Text = CardDatabase.FormatCombatPower(normalizedCardRef, foilChancePoints)
	newCard.AttackLabel.Size = UDim2.fromScale(0.9, 0.4)
	newCard.AttackLabel.Position = UDim2.fromScale(0.03, 0.62)
	newCard.AttackLabel.Font = CARD_STAT_FONT
	newCard.AttackLabel.TextColor3 = Color3.new(1, 0, 0)  -- Red text for attack
	newCard.AttackLabel.BackgroundTransparency = 1  -- No background
	newCard.AttackLabel.TextStrokeColor3 = Color3.new(0, 0, 0)  -- Black outline
	newCard.AttackLabel.TextStrokeTransparency = 0  -- Fully visible outline
	newCard.AttackLabel.TextXAlignment = Enum.TextXAlignment.Left
	newCard.AttackLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	newCard.AttackLabel.TextWrapped = false
	newCard.AttackLabel.TextScaled = true
	local attackSizeConstraint = newCard.AttackLabel:FindFirstChild("AttackTextSizeConstraint")
	if not (attackSizeConstraint and attackSizeConstraint:IsA("UITextSizeConstraint")) then
		attackSizeConstraint = Instance.new("UITextSizeConstraint")
		attackSizeConstraint.Name = "AttackTextSizeConstraint"
		attackSizeConstraint.Parent = newCard.AttackLabel
	end
	-- Cap growth so short values don't become larger than the intended 6-digit look.
	attackSizeConstraint.MaxTextSize = 42
	attackSizeConstraint.MinTextSize = 16

	local hpLabel = newCard:FindFirstChild("HpLabel")
	if not (hpLabel and hpLabel:IsA("TextLabel")) then
		hpLabel = Instance.new("TextLabel")
		hpLabel.Name = "HpLabel"
		hpLabel.Parent = newCard
	end
	hpLabel.Text = "" -- Hide HP when showing CP
	hpLabel.Size = UDim2.fromScale(0.9, 0.22)
	hpLabel.Position = UDim2.fromScale(0.03, 0.47)
	hpLabel.Font = CARD_STAT_FONT
	hpLabel.TextColor3 = Color3.fromRGB(108, 255, 145)
	hpLabel.BackgroundTransparency = 1
	hpLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.TextXAlignment = Enum.TextXAlignment.Left
	hpLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	hpLabel.TextWrapped = false
	hpLabel.TextScaled = true
	local hpSizeConstraint = hpLabel:FindFirstChild("HpTextSizeConstraint")
	if not (hpSizeConstraint and hpSizeConstraint:IsA("UITextSizeConstraint")) then
		hpSizeConstraint = Instance.new("UITextSizeConstraint")
		hpSizeConstraint.Name = "HpTextSizeConstraint"
		hpSizeConstraint.Parent = hpLabel
	end
	hpSizeConstraint.MaxTextSize = 34
	hpSizeConstraint.MinTextSize = 14
	
	newCard.NumberLabel.Size = UDim2.fromScale(0.16, 0.11)  -- Smaller count badge to free attack space
	newCard.NumberLabel.Position = UDim2.fromScale(0.82, 0.03)  -- Top right corner
	newCard.NumberLabel.Font = CARD_META_FONT
	newCard.NumberLabel.TextColor3 = Color3.new(1, 1, 1)  -- White text
	newCard.NumberLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	newCard.NumberLabel.TextStrokeTransparency = 0
	newCard.NumberLabel.BackgroundTransparency = 1  -- No background
	newCard.NumberLabel.TextScaled = true
	
	-- Make ArtLabel fill the card and remove background
	newCard.ArtLabel.Size = UDim2.fromScale(1, 1)
	newCard.ArtLabel.Position = UDim2.fromOffset(0, 0)
	newCard.ArtLabel.BackgroundTransparency = 1
	newCard.ArtLabel.ScaleType = Enum.ScaleType.Fit
	newCard.ArtLabel.ZIndex = 6
	newCard.NameLabel.ZIndex = 7
	hpLabel.ZIndex = 7
	newCard.AttackLabel.ZIndex = 7
	newCard.NumberLabel.ZIndex = 7  -- Stack number on top
	newCard.NumberLabel.Text = "1"  -- Default to 1
	applyAnimatedCardBorder(newCard, data.Rarity, resolvedCardId)

	-- foilTier already resolved above for name prefix and foil visual

	-- Capture the foil controller so MouseEnter/Leave can switch its intensity.
	local foilController = nil
	if parsed.IsBordered then
		foilController = applyBorderedVariantVisual(newCard, foilTier)
	end

	applyCardArtVisual(newCard, normalizedCardRef, data)

	-- Why: One UIScale per card, created once, lets us spring-animate scale on hover
	-- without modifying Size (which would corrupt layout calculations).
	-- The Spring integrator produces an overshoot (slight bounce) that feels more
	-- physical than a linear or ease-out tween.
	local cardScale = newCard:FindFirstChild("HoverUIScale")
	if not (cardScale and cardScale:IsA("UIScale")) then
		cardScale = Instance.new("UIScale")
		cardScale.Name   = "HoverUIScale"
		cardScale.Scale  = 1
		cardScale.Parent = newCard
	end

	local cardSpring = Spring.new(1, 200, 22)
	activeScaleSprings[cardSpring] = cardScale
	ensureSpringDriver()

	-- Drag to move cards between decks. If no drag occurs, click still quick-moves one card.
	local dragging = false
	local dragStart = nil
	local lastPointerPos = nil
	local dragOriginContainer = nil
	local dragTrackType = nil
	local ghostCard = nil
	local dragMoveConnection = nil
	local suppressNextClick = false
	local DRAG_START_THRESHOLD = 8
	local sellHoldActive = false
	local sellHoldGeneration = 0

	local function incrementSellSelection()
		if getCardDeckContainer(newCard) ~= inventoryFrame then
			return
		end
		local stackCount = tonumber(newCard.NumberLabel.Text) or 1
		local current = selectedSellCountByCard[newCard] or 0
		local nextCount = math.min(stackCount, current + 1)
		selectedSellCountByCard[newCard] = nextCount
		applySellSelectionVisual(newCard, nextCount)
		refreshSellSelectionTotals()
	end

	local function setGhostCardPosition(screenPos)
		if not ghostCard then
			return
		end
		ghostCard.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	end

	local function startGhostDrag(screenPos)
		if dragging or not newCard.Parent then
			return
		end
		dragging = true
		hideHoverPreview(0)

		ghostCard = newCard:Clone()
		ghostCard.Name = "DragGhost_" .. newCard.Name
		ghostCard.AnchorPoint = Vector2.new(0.5, 0.5)
		ghostCard.Size = UDim2.fromOffset(newCard.AbsoluteSize.X, newCard.AbsoluteSize.Y)
		ghostCard.Parent = mainUI
		ghostCard.ZIndex = 80
		ghostCard.BackgroundTransparency = 0.22

		for _, obj in ipairs(ghostCard:GetDescendants()) do
			if obj:IsA("GuiObject") then
				obj.ZIndex = math.max(obj.ZIndex, 81)
			end
		end

		setGhostCardPosition(screenPos)
	end

	local function finishDrag(screenPos)
		if dragMoveConnection then
			dragMoveConnection:Disconnect()
			dragMoveConnection = nil
		end

		if ghostCard then
			ghostCard:Destroy()
			ghostCard = nil
		end

		if dragging then
			local releasePos = screenPos or lastPointerPos or Vector2.new(0, 0)
			local dropTarget = getDropTargetAtPoint(releasePos)
			if dropTarget then
				local moved = moveOneCardToFrame(newCard, dropTarget.frame, dropTarget.slotIndex)
				-- If a combat-origin drag fails to place, prefer returning to inventory.
				if not moved and dragOriginContainer == combatDeckFrame then
					moveOneCardToFrame(newCard, inventoryFrame)
				end
			elseif dragOriginContainer == combatDeckFrame then
				-- Releasing outside valid drop zones should still let combat cards leave.
				moveOneCardToFrame(newCard, inventoryFrame)
			end
			suppressNextClick = true
			task.delay(0.05, function()
				suppressNextClick = false
			end)
		end

		dragging = false
		dragStart = nil
		lastPointerPos = nil
		dragOriginContainer = nil
		dragTrackType = nil
	end

	newCard.InputBegan:Connect(function(input)
		if sellModeEnabledValue.Value then
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				incrementSellSelection()
				sellHoldActive = true
				sellHoldGeneration += 1
				local myGeneration = sellHoldGeneration

				task.spawn(function()
					local holdStart = os.clock()
					task.wait(0.24)
					while sellHoldActive and sellHoldGeneration == myGeneration and sellModeEnabledValue.Value do
						incrementSellSelection()
						local heldSeconds = os.clock() - holdStart
						-- Accelerate repeat speed the longer the press is held.
						local repeatInterval = math.max(0.02, 0.11 - (heldSeconds * 0.04))
						task.wait(repeatInterval)
					end
				end)

				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						sellHoldActive = false
					end
				end)
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragStart = input.Position
			lastPointerPos = input.Position
			dragOriginContainer = getCardDeckContainer(newCard)
			dragTrackType = (input.UserInputType == Enum.UserInputType.Touch) and Enum.UserInputType.Touch or Enum.UserInputType.MouseMovement
			if dragMoveConnection then
				dragMoveConnection:Disconnect()
			end
			dragMoveConnection = UserInputService.InputChanged:Connect(function(changedInput)
				if not dragStart then
					return
				end
				if changedInput.UserInputType ~= dragTrackType then
					return
				end
				lastPointerPos = changedInput.Position

				local delta = changedInput.Position - dragStart
				if not dragging and delta.Magnitude >= DRAG_START_THRESHOLD then
					startGhostDrag(changedInput.Position)
				end

				if dragging then
					setGhostCardPosition(changedInput.Position)
				end
			end)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					finishDrag(input.Position)
				end
			end)
		end
	end)

	newCard.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			lastPointerPos = input.Position
		end
	end)

	newCard.MouseButton1Click:Connect(function()
		if suppressNextClick then
			return
		end
		if sellModeEnabledValue.Value then
			return
		end
		local currentParent = getCardDeckContainer(newCard)
		local targetParent = (currentParent == inventoryFrame) and combatDeckFrame or inventoryFrame
		moveOneCardToFrame(newCard, targetParent)
	end)

	newCard.MouseEnter:Connect(function()
		if not dragging then
			if not DeviceContext.getIsMobile() then
				showHoverPreview(normalizedCardRef)
			end
			-- Spring zoom: target 1.08 produces a natural overshoot then settle,
			-- making the card feel like it physically lifts toward the cursor.
			cardSpring.target = 1.08
			ensureSpringDriver()
			-- Intensify foil shimmer on bordered cards to signal interactivity.
			if foilController then
				foilController:SetIntensity("Hover")
			end
		end
	end)

	newCard.MouseLeave:Connect(function()
		if not DeviceContext.getIsMobile() then
			hideHoverPreview(0.05)
		end
		cardSpring.target = 1.0
		if foilController then
			foilController:SetIntensity("Idle")
		end
	end)

	-- Why: Unregister spring and destroy foil when the card is removed so the
	-- shared driver and HoloFoilController have no dangling references.
	newCard.Destroying:Connect(function()
		activeScaleSprings[cardSpring] = nil
		if foilController then
			foilController:Destroy()
		end
	end)

	SetCardStackVisual(newCard, getCardDeckContainer(newCard) or inventoryFrame)
	applyCardArtVisual(newCard, normalizedCardRef, data)

	return newCard
end

-- Function to add a card to inventory
AddCardToInventory = function(cardId, shouldSave)
	local normalizedCardRef = normalizeCardReference(cardId)
	if not normalizedCardRef then
		return
	end

	ClientStateManager.addCardToInventory(normalizedCardRef)

	for _, existingCard in ipairs(inventoryFrame:GetChildren()) do
		if existingCard:IsA("GuiButton") and getCardIdFromGuiCard(existingCard) == normalizedCardRef then
			local num = tonumber(existingCard.NumberLabel.Text) or 1
			existingCard.NumberLabel.Text = tostring(num + 1)
			SetCardStackVisual(existingCard, inventoryFrame)
			if shouldSave ~= false then
				deckDirtySinceLastSave = true
				SaveDeckState()
			end
			if sellModeEnabledValue.Value then
				refreshSellSelectionTotals()
			end
			return
		end
	end

	local card = CreateCard(normalizedCardRef)
	if card then
		card.NumberLabel.Text = "1"
		card.Parent = inventoryFrame
		SetCardStackVisual(card, inventoryFrame)
		applyCardArtVisual(card, normalizedCardRef, CardDatabase.GetCardData(getBaseCardId(normalizedCardRef)))
	end

	if shouldSave ~= false then
		deckDirtySinceLastSave = true
		SaveDeckState()
	end
	if sellModeEnabledValue.Value then
		refreshSellSelectionTotals()
	end
end

local function AddMultipleCardsToInventory(cardIds)
	if type(cardIds) ~= "table" then
		return
	end

	for _, cardId in ipairs(cardIds) do
		if type(cardId) == "string" then
			AddCardToInventory(cardId, false)
		end
	end

	deckDirtySinceLastSave = true
	SaveDeckState()
	if sellModeEnabledValue.Value then
		refreshSellSelectionTotals()
	end
end

-- Listen for idle card gains
idleEvent.Event:Connect(function(payload)
	if type(payload) == "table" then
		SetProgress(payload.rollCount, payload.level)
		if payload.cardIds then
			AddMultipleCardsToInventory(payload.cardIds)
			return
		end
		if payload.cardId then
			AddCardToInventory(payload.cardId)
		end
		return
	end

	AddCardToInventory(payload)
end)

-- Setup grid layouts for even spacing
function SetupGridLayouts()
	for _, frame in pairs({inventoryFrame, combatDeckFrame}) do
		if frame == inventoryFrame then
			frame.ScrollingDirection = Enum.ScrollingDirection.Y
			frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
			frame.CanvasSize = UDim2.fromOffset(0, 0)
			frame.ScrollBarThickness = 8

			ensureDeckBackground(frame, "InventoryDeckBackground", INVENTORY_BG_IMAGE, Color3.fromRGB(74, 130, 225))
		else
			frame.ScrollingDirection = Enum.ScrollingDirection.X
			frame.AutomaticCanvasSize = Enum.AutomaticSize.None
			frame.CanvasSize = UDim2.fromOffset(0, 0)
			frame.ScrollBarThickness = 0

			ensureDeckBackground(frame, "CombatDeckBackground", COMBAT_BG_IMAGE, Color3.fromRGB(225, 88, 88))
			ensureCombatSlots()
		end

		if frame == inventoryFrame then
			local gridLayout = frame:FindFirstChildOfClass("UIGridLayout")
			if not gridLayout then
				gridLayout = Instance.new("UIGridLayout")
				gridLayout.Parent = frame
			end
			gridLayout.CellSize = UDim2.fromOffset(100, 150)
			gridLayout.CellPadding = UDim2.fromOffset(10, 10)
			gridLayout.FillDirection = Enum.FillDirection.Horizontal
			gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
			gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
			gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		else
			local combatGrid = frame:FindFirstChildOfClass("UIGridLayout")
			if combatGrid then
				combatGrid:Destroy()
			end
		end

		local padding = frame:FindFirstChild("DeckPadding")
		if not (padding and padding:IsA("UIPadding")) then
			padding = Instance.new("UIPadding")
			padding.Name = "DeckPadding"
			padding.Parent = frame
		end
		if frame == inventoryFrame then
			padding.PaddingLeft = UDim.new(0, 8)
			padding.PaddingRight = UDim.new(0, 8)
			padding.PaddingTop = UDim.new(0, 8)
			padding.PaddingBottom = UDim.new(0, 8)
		else
			-- Combat slots are already explicitly positioned; avoid double offset.
			padding.PaddingLeft = UDim.new(0, 0)
			padding.PaddingRight = UDim.new(0, 0)
			padding.PaddingTop = UDim.new(0, 0)
			padding.PaddingBottom = UDim.new(0, 0)
		end
		
		-- Ensure clipping for clean scrolling
		frame.ClipsDescendants = true
	end
end

-- Apply buff state from snapshot so potion timers persist across rejoin
local function applyBuffSnapshot(buffs)
	if type(buffs) ~= "table" then return end
	local now = os.time()
	local autoRollEv = ReplicatedStorage:FindFirstChild("AutoRollBuffEvent")
	local luckEv = require(script.Parent.core:WaitForChild("BuffBridge")).GetLuckBuffEvent()
	local foilEv = require(script.Parent.core:WaitForChild("BuffBridge")).GetFoilChanceBuffEvent()
	if buffs.autoRoll and type(buffs.autoRoll) == "table" then
		local endsAt = tonumber(buffs.autoRoll.endsAt)
		local mult = tonumber(buffs.autoRoll.multiplier) or 1
		if endsAt and endsAt > now and autoRollEv then
			autoRollEv:Fire({ multiplier = mult, duration = math.max(1, endsAt - now) })
		end
	end
	if buffs.luck and type(buffs.luck) == "table" then
		local endsAt = tonumber(buffs.luck.endsAt)
		local bonus = tonumber(buffs.luck.bonus) or 0
		if endsAt and endsAt > now and bonus > 0 and luckEv then
			luckEv:Fire({ luckBonus = bonus, duration = math.max(1, endsAt - now) })
		end
	end
	-- Accept foilChance or legacy borderChance for backward compat
	local fc = buffs.foilChance or buffs.borderChance
	if fc and type(fc) == "table" then
		local endsAt = tonumber(fc.endsAt)
		local bonus = tonumber(fc.bonus) or 0
		if endsAt and endsAt > now and bonus > 0 and foilEv then
			foilEv:Fire({ foilChanceBonus = bonus, duration = math.max(1, endsAt - now) })
		end
	end
end

-- Handle incoming data
saveEvent.OnClientEvent:Connect(function(data)
	-- Clear dirty flag; briefly block saves so any deferred SaveDeckState doesn't
	-- race with UI rebuild. Snapshot is authoritative.
	deckDirtySinceLastSave = false
	saveBlockedUntil = os.clock() + 1
	-- Sync all server state (including reconciled stats) into ClientStateManager so
	-- every subscriber (Profile UI, HUD, etc.) reflects the authoritative snapshot.
	if type(data) == "table" then
		ClientStateManager.syncFromServer(data)
		applyBuffSnapshot(data.buffs)
		if data.clientSettings then
			SettingsUIController.ApplyClientSettings(data.clientSettings)
		end
	end
	SetProgress(data and data.rollCount, data and data.level)
	if data and type(data.coins) == "number" then
		getCurrencyValueObject().Value = math.max(0, math.floor(data.coins))
	end
	BoosterPackSystem.LoadOwnedSnapshot(data and data.boosterPacks)
	if data and type(data.items) == "table" then
		local owned = tonumber(data.items.AutoRoll2x20s) or 0
		getAutoRollOwnedValueObject().Value = math.max(0, math.floor(owned))
	else
		getAutoRollOwnedValueObject().Value = 0
	end
	clearSellSelections()

	-- Preserve whichever deck is currently shown (inventory vs combat) so a
	-- server-triggered reload does not collapse the open modal to blank.
	local wasInventoryVisible = inventoryFrame.Visible
	local wasCombatVisible = combatDeckFrame.Visible
	inventoryFrame.Parent = mainUI
	combatDeckFrame.Parent = mainUI
	inventoryFrame.Visible = wasInventoryVisible
	combatDeckFrame.Visible = wasCombatVisible

	local statsBar = mainUI:FindFirstChild("BottomStatsBar")
	if statsBar then
		statsBar.Visible = true
		statsBar.Parent = mainUI
	end

	-- Clear frames
	inventoryFrame:ClearAllChildren()
	combatDeckFrame:ClearAllChildren()

	-- Setup layouts
	SetupGridLayouts()

	-- Group inventory by card ID and count
	local inventoryCounts = {}
	for _, cardId in ipairs(data.inventory or {}) do
		inventoryCounts[cardId] = (inventoryCounts[cardId] or 0) + 1
	end

	-- Create stacked cards for inventory
	for cardId, count in pairs(inventoryCounts) do
		local card = CreateCard(cardId)
		if card then
			card.NumberLabel.Text = tostring(count)
			card.Parent = inventoryFrame
			SetCardStackVisual(card, inventoryFrame)
		end
	end

	-- Rebuild combat deck exactly by slot order (duplicates allowed).
	for slotIndex = 1, COMBAT_MAX_UNIQUE do
		local cardId = data and data.combat and data.combat[slotIndex]
		if type(cardId) == "string" and cardId ~= "" then
			local slot = getCombatSlot(slotIndex)
			local card = CreateCard(cardId)
			if card and slot then
				for _, child in ipairs(slot:GetChildren()) do
					if child:IsA("GuiButton") then
						child:Destroy()
					end
				end
				card.NumberLabel.Text = "1"
				card.Parent = slot
				card.Size = UDim2.fromScale(1, 1)
				card.Position = UDim2.fromOffset(0, 0)
				SetCardStackVisual(card, combatDeckFrame)
			end
		end
	end

	enforceCombatDeckIntegrity()

	hasLoadedSaveData = true
	if pendingSaveAfterLoad then
		pendingSaveAfterLoad = false
		task.defer(function()
			SaveDeckState()
		end)
	end

	-- Force layout update, then signal rebuild so sort preference can be reapplied
	task.defer(function()
		for _, frame in pairs({inventoryFrame}) do
			local layout = frame:FindFirstChildOfClass("UIGridLayout")
			if layout then
				local oldPadding = layout.CellPadding
				layout.CellPadding = UDim2.fromOffset(0, 0)
				layout.CellPadding = oldPadding
			end
		end
		inventoryRebuiltEvent:Fire()
	end)

	-- Restore BottomStatsBar visibility in case a prior event hid it.
	local restoredStatsBar = mainUI:FindFirstChild("BottomStatsBar")
	if restoredStatsBar then
		restoredStatsBar.Visible = true
		restoredStatsBar.Parent = mainUI
	end

	-- Ensure the sell toolbar exists and is correctly positioned.
	ensureSellToolbar()
end)

-- Request initial data
task.wait(1)
hasLoadedSaveData = false
saveEvent:FireServer("RequestLoad")