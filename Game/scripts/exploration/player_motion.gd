class_name ExplorationPlayerMotion
extends RefCounted
const WALK_SPEED := 188.0 # Original 235 reduced by 20%.
const RUN_MULTIPLIER := 1.5
const BODY_SIZE := Vector2(32,64)
const MAX_STAMINA := 100.0
const DRAIN := 25.0
const REGEN := 20.0
var stamina := MAX_STAMINA
var exhausted := false
var running := false
var moving := false
var slow_remaining := 0.0
var slow_multiplier := 0.8
var recovery_delay := 0.0

func step(delta: float, axis: float, shift: bool) -> float:
	delta = maxf(delta,0)
	slow_remaining = maxf(0,slow_remaining-delta)
	moving = not is_zero_approx(axis)
	if not shift and stamina >= 25: exhausted = false
	running = moving and shift and not exhausted and stamina > 0
	if running:
		stamina = maxf(0,stamina-DRAIN*delta)
		recovery_delay = 0.6
		if stamina <= 0: exhausted = true
	else:
		recovery_delay = maxf(0,recovery_delay-delta)
		if recovery_delay <= 0: stamina = minf(MAX_STAMINA,stamina+REGEN*delta)
	return axis * WALK_SPEED * (RUN_MULTIPLIER if running else 1.0) * (slow_multiplier if slow_remaining > 0 else 1.0)

func noise_radius() -> float:
	return BODY_SIZE.y*(1.5 if running else 0.5) if moving else 0.0

func apply_slow(seconds: float = 2.0, multiplier: float = 0.8) -> void:
	slow_remaining = maxf(slow_remaining,seconds)
	slow_multiplier = multiplier
