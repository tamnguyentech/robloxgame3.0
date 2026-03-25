-- DamagePopupManager.luau
-- MapleStory-style scatter, layering, and caps for combat floating numbers.
-- Single entry point for PvE/PvP; StyleConfig.DamageNumbers + DamageCategoryOverrides.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local StyleConfig = require(script.Parent:WaitForChild("styles"):WaitForChild("StyleConfig"))
local SettingsUIController = require(script.Parent:WaitForChild("controllers"):WaitForChild("SettingsUIController"))

local DamagePopupManager = {}

local BURST_WINDOW_SEC = 0.2
local MAX_PER_TARGET = 10
local GLOBAL_MAX_POPUPS = 80
local STAGGER_SEC = 0.012
local STACK_X_JITTER_PX = 3

-- Gradient palette inspired by UltraRareTextEffect (HSV sweep).
local GRADIENT_PALETTE = {
	{ h = 0.12, s = 0.92, v = 1.00 },
	{ h = 0.14, s = 0.50, v = 1.00 },
	{ h = 0.00, s = 0.00, v = 1.00 },
	{ h = 0.54, s = 0.60, v = 1.00 },
	{ h = 0.75, s = 0.65, v = 1.00 },
	{ h = 0.12, s = 0.92, v = 1.00 },
}

local function buildGradientSequence(huePhase)
	local n = #GRADIENT_PALETTE
	local kps = table.create(n)
	for i = 1, n do
		local frac = (i - 1) / (n - 1)
		local p = GRADIENT_PALETTE[i]
		local h = (p.h + huePhase) % 1
		kps[i] = ColorSequenceKeypoint.new(frac, Color3.fromHSV(h, p.s, p.v))
	end
	return ColorSequence.new(kps)
end

local function attachGradient(label, profile, seq)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "DamageGradient"
	local phase = ((tonumber(seq) or 0) % 20) / 20
	gradient.Color = buildGradientSequence(phase)
	gradient.Rotation = -15
	gradient.Parent = label
	local sweepDuration = math.max(0.8, tonumber(profile.GradientSweepSeconds) or 1.6)
	TweenService:Create(
		gradient,
		TweenInfo.new(sweepDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 345 }
	):Play()
end

local globalActiveCount = 0

-- sessionId -> { [targetKey] = { burstTimes = {}, laneCursor = number, zCursor = number, count = number } }
local sessionTargetState = {}

local function getSettingsShowNumbers()
	local st = SettingsUIController.GetState()
	return st and st.ShowDamageNumbers ~= false
end

function DamagePopupManager.ClearSession(sessionId)
	if not sessionId then
		return
	end
	sessionTargetState[sessionId] = nil
end

local function pruneBurst(times, now)
	local i = 1
	while i <= #times do
		if now - times[i] > BURST_WINDOW_SEC then
			table.remove(times, i)
		else
			i += 1
		end
	end
end

local function deterministicUnit(seed)
	seed = seed % 2147483647
	if seed <= 0 then
		seed = 1
	end
	return (seed * 48271) % 2147483647 / 2147483647
end

local function jitterFromSeq(seq, targetKey, salt)
	local s = tostring(seq) .. "|" .. tostring(targetKey) .. "|" .. tostring(salt)
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	local jx = deterministicUnit(h) * 10 - 5
	local jy = deterministicUnit(h + 1337) * 8 - 4
	return jx, jy
end

local function shallowMerge(baseTable, patchTable)
	local out = {}
	for k, v in pairs(baseTable) do
		out[k] = v
	end
	if patchTable then
		for k, v in pairs(patchTable) do
			out[k] = v
		end
	end
	return out
end

local function mergeProfile(contextKind, category)
	local base = StyleConfig.DamageNumbers[contextKind] or StyleConfig.DamageNumbers.Default
	local overrides = StyleConfig.DamageCategoryOverrides
	local cat = category and overrides and overrides[category] or {}
	return shallowMerge(base, cat)
end

function DamagePopupManager.MapCategory(finalDamage, isCrit, isDodged, absorbed)
	if isDodged then
		return "Dodge"
	end
	local absAmt = math.max(0, math.floor(tonumber(absorbed) or 0))
	local dmg = math.max(0, math.floor(tonumber(finalDamage) or 0))
	if absAmt > 0 and dmg <= 0 then
		return "ShieldAbsorb"
	end
	if isCrit then
		return "CritDamage"
	end
	return "NormalDamage"
end

local function formatAmountText(profile, amount, category, absorbedAmt)
	if type(profile.OverrideText) == "string" then
		return profile.OverrideText
	end
	if category == "Dodge" then
		return profile.OverrideText or "MISS"
	end
	if category == "ShieldAbsorb" then
		local a = math.max(0, math.floor(tonumber(absorbedAmt) or 0))
		local prefix = profile.Prefix or "«"
		return prefix .. CardDatabase.FormatAttack(a)
	end
	local prefix = profile.Prefix or "-"
	return prefix .. CardDatabase.FormatAttack(amount)
end

function DamagePopupManager.EnqueueFloating(spec)
	if not getSettingsShowNumbers() then
		return
	end
	if not spec or not spec.rootFrame or not spec.targetGui then
		return
	end
	local sessionId = spec.sessionId
	local targetKey = spec.targetKey or "unknown"
	local seq = tonumber(spec.sequence) or 0
	local category = spec.category or "NormalDamage"
	local contextKind = spec.contextKind or "Default"
	local staggerDelay = tonumber(spec.staggerDelay) or 0

	if globalActiveCount >= GLOBAL_MAX_POPUPS then
		return
	end

	local function doSpawn()
		if not getSettingsShowNumbers() then
			return
		end
		if not (spec.rootFrame.Parent and spec.targetGui.Parent) then
			return
		end

		local amtEarly = math.max(0, math.floor(tonumber(spec.amount) or 0))
		local absEarly = tonumber(spec.absorbed) or 0
		if category ~= "Dodge" and category ~= "ShieldAbsorb" and amtEarly <= 0 then
			return
		end
		if category == "ShieldAbsorb" and absEarly <= 0 then
			return
		end

		local bucket = sessionId and sessionTargetState[sessionId]
		if not bucket then
			bucket = {}
			if sessionId then
				sessionTargetState[sessionId] = bucket
			end
		end
		local st = bucket[targetKey]
		if not st then
			st = { burstTimes = {}, laneCursor = 0, zCursor = 0, count = 0 }
			bucket[targetKey] = st
		end

		local now = os.clock()
		pruneBurst(st.burstTimes, now)
		table.insert(st.burstTimes, now)
		local burstN = #st.burstTimes

		if st.count >= MAX_PER_TARGET then
			return
		end
		st.count += 1

		local profile = mergeProfile(contextKind, category)
		local stackSpacingPx = tonumber(profile.VerticalStackSpacingPx) or 16
		local stackOffsetY = -(math.max(0, burstN - 1) * stackSpacingPx)
		local jx, jy = jitterFromSeq(seq, targetKey, burstN)
		jx = math.clamp(jx, -STACK_X_JITTER_PX, STACK_X_JITTER_PX)
		if category == "CritDamage" then
			jx += (deterministicUnit(seq + 3) - 0.5) * 4
		end

		local amount = math.max(0, math.floor(tonumber(spec.amount) or 0))
		local absorbedAmt = tonumber(spec.absorbed) or 0
		local text = formatAmountText(profile, amount, category, absorbedAmt)

		local rootFrame = spec.rootFrame
		local targetGui = spec.targetGui

		local rootAbs = rootFrame.AbsolutePosition
		local center = targetGui.AbsolutePosition + (targetGui.AbsoluteSize * 0.5)
		local cx = center.X - rootAbs.X
		local cy = center.Y - rootAbs.Y

		local y0 = cy + (tonumber(profile.RootStartOffsetY) or -12) + stackOffsetY + jy
		local y1 = cy + (tonumber(profile.RootEndOffsetY) or -72) + stackOffsetY + jy
		local ox = jx

		local size = profile.Size or UDim2.fromOffset(96, 26)
		local textSize = profile.TextSize or 16
		if type(profile.TextSizeAdd) == "number" then
			textSize = textSize + profile.TextSizeAdd
		end

		st.zCursor += 1
		local zBase = math.max(500, profile.ZIndex or 120)
		local zIndex = zBase + (st.zCursor % 40)

		local label = Instance.new("TextLabel")
		label.Name = "DamageNumber"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = size
		label.Position = UDim2.fromOffset(cx + ox, y0)
		label.BackgroundTransparency = 1
		label.TextTransparency = 0
		label.Text = text
		label.Font = profile.Font or Enum.Font.GothamBlack
		label.TextSize = textSize
		label.TextColor3 = profile.TextColor or Color3.fromRGB(255, 120, 120)
		label.TextStrokeColor3 = profile.TextStrokeColor or Color3.fromRGB(8, 8, 8)
		label.TextStrokeTransparency = profile.TextStrokeTransparency or 0
		label.ZIndex = zIndex
		label.Parent = rootFrame
		attachGradient(label, profile, seq)

		local uiScale = Instance.new("UIScale")
		local punch = tonumber(profile.ScalePunch) or 1
		if punch ~= 1 then
			uiScale.Scale = punch * 0.88
			uiScale.Parent = label
			TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = punch,
			}):Play()
		else
			uiScale.Scale = 1
			uiScale.Parent = label
		end

		globalActiveCount += 1

		local dur = profile.DurationSeconds or 1.2
		local riseDur = math.max(0.1, tonumber(profile.RiseDurationSeconds) or math.min(0.35, dur * 0.35))
		local fadeDur = math.max(0.2, tonumber(profile.FadeDurationSeconds) or math.max(0.3, dur - riseDur))
		local once
		once = RunService.Heartbeat:Connect(function()
			if once then
				once:Disconnect()
			end
			if not (label.Parent and targetGui.Parent and rootFrame.Parent) then
				globalActiveCount = math.max(0, globalActiveCount - 1)
				if st then
					st.count = math.max(0, st.count - 1)
				end
				return
			end
			rootAbs = rootFrame.AbsolutePosition
			center = targetGui.AbsolutePosition + (targetGui.AbsoluteSize * 0.5)
			cx = center.X - rootAbs.X
			cy = center.Y - rootAbs.Y
			y0 = cy + (tonumber(profile.RootStartOffsetY) or -12) + stackOffsetY + jy
			y1 = cy + (tonumber(profile.RootEndOffsetY) or -72) + stackOffsetY + jy
			label.Position = UDim2.fromOffset(cx + ox, y0)

			TweenService:Create(
				label,
				TweenInfo.new(riseDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromOffset(cx + ox, y1),
				}
			):Play()
			task.delay(riseDur * 0.35, function()
				if not (label and label.Parent) then
					return
				end
				TweenService:Create(
					label,
					TweenInfo.new(fadeDur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						TextTransparency = 1,
						TextStrokeTransparency = 1,
					}
				):Play()
			end)

			task.delay(riseDur + fadeDur + 0.15, function()
				if label and label.Parent then
					label:Destroy()
				end
				globalActiveCount = math.max(0, globalActiveCount - 1)
				if st then
					st.count = math.max(0, st.count - 1)
				end
			end)
		end)
	end

	if staggerDelay > 0 then
		task.delay(staggerDelay, doSpawn)
	else
		doSpawn()
	end
end

-- PvP: anchored to card frame (scale positions), with scatter via UDim offset from center
function DamagePopupManager.EnqueueOnCard(spec)
	if not getSettingsShowNumbers() then
		return
	end
	if not spec or not spec.cardFrame then
		return
	end
	local sessionId = spec.sessionId
	local targetKey = spec.targetKey or "pvp_slot"
	local seq = tonumber(spec.sequence) or 0
	local category = spec.category or "NormalDamage"
	local contextKind = spec.contextKind or "PvpHit"
	local staggerDelay = tonumber(spec.staggerDelay) or 0

	if globalActiveCount >= GLOBAL_MAX_POPUPS then
		return
	end

	local function doSpawn()
		if not getSettingsShowNumbers() then
			return
		end
		local cardFrame = spec.cardFrame
		if not (cardFrame and cardFrame.Parent) then
			return
		end

		local amtEarly = math.max(0, math.floor(tonumber(spec.amount) or 0))
		local absEarly = tonumber(spec.absorbed) or 0
		if category ~= "Dodge" and category ~= "ShieldAbsorb" and amtEarly <= 0 then
			return
		end
		if category == "ShieldAbsorb" and absEarly <= 0 then
			return
		end

		local bucket = sessionId and sessionTargetState[sessionId]
		if not bucket then
			bucket = {}
			if sessionId then
				sessionTargetState[sessionId] = bucket
			end
		end
		local st = bucket[targetKey]
		if not st then
			st = { burstTimes = {}, laneCursor = 0, zCursor = 0, count = 0 }
			bucket[targetKey] = st
		end

		local now = os.clock()
		pruneBurst(st.burstTimes, now)
		table.insert(st.burstTimes, now)
		local burstN = #st.burstTimes

		if st.count >= MAX_PER_TARGET then
			return
		end
		st.count += 1

		local profile = mergeProfile(contextKind, category)
		local stackSpacingPx = tonumber(profile.VerticalStackSpacingPx) or 16
		local stackOffsetY = -(math.max(0, burstN - 1) * stackSpacingPx)
		local jx, jy = jitterFromSeq(seq, targetKey, burstN)
		jx = math.clamp(jx, -STACK_X_JITTER_PX, STACK_X_JITTER_PX)
		if category == "CritDamage" then
			jx += (deterministicUnit(seq + 9) - 0.5) * 4
		end

		local amount = math.max(0, math.floor(tonumber(spec.amount) or 0))
		local absorbedAmt = tonumber(spec.absorbed) or 0
		local text = formatAmountText(profile, amount, category, absorbedAmt)

		local size = profile.Size or UDim2.fromOffset(86, 24)
		local textSize = profile.TextSize or 16
		if type(profile.TextSizeAdd) == "number" then
			textSize = textSize + profile.TextSizeAdd
		end

		st.zCursor += 1
		local zBase = profile.ZIndex or 122
		local zIndex = zBase + (st.zCursor % 40)

		local sz = cardFrame.AbsoluteSize
		local w = math.max(1, sz.X)
		local h = math.max(1, sz.Y)
		local px = w * 0.5 + jx
		local py0 = h * 0.38 + stackOffsetY + jy
		local py1 = h * 0.1 + stackOffsetY + jy

		local label = Instance.new("TextLabel")
		label.Name = "DamageNumber"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = size
		label.Position = UDim2.fromOffset(px, py0)
		label.BackgroundTransparency = 1
		label.Text = text
		label.Font = profile.Font or Enum.Font.GothamBlack
		label.TextSize = textSize
		label.TextColor3 = profile.TextColor or Color3.fromRGB(255, 120, 120)
		label.TextStrokeColor3 = profile.TextStrokeColor or Color3.fromRGB(8, 8, 8)
		label.TextStrokeTransparency = profile.TextStrokeTransparency or 0
		label.ZIndex = zIndex
		label.Parent = cardFrame
		attachGradient(label, profile, seq)

		local uiScale = Instance.new("UIScale")
		local punch = tonumber(profile.ScalePunch) or 1
		if punch ~= 1 then
			uiScale.Scale = punch * 0.88
			uiScale.Parent = label
			TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = punch,
			}):Play()
		else
			uiScale.Scale = 1
			uiScale.Parent = label
		end

		globalActiveCount += 1

		local dur = profile.DurationSeconds or 1.2
		local riseDur = math.max(0.1, tonumber(profile.RiseDurationSeconds) or math.min(0.35, dur * 0.35))
		local fadeDur = math.max(0.2, tonumber(profile.FadeDurationSeconds) or math.max(0.3, dur - riseDur))
		local once
		once = RunService.Heartbeat:Connect(function()
			if once then
				once:Disconnect()
			end
			if not (label.Parent and cardFrame.Parent) then
				globalActiveCount = math.max(0, globalActiveCount - 1)
				if st then
					st.count = math.max(0, st.count - 1)
				end
				return
			end
			sz = cardFrame.AbsoluteSize
			w = math.max(1, sz.X)
			h = math.max(1, sz.Y)
			px = w * 0.5 + jx
			py0 = h * 0.38 + stackOffsetY + jy
			py1 = h * 0.1 + stackOffsetY + jy
			label.Position = UDim2.fromOffset(px, py0)
			TweenService:Create(
				label,
				TweenInfo.new(riseDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromOffset(px, py1),
				}
			):Play()
			task.delay(riseDur * 0.35, function()
				if not (label and label.Parent) then
					return
				end
				TweenService:Create(
					label,
					TweenInfo.new(fadeDur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{
						TextTransparency = 1,
						TextStrokeTransparency = 1,
					}
				):Play()
			end)
			task.delay(riseDur + fadeDur + 0.15, function()
				if label and label.Parent then
					label:Destroy()
				end
				globalActiveCount = math.max(0, globalActiveCount - 1)
				if st then
					st.count = math.max(0, st.count - 1)
				end
			end)
		end)
	end

	if staggerDelay > 0 then
		task.delay(staggerDelay, doSpawn)
	else
		doSpawn()
	end
end

DamagePopupManager.STAGGER_SEC = STAGGER_SEC

return DamagePopupManager
