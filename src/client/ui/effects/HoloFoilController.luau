-- HoloFoilController.luau
-- Phase-shifted, sine-modulated holographic foil overlay for bordered card variants.
--
-- Architecture: one shared Heartbeat driver updates every live foil each frame.
-- The driver auto-starts on first Attach and auto-stops when all foils are Destroyed,
-- so idle CPU cost is zero when no bordered cards are visible.
--
-- Seamless loop: Offset.X = sin(ω·t + φ).  A sine is naturally periodic with no
-- discontinuity, so the shimmer band oscillates forever with zero snap artefacts —
-- unlike a tween that resets Offset from +1 back to -1 at the end of each cycle.
--
-- Intensity smoothing: ω, αBase, and αAmp smoothly exponential-decay toward their
-- target values each frame, so switching Idle ↔ Hover is framerate-independent and
-- never produces a jarring jump.
--
-- Public API (unchanged from previous version — callers require no edits):
--   HoloFoilController.Attach(cardGui, opts) → controller
--   controller:SetIntensity("Idle" | "Hover")
--   controller:Destroy()

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- ── Shared driver ─────────────────────────────────────────────────────────────
-- Why: one Heartbeat for N foils is far cheaper than N individual connections.
-- activeFoils is a hash-set so registration/deregistration are O(1).

local activeFoils = {}  -- { [foilInstance] = true }
local driverConnection = nil
local globalT = 0  -- monotonically increasing time, shared by all foil instances

local function ensureDriver()
	if driverConnection then return end
	driverConnection = RunService.Heartbeat:Connect(function(dt)
		globalT = globalT + dt
		for foil in pairs(activeFoils) do
			foil:_tick(globalT, dt)
		end
	end)
end

local function releaseDriverIfEmpty()
	if next(activeFoils) then return end
	if driverConnection then
		driverConnection:Disconnect()
		driverConnection = nil
	end
end

-- ── Tier palettes ─────────────────────────────────────────────────────────────
-- Per-tier parameters drive the sine math inside _tick.
--
-- omegaIdle / omegaHover  (rad/s)  — sweep angular frequency.
--   Higher = faster shimmer.  Hover is always ~1.5× Idle ("Ultra Rare" feel).
--
-- alphaBaseIdle / alphaBaseHover   — BackgroundTransparency at the trough of the
--   alpha sine.  Lower number = more visible foil.  Hover is noticeably lower.
--
-- alphaAmpIdle / alphaAmpHover     — How much the alpha oscillates around the base.
--   Combined with the sine, the visible range is [base, base+amp].
--
-- phiX / phiY              (rad)   — Independent phase offsets for X and Y axes.
--   Y-drift at 0.6× frequency creates a faint diagonal shimmy that reads as 3-D.
--
-- phiA                     (rad)   — Phase of the alpha pulse relative to X sweep.
--   π/2 means the foil is brightest when the band crosses the card centre.
--
-- sparkles                          — Diamond only.  Table of spawning params.
-- hueShift / hueOmega /
--   hueUpdateInterval               — Rainbow only.  Drives ColorSequence rebuild.

local TWOPI = math.pi * 2

local TIER_CONFIG = {

	-- ── Silver (Obsidian Chrome) ──────────────────────────────────────────────
	-- Same foil mechanics as Gold: sine sweep + transparency pulse. High-contrast
	-- Deep Steel (#1A1A1A) to Pure White (#FFFFFF) gradient — no flat gray.
	Silver = {
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(182, 182, 182)),   -- Deep Steel
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(140, 148, 165)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 255, 255)), -- Pure White
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(130, 138, 155)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(26, 26, 26)),
		}),
		rotation       = 45,
		omegaIdle      = 0.55,
		omegaHover     = 0.75,
		alphaBaseIdle  = 0.78,
		alphaAmpIdle   = 0.09,
		alphaBaseHover = 0.62,
		alphaAmpHover  = 0.11,
		phiX           = 0,
		phiY           = math.pi * 0.40,
		phiA           = math.pi * 0.50,
		sparkles       = nil,
		hueShift       = false,
	},

	-- ── Gold ──────────────────────────────────────────────────────────────────
	-- Warm amber: dark base with a sunlit gold/white stripe.
	Gold = {
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(160, 118, 20)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 210, 60)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 252, 190)),
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(245, 195, 45)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(160, 118, 20)),
		}),
		rotation       = 45,
		omegaIdle      = 0.44,
		omegaHover     = 0.60,
		alphaBaseIdle  = 0.68,
		alphaAmpIdle   = 0.10,
		alphaBaseHover = 0.54,
		alphaAmpHover  = 0.13,
		phiX           = 0,
		phiY           = math.pi * 0.35,
		phiA           = math.pi * 0.50,
		sparkles       = nil,
		hueShift       = false,
	},

	-- ── Diamond (Prismatic Glitch) ────────────────────────────────────────────
	-- Cyan/Magenta shards + math.sin gradient rotation for glitch refraction.
	Diamond = {
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(0, 255, 255)),   -- Cyan
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 0, 255)),   -- Magenta
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(180, 255, 255)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 100, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(0, 255, 255)),
		}),
		rotation         = 45,
		rotationSinAmp   = 25,   -- degrees; gradient wobbles via math.sin
		rotationSinOmega = 0.8,
		omegaIdle        = 0.48,
		omegaHover       = 0.66,
		alphaBaseIdle    = 0.60,
		alphaAmpIdle     = 0.11,
		alphaBaseHover   = 0.46,
		alphaAmpHover    = 0.14,
		phiX             = 0,
		phiY             = math.pi * 0.45,
		phiA             = math.pi * 0.50,
		shards = {
			maxCount = 6,
			interval = 0.38,
			widthMin = 2,
			widthMax = 5,
			heightMin = 6,
			heightMax = 14,
			lifespan = 0.5,
			colors = {
				Color3.fromRGB(0, 255, 255),
				Color3.fromRGB(255, 0, 255),
				Color3.fromRGB(150, 255, 255),
				Color3.fromRGB(255, 150, 255),
			},
		},
		sparkles   = nil,
		hueShift   = false,
	},

	-- ── Corrupted (Ember Vein) ────────────────────────────────────────────────
	-- 5-keypoint heat gradient + dual-frequency breath + overlay anti-phase.
	Corrupted = {
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(128, 0, 0)),   -- Deep Red #800000
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(176, 48, 0)),  -- Dark Orange #B03000
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 69, 0)),  -- Bright Orange #FF4500
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(176, 48, 0)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(128, 0, 0)),
		}),
		rotation         = 45,
		omegaIdle        = 0.22,
		omegaHover       = 0.32,
		alphaBaseIdle    = 0.58,
		alphaAmpIdle     = 0.14,
		alphaBaseHover   = 0.44,
		alphaAmpHover    = 0.18,
		phiX             = 0,
		phiY             = math.pi * 0.35,
		phiA             = math.pi * 0.5,
		sparkles         = nil,
		hueShift         = false,
		overlayColor     = Color3.fromRGB(18, 18, 18),  -- Charcoal #121212
		overlayAlpha     = 0.50,
		overlayPulseAmp  = 0.06,
		dualFreqAlpha    = true,
		dualFreqRatio    = 1.37,
	},

	-- ── Rainbow ───────────────────────────────────────────────────────────────
	-- Full-spectrum hue cycle: the ColorSequence shifts through the HUE wheel at
	-- hueOmega rad/s, rebuilt at hueUpdateInterval seconds (≈ 20 Hz) so the eye
	-- perceives continuous colour flow without per-frame ColorSequence allocation.
	Rainbow = {
		colorSequence = ColorSequence.new({       -- placeholder; rebuilt at runtime
			ColorSequenceKeypoint.new(0,   Color3.fromHSV(0,    0.85, 1)),
			ColorSequenceKeypoint.new(0.2, Color3.fromHSV(0.20, 0.85, 1)),
			ColorSequenceKeypoint.new(0.4, Color3.fromHSV(0.40, 0.85, 1)),
			ColorSequenceKeypoint.new(0.6, Color3.fromHSV(0.60, 0.85, 1)),
			ColorSequenceKeypoint.new(0.8, Color3.fromHSV(0.80, 0.85, 1)),
			ColorSequenceKeypoint.new(1,   Color3.fromHSV(0,    0.85, 1)),
		}),
		rotation           = 45,
		omegaIdle          = 0.44,
		omegaHover         = 0.60,
		alphaBaseIdle      = 0.62,
		alphaAmpIdle       = 0.10,
		alphaBaseHover     = 0.50,
		alphaAmpHover      = 0.13,
		phiX               = 0,
		phiY               = math.pi * 0.40,
		phiA               = math.pi * 0.50,
		sparkles           = nil,
		hueShift           = true,
		hueOmega           = 0.18,   -- slowed: gentle hue drift rather than rapid cycling
		hueUpdateInterval  = 0.05,   -- seconds between ColorSequence rebuilds (20 Hz)
	},
}

local DEFAULT_TIER_CFG    = TIER_CONFIG.Silver
local DEFAULT_CORNER      = UDim.new(0, 10)
local HUE_KEYPOINT_COUNT  = 6    -- number of hue stops in the rebuilt Rainbow sequence
-- Decay of 3 (vs 5) gives a softer ~0.33 s ramp when switching Idle↔Hover,
-- preventing the abrupt brightness jump that reads as a flash.
local SMOOTH_DECAY        = 3

-- Rebuild the Rainbow ColorSequence with hue rotated by huePhase.
-- Why: modifying individual keypoints is not possible in Luau; we build a fresh
-- ColorSequence.  At 20 Hz this is negligible CPU cost.
local function buildRainbowCS(huePhase)
	local kps = table.create(HUE_KEYPOINT_COUNT)
	for i = 1, HUE_KEYPOINT_COUNT do
		local frac = (i - 1) / (HUE_KEYPOINT_COUNT - 1)
		local hue  = (huePhase + frac) % 1
		kps[i] = ColorSequenceKeypoint.new(frac, Color3.fromHSV(hue, 0.85, 1))
	end
	return ColorSequence.new(kps)
end

-- ── Public API ────────────────────────────────────────────────────────────────

local HoloFoilController = {}
HoloFoilController.__index = HoloFoilController

-- Attach a holographic foil overlay to a GuiObject.
--
-- opts (all optional):
--   tier         string   "Silver" | "Gold" | "Diamond" | "Rainbow"
--   cornerRadius UDim     Card corner radius   (default 10 px)
--   zIndex       number   Base ZIndex          (default 6)
--   alphaBias    number   Add to transparency (0.1 = lighter, less darkening). Use for hover preview.
function HoloFoilController.Attach(cardGui, opts)
	opts = opts or {}
	local tierCfg  = TIER_CONFIG[opts.tier or ""] or DEFAULT_TIER_CFG
	local baseZI   = opts.zIndex or 6
	local alphaBias = opts.alphaBias or 0

	local self = setmetatable({}, HoloFoilController)
	self._alive     = true
	self._tierCfg   = tierCfg
	self._mode      = "Idle"
	self._alphaBias = alphaBias

	-- Each instance starts at a random phase so stacks of cards shimmer out-of-sync,
	-- which looks natural (like cards sitting at different angles to the light source).
	self._phiOffset = math.random() * TWOPI

	-- Smoothed working values — lerp toward mode targets each frame.
	self._omega     = tierCfg.omegaIdle
	self._alphaBase = tierCfg.alphaBaseIdle
	self._alphaAmp  = tierCfg.alphaAmpIdle

	-- Diamond sparkle state
	if tierCfg.sparkles then
		self._sparkleAcc   = 0
		self._sparkleCount = 0
	end

	-- Diamond shard state (Prismatic Glitch)
	if tierCfg.shards then
		self._shardAcc   = 0
		self._shardCount = 0
	end

	-- Rainbow hue state
	if tierCfg.hueShift then
		self._hueAcc   = 0
		self._huePhase = math.random()  -- start at a random hue so cards differ
	end

	-- ── Clipping mask ────────────────────────────────────────────────────────
	-- Why: Frame + ClipsDescendants + UICorner clips the foil to the card's
	-- rounded corners without an expensive CanvasGroup compositing pass.
	local mask = Instance.new("Frame")
	mask.Name                   = "HoloFoilMask"
	mask.Size                   = UDim2.fromScale(1, 1)
	mask.Position               = UDim2.fromOffset(0, 0)
	mask.BackgroundTransparency = 1
	mask.ClipsDescendants       = true
	mask.BorderSizePixel        = 0
	mask.ZIndex                 = baseZI
	mask.Parent                 = cardGui

	local maskCorner = Instance.new("UICorner")
	maskCorner.CornerRadius = opts.cornerRadius or DEFAULT_CORNER
	maskCorner.Parent       = mask

	-- ── Foil layer ───────────────────────────────────────────────────────────
	-- Oversized by 20 px per axis so the gradient edge stays off-screen during
	-- the full [-1, +1] offset sweep without revealing a hard clip boundary.
	local foilLayer = Instance.new("Frame")
	foilLayer.Name                   = "HoloFoilLayer"
	foilLayer.Size                   = UDim2.new(1, 20, 1, 20)
	foilLayer.Position               = UDim2.fromOffset(-10, -10)
	foilLayer.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	foilLayer.BackgroundTransparency = tierCfg.alphaBaseIdle
	foilLayer.BorderSizePixel        = 0
	foilLayer.ZIndex                 = baseZI
	foilLayer.Parent                 = mask

	local gradient = Instance.new("UIGradient")
	gradient.Color    = tierCfg.colorSequence
	gradient.Rotation = tierCfg.rotation
	gradient.Offset   = Vector2.new(0, 0)
	gradient.Parent   = foilLayer

	self._mask      = mask
	self._foilLayer = foilLayer
	self._gradient  = gradient
	self._tierKey   = opts.tier or ""

	-- Corrupted: charcoal overlay on top of heat pulse
	if self._tierKey == "Corrupted" and tierCfg.overlayColor then
		local overlay = Instance.new("Frame")
		overlay.Name                   = "CharcoalOverlay"
		overlay.Size                   = UDim2.fromScale(1, 1)
		overlay.Position               = UDim2.fromOffset(0, 0)
		overlay.BackgroundColor3       = tierCfg.overlayColor
		overlay.BackgroundTransparency = 1 - (tierCfg.overlayAlpha or 0.50)
		overlay.BorderSizePixel        = 0
		overlay.ZIndex                 = baseZI + 1
		overlay.Parent                 = mask
		local overlayCorner = Instance.new("UICorner")
		overlayCorner.CornerRadius = opts.cornerRadius or DEFAULT_CORNER
		overlayCorner.Parent       = overlay
		self._overlay = overlay
	else
		self._overlay = nil
	end

	activeFoils[self] = true
	ensureDriver()

	return self
end

-- Per-frame update called by the shared Heartbeat driver.
-- t  = globalT (monotonic seconds since first foil was created)
-- dt = frame delta (seconds)
function HoloFoilController:_tick(t, dt)
	if not (self._alive and self._mask and self._mask.Parent) then
		return
	end

	local cfg = self._tierCfg
	local phi = self._phiOffset

	-- Smooth the working values toward the mode target.
	-- Why: exponential decay (1 - e^(-k·dt)) is framerate-independent and settles
	-- in ≈ 3/k seconds regardless of whether the game runs at 30 or 120 fps.
	local smooth = 1 - math.exp(-SMOOTH_DECAY * dt)

	local targetOmega = (self._mode == "Hover") and cfg.omegaHover     or cfg.omegaIdle
	local targetAB    = (self._mode == "Hover") and cfg.alphaBaseHover  or cfg.alphaBaseIdle
	local targetAA    = (self._mode == "Hover") and cfg.alphaAmpHover   or cfg.alphaAmpIdle

	self._omega     = self._omega     + (targetOmega - self._omega)     * smooth
	self._alphaBase = self._alphaBase + (targetAB    - self._alphaBase) * smooth
	self._alphaAmp  = self._alphaAmp  + (targetAA    - self._alphaAmp)  * smooth

	local omega = self._omega

	-- ── Gradient sweep (sine with diagonal shimmy) ────────────────────────────
	local ox = math.sin(omega * t + phi + cfg.phiX)
	local oy = math.cos(omega * t * 0.5 + phi + cfg.phiY) * 0.07
	self._gradient.Offset = Vector2.new(ox, oy)

	-- ── Transparency pulse ────────────────────────────────────────────────────
	local alpha
	if cfg.dualFreqAlpha then
		-- Corrupted: dual-frequency breath for organic "living" pulse
		local p1 = 0.5 + 0.5 * math.sin(omega * t + phi + cfg.phiA)
		local p2 = 0.2 * math.sin(omega * t * (cfg.dualFreqRatio or 1.37) + phi * 0.8)
		alpha = self._alphaBase + self._alphaAmp * (p1 + p2)
	else
		alpha = self._alphaBase
			+ self._alphaAmp * (0.5 + 0.5 * math.sin(omega * t + phi + cfg.phiA))
	end
	-- Readability: foil never fully opaque; keep at least 30% transparency.
	-- alphaBias (e.g. 0.12 for hover preview) lightens the overlay to reduce darkening.
	local finalAlpha = math.clamp(math.max(0.30, alpha) + (self._alphaBias or 0), 0, 1)
	self._foilLayer.BackgroundTransparency = finalAlpha

	-- ── Corrupted: overlay anti-phase (heat breathes through when pulse peaks) ──
	if self._overlay and self._overlay.Parent and cfg.overlayPulseAmp then
		local overlayBase = 1 - (cfg.overlayAlpha or 0.50)
		local pulse = cfg.overlayPulseAmp * math.sin(omega * t + phi + math.pi)
		self._overlay.BackgroundTransparency = math.clamp(overlayBase + pulse, 0, 1)
	end

	-- ── Diamond: Prismatic Glitch — sin-driven gradient rotation ───────────────
	if self._tierKey == "Diamond" and cfg.rotationSinAmp then
		local wobble = cfg.rotationSinAmp * math.sin(t * (cfg.rotationSinOmega or 0.8) + phi)
		self._gradient.Rotation = (cfg.rotation or 45) + wobble
	end

	-- ── Diamond shards (Cyan/Magenta prismatic shards) ─────────────────────────
	local sh = cfg.shards
	if sh and self._shardCount < sh.maxCount then
		self._shardAcc = self._shardAcc + dt
		if self._shardAcc >= sh.interval then
			self._shardAcc = self._shardAcc - sh.interval
			self:_spawnShard(sh)
		end
	end

	-- ── Diamond/Rainbow sparkles (legacy) ──────────────────────────────────────
	local sp = cfg.sparkles
	if sp and self._sparkleCount < sp.maxCount then
		self._sparkleAcc = self._sparkleAcc + dt
		if self._sparkleAcc >= sp.interval then
			self._sparkleAcc = self._sparkleAcc - sp.interval
			self:_spawnSparkle(sp)
		end
	end

	-- ── Rainbow hue cycle ─────────────────────────────────────────────────────
	if cfg.hueShift then
		self._huePhase = (self._huePhase + cfg.hueOmega * dt / TWOPI) % 1
		self._hueAcc   = self._hueAcc + dt
		if self._hueAcc >= cfg.hueUpdateInterval then
			self._hueAcc = self._hueAcc - cfg.hueUpdateInterval
			self._gradient.Color = buildRainbowCS(self._huePhase)
		end
	end
end

-- Spawn one Diamond shard: thin rectangular Cyan/Magenta prism slice.
function HoloFoilController:_spawnShard(sh)
	if not (self._mask and self._mask.Parent) then return end

	local w = sh.widthMin + math.random() * (sh.widthMax - sh.widthMin)
	local h = sh.heightMin + math.random() * (sh.heightMax - sh.heightMin)
	local color = sh.colors[math.random(#sh.colors)]

	local shard = Instance.new("Frame")
	shard.Name                   = "DiamondShard"
	shard.Size                   = UDim2.fromOffset(w, h)
	shard.AnchorPoint            = Vector2.new(0.5, 0.5)
	shard.Position               = UDim2.fromScale(math.random() * 0.85 + 0.075, math.random() * 0.85 + 0.075)
	shard.BackgroundColor3       = color
	shard.BackgroundTransparency = 0.12
	shard.BorderSizePixel        = 0
	shard.Rotation               = math.random() * 360
	shard.ZIndex                 = (self._foilLayer.ZIndex or 6) + 1
	shard.Parent                 = self._mask

	self._shardCount = self._shardCount + 1

	TweenService:Create(
		shard,
		TweenInfo.new(sh.lifespan, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1, Rotation = shard.Rotation + 45 * (math.random(2) == 1 and 1 or -1) }
	):Play()

	Debris:AddItem(shard, sh.lifespan + 0.05)
	self._shardCount = self._shardCount - 1
end

-- Spawn one Diamond sparkle: a tiny frame that rotates and fades out quickly.
function HoloFoilController:_spawnSparkle(sp)
	if not (self._mask and self._mask.Parent) then return end

	local size  = sp.sizeMin + math.random() * (sp.sizeMax - sp.sizeMin)
	local color = sp.colors[math.random(#sp.colors)]

	local spark = Instance.new("Frame")
	spark.Name                   = "DiamondSparkle"
	spark.Size                   = UDim2.fromOffset(size, size)
	spark.AnchorPoint            = Vector2.new(0.5, 0.5)
	spark.Position               = UDim2.fromScale(math.random() * 0.8 + 0.1, math.random() * 0.8 + 0.1)
	spark.BackgroundColor3       = color
	spark.BackgroundTransparency = 0.10
	spark.BorderSizePixel        = 0
	spark.Rotation               = math.random() * 360
	spark.ZIndex                 = (self._foilLayer.ZIndex or 6) + 1
	spark.Parent                 = self._mask

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent       = spark

	self._sparkleCount = self._sparkleCount + 1

	-- Fade + rotate out via a short tween; destroy when done.
	TweenService:Create(
		spark,
		TweenInfo.new(sp.lifespan, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1, Rotation = spark.Rotation + 90 * (math.random(2) == 1 and 1 or -1) }
	):Play()

	Debris:AddItem(spark, sp.lifespan + 0.05)

	self._sparkleCount = self._sparkleCount - 1
end

-- Switch animation intensity between "Idle" and "Hover".
-- The working omega and alpha values smoothly decay toward the new targets
-- each frame — no abrupt jump, no restart of the sweep.
function HoloFoilController:SetIntensity(mode)
	if not self._alive then return end
	self._mode = (mode == "Hover") and "Hover" or "Idle"
end

-- Stop all activity and destroy every instance created by this controller.
function HoloFoilController:Destroy()
	if not self._alive then return end
	self._alive = false

	activeFoils[self] = nil
	releaseDriverIfEmpty()

	if self._mask and self._mask.Parent then
		self._mask:Destroy()
	end

	self._mask      = nil
	self._foilLayer = nil
	self._gradient  = nil
	self._overlay   = nil
end

return HoloFoilController
