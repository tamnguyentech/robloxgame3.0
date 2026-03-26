local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local CardDatabase       = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local CardVisualResolver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardVisualResolver"))
local ClientStateManager = require(script.Parent.Parent.core:WaitForChild("ClientStateManager"))
local RarityConfig       = require(script.Parent.Parent:WaitForChild("RarityConfig"))
-- Why: HoloFoilController is the single source of foil animation logic; importing
-- here lets the preview panel show the same tier effect as the inventory card.
local HoloFoilController        = require(script.Parent.effects:WaitForChild("HoloFoilController"))
local LightningOverlayController = require(script.Parent.effects:WaitForChild("LightningOverlayController"))
local ParallaxNameLabel         = require(script.Parent:WaitForChild("ParallaxNameLabel"))
local UltraRareTextEffect  = require(script.Parent.effects:WaitForChild("UltraRareTextEffect"))
local RainbowBorderStroke  = require(script.Parent.effects:WaitForChild("RainbowBorderStroke"))

local HoverPreview = {}

local PREVIEW_NAME_FONT = Enum.Font.GothamBold
local PREVIEW_STAT_FONT = Enum.Font.GothamBold
local PREVIEW_META_FONT = Enum.Font.GothamMedium

local PREVIEW_WIDTH = 320
local PREVIEW_HEIGHT = 460
local PREVIEW_RIGHT_OFFSET = -340
local PREVIEW_HALF_HEIGHT = math.floor(PREVIEW_HEIGHT * 0.5)
local PREVIEW_POP_WIDTH = PREVIEW_WIDTH - 20
local PREVIEW_POP_HEIGHT = PREVIEW_HEIGHT - 30
local PREVIEW_POP_RIGHT_OFFSET = PREVIEW_RIGHT_OFFSET + 30

-- Layout: name top; rarity; spd; description in bottom half above ATK/HP; no backdrops
local PREVIEW_ART_HEIGHT = 460
local PREVIEW_NAME_Y = 10
local PREVIEW_NAME_HEIGHT = 32
local PREVIEW_META_HEIGHT = 18
local PREVIEW_META_GAP = 2
local PREVIEW_RARITY_Y = PREVIEW_NAME_Y + PREVIEW_NAME_HEIGHT + 2
local PREVIEW_SPD_Y = PREVIEW_RARITY_Y + PREVIEW_META_HEIGHT + PREVIEW_META_GAP
local PREVIEW_ATTACK_HEIGHT = 36
local PREVIEW_ATTACK_Y = PREVIEW_HEIGHT - PREVIEW_ATTACK_HEIGHT - 14
local PREVIEW_ATTACK_X = 14
local PREVIEW_HEALTH_X = PREVIEW_WIDTH - 130
local PREVIEW_DESC_HEIGHT = 100  -- ability/description text above ATK/HP
local PREVIEW_DESC_Y = PREVIEW_ATTACK_Y - PREVIEW_DESC_HEIGHT - 12
local PREVIEW_BASE_ZINDEX = 260
local PREVIEW_TEXT_ZINDEX = PREVIEW_BASE_ZINDEX + 12 -- Above foil (+5) and effects; ensures labels always readable
-- Ultra Rare concept line on the shop hover preview: fixed pixel size (no diagonal autofit).
-- Tune this if it feels too big or too small.
local PREVIEW_ULTRA_RARE_TEXT_SIZE = 45

local PREVIEW_RARITY_PUNCH = {
	Common = 1.015,
	Uncommon = 1.03,
	Rare = 1.055,
	Legendary = 1.125,
	Mythic = 1.085,
	God = 1.165,
	Transcendent = 1.22,
}

local FLASH_RARITY_ENABLED = {
	Mythic = true,
	Legendary = true,
	God = true,
	Transcendent = true,
}



local function getPreviewPunchScale(rarity)
	return PREVIEW_RARITY_PUNCH[rarity] or PREVIEW_RARITY_PUNCH.Common
end

local function buildPreviewFrameGoals(scale)
	local width = math.floor((PREVIEW_WIDTH * scale) + 0.5)
	local height = math.floor((PREVIEW_HEIGHT * scale) + 0.5)
	local rightOffset = PREVIEW_RIGHT_OFFSET - (width - PREVIEW_WIDTH)
	local halfHeight = math.floor(height * 0.5)
	return {
		Position = UDim2.new(1, rightOffset, 0.5, -halfHeight),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 0.06,
	}
end

local preloadedPreviewVideoAssets = {}
local HOVER_VIDEO_LOOP_START_OFFSET_SECONDS = 1.0

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

local function ensurePreviewVideoPlayback(videoFrame, videoAssetId)
	if not (videoFrame and videoFrame:IsA("VideoFrame")) then
		return
	end

	local function forcePlay()
		videoFrame.Playing = true
		pcall(function()
			videoFrame:Play()
		end)
	end

	if not preloadedPreviewVideoAssets[videoAssetId] then
		preloadedPreviewVideoAssets[videoAssetId] = true
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
		videoFrame.TimePosition = HOVER_VIDEO_LOOP_START_OFFSET_SECONDS
	end
	forcePlay()

	-- Re-assert after frame becomes visible and tweens settle.
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
	task.delay(0.35, function()
		if videoFrame.Parent and videoFrame.Visible and videoFrame.Video == videoAssetId then
			forcePlay()
		end
	end)
end

function HoverPreview.Init(mainUI, artFolder, config)
	local _settings = config or {}

	local state = {
		hideTaskId = 0,
		edges = {},
		stripConnection = nil,
		beliodusAuraGeneration = 0,
		beliodusAuraConnection = nil,
		beliodusAuraPrimaryAccumulator = 0,
		beliodusAuraWispAccumulator = 0,
		beliodusAuraSmokeAccumulator = 0,
		hoverVideoGuardGeneration = 0,
		hoverVideoGuardConnection = nil,
		gradientRotationConnection = nil,
		-- Foil controller for the currently-displayed bordered card preview.
		-- Destroyed whenever the preview hides or a non-bordered card replaces it.
		previewFoilController = nil,
		-- Lightning overlay (shop Lightning concept tile hover).
		previewLightningController = nil,
		-- Ultra Rare concept text overlay (shop gallery hover).
		previewUltraRareController = nil,
	}
	-- Helper to start looping gradient border rotation
	local function startGradientBorderLoop()
		if state.gradientRotationConnection then
			return
		end
		local stroke = mainUI:FindFirstChild("CardHoverPreview")
			and mainUI:FindFirstChild("CardHoverPreview"):FindFirstChildOfClass("UIStroke")
		local gradient = stroke and stroke:FindFirstChild("RarityBorderGradient")
		if not gradient then
			return
		end
		-- Legendary effect: fast, glowing, sharp color transitions
		local pulse = 0
		state.gradientRotationConnection = RunService.RenderStepped:Connect(function(dt)
			gradient.Rotation = (gradient.Rotation + (dt * 220)) % 360
			pulse = pulse + dt
			local glow = 0.5 + 0.5 * math.sin(pulse * 3)
			gradient.Offset = Vector2.new(0, 0.22 * math.sin(pulse * 2))
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.08 * glow),
				NumberSequenceKeypoint.new(0.25, 0.02 * glow),
				NumberSequenceKeypoint.new(0.5, 0.01 * glow),
				NumberSequenceKeypoint.new(0.75, 0.02 * glow),
				NumberSequenceKeypoint.new(1, 0.08 * glow),
			})
		end)
	end

	-- Helper to stop looping gradient border rotation
	local function stopGradientBorderLoop()
		if state.gradientRotationConnection then
			state.gradientRotationConnection:Disconnect()
			state.gradientRotationConnection = nil
		end
	end

	local function ensurePreviewRarityBorderGradient(previewUiStroke)
		if not (previewUiStroke and previewUiStroke:IsA("UIStroke")) then
			return
		end
		local g = previewUiStroke:FindFirstChild("RarityBorderGradient")
		if not (g and g:IsA("UIGradient")) then
			if g then
				g:Destroy()
			end
			g = Instance.new("UIGradient")
			g.Name = "RarityBorderGradient"
			g.Parent = previewUiStroke
		end
		g.Color = RarityConfig.GetDefaultRarityBorderColorSequence()
		g.Rotation = 0
		g.Offset = Vector2.new(0, 0)
		g.Transparency = NumberSequence.new(0)
	end

	-- Destroy any foil currently attached to the preview panel.
	-- Why: Called before attaching a new foil (tier may have changed) and on Hide,
	-- so the old tween never fires after the panel is invisible.
	local function stopPreviewFoil()
		if state.previewFoilController then
			state.previewFoilController:Destroy()
			state.previewFoilController = nil
		end
	end

	local function stopPreviewLightning()
		if state.previewLightningController then
			state.previewLightningController:Destroy()
			state.previewLightningController = nil
		end
	end

	local function stopPreviewUltraRare()
		if state.previewUltraRareController then
			state.previewUltraRareController:Destroy()
			state.previewUltraRareController = nil
		end
	end

	local hoverVideoPreviewActiveValue = getOrCreateHoverVideoPreviewActiveValue()

	local function setPreviewArtTransform(previewImage)
		if not (previewImage and previewImage:IsA("GuiObject")) then
			return
		end
		previewImage.ScaleType = Enum.ScaleType.Stretch
		previewImage.AnchorPoint = Vector2.new(0, 0)
		previewImage.Size = UDim2.fromScale(1, 1)
		previewImage.Position = UDim2.fromOffset(0, 0)
	end

	local hoverPreviewFrame = mainUI:FindFirstChild("CardHoverPreview")
	if not hoverPreviewFrame then
		hoverPreviewFrame = Instance.new("Frame")
		hoverPreviewFrame.Name = "CardHoverPreview"
		hoverPreviewFrame.Size = UDim2.fromOffset(PREVIEW_WIDTH, PREVIEW_HEIGHT)
		hoverPreviewFrame.Position = UDim2.new(1, PREVIEW_RIGHT_OFFSET, 0.5, -PREVIEW_HALF_HEIGHT)
		hoverPreviewFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
		hoverPreviewFrame.BackgroundTransparency = 0.9
		hoverPreviewFrame.BorderSizePixel = 0
		hoverPreviewFrame.Visible = false
		hoverPreviewFrame.ZIndex = PREVIEW_BASE_ZINDEX
		hoverPreviewFrame.Parent = mainUI

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = hoverPreviewFrame

		local stroke = Instance.new("UIStroke")
		-- Use a stronger outline that will be tinted per-card rarity.
		stroke.Thickness = 10
		stroke.Color = Color3.fromRGB(200, 200, 200)
		stroke.Transparency = 0
		stroke.Parent = hoverPreviewFrame

		-- Add UIGradient for animated rarity border effect
		local gradient = Instance.new("UIGradient")
		gradient.Name = "RarityBorderGradient"
		gradient.Color = RarityConfig.GetDefaultRarityBorderColorSequence()
		gradient.Rotation = 0
		gradient.Parent = stroke

		local previewArt = Instance.new("Frame")
		previewArt.Name = "PreviewArt"
		previewArt.Size = UDim2.new(1, 0, 1, 0)
		previewArt.Position = UDim2.fromOffset(0, 0)
		previewArt.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
		previewArt.BackgroundTransparency = 0.95
		previewArt.BorderSizePixel = 0
		previewArt.ClipsDescendants = true
		previewArt.ZIndex = PREVIEW_BASE_ZINDEX + 1
		previewArt.Parent = hoverPreviewFrame

		local artCorner = Instance.new("UICorner")
		artCorner.CornerRadius = UDim.new(0, 12)
		artCorner.Parent = previewArt

		local previewArtImage = Instance.new("ImageLabel")
		previewArtImage.Name = "PreviewArtImage"
		previewArtImage.BackgroundTransparency = 1
		previewArtImage.BorderSizePixel = 0
		previewArtImage.ZIndex = PREVIEW_BASE_ZINDEX + 2
		previewArtImage.Parent = previewArt
		setPreviewArtTransform(previewArtImage)

		local previewArtVideo = Instance.new("VideoFrame")
		previewArtVideo.Name = "PreviewArtVideo"
		previewArtVideo.Size = UDim2.fromScale(1, 1)
		previewArtVideo.Position = UDim2.fromOffset(0, 0)
		previewArtVideo.BackgroundTransparency = 1
		previewArtVideo.BorderSizePixel = 0
		previewArtVideo.ZIndex = PREVIEW_BASE_ZINDEX + 2
		previewArtVideo.Looped = true
		previewArtVideo.Playing = false
		previewArtVideo.Visible = false
		previewArtVideo.Parent = previewArt

		-- Name: 3-layer parallax, top-most, left-aligned
		local _previewName = ParallaxNameLabel.create(hoverPreviewFrame, {
			size = UDim2.new(1, -24, 0, PREVIEW_NAME_HEIGHT),
			position = UDim2.fromOffset(12, PREVIEW_NAME_Y),
			font = PREVIEW_NAME_FONT,
			textSize = 22,
			textColor = Color3.fromRGB(255, 255, 255),
			zIndex = PREVIEW_TEXT_ZINDEX,
			baseName = "PreviewName",
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Top,
			textWrapped = true,
		})

		-- Rarity: below name (order: name → rarity → spd)
		local previewRarity = Instance.new("TextLabel")
		previewRarity.Name = "PreviewRarity"
		previewRarity.Size = UDim2.new(1, -24, 0, PREVIEW_META_HEIGHT)
		previewRarity.Position = UDim2.fromOffset(12, PREVIEW_RARITY_Y)
		previewRarity.BackgroundTransparency = 1
		previewRarity.TextXAlignment = Enum.TextXAlignment.Left
		previewRarity.TextYAlignment = Enum.TextYAlignment.Center
		previewRarity.TextWrapped = false
		previewRarity.Font = PREVIEW_META_FONT
		previewRarity.TextSize = 14
		previewRarity.TextColor3 = Color3.fromRGB(220, 220, 220)
		previewRarity.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		previewRarity.TextStrokeTransparency = 0
		previewRarity.ZIndex = PREVIEW_TEXT_ZINDEX
		previewRarity.Parent = hoverPreviewFrame

		-- SPD: below rarity
		local previewAttackSpeed = Instance.new("TextLabel")
		previewAttackSpeed.Name = "PreviewAttackSpeed"
		previewAttackSpeed.Size = UDim2.new(1, -24, 0, PREVIEW_META_HEIGHT)
		previewAttackSpeed.Position = UDim2.fromOffset(12, PREVIEW_SPD_Y)
		previewAttackSpeed.BackgroundTransparency = 1
		previewAttackSpeed.TextXAlignment = Enum.TextXAlignment.Left
		previewAttackSpeed.TextYAlignment = Enum.TextYAlignment.Center
		previewAttackSpeed.TextWrapped = false
		previewAttackSpeed.Font = PREVIEW_META_FONT
		previewAttackSpeed.TextSize = 14
		previewAttackSpeed.TextColor3 = Color3.fromRGB(220, 235, 255)
		previewAttackSpeed.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		previewAttackSpeed.TextStrokeTransparency = 0
		previewAttackSpeed.ZIndex = PREVIEW_TEXT_ZINDEX
		previewAttackSpeed.Parent = hoverPreviewFrame

		-- Description: bottom half, above ATK/HP, transparent (no backdrop)
		local previewDescription = Instance.new("TextLabel")
		previewDescription.Name = "PreviewDescription"
		previewDescription.Size = UDim2.new(1, -24, 0, PREVIEW_DESC_HEIGHT)
		previewDescription.Position = UDim2.fromOffset(12, PREVIEW_DESC_Y)
		previewDescription.BackgroundTransparency = 1
		previewDescription.TextXAlignment = Enum.TextXAlignment.Left
		previewDescription.TextYAlignment = Enum.TextYAlignment.Top
		previewDescription.TextWrapped = true
		-- Bubbly / folksy title-style font for descriptions.
		previewDescription.Font = Enum.Font.Fantasy
		previewDescription.TextSize = 20
		previewDescription.TextColor3 = Color3.fromRGB(230, 238, 255)
		previewDescription.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		previewDescription.TextStrokeTransparency = 0.1
		previewDescription.ZIndex = PREVIEW_TEXT_ZINDEX
		previewDescription.Text = ""
		previewDescription.Parent = hoverPreviewFrame

		-- ATK: bottom-left corner (no backdrop)
		local previewAttack = Instance.new("TextLabel")
		previewAttack.Name = "PreviewAttack"
		previewAttack.Size = UDim2.new(0, 120, 0, PREVIEW_ATTACK_HEIGHT)
		previewAttack.Position = UDim2.fromOffset(PREVIEW_ATTACK_X, PREVIEW_ATTACK_Y)
		previewAttack.BackgroundTransparency = 1
		previewAttack.TextXAlignment = Enum.TextXAlignment.Left
		previewAttack.TextYAlignment = Enum.TextYAlignment.Center
		previewAttack.Font = PREVIEW_STAT_FONT
		previewAttack.TextSize = 22
		previewAttack.TextColor3 = Color3.fromRGB(255, 140, 100)
		previewAttack.TextStrokeColor3 = Color3.fromRGB(20, 8, 4)
		previewAttack.TextStrokeTransparency = 0.2
		previewAttack.ZIndex = PREVIEW_TEXT_ZINDEX
		previewAttack.Parent = hoverPreviewFrame

		-- HP: bottom-right corner
		local previewHealth = Instance.new("TextLabel")
		previewHealth.Name = "PreviewHealth"
		previewHealth.Size = UDim2.new(0, 100, 0, PREVIEW_ATTACK_HEIGHT)
		previewHealth.Position = UDim2.fromOffset(PREVIEW_HEALTH_X, PREVIEW_ATTACK_Y)
		previewHealth.BackgroundTransparency = 1
		previewHealth.TextXAlignment = Enum.TextXAlignment.Right
		previewHealth.TextYAlignment = Enum.TextYAlignment.Center
		previewHealth.TextWrapped = false
		previewHealth.Font = PREVIEW_STAT_FONT
		previewHealth.TextSize = 22
		previewHealth.TextColor3 = Color3.fromRGB(100, 255, 130)
		previewHealth.TextStrokeColor3 = Color3.fromRGB(4, 18, 10)
		previewHealth.TextStrokeTransparency = 0.2
		previewHealth.ZIndex = PREVIEW_TEXT_ZINDEX
		previewHealth.Parent = hoverPreviewFrame

	end

	local function enforcePreviewLayering()
		hoverPreviewFrame.ZIndex = PREVIEW_BASE_ZINDEX
		local art = hoverPreviewFrame:FindFirstChild("PreviewArt")
		if art and art:IsA("GuiObject") then
			art.ZIndex = PREVIEW_BASE_ZINDEX + 1
			local artImage = art:FindFirstChild("PreviewArtImage")
			if artImage and artImage:IsA("GuiObject") then
				artImage.ZIndex = PREVIEW_BASE_ZINDEX + 2
			end
		end
		local textLabelNames = {"PreviewName", "PreviewAttack", "PreviewHealth", "PreviewAttackSpeed", "PreviewRarity", "PreviewDescription"}
		for _, name in ipairs(textLabelNames) do
			local label = hoverPreviewFrame:FindFirstChild(name)
			if label and label:IsA("GuiObject") then
				label.ZIndex = PREVIEW_TEXT_ZINDEX
			end
		end
	end

	enforcePreviewLayering()

	
	local function ensureRarityFlash(previewFrame)
		local existing = previewFrame:FindFirstChild("PreviewRarityFlash")
		if existing and existing:IsA("Frame") then
			return existing
		end

		local flash = Instance.new("Frame")
		flash.Name = "PreviewRarityFlash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.Position = UDim2.fromOffset(0, 0)
		flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.ZIndex = hoverPreviewFrame.ZIndex + 3
		flash.Visible = false
		flash.Parent = previewFrame

		local flashCorner = Instance.new("UICorner")
		flashCorner.CornerRadius = UDim.new(0, 12)
		flashCorner.Parent = flash

		return flash
	end

	local function ensureBeliodusAura(previewFrame)
		local existing = previewFrame:FindFirstChild("PreviewBeliodusAura")
		if existing and existing:IsA("Frame") then
			existing.ZIndex = math.max(previewFrame.ZIndex + 20, 120)
			return existing
		end

		local aura = Instance.new("Frame")
		aura.Name = "PreviewBeliodusAura"
		aura.Size = UDim2.new(1, 52, 1, 52)
		aura.Position = UDim2.fromOffset(-26, -26)
		aura.BackgroundTransparency = 1
		aura.BorderSizePixel = 0
		-- Keep aura effects above all preview text/image layers.
		aura.ZIndex = math.max(hoverPreviewFrame.ZIndex + 20, 120)
		aura.ClipsDescendants = false
		aura.Visible = false
		aura.Parent = previewFrame

		return aura
	end

	local function stopBeliodusAura(previewFrame)
		state.beliodusAuraGeneration = state.beliodusAuraGeneration + 1
		if state.beliodusAuraConnection then
			state.beliodusAuraConnection:Disconnect()
			state.beliodusAuraConnection = nil
		end
		local aura = previewFrame:FindFirstChild("PreviewBeliodusAura")
		if not (aura and aura:IsA("Frame")) then
			return
		end

		aura.Visible = false
		for _, child in ipairs(aura:GetChildren()) do
			if child.Name == "BeliodusParticle" then
				child:Destroy()
			end
		end
	end

	local function _startBeliodusAura(previewFrame)
		local aura = ensureBeliodusAura(previewFrame)
		state.beliodusAuraGeneration = state.beliodusAuraGeneration + 1
		local myGeneration = state.beliodusAuraGeneration
		aura.Visible = true

		-- Replaced all task.wait loops with a single Heartbeat-driven emitter.
		-- Why: avoids spawning multiple busy loops and keeps aura cost predictable.
		state.beliodusAuraPrimaryAccumulator = 0
		state.beliodusAuraWispAccumulator = 0
		state.beliodusAuraSmokeAccumulator = 0

		if state.beliodusAuraConnection then
			state.beliodusAuraConnection:Disconnect()
			state.beliodusAuraConnection = nil
		end

		state.beliodusAuraConnection = RunService.Heartbeat:Connect(function(dt)
			if not (aura.Parent and previewFrame.Visible and myGeneration == state.beliodusAuraGeneration) then
				stopBeliodusAura(previewFrame)
				return
			end

			state.beliodusAuraPrimaryAccumulator = state.beliodusAuraPrimaryAccumulator + dt
			state.beliodusAuraWispAccumulator = state.beliodusAuraWispAccumulator + dt
			state.beliodusAuraSmokeAccumulator = state.beliodusAuraSmokeAccumulator + dt

			-- Primary edge particles (high rate, small size).
			while state.beliodusAuraPrimaryAccumulator >= 0.06 do
				state.beliodusAuraPrimaryAccumulator = state.beliodusAuraPrimaryAccumulator - 0.06
				for _ = 1, 4 do
					local particle = Instance.new("Frame")
					particle.Name = "BeliodusParticle"
					particle.AnchorPoint = Vector2.new(0.5, 0.5)
					particle.BorderSizePixel = 0
					particle.BackgroundColor3 = Color3.fromRGB(6, 6, 6)
					particle.BackgroundTransparency = 0.08 + (math.random() * 0.2)
					particle.ZIndex = aura.ZIndex + 1

					local px = math.random(5, 13)
					particle.Size = UDim2.fromOffset(px, px)

					local side = math.random(1, 4)
					local startX
					local startY
					if side == 1 then
						startX = math.random(4, math.max(5, aura.AbsoluteSize.X - 4))
						startY = 4
					elseif side == 2 then
						startX = aura.AbsoluteSize.X - 4
						startY = math.random(4, math.max(5, aura.AbsoluteSize.Y - 4))
					elseif side == 3 then
						startX = math.random(4, math.max(5, aura.AbsoluteSize.X - 4))
						startY = aura.AbsoluteSize.Y - 4
					else
						startX = 4
						startY = math.random(4, math.max(5, aura.AbsoluteSize.Y - 4))
					end
					particle.Position = UDim2.fromOffset(startX, startY)

					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(1, 0)
					corner.Parent = particle

					particle.Parent = aura

					local rise = math.random(14, 50)
					local drift = math.random(-36, 36)
					local duration = 0.45 + (math.random() * 0.45)
					TweenService:Create(
						particle,
						TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{
							Position = UDim2.fromOffset(startX + drift, startY - rise),
							BackgroundTransparency = 1,
							Size = UDim2.fromOffset(px + 2, px + 2),
						}
					):Play()

					task.delay(duration + 0.05, function()
						if particle and particle.Parent then
							particle:Destroy()
						end
					end)
				end
			end

			-- Orbiting wisps (medium rate).
			while state.beliodusAuraWispAccumulator >= 0.18 do
				state.beliodusAuraWispAccumulator = state.beliodusAuraWispAccumulator - 0.18
				local wisp = Instance.new("Frame")
				wisp.Name = "BeliodusParticle"
				wisp.AnchorPoint = Vector2.new(0.5, 0.5)
				wisp.BorderSizePixel = 0
				wisp.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
				wisp.BackgroundTransparency = 0.26
				wisp.ZIndex = aura.ZIndex + 2

				local size = math.random(8, 16)
				wisp.Size = UDim2.fromOffset(size, size)

				local cx = math.floor(aura.AbsoluteSize.X * 0.5)
				local cy = math.floor(aura.AbsoluteSize.Y * 0.5)
				local angle = math.random() * (math.pi * 2)
				local radius = math.random(58, 130)
				local sx = cx + math.floor(math.cos(angle) * radius)
				local sy = cy + math.floor(math.sin(angle) * radius)
				wisp.Position = UDim2.fromOffset(sx, sy)

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = wisp

				wisp.Parent = aura

				local spin = angle + ((math.random(0, 1) == 0 and -1 or 1) * math.rad(math.random(65, 125)))
				local endRadius = math.max(26, radius - math.random(24, 56))
				local ex = cx + math.floor(math.cos(spin) * endRadius)
				local ey = cy + math.floor(math.sin(spin) * endRadius)
				local dur = 0.54 + (math.random() * 0.5)

				TweenService:Create(
					wisp,
					TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromOffset(ex, ey),
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(size + 2, size + 2),
					}
				):Play()

				task.delay(dur + 0.05, function()
					if wisp and wisp.Parent then
						wisp:Destroy()
					end
				end)
			end

			-- Smoky shadows (low rate).
			while state.beliodusAuraSmokeAccumulator >= 0.28 do
				state.beliodusAuraSmokeAccumulator = state.beliodusAuraSmokeAccumulator - 0.28
				local smoke = Instance.new("Frame")
				smoke.Name = "BeliodusParticle"
				smoke.AnchorPoint = Vector2.new(0.5, 0.5)
				smoke.BorderSizePixel = 0
				smoke.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				smoke.BackgroundTransparency = 0.72
				smoke.ZIndex = aura.ZIndex

				local smokeSize = math.random(18, 34)
				smoke.Size = UDim2.fromOffset(smokeSize, smokeSize)

				local cx = math.floor(aura.AbsoluteSize.X * 0.5)
				local cy = math.floor(aura.AbsoluteSize.Y * 0.5)
				local angle = math.random() * (math.pi * 2)
				local radius = math.random(36, 90)
				local sx = cx + math.floor(math.cos(angle) * radius)
				local sy = cy + math.floor(math.sin(angle) * radius)
				smoke.Position = UDim2.fromOffset(sx, sy)

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = smoke

				smoke.Parent = aura

				local ex = cx + math.floor(math.cos(angle + math.rad(math.random(-25, 25))) * math.max(16, radius - math.random(8, 24)))
				local ey = cy + math.floor(math.sin(angle + math.rad(math.random(-25, 25))) * math.max(16, radius - math.random(8, 24)))
				local dur = 0.75 + (math.random() * 0.55)

				TweenService:Create(
					smoke,
					TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						Position = UDim2.fromOffset(ex, ey),
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(smokeSize + 8, smokeSize + 8),
					}
				):Play()

				task.delay(dur + 0.05, function()
					if smoke and smoke.Parent then
						smoke:Destroy()
					end
				end)
			end
		end)
	end

	local function playRarityFlash(previewFrame, rarityKey, rarityColor)
		if not FLASH_RARITY_ENABLED[rarityKey] then
			return
		end

		local flash = ensureRarityFlash(previewFrame)
		flash.Visible = true
		flash.BackgroundColor3 = rarityColor:Lerp(Color3.fromRGB(255, 255, 255), 0.7)
		flash.BackgroundTransparency = 1

		TweenService:Create(
			flash,
			TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0.76}
		):Play()

		task.delay(0.07, function()
			if not flash.Parent then
				return
			end
			local fadeTween = TweenService:Create(
				flash,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{BackgroundTransparency = 1}
			)
			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				if flash and flash.Parent then
					flash.Visible = false
				end
			end)
		end)
	end

	ensureRarityFlash(hoverPreviewFrame)

	local api = {}

	-- previewOpts (optional): { ultraRareOverlay = boolean } - shop concept tile only.
	function api.Show(cardId, data, rarityColor, previewOpts)
		state.hideTaskId = state.hideTaskId + 1
		local requestId = state.hideTaskId
		stopPreviewUltraRare()
		stopPreviewLightning()
		local isUltraConcept = previewOpts ~= nil and previewOpts.ultraRareOverlay == true
		local isLightningConcept = previewOpts ~= nil and previewOpts.lightningOverlay == true
		local parsed = CardDatabase.ParseCardReference(cardId)
		local baseCardId = parsed and parsed.BaseCardId or cardId
		local isBordered = parsed and parsed.IsBordered == true
		local currentStats = ClientStateManager.getStats()
		local foilChancePoints = currentStats and (currentStats.FoilChance or currentStats.BorderChance) or 0
		local foilMultipliers = CardDatabase.GetFoilStatMultipliers(cardId, foilChancePoints)
		-- CardVisualResolver provides a per-tier accent colour so each border tier
		-- shows a distinct hue on the preview stroke and rarity label - not a single
		-- generic gold colour for every bordered card.
		local visualStyle     = CardVisualResolver.resolve(cardId, foilChancePoints, rarityColor)
		local previewAccentColor = visualStyle.strokeColor

		local art = hoverPreviewFrame:FindFirstChild("PreviewArt")
		local artImage = art and art:FindFirstChild("PreviewArtImage")
		local artVideo = art and art:FindFirstChild("PreviewArtVideo")
		local nameLabel = hoverPreviewFrame:FindFirstChild("PreviewName")
		local atkLabel = hoverPreviewFrame:FindFirstChild("PreviewAttack")
		local healthLabel = hoverPreviewFrame:FindFirstChild("PreviewHealth")
		local atkSpeedLabel = hoverPreviewFrame:FindFirstChild("PreviewAttackSpeed")
		if not healthLabel then
			-- Migrate from legacy label name used in older sessions.
			healthLabel = hoverPreviewFrame:FindFirstChild("PreviewCategory")
			if healthLabel and healthLabel:IsA("TextLabel") then
				healthLabel.Name = "PreviewHealth"
			end
		end
		if not atkSpeedLabel then
			atkSpeedLabel = Instance.new("TextLabel")
			atkSpeedLabel.Name = "PreviewAttackSpeed"
			atkSpeedLabel.Size = UDim2.new(1, -20, 0, PREVIEW_META_HEIGHT)
			atkSpeedLabel.Position = UDim2.fromOffset(12, PREVIEW_SPD_Y)
			atkSpeedLabel.BackgroundTransparency = 1
			atkSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
			atkSpeedLabel.TextYAlignment = Enum.TextYAlignment.Center
			atkSpeedLabel.TextWrapped = false
			atkSpeedLabel.Font = PREVIEW_META_FONT
			atkSpeedLabel.TextSize = 18
			atkSpeedLabel.TextColor3 = Color3.fromRGB(120, 196, 255)
			atkSpeedLabel.TextStrokeColor3 = Color3.fromRGB(8, 14, 32)
			atkSpeedLabel.TextStrokeTransparency = 0
			atkSpeedLabel.ZIndex = PREVIEW_TEXT_ZINDEX
			atkSpeedLabel.Parent = hoverPreviewFrame

			local atkSpeedPadding = Instance.new("UIPadding")
			atkSpeedPadding.PaddingLeft = UDim.new(0, 10)
			atkSpeedPadding.PaddingRight = UDim.new(0, 10)
			atkSpeedPadding.Parent = atkSpeedLabel

		end
		local rarityLabel = hoverPreviewFrame:FindFirstChild("PreviewRarity")
		if not rarityLabel then
			rarityLabel = Instance.new("TextLabel")
			rarityLabel.Name = "PreviewRarity"
			rarityLabel.Size = UDim2.new(1, -20, 0, PREVIEW_META_HEIGHT)
			rarityLabel.Position = UDim2.fromOffset(12, PREVIEW_RARITY_Y)
			rarityLabel.BackgroundTransparency = 1
			rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
			rarityLabel.TextYAlignment = Enum.TextYAlignment.Center
			rarityLabel.TextWrapped = false
			rarityLabel.Font = PREVIEW_META_FONT
			rarityLabel.TextSize = 16
			rarityLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
			rarityLabel.TextStrokeColor3 = Color3.fromRGB(12, 12, 16)
			rarityLabel.TextStrokeTransparency = 0
			rarityLabel.ZIndex = PREVIEW_TEXT_ZINDEX
			rarityLabel.Parent = hoverPreviewFrame
		end
		local descLabel = hoverPreviewFrame:FindFirstChild("PreviewDescription")
		if not descLabel or not descLabel:IsA("TextLabel") then
			if descLabel then descLabel:Destroy() end
			descLabel = Instance.new("TextLabel")
			descLabel.Name = "PreviewDescription"
			descLabel.Size = UDim2.new(1, -24, 0, PREVIEW_DESC_HEIGHT)
			descLabel.Position = UDim2.fromOffset(12, PREVIEW_DESC_Y)
			descLabel.BackgroundTransparency = 1
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.TextYAlignment = Enum.TextYAlignment.Top
			descLabel.TextWrapped = true
			descLabel.Font = Enum.Font.Fantasy
			descLabel.TextSize = 18
			descLabel.TextColor3 = Color3.fromRGB(230, 238, 255)
			descLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			descLabel.TextStrokeTransparency = 0.2
			descLabel.ZIndex = PREVIEW_TEXT_ZINDEX
			descLabel.Text = ""
			descLabel.Parent = hoverPreviewFrame
		end
		if not (art and artImage and nameLabel and atkLabel and healthLabel and atkSpeedLabel and rarityLabel) then
			return
		end

		art.Size = UDim2.new(1, 0, 1, 0)
		art.Position = UDim2.fromOffset(0, 0)
		nameLabel.Size = UDim2.new(1, -24, 0, PREVIEW_NAME_HEIGHT)
		nameLabel.Position = UDim2.fromOffset(12, PREVIEW_NAME_Y)

		healthLabel.Size = UDim2.new(0, 100, 0, PREVIEW_ATTACK_HEIGHT)
		healthLabel.Position = UDim2.fromOffset(PREVIEW_HEALTH_X, PREVIEW_ATTACK_Y)
		healthLabel.TextXAlignment = Enum.TextXAlignment.Right
		healthLabel.Font = PREVIEW_STAT_FONT
		healthLabel.TextColor3 = Color3.fromRGB(108, 255, 145)
		healthLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		healthLabel.TextStrokeTransparency = 0
		healthLabel.TextSize = 16
		healthLabel.TextWrapped = false
		healthLabel.ZIndex = PREVIEW_TEXT_ZINDEX

		atkSpeedLabel.Size = UDim2.new(1, -24, 0, PREVIEW_META_HEIGHT)
		atkSpeedLabel.Position = UDim2.fromOffset(12, PREVIEW_SPD_Y)
		atkSpeedLabel.Font = PREVIEW_META_FONT
		atkSpeedLabel.TextColor3 = Color3.fromRGB(160, 210, 255)
		atkSpeedLabel.TextStrokeColor3 = Color3.fromRGB(8, 14, 32)
		atkSpeedLabel.TextStrokeTransparency = 0.2
		atkSpeedLabel.TextSize = 16
		atkSpeedLabel.TextWrapped = false

		rarityLabel.Size = UDim2.new(1, -24, 0, PREVIEW_META_HEIGHT)
		rarityLabel.Position = UDim2.fromOffset(12, PREVIEW_RARITY_Y)
		rarityLabel.Font = PREVIEW_META_FONT
		rarityLabel.TextStrokeColor3 = Color3.fromRGB(12, 12, 16)
		rarityLabel.TextStrokeTransparency = 0
		rarityLabel.TextSize = 16
		rarityLabel.TextWrapped = false

		-- Sync font/size to all parallax layers (PreviewName is a 3-layer container)
		if ParallaxNameLabel.isParallaxContainer(nameLabel) then
			for _, child in ipairs(nameLabel:GetChildren()) do
				if child:IsA("TextLabel") then
					child.Font = PREVIEW_NAME_FONT
					child.TextColor3 = Color3.fromRGB(230, 245, 255)
					child.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
					child.TextStrokeTransparency = 0
					child.TextSize = 22
				end
			end
		end

		atkLabel.Size = UDim2.new(0, 120, 0, PREVIEW_ATTACK_HEIGHT)
		atkLabel.Position = UDim2.fromOffset(PREVIEW_ATTACK_X, PREVIEW_ATTACK_Y)
		atkLabel.Font = PREVIEW_STAT_FONT
		atkLabel.TextSize = 20
		atkLabel.TextColor3 = Color3.fromRGB(255, 125, 90)
		atkLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		atkLabel.TextStrokeTransparency = 0
		atkLabel.BackgroundTransparency = 1
		atkLabel.TextYAlignment = Enum.TextYAlignment.Center
		atkLabel.ZIndex = PREVIEW_TEXT_ZINDEX

		setPreviewArtTransform(artImage)
		local displayAttack = math.max(1, math.floor((tonumber(data.Attack) or 1) * (tonumber(foilMultipliers.AtkMultiplier) or 1)))
		local displayHealth = math.max(1, math.floor((tonumber(data.Health) or 1) * (tonumber(foilMultipliers.HpMultiplier) or 1)))
		ParallaxNameLabel.setText(nameLabel, isBordered and ("* " .. tostring(data.Name or baseCardId)) or (data.Name or cardId))
		atkLabel.Text = "ATK: " .. CardDatabase.FormatAttack(displayAttack)
		healthLabel.Text = "HP: " .. CardDatabase.FormatAttack(displayHealth)

		local attackInterval = tonumber(data.AttackIntervalSeconds)
		if attackInterval and attackInterval > 0 then
			atkSpeedLabel.Text = string.format("spd: %.1f/s", 1 / attackInterval)
		else
			atkSpeedLabel.Text = "spd: ?"
		end
		healthLabel.TextSize = 20
		healthLabel.BackgroundTransparency = 1
		atkSpeedLabel.TextSize = 18
		atkSpeedLabel.BackgroundTransparency = 1
		-- foilTier comes from visualStyle so the rarity label, border stroke, and foil
		-- all use the same resolved tier (no three-way desync).
		local TIER_DISPLAY_NAME = { Silver = "Silver", Gold = "Gold", Diamond = "Diamond", Rainbow = "Rainbow" }
		local foilTier = isBordered and visualStyle.tierKey or nil
		local tierDisplayName = foilTier and (TIER_DISPLAY_NAME[foilTier] or foilTier) or nil
		if isBordered and tierDisplayName then
			rarityLabel.Text = "Rarity: " .. tostring(data.Rarity or "Common") .. " - " .. tierDisplayName .. " Foil"
		else
			rarityLabel.Text = "Rarity: " .. tostring(data.Rarity or "Common")
		end
		rarityLabel.TextSize = 18
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.ZIndex = PREVIEW_TEXT_ZINDEX
		rarityLabel.TextColor3 = previewAccentColor
		if tostring(data.Rarity) == "God" or tostring(data.Rarity) == "Transcendent" then
			rarityLabel.TextStrokeColor3 = Color3.fromRGB(210, 45, 45)
			rarityLabel.TextStrokeTransparency = 0

		else
			rarityLabel.TextStrokeColor3 = Color3.fromRGB(12, 12, 16)
			rarityLabel.TextStrokeTransparency = 0
		end

		-- Description / ability text (future-proof; always readable over foil)
		if descLabel and descLabel:IsA("TextLabel") then
			-- `data` comes from callers (inventory/shop). Use CardDatabase as source of truth
			-- for the hover "ability/description" text to avoid missing or mismatched fields.
			local cardRow = CardDatabase.GetCardData(baseCardId)
			local resolvedDesc =
				(type(data) == "table" and type(data.Description) == "string" and data.Description ~= "") and data.Description
				or (cardRow and cardRow.Description)
				or ""
			descLabel.Text = (type(resolvedDesc) == "string" and resolvedDesc) or ""
			descLabel.ZIndex = PREVIEW_TEXT_ZINDEX
		end

		local previewUiStroke = hoverPreviewFrame:FindFirstChildOfClass("UIStroke")
		if previewUiStroke then
			local useRainbowBorder = isBordered and visualStyle.tierKey == "Rainbow"
			local strokeTweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if useRainbowBorder then
				stopGradientBorderLoop()
				RainbowBorderStroke.detach(previewUiStroke)
				local rb = previewUiStroke:FindFirstChild("RarityBorderGradient")
				if rb then
					rb:Destroy()
				end
				TweenService:Create(previewUiStroke, strokeTweenInfo, { Color = Color3.new(1, 1, 1) }):Play()
				RainbowBorderStroke.attach(previewUiStroke)
			else
				RainbowBorderStroke.detach(previewUiStroke)
				ensurePreviewRarityBorderGradient(previewUiStroke)
				local borderGradient = previewUiStroke:FindFirstChild("RarityBorderGradient")
				local strokeTweenGoals = { Color = previewAccentColor }
				TweenService:Create(previewUiStroke, strokeTweenInfo, strokeTweenGoals):Play()
				if borderGradient then
					borderGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, previewAccentColor),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1, previewAccentColor),
					})
					borderGradient.Rotation = 0
					startGradientBorderLoop()
				end
			end
		end

		-- Apply (or clear) the holographic foil or lightning on the preview panel.
		-- foilTier is already resolved above for the rarity label; reuse it here
		-- so the preview foil always matches the inventory card's foil exactly.
		stopPreviewFoil()
		if isLightningConcept then
			-- Lightning concept tile: procedural bolt overlay only
			state.previewLightningController = LightningOverlayController.Attach(hoverPreviewFrame, {
				baseZIndex       = PREVIEW_BASE_ZINDEX + 5,
				cornerRadius     = UDim.new(0, 12),
				flashIntervalSec = 1.4,
			})
			state.previewLightningController:SetIntensity("Hover")
		elseif isBordered and foilTier then
			-- Use alphaBias to lighten foil overlay so card art stays visible.
			state.previewFoilController = HoloFoilController.Attach(hoverPreviewFrame, {
				tier         = foilTier,
				cornerRadius = UDim.new(0, 12),
				zIndex       = PREVIEW_BASE_ZINDEX + 5,
				alphaBias    = 0.14,
			})
			-- Start at Hover intensity since the preview is inherently a "focused" view.
			state.previewFoilController:SetIntensity("Hover")
		end

		-- Ultra Rare text: over the art box only; fixed textSize (no autofit — adjust PREVIEW_ULTRA_RARE_TEXT_SIZE).
		if isUltraConcept then
			local artInsetX = 10
			local artBandH = PREVIEW_ART_HEIGHT
			local ultraAttachOpts = {
				zIndex = PREVIEW_BASE_ZINDEX + 28,
				cornerRadius = UDim.new(0, 8),
				regionPosition = UDim2.fromOffset(artInsetX, 10),
				regionSize = UDim2.new(1, -artInsetX * 2, 0, artBandH),
				textSize = PREVIEW_ULTRA_RARE_TEXT_SIZE,
				diagonalDegrees = 32,
				rowYScale = 0.42,
				snakeSpeed = 2,
				snakeWavelength = 0.48,
			}
			state.previewUltraRareController = UltraRareTextEffect.Attach(hoverPreviewFrame, ultraAttachOpts)
		end

		local artBgTweenGoals = {}
		artBgTweenGoals.BackgroundColor3 = previewAccentColor
		local artBgTween = TweenService:Create(
			art,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			artBgTweenGoals
		)
		artBgTween:Play()

		art.BackgroundTransparency = 0.88  -- lighter so art shows through foil better
		local videoAssetId = nil
		if data then
			if data.HoverVideoAssetId and data.HoverVideoAssetId ~= "" and data.HoverVideoAssetId ~= "rbxassetid://0" then
				videoAssetId = data.HoverVideoAssetId
			elseif data.VideoAssetId and data.VideoAssetId ~= "" and data.VideoAssetId ~= "rbxassetid://0" then
				videoAssetId = data.VideoAssetId
			end
		end
		if artVideo and artVideo:IsA("VideoFrame") and videoAssetId and videoAssetId ~= "" and videoAssetId ~= "rbxassetid://0" then
			hoverVideoPreviewActiveValue.Value = true
			ensurePreviewVideoPlayback(artVideo, videoAssetId)
			state.hoverVideoGuardGeneration = state.hoverVideoGuardGeneration + 1
			local guardGeneration = state.hoverVideoGuardGeneration
			if state.hoverVideoGuardConnection then
				state.hoverVideoGuardConnection:Disconnect()
				state.hoverVideoGuardConnection = nil
			end
			local lastPos = nil
			local accumulator = 0
			state.hoverVideoGuardConnection = RunService.Heartbeat:Connect(function(dt)
				if guardGeneration ~= state.hoverVideoGuardGeneration or not (artVideo and artVideo.Parent) then
					if state.hoverVideoGuardConnection then
						state.hoverVideoGuardConnection:Disconnect()
						state.hoverVideoGuardConnection = nil
					end
					return
				end

				accumulator = accumulator + dt
				if accumulator < 0.2 then
					return
				end
				accumulator = 0

				if hoverPreviewFrame.Visible and artVideo.Visible and artVideo.Video == videoAssetId and not artVideo.Playing then
					artVideo.Playing = true
					pcall(function()
						artVideo:Play()
					end)
				end
				if hoverPreviewFrame.Visible and artVideo.Visible and artVideo.Video == videoAssetId then
					local currentPos = tonumber(artVideo.TimePosition) or 0
					if lastPos and currentPos + 0.03 < lastPos and currentPos < HOVER_VIDEO_LOOP_START_OFFSET_SECONDS then
						artVideo.TimePosition = HOVER_VIDEO_LOOP_START_OFFSET_SECONDS
						currentPos = HOVER_VIDEO_LOOP_START_OFFSET_SECONDS
					end
					lastPos = currentPos
				end
			end)
			artImage.Image = ""
		else
			hoverVideoPreviewActiveValue.Value = false
			if artVideo and artVideo:IsA("VideoFrame") then
				state.hoverVideoGuardGeneration = state.hoverVideoGuardGeneration + 1
				if state.hoverVideoGuardConnection then
					state.hoverVideoGuardConnection:Disconnect()
					state.hoverVideoGuardConnection = nil
				end
				artVideo.Visible = false
				artVideo.Playing = false
			end
			-- `artFolder` is optional when `ReplicatedStorage.CardArt` is not used (image ids live on card data).
			local imageObj = nil
			if artFolder then
				imageObj = artFolder:FindFirstChild(baseCardId)
			end
			if imageObj and imageObj:IsA("Decal") then
				artImage.Image = imageObj.Texture
			elseif data and data.ArtAssetId and data.ArtAssetId ~= "" and data.ArtAssetId ~= "rbxassetid://0" then
				artImage.Image = data.ArtAssetId

			else
				artImage.Image = ""
			end
		end

		hoverPreviewFrame.Visible = true
		hoverPreviewFrame.Position = UDim2.new(1, PREVIEW_POP_RIGHT_OFFSET, 0.5, -PREVIEW_HALF_HEIGHT)
		hoverPreviewFrame.Size = UDim2.fromOffset(PREVIEW_POP_WIDTH, PREVIEW_POP_HEIGHT)
		hoverPreviewFrame.BackgroundTransparency = 0.25
		if artVideo and artVideo:IsA("VideoFrame") and videoAssetId and videoAssetId ~= "" and videoAssetId ~= "rbxassetid://0" then
			task.defer(function()
				if requestId == state.hideTaskId and hoverPreviewFrame.Visible then
					ensurePreviewVideoPlayback(artVideo, videoAssetId)
				end
			end)
		end

		local rarityKey = tostring(data.Rarity or "Common")
		-- Black particle aura disabled for God/Transcendent rarity
		stopBeliodusAura(hoverPreviewFrame)
		local punchGoals = buildPreviewFrameGoals(getPreviewPunchScale(rarityKey))
		playRarityFlash(hoverPreviewFrame, rarityKey, previewAccentColor)
		local settleGoals = {
			Position = UDim2.new(1, PREVIEW_RIGHT_OFFSET, 0.5, -PREVIEW_HALF_HEIGHT),
			Size = UDim2.fromOffset(PREVIEW_WIDTH, PREVIEW_HEIGHT),
			BackgroundTransparency = 0.06,
		}

		local punchTween = TweenService:Create(
			hoverPreviewFrame,
			TweenInfo.new(0.17, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			punchGoals
		)
		punchTween:Play()

		local function runPreviewSettleTween()
			if requestId ~= state.hideTaskId or not hoverPreviewFrame.Visible then
				return
			end
			local settleTween = TweenService:Create(
				hoverPreviewFrame,
				TweenInfo.new(0.11, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				settleGoals
			)
			settleTween:Play()
		end
		task.delay(0.17, runPreviewSettleTween)
	end

	function api.Hide(delaySeconds)
		local requestId = state.hideTaskId + 1
		state.hideTaskId = requestId

		task.delay(delaySeconds or 0, function()
			if requestId ~= state.hideTaskId then
				return
			end
			stopBeliodusAura(hoverPreviewFrame)
			stopGradientBorderLoop()
			local previewStrokeOnHide = hoverPreviewFrame:FindFirstChildOfClass("UIStroke")
			if previewStrokeOnHide then
				RainbowBorderStroke.detach(previewStrokeOnHide)
				ensurePreviewRarityBorderGradient(previewStrokeOnHide)
			end
			stopPreviewFoil()
			stopPreviewLightning()
			stopPreviewUltraRare()
			local art = hoverPreviewFrame:FindFirstChild("PreviewArt")
			local artVideo = art and art:FindFirstChild("PreviewArtVideo")
			hoverVideoPreviewActiveValue.Value = false
			if artVideo and artVideo:IsA("VideoFrame") then
				state.hoverVideoGuardGeneration = state.hoverVideoGuardGeneration + 1
				if state.hoverVideoGuardConnection then
					state.hoverVideoGuardConnection:Disconnect()
					state.hoverVideoGuardConnection = nil
				end
				artVideo.Visible = false
				artVideo.Playing = false
			end

			local hideGoals = {
				Position = UDim2.new(1, PREVIEW_POP_RIGHT_OFFSET, 0.5, -PREVIEW_HALF_HEIGHT),
				Size = UDim2.fromOffset(PREVIEW_POP_WIDTH, PREVIEW_POP_HEIGHT),
				BackgroundTransparency = 0.25
			}
			local hideTween = TweenService:Create(hoverPreviewFrame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), hideGoals)
			hideTween:Play()
			hideTween.Completed:Wait()
			if requestId == state.hideTaskId then
				hoverPreviewFrame.Visible = false
			end
		end)
	end

	return api
end

return HoverPreview