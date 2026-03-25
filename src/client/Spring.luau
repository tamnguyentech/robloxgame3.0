-- Spring.luau  (client utility)
-- Minimal second-order spring integrator for smooth UI animations.
--
-- Why a spring instead of a tween:
--   A spring integrator produces natural acceleration + deceleration with
--   overshoot (bounce), giving UI elements a physical "weight" that linear or
--   ease-out tweens cannot replicate.  The overshoot makes card hover-zoom feel
--   like the card is physically lifting toward the cursor rather than sliding.
--
-- How — semi-implicit Euler integration (one step per frame):
--   F   = k * (target - value) - d * velocity   (spring restoring + damping force)
--   vel = vel + F * dt                           (integrate velocity)
--   val = val + vel * dt                         (integrate position)
--
--   This is unconditionally stable for any k and d > 0, making it safe to use
--   at any frame rate without the instability seen in explicit Euler methods at
--   large dt values.
--
-- Typical good values for UI:
--   k = 200, d = 22  →  snappy with slight overshoot  (card zoom)
--   k = 120, d = 18  →  slightly looser feel           (panel slide)
--   k = 80,  d = 14  →  more springy / bouncy

local Spring = {}
Spring.__index = Spring

-- Construct a new spring starting at `initialValue`.
-- k = stiffness (larger = faster/snappier), d = damping (larger = less bounce).
function Spring.new(initialValue, k, d)
	return setmetatable({
		value    = initialValue or 1,
		velocity = 0,
		target   = initialValue or 1,
		k        = k or 200,
		d        = d or 22,
	}, Spring)
end

-- Advance the spring by `dt` seconds toward `self.target`.  Returns the new value.
-- Call this from a Heartbeat/RenderStepped callback; do NOT call multiple times per frame.
function Spring:step(dt)
	local force    = (self.target - self.value) * self.k - self.velocity * self.d
	self.velocity  = self.velocity + force * dt
	self.value     = self.value    + self.velocity * dt
	return self.value
end

-- Returns true when the spring has essentially settled (useful to unregister idle springs).
function Spring:isSettled(tolerance)
	local tol = tolerance or 0.001
	return math.abs(self.value - self.target) < tol and math.abs(self.velocity) < tol
end

return Spring
