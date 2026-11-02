class_name SoundSynth
extends RefCounted

## Synthesised kitchen sounds, built once as AudioStreamWAV buffers: the
## looping beds the pot and stove play (sizzle, crackle, boiling, gas) and
## the one-shots of the hands (the spark, the crank's ratchet, the knock of
## the blade on the board, and the five bite layers). They are physical in
## the way that matters for play: KitchenAudio drives their loudness and
## pitch from the simulation, so a hard sizzle means hard steaming. Recorded
## samples can replace any of them through KitchenAudio's exported slots.
##
## Everything is deterministic (seeded noise), mono, 16-bit.

const MIX_RATE: int = 22050

enum Bed { SIZZLE, CRACKLE, BOIL, GAS, POUR }
enum Shot { SPARK, RATCHET, KNOCK }

static func bed(kind: Bed) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + kind
	var seconds: float = 1.6
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * MIX_RATE))
	match kind:
		Bed.SIZZLE:
			# Fine, bright frying hiss with a restless flutter.
			var low: float = 0.0
			var flutter: float = 0.5
			for i in samples.size():
				var white: float = rng.randf_range(-1.0, 1.0)
				low += 0.35 * (white - low)
				if i % 200 == 0:
					flutter = clampf(flutter + rng.randf_range(-0.25, 0.25), 0.35, 1.0)
				samples[i] = (white - low) * 0.6 * flutter
		Bed.CRACKLE:
			# Popping steam bubbles bursting through hot oil.
			_scatter_pops(samples, rng, 520.0, 0.0012, 0.0035, 4200.0)
		Bed.BOIL:
			# Big bubbles breaking at a rolling boil: short rising blips.
			var t: int = 0
			while t < samples.size():
				var length: int = int(rng.randf_range(0.018, 0.04) * MIX_RATE)
				var pitch: float = rng.randf_range(160.0, 420.0)
				var amplitude: float = rng.randf_range(0.25, 0.6)
				for j in length:
					if t + j >= samples.size():
						break
					var progress: float = float(j) / length
					var phase: float = TAU * pitch * (1.0 + progress * 0.8) * j / MIX_RATE
					samples[t + j] += sin(phase) * amplitude * (1.0 - progress) * (1.0 - progress)
				t += int(rng.randf_range(0.012, 0.05) * MIX_RATE)
		Bed.GAS:
			# Soft, steady roar of the burner.
			var low: float = 0.0
			var lower: float = 0.0
			for i in samples.size():
				var white: float = rng.randf_range(-1.0, 1.0)
				low += 0.12 * (white - low)
				lower += 0.02 * (white - lower)
				samples[i] = (low - lower) * 1.6
		Bed.POUR:
			# Liquid running from a spout: a burbling, low gurgle.
			var low: float = 0.0
			for i in samples.size():
				var white: float = rng.randf_range(-1.0, 1.0)
				low += 0.05 * (white - low)
				var glug: float = 0.6 + 0.4 * sin(TAU * 7.0 * i / MIX_RATE + sin(TAU * 1.3 * i / MIX_RATE) * 2.0)
				samples[i] = low * 3.0 * glug
	_fade_loop_seam(samples)
	return _to_wav(samples, true)

static func shot(kind: Shot) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + kind
	var samples := PackedFloat32Array()
	match kind:
		Shot.SPARK:
			samples.resize(int(0.03 * MIX_RATE))
			_ring(samples, 0, 5200.0, 0.004, 0.9, rng)
		Shot.RATCHET:
			samples.resize(int(0.04 * MIX_RATE))
			_ring(samples, 0, 1900.0, 0.008, 0.7, rng)
			_ring(samples, int(0.004 * MIX_RATE), 3100.0, 0.004, 0.3, rng)
		Shot.KNOCK:
			# The blade meeting the board through the food: a woody thock.
			samples.resize(int(0.12 * MIX_RATE))
			_ring(samples, 0, 190.0, 0.035, 0.8, rng)
			_ring(samples, 0, 900.0, 0.01, 0.35, rng)
	return _to_wav(samples, false)

## One layer of a bite (see BiteSound.Layer).
static func bite(layer: BiteSound.Layer) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3000 + layer
	var samples := PackedFloat32Array()
	samples.resize(int(0.32 * MIX_RATE))
	match layer:
		BiteSound.Layer.CRISP:
			# A dry crust shattering: a dense, bright burst of fractures.
			_scatter_pops(samples, rng, 2400.0, 0.0006, 0.002, 5200.0, 0.13)
		BiteSound.Layer.CRUNCH:
			# Raw, firm flesh splitting: fewer, deeper fractures and a thud.
			_scatter_pops(samples, rng, 700.0, 0.002, 0.006, 1600.0, 0.16)
			_ring(samples, 0, 140.0, 0.04, 0.5, rng)
		BiteSound.Layer.SOFT:
			# Teeth closing through something tender: a muffled thud.
			_ring(samples, 0, 110.0, 0.05, 0.7, rng)
			_muffled_noise(samples, rng, 0, int(0.07 * MIX_RATE), 0.04, 0.25)
		BiteSound.Layer.SQUELCH:
			# Grease or mush giving way: a wet, sliding low sound.
			var low: float = 0.0
			var length: int = int(0.22 * MIX_RATE)
			for i in length:
				var progress: float = float(i) / length
				var white: float = rng.randf_range(-1.0, 1.0)
				low += 0.08 * (white - low)
				var glide: float = sin(TAU * lerpf(320.0, 110.0, progress) * i / MIX_RATE)
				samples[i] = (low * 2.0 + glide * 0.35) * sin(progress * PI) * (0.7 + 0.3 * sin(TAU * 23.0 * progress))
		BiteSound.Layer.CHEW:
			# Leathery food worked between the teeth: soft, repeated thuds.
			for bite_index in 3:
				var start: int = int((0.02 + bite_index * 0.09) * MIX_RATE)
				_ring(samples, start, 95.0 + bite_index * 10.0, 0.03, 0.45, rng)
				_muffled_noise(samples, rng, start, int(0.05 * MIX_RATE), 0.05, 0.15)
	return _to_wav(samples, false)

## Random clicks, each a short decaying burst of filtered noise. With
## `span_s` they thin out over that span, as a fracturing crust does.
static func _scatter_pops(
		samples: PackedFloat32Array, rng: RandomNumberGenerator, per_second: float,
		shortest_s: float, longest_s: float, brightness_hz: float, span_s: float = -1.0) -> void:
	var limit: int = samples.size() if span_s <= 0.0 else mini(int(span_s * MIX_RATE), samples.size())
	var smoothing: float = clampf(TAU * brightness_hz / MIX_RATE, 0.01, 1.0)
	var i: int = 0
	while i < limit:
		var density: float = per_second
		if span_s > 0.0:
			density *= 1.0 - float(i) / limit
		i += maxi(int(-log(maxf(rng.randf(), 1e-6)) / maxf(density, 1.0) * MIX_RATE), 1)
		if i >= limit:
			break
		var length: int = int(rng.randf_range(shortest_s, longest_s) * MIX_RATE)
		var amplitude: float = rng.randf_range(0.2, 1.0)
		var low: float = 0.0
		for j in length:
			if i + j >= samples.size():
				break
			var white: float = rng.randf_range(-1.0, 1.0)
			low += smoothing * (white - low)
			samples[i + j] += (white - low * 0.5) * amplitude * exp(-5.0 * j / length)

## A struck resonance: a decaying sine with a noisy attack.
static func _ring(
		samples: PackedFloat32Array, start: int, frequency: float, decay_s: float,
		amplitude: float, rng: RandomNumberGenerator) -> void:
	var length: int = mini(int(decay_s * 6.0 * MIX_RATE), samples.size() - start)
	for j in length:
		var t: float = float(j) / MIX_RATE
		var envelope: float = exp(-t / decay_s)
		var attack: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.0008)
		samples[start + j] += (sin(TAU * frequency * t) + attack * 0.5) * envelope * amplitude

static func _muffled_noise(
		samples: PackedFloat32Array, rng: RandomNumberGenerator, start: int, length: int,
		smoothing: float, amplitude: float) -> void:
	var low: float = 0.0
	for j in mini(length, samples.size() - start):
		low += smoothing * (rng.randf_range(-1.0, 1.0) - low)
		samples[start + j] += low * amplitude * 6.0 * sin(PI * float(j) / length)

## Crossfades the end of a loop into its start so it repeats without a
## click.
static func _fade_loop_seam(samples: PackedFloat32Array) -> void:
	var fade: int = int(0.05 * MIX_RATE)
	var size: int = samples.size()
	for j in fade:
		var weight: float = float(j) / fade
		samples[j] = samples[j] * weight + samples[size - fade + j] * (1.0 - weight)
	samples.resize(size - fade)

static func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var peak: float = 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	var gain: float = 0.9 / peak if peak > 0.0 else 0.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
