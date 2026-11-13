extends RefCounted
## Процедурный ambient арен (Этап 6): без внешних ассетов, синтез в AudioStreamWAV.
##
## Толпа/ветер/пар/металл/море/город/огонь — детерминированный шум + низкие тона,
## зациклено вперёд. Точка входа: ArenaAudio.make(kind) → AudioStreamWAV или null.
## Всё под флагами визуала: при visual_level=OFF звук не создаётся вообще.

## Частота: 11 кГц хватает для шумов и низких тонов, синтез быстрый.
const RATE := 11025
const LOOP_SECONDS := 4.0
const VOLUME_DB := -19.0
const MAX_DISTANCE := 30.0
## Шум/тон/гул на тип фона.
const NOISE := {"crowd": 0.050, "wind": 0.060, "steam": 0.075, "metal": 0.025,
        "sea": 0.055, "city": 0.035, "fire": 0.070}
const TONE := {"crowd": 0.022, "wind": 0.012, "steam": 0.020, "metal": 0.030,
        "sea": 0.018, "city": 0.014, "fire": 0.016}
const HUM := {"crowd": 58.0, "wind": 0.0, "steam": 92.0, "metal": 140.0,
        "sea": 41.0, "city": 50.0, "fire": 34.0}


static func make(kind: String) -> AudioStreamWAV:
    if not NOISE.has(kind):
        return null
    var n := int(LOOP_SECONDS * float(RATE))
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("arena_" + kind)
    var noise_lvl := float(NOISE.get(kind, 0.04))
    var tone_lvl := float(TONE.get(kind, 0.02))
    var hum := float(HUM.get(kind, 0.0))
    var lp := 0.0
    var lp_k := 0.02
    match kind:
        "wind", "sea":
            lp_k = 0.008
        "city", "crowd":
            lp_k = 0.03
        "steam":
            lp_k = 0.06
        "fire":
            lp_k = 0.05
        _:
            lp_k = 0.08
    var data := PackedByteArray()
    data.resize(n * 2)
    var phase := 0.0
    var prev_noise := 0.0
    for i in n:
        var x := float(i) / float(n)
        # «дыхание» амплитуды: целые периоды на длине петли
        var breathe := 0.72 + 0.28 * sin(x * TAU * 2.0)
        var white := rng.randf_range(-1.0, 1.0)
        lp += (white - lp) * lp_k
        var nz := (white * 0.35 + lp * 0.65) * noise_lvl * breathe
        var tone := 0.0
        if hum > 0.0:
            phase += TAU * hum / float(RATE)
            tone = sin(phase) * tone_lvl
        # короткие события: у металла «удары», у пара — шипение
        var ev := 0.0
        if kind == "metal" and fmod(x * 4.0, 1.0) < 0.06:
            ev = sin(x * TAU * 8.0) * 0.02
        elif kind == "steam" and fmod(x * 3.0, 1.0) < 0.12:
            ev = white * 0.02
        elif kind == "fire" and rng.randf() < 0.002:
            ev = white * 0.05
        var v := clampf(nz + tone + ev, -0.95, 0.95)
        var s := int(v * 32767.0)
        data[i * 2] = s & 0xFF
        data[i * 2 + 1] = (s >> 8) & 0xFF
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = RATE
    stream.stereo = false
    stream.data = data
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = n
    return stream
