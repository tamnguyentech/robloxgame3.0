-- UltraRareTextEffect.luau
-- Secret-rare style "ULTRA RARE" diagonal text: per-letter depth layers + snake wiggle.
--
-- Snake motion: each glyph's Y offset is sin(ωt + i·φ) so the wave runs along the string
-- seamlessly (looping in phase space).
--
-- Public API:
--   UltraRareTextEffect.Attach(cardGui, opts?) → controller
--   controller:Destroy()
--
-- opts (optional):
--   zIndex          number       Base ZIndex (default 8)
--   cornerRadius    UDim         Clip mask corners (default UDim.new(0, 14))
--   text            string       (default "ULTRA RARE")
--   textSize        number       (default 22)
--   font            Enum.Font    (default LuckiestGuy — chunky “collectible card” look)
--   snakeAmplitude  number       Peak Y wiggle in px (default ~0.35 * textSize)
--   snakeSpeed      number       Angular speed ω in rad/s (default 3.2)
--   snakeWavelength number       Phase step per letter in rad (default 0.55)
--   maxTextSize     number       Optional cap after diagonal auto-fit (smaller previews)

local RunService   = game:GetService("RunService")
local TextService  = game:GetService("TextService")

-- ── Shared driver ─────────────────────────────────────────────────────────────
local activeEffects:    { [any]: boolean } = {}
local driverConnection: RBXScriptConnection? = nil
local globalT = 0

local function ensureDriver()
	if driverConnection then return end
	driverConnection = RunService.Heartbeat:Connect(function(dt: number)
		globalT = globalT + dt
		for effect in pairs(activeEffects) do
			effect:_tick(globalT, dt)
		end
	end)
end

local function releaseDriverIfEmpty()
	if next(activeEffects) then return end
	if driverConnection then
		driverConnection:Disconnect()
		driverConnection = nil
	end
end

-- ── Animated fill palette (shared across all glyph gradients) ───────────────
local PALETTE = {
	{ h = 0.12, s = 0.92, v = 1.00 },
	{ h = 0.14, s = 0.50, v = 1.00 },
	{ h = 0.00, s = 0.00, v = 1.00 },
	{ h = 0.54, s = 0.60, v = 1.00 },
	{ h = 0.75, s = 0.65, v = 1.00 },
	{ h = 0.12, s = 0.92, v = 1.00 },
}

local HUE_OMEGA         = 0.11
local HUE_UPDATE_PERIOD = 0.05
local SWEEP_OMEGA       = 1.0
local GLOW_OMEGA        = 1.8

local function buildGradientCS(huePhase: number): ColorSequence
	local n   = #PALETTE
	local kps = table.create(n)
	for i = 1, n do
		local frac = (i - 1) / (n - 1)
		local p    = PALETTE[i]
		local h    = (p.h + huePhase) % 1
		kps[i]     = ColorSequenceKeypoint.new(frac, Color3.fromHSV(h, p.s, p.v))
	end
	return ColorSequence.new(kps)
end

local function makeGlyphLabel(
	parent: Instance,
	text: string,
	textSize: number,
	font: Enum.Font,
	color: Color3,
	strokeColor: Color3,
	strokeTr: number,
	zIndex: number,
	rotation: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel        = 0
	label.Text                   = text
	label.Font                   = font
	label.TextSize               = textSize
	label.TextColor3             = color
	label.TextStrokeColor3       = strokeColor
	label.TextStrokeTransparency = strokeTr
	label.TextXAlignment         = Enum.TextXAlignment.Center
	label.TextYAlignment         = Enum.TextYAlignment.Center
	label.Rotation               = rotation
	label.ZIndex                 = zIndex
	label.Size                   = UDim2.fromOffset(1, 1) -- set by caller after measure
	label.Parent                 = parent
	return label
end

-- ── Effect class ──────────────────────────────────────────────────────────────
local UltraRareTextEffect = {}
UltraRareTextEffect.__index = UltraRareTextEffect

function UltraRareTextEffect.Attach(cardGui: GuiObject, opts: {
	zIndex:                  number?,
	cornerRadius:            UDim?,
	text:                    string?,
	textSize:                number?,
	font:                    Enum.Font?,
	snakeAmplitude:          number?,
	snakeSpeed:              number?,
	snakeWavelength:         number?,
	regionPosition:          UDim2?,
	regionSize:              UDim2?,
	fitDiagonalMaxWidth:     number?,
	fitDiagonalMaxHeight:    number?,
	diagonalDegrees:         number?,
	rowYScale:               number?,
}?): any

	opts = opts or {}
	local baseZI      = (opts :: any).zIndex          or 8
	local corner      = (opts :: any).cornerRadius    or UDim.new(0, 14)
	local labelText   = (opts :: any).text            or "ULTRA RARE"
	local font        = (opts :: any).font            or Enum.Font.LuckiestGuy
	local snakeSpeed  = (opts :: any).snakeSpeed      or 3.2
	local phaseStep   = (opts :: any).snakeWavelength or 0.55
	local rowYScale   = (opts :: any).rowYScale
	if rowYScale == nil then
		rowYScale = 0.52
	end
	local rotMag      = (opts :: any).diagonalDegrees
	if rotMag == nil then
		rotMag = 18
	end
	local ROT         = -math.abs(rotMag)

	local regionPos   = (opts :: any).regionPosition
	local regionSz    = (opts :: any).regionSize
	local fitW        = (opts :: any).fitDiagonalMaxWidth
	local fitH        = (opts :: any).fitDiagonalMaxHeight

	local function measureTotalTextWidth(fs: number, spaceW: number, letterSpacing: number): number
		local totalW = 0
		for i = 1, #labelText do
			local ch = labelText:sub(i, i)
			if ch == " " then
				totalW = totalW + spaceW + letterSpacing
			else
				local sz = TextService:GetTextSize(ch, fs, font, Vector2.new(512, 512))
				totalW = totalW + math.max(1, math.ceil(sz.X)) + letterSpacing
			end
		end
		return math.max(1, totalW - letterSpacing)
	end

	local function rotatedAabbWidthHeight(totalW: number, rowH: number): (number, number)
		local theta = math.rad(math.abs(ROT))
		local c = math.cos(theta)
		local s = math.sin(theta)
		return totalW * c + rowH * s, totalW * s + rowH * c
	end

	local fontSize = (opts :: any).textSize or 22
	if type(fitW) == "number" and type(fitH) == "number" and fitW > 8 and fitH > 8 then
		local best = 12
		for fs = 96, 12, -1 do
			local spaceW = math.max(4, math.floor(fs * 0.38))
			local letterSpacing = 1
			local ampEst = math.clamp(math.floor(fs * 0.28), 3, 12)
			local rowH = math.ceil(fs * 1.35 + ampEst * 2 + 8)
			local tw = measureTotalTextWidth(fs, spaceW, letterSpacing)
			local bw, bh = rotatedAabbWidthHeight(tw, rowH)
			if bw <= fitW and bh <= fitH then
				best = fs
				break
			end
		end
		fontSize = best
	end

	local maxFs = (opts :: any).maxTextSize
	if type(maxFs) == "number" and maxFs >= 8 then
		fontSize = math.min(fontSize, math.floor(maxFs))
	end

	local amplitude = (opts :: any).snakeAmplitude
	if amplitude == nil then
		amplitude = math.clamp(math.floor(fontSize * 0.34 + 0.5), 4, 16)
	end

	local self = setmetatable({}, UltraRareTextEffect)
	self._alive           = true
	self._huePhase        = 0
	self._hueAcc          = 0
	self._snakeSpeed      = snakeSpeed
	self._phaseStep       = phaseStep
	self._amplitude       = amplitude
	self._glyphs = {}

	-- Clip mask (full card or a sub-rect e.g. hover preview art area)
	local mask                  = Instance.new("Frame")
	mask.Name                   = "UltraRareTextMask"
	if regionPos and regionSz then
		mask.AnchorPoint            = Vector2.new(0, 0)
		mask.Position               = regionPos
		mask.Size                   = regionSz
	else
		mask.Size                   = UDim2.fromScale(1, 1)
		mask.Position               = UDim2.fromOffset(0, 0)
	end
	mask.BackgroundTransparency = 1
	mask.ClipsDescendants       = true
	mask.BorderSizePixel        = 0
	mask.ZIndex                 = baseZI
	mask.Parent                 = cardGui

	local maskCorner            = Instance.new("UICorner")
	maskCorner.CornerRadius     = corner
	maskCorner.Parent           = mask

	-- Rotated row root (all glyphs share this rotation)
	local row                   = Instance.new("Frame")
	row.Name                    = "UltraRareLetterRow"
	row.BackgroundTransparency  = 1
	row.BorderSizePixel         = 0
	row.AnchorPoint             = Vector2.new(0.5, 0.5)
	row.Position                = UDim2.new(0.5, 0, rowYScale, 0)
	row.ZIndex                  = baseZI
	row.Parent                  = mask

	local spaceW = math.max(4, math.floor(fontSize * 0.38))
	local letterSpacing = 1
	local sizes = {}
	local totalW = 0

	for i = 1, #labelText do
		local ch = labelText:sub(i, i)
		if ch == " " then
			totalW = totalW + spaceW + letterSpacing
			table.insert(sizes, { ch = " ", w = spaceW })
		else
			local sz = TextService:GetTextSize(ch, fontSize, font, Vector2.new(512, 512))
			local w = math.max(1, math.ceil(sz.X))
			totalW = totalW + w + letterSpacing
			table.insert(sizes, { ch = ch, w = w })
		end
	end
	totalW = totalW - letterSpacing
	if totalW < 1 then totalW = 1 end

	local rowH = math.ceil(fontSize * 1.35 + amplitude * 2 + 8)
	row.Size = UDim2.fromOffset(math.ceil(totalW) + amplitude * 2 + 24, rowH)
	row.Rotation = ROT

	local half = totalW * 0.5
	local cursor = -half

	for strIndex, spec in ipairs(sizes) do
		local w = spec.w
		local ch = spec.ch
		local cx = cursor + w * 0.5
		cursor = cursor + w + letterSpacing

		if ch ~= " " then
			local h = math.ceil(fontSize * 1.25)

			local shadow = makeGlyphLabel(
				row, ch, fontSize, font,
				Color3.fromRGB(12, 6, 28),
				Color3.fromRGB(8, 4, 18), 0.12,
				baseZI + 1, 0
			)
			shadow.Size = UDim2.fromOffset(w + 2, h)
			shadow.AnchorPoint = Vector2.new(0.5, 0.5)
			shadow.Position = UDim2.new(0.5, cx + 4, 0.5, 4)

			local main = makeGlyphLabel(
				row, ch, fontSize, font,
				Color3.fromRGB(255, 220, 100),
				Color3.fromRGB(255, 245, 160), 0.32,
				baseZI + 2, 0
			)
			main.Size = UDim2.fromOffset(w + 2, h)
			main.AnchorPoint = Vector2.new(0.5, 0.5)
			main.Position = UDim2.new(0.5, cx, 0.5, 0)

			local grad = Instance.new("UIGradient")
			grad.Color = buildGradientCS(0)
			grad.Rotation = 40
			grad.Offset = Vector2.new(0, 0)
			grad.Parent = main
			local rim = makeGlyphLabel(
				row, ch, fontSize, font,
				Color3.fromRGB(255, 252, 240),
				Color3.fromRGB(255, 255, 255), 0.6,
				baseZI + 3, 0
			)
			rim.TextTransparency = 0.42
			rim.Size = UDim2.fromOffset(w + 2, h)
			rim.AnchorPoint = Vector2.new(0.5, 0.5)
			rim.Position = UDim2.new(0.5, cx - 1, 0.5, -1)

			table.insert(self._glyphs, {
				cx = cx,
				shadow = shadow,
				main = main,
				rim = rim,
				grad = grad,
				index = strIndex,
			})
		end
	end

	self._mask = mask
	self._row  = row

	activeEffects[self] = true
	ensureDriver()

	return self
end

function UltraRareTextEffect:_tick(t: number, dt: number)
	if not (self._alive and self._mask and self._mask.Parent) then return end

	-- Shared gradient motion: sweep + hue drift (all glyphs stay in sync).
	local sweepX = math.sin(SWEEP_OMEGA * t) * 0.55
	self._huePhase = (self._huePhase + HUE_OMEGA * dt) % 1
	self._hueAcc = self._hueAcc + dt
	local newCS: ColorSequence? = nil
	if self._hueAcc >= HUE_UPDATE_PERIOD then
		self._hueAcc = self._hueAcc - HUE_UPDATE_PERIOD
		newCS = buildGradientCS(self._huePhase)
	end

	for _, g in ipairs(self._glyphs) do
		local phase = self._snakeSpeed * t + (g.index - 1) * self._phaseStep
		local y = math.sin(phase) * self._amplitude

		g.shadow.Position = UDim2.new(0.5, g.cx + 4, 0.5, y + 4)
		g.main.Position   = UDim2.new(0.5, g.cx,     0.5, y)
		g.rim.Position    = UDim2.new(0.5, g.cx - 1, 0.5, y - 1)

		g.grad.Offset = Vector2.new(sweepX, 0.12 * math.sin(t * 1.3 + g.index * 0.2))
		if newCS then
			g.grad.Color = newCS
		end
	end

	-- Breathing stroke on all mains
	local glow = 0.28 + 0.28 * math.sin(GLOW_OMEGA * t)
	local tr = math.clamp(glow, 0.06, 0.58)
	for _, g in ipairs(self._glyphs) do
		g.main.TextStrokeTransparency = tr
	end
end

function UltraRareTextEffect:Destroy()
	if not self._alive then return end
	self._alive = false
	activeEffects[self] = nil
	releaseDriverIfEmpty()
	if self._mask and self._mask.Parent then
		self._mask:Destroy()
	end
	self._mask      = nil
	self._row       = nil
	self._glyphs = {}
end

return UltraRareTextEffect
