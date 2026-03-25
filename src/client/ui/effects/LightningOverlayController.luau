-- LightningOverlayController.luau
-- Procedural lightning overlay for cards using midpoint-displacement and layered math.
--
-- Algorithm: 2D midpoint displacement with perpendicular jitter (fractal dimension ~1.5),
-- yielding organic Lichtenberg-style bolt paths. Segments rendered as rotated Frames.
-- Flash animation uses exponential decay for alpha; optional multi-octave flicker.
--
-- Public API:
--   LightningOverlayController.Attach(cardGui, opts) → controller
--   controller:SetIntensity("Idle" | "Hover")
--   controller:Destroy()
--
-- opts: { tier = "Lightning" | "God", flashIntervalSec = 1.2, cornerRadius = UDim }

local RunService = game:GetService("RunService")

-- ── Procedural bolt math ───────────────────────────────────────────────────────

-- Seeded PRNG (Mulberry32) for reproducible bolts per flash.
local function mulberry32(seed)
	seed = bit32.band(seed or 0, 0x7FFFFFFF)
	return function()
		seed = bit32.band(seed + 0x6D2B79F5, 0xFFFFFFFF)
		local t = seed
		t = bit32.bxor(bit32.rshift(t, 15), t)
		t = bit32.band(t * 2057, 0xFFFFFFFF)
		t = bit32.bxor(bit32.rshift(t, 13), t)
		t = bit32.band(t * 749, 0xFFFFFFFF)
		t = bit32.bxor(bit32.rshift(t, 16), t)
		return t / 4294967296
	end
end

-- Midpoint displacement: displace midpoint perpendicular to segment.
-- Returns array of Vector2 points in [0,1]×[0,1].
local function midpointDisplace(a, b, rng, roughness, decay, depth, maxDepth)
	if depth >= maxDepth then
		return { a, b }
	end
	local mid = (a + b) / 2
	local seg = b - a
	local len = seg.Magnitude
	if len < 0.01 then
		return { a, b }
	end
	-- Perpendicular unit vector (rotate 90°)
	local perp = Vector2.new(-seg.Y, seg.X).Unit
	local h = roughness * len * math.pow(0.5, decay * depth)
	local jitter = (rng() * 2 - 1) * h
	mid = mid + perp * jitter
	-- Clamp to [0,1] bounds
	mid = Vector2.new(math.clamp(mid.X, 0, 1), math.clamp(mid.Y, 0, 1))
	local left  = midpointDisplace(a, mid, rng, roughness, decay, depth + 1, maxDepth)
	local right = midpointDisplace(mid, b, rng, roughness, decay, depth + 1, maxDepth)
	-- Merge: left + right[2:]
	local out = {}
	for i = 1, #left do
		table.insert(out, left[i])
	end
	for i = 2, #right do
		table.insert(out, right[i])
	end
	return out
end

-- Generate main bolt from (0.1,0) to (0.9,1) with variance.
local function generateBolt(rng, roughness, maxDepth)
	local a = Vector2.new(0.1 + rng() * 0.15, 0.02)
	local b = Vector2.new(0.7 + rng() * 0.2, 0.98)
	return midpointDisplace(a, b, rng, roughness or 0.35, 0.8, 0, maxDepth or 5)
end

-- Second bolt (branch or parallel) for density.
local function generateBranch(rng, roughness, maxDepth)
	local a = Vector2.new(0.8 - rng() * 0.2, 0.1)
	local b = Vector2.new(0.15 + rng() * 0.1, 0.9)
	return midpointDisplace(a, b, rng, roughness or 0.3, 0.9, 0, (maxDepth or 5) - 1)
end

-- ── Segment chain to GUI ───────────────────────────────────────────────────────

local function createSegmentFrame(parent, from, to, thickness, color, zIndex)
	local dx = to.X - from.X
	local dy = to.Y - from.Y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return nil end
	local angle = math.atan2(dy, dx)
	local deg = math.deg(angle)
	local seg = Instance.new("Frame")
	seg.Name = "LightningSegment"
	seg.Size = UDim2.new(0, math.ceil(len) + 2, 0, thickness)
	seg.Position = UDim2.new(0, from.X, 0, from.Y)
	seg.AnchorPoint = Vector2.new(0, 0.5)
	seg.Rotation = deg
	seg.BackgroundColor3 = color
	seg.BackgroundTransparency = 0.2
	seg.BorderSizePixel = 0
	seg.ZIndex = zIndex
	-- Gradient for brighter core glow (bigger streaks read better)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0.5, 0.7, 1)),
		ColorSequenceKeypoint.new(0.3, Color3.new(0.85, 0.95, 1)),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(0.7, Color3.new(0.85, 0.95, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(0.5, 0.7, 1)),
	})
	grad.Rotation = 90
	grad.Parent = seg
	seg.Parent = parent
	return seg
end

-- ── LightningOverlayController ──────────────────────────────────────────────────

local LightningOverlayController = {}
LightningOverlayController.__index = LightningOverlayController

local LIGHTNING_COLOR = Color3.fromRGB(180, 220, 255)

local activeOverlays = {}
local driverConnection = nil
local globalT = 0

local function ensureDriver()
	if driverConnection then return end
	driverConnection = RunService.Heartbeat:Connect(function(dt)
		globalT = globalT + dt
		for overlay in pairs(activeOverlays) do
			overlay:_tick(globalT, dt)
		end
	end)
end

local function releaseDriverIfEmpty()
	if next(activeOverlays) then return end
	if driverConnection then
		driverConnection:Disconnect()
		driverConnection = nil
	end
end

function LightningOverlayController.new()
	local self = setmetatable({}, LightningOverlayController)
	self._alive = true
	self._container = nil
	self._segments = {}      -- { segment, progress } progress 0-1 along bolt path
	self._flashPhase = 0
	self._flashDuration = 0.55   -- longer flash so lightning lingers
	self._travelDuration = 0.18  -- how long the "flow" takes to travel along each bolt
	self._nextFlashAt = 0
	self._mode = "Idle"
	self._flashInterval = 1.4
	self._sizeX = 168
	self._sizeY = 234
	return self
end

function LightningOverlayController:Destroy()
	self._alive = false
	activeOverlays[self] = nil
	releaseDriverIfEmpty()
	if self._container and self._container.Parent then
		self._container:Destroy()
	end
	self._container = nil
	self._segments = {}
end

function LightningOverlayController:SetIntensity(mode)
	self._mode = (mode == "Hover") and "Hover" or "Idle"
end

function LightningOverlayController:_tick(t, dt)
	if not (self._alive and self._container and self._container.Parent) then
		return
	end
	-- Schedule next flash
	if t >= self._nextFlashAt then
		self._flashPhase = 0
		self._nextFlashAt = t + self._flashInterval + (math.random() * 0.4 - 0.2)
		-- Regenerate bolts for variety
		self:_rebuildBolts()
	end
	-- Animate flash: traveling wave flows along each bolt, then gradual decay
	self._flashPhase = self._flashPhase + dt
	local baseAlpha = (self._mode == "Hover") and 0.12 or 0.06
	local travelDur = self._travelDuration
	local flashDur = self._flashDuration
	for _, entry in ipairs(self._segments) do
		local seg, progress = entry.seg, entry.progress
		if seg.Parent then
			-- Traveling wave: brightness peaks when (phase - progress*travelDur) ≈ 0
			-- So the "front" of the flow is at phase = progress * travelDur
			local wavePos = self._flashPhase - progress * travelDur
			local peakAlpha
			if wavePos < 0 then
				peakAlpha = 0
			elseif wavePos < travelDur * 0.15 then
				peakAlpha = wavePos / (travelDur * 0.15)
			elseif wavePos < travelDur * 0.5 then
				peakAlpha = 1
			else
				peakAlpha = math.exp(-3 * (wavePos - travelDur * 0.5) / travelDur)
			end
			-- Overall flash envelope: rise fast, decay slowly
			local envelope
			if self._flashPhase < flashDur * 0.1 then
				envelope = self._flashPhase / (flashDur * 0.1)
			else
				envelope = math.exp(-2.5 * (self._flashPhase - flashDur * 0.1) / flashDur)
			end
			local alpha = peakAlpha * envelope
			local targetTransparency = 1 - (baseAlpha + math.clamp(alpha, 0, 1) * 0.78)
			seg.BackgroundTransparency = targetTransparency
		end
	end
end

function LightningOverlayController:_rebuildBolts()
	for _, entry in ipairs(self._segments) do
		local seg = entry.seg
		if seg and seg.Parent then
			seg:Destroy()
		end
	end
	self._segments = {}
	local rng = mulberry32(math.floor(globalT * 1000) % 0x7FFFFFFF)
	-- Bigger streaks: main bolts 6-8px thick, branches 4-5px
	local mainThick = (self._mode == "Hover") and 8 or 6
	local branchThick = (self._mode == "Hover") and 5 or 4
	local color = LIGHTNING_COLOR
	local zIdx = 100
	-- Three bolts for fuller coverage, more depth for longer paths
	local bolt1 = generateBolt(rng, 0.38, 5)
	local totalSegs = #bolt1 - 1
	for i = 1, #bolt1 - 1 do
		local a, b = bolt1[i], bolt1[i + 1]
		local from = Vector2.new(a.X * self._sizeX, a.Y * self._sizeY)
		local to   = Vector2.new(b.X * self._sizeX, b.Y * self._sizeY)
		local seg = createSegmentFrame(self._container, from, to, mainThick, color, zIdx)
		if seg then
			table.insert(self._segments, { seg = seg, progress = (i - 0.5) / totalSegs })
		end
	end
	local bolt2 = generateBranch(rng, 0.32, 4)
	for i = 1, #bolt2 - 1 do
		local a, b = bolt2[i], bolt2[i + 1]
		local from = Vector2.new(a.X * self._sizeX, a.Y * self._sizeY)
		local to   = Vector2.new(b.X * self._sizeX, b.Y * self._sizeY)
		local seg = createSegmentFrame(self._container, from, to, branchThick, color, zIdx - 1)
		if seg then
			table.insert(self._segments, { seg = seg, progress = (i - 0.5) / (#bolt2 - 1) })
		end
	end
	-- Third bolt: flows with slight delay for staggered "crackling" feel
	local bolt3Start = Vector2.new(0.05 + rng() * 0.1, 0.5 + rng() * 0.2)
	local bolt3End   = Vector2.new(0.85 + rng() * 0.1, 0.3 + rng() * 0.2)
	local bolt3 = midpointDisplace(bolt3Start, bolt3End, rng, 0.4, 0.75, 0, 4)
	local phaseOffset = 0.12 + rng() * 0.08  -- offset so bolt3 flows slightly after bolt1/2
	for i = 1, #bolt3 - 1 do
		local a, b = bolt3[i], bolt3[i + 1]
		local from = Vector2.new(a.X * self._sizeX, a.Y * self._sizeY)
		local to   = Vector2.new(b.X * self._sizeX, b.Y * self._sizeY)
		local seg = createSegmentFrame(self._container, from, to, branchThick - 1, color, zIdx - 2)
		if seg then
			table.insert(self._segments, { seg = seg, progress = phaseOffset + (i - 0.5) / (#bolt3 - 1) * (1 - phaseOffset) })
		end
	end
end

function LightningOverlayController.Attach(cardGui, opts)
	if not (cardGui and cardGui:IsA("GuiObject")) then
		return nil
	end
	opts = opts or {}
	local self = LightningOverlayController.new()
	self._flashInterval = opts.flashIntervalSec or 1.2
	local baseZI = opts.baseZIndex or 50
	local absSize = cardGui.AbsoluteSize
	self._sizeX = math.max(80, absSize.X > 0 and absSize.X or 190)
	self._sizeY = math.max(100, absSize.Y > 0 and absSize.Y or 270)
	local cornerR = opts.cornerRadius or UDim.new(0, 10)
	local container = Instance.new("Frame")
	container.Name = "LightningOverlay"
	container.Size = UDim2.fromScale(1, 1)
	container.Position = UDim2.fromOffset(0, 0)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ZIndex = baseZI
	container.ClipsDescendants = true
	container.Parent = cardGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = cornerR
	corner.Parent = container
	self._container = container
	self:_rebuildBolts()
	self._nextFlashAt = globalT + 0.3
	activeOverlays[self] = true
	ensureDriver()
	return self
end

return LightningOverlayController
