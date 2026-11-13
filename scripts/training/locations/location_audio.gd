extends RefCounted
## Процедурные ambient-звуки тренировочных локаций (Этап 5).
##
## В проекте нет внешних аудио-ассетов, поэтому каждый фон синтезируется в
## AudioStreamWAV прямо в рантайме: шум + низкие синусы + короткие события
## (птицы, капли, скрип). Всё детерминировано (seed от имени локации), поэтому
## один и тот же фон в каждом прогоне. Громкости/время цикла — константы ниже.
##
## Точка входа: `LocationAudio.make("gym")` → AudioStreamWAV (loop forward) или null.

## Частота дискретизации: 11 кГц хватает для шума и низких тонов, синтез быстрый.
const RATE := 11025
## Длительность цикла, с. Все тона подгоняются под целое число периодов.
const LOOP_SECONDS := 4.0
## Амплитуды: сумма ≤ 1.0, иначе клиппинг (и щелчки на стыке петли).
const NOISE_LEVEL := {"gym": 0.055, "park": 0.045, "dojo": 0.020,
        "roof": 0.090, "basement": 0.030}
const TONE_LEVEL := {"gym": 0.030, "park": 0.010, "dojo": 0.012,
        "roof": 0.020, "basement": 0.028}
## Частоты «гула» локации, Гц.
const HUM_HZ := {"gym": 60.0, "park": 0.0, "dojo": 0.0,
        "roof": 45.0, "basement": 52.0}
## Максимальная громкость плеера, дБ (плеер 3D, дальше — затухание по дистанции).
const VOLUME_DB := -16.0
const MAX_DISTANCE := 26.0
const UNIT_SIZE := 6.0


## Основной вход: имя локации → зацикленный поток или null для неизвестной.
static func make(loc_id: String) -> AudioStreamWAV:
    match loc_id:
        "gym", "park", "dojo", "roof", "basement":
            return _synth(loc_id)
        _:
            return null


## Синтез одного фона. Для события (птицы/капли/скрип) заранее считаем тайминги,
## чтобы они не попадали на стык петли (иначе будет щелчок на склейке).
static func _synth(loc_id: String) -> AudioStreamWAV:
    var n := int(LOOP_SECONDS * float(RATE))
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(loc_id)
    var data := PackedByteArray()
    data.resize(n * 2)
    var noise_lvl := float(NOISE_LEVEL.get(loc_id, 0.03))
    var tone_lvl := float(TONE_LEVEL.get(loc_id, 0.02))
    var hum := float(HUM_HZ.get(loc_id, 0.0))
    # низкочастотный фильтр для «ветра»: один полюс, коэффициент от локации
    var lp := 0.0
    var lp_k := 0.02
    match loc_id:
        "park":
            lp_k = 0.008
        "roof":
            lp_k = 0.012
        "dojo":
            lp_k = 0.004
        "basement":
            lp_k = 0.010
        _:
            lp_k = 0.006
    # события: список {t, type, f0, f1, dur}
    var events: Array = []
    match loc_id:
        "park":
            for i in 6:
                events.append({"t": 0.30 + float(i) * 0.58 + rng.randf() * 0.12,
                        "f0": rng.randf_range(2100.0, 2500.0),
                        "f1": rng.randf_range(2900.0, 3400.0),
                        "dur": rng.randf_range(0.08, 0.14), "amp": 0.10})
        "dojo":
            for i in 3:
                events.append({"t": 0.50 + float(i) * 1.10,
                        "f0": rng.randf_range(140.0, 190.0),
                        "f1": rng.randf_range(90.0, 120.0),
                        "dur": rng.randf_range(0.20, 0.32), "amp": 0.06})
        "basement":
            var t := 0.20
            while t < LOOP_SECONDS - 0.40:
                events.append({"t": t, "f0": rng.randf_range(700.0, 950.0),
                        "f1": rng.randf_range(300.0, 450.0),
                        "dur": rng.randf_range(0.06, 0.11), "amp": 0.12})
                t += rng.randf_range(0.55, 1.10)
        "roof":
            for i in 4:
                events.append({"t": 0.25 + float(i) * 0.95,
                        "f0": rng.randf_range(500.0, 800.0),
                        "f1": rng.randf_range(300.0, 400.0),
                        "dur": 0.18, "amp": 0.03})
        _:
            pass
    var loop_f := 1.0 / float(n)  # шаг сетки частот для бесшовной петли
    for i in n:
        var t := float(i) / float(RATE)
        # детерминированный белый шум
        var w := rng.randf_range(-1.0, 1.0)
        lp += (w - lp) * lp_k
        var s := lp * noise_lvl * 6.0
        # порывы ветра: медленная модуляция (целое число циклов на петлю)
        var gust := 0.65 + 0.35 * sin(TAU * 2.0 * t / LOOP_SECONDS)
        s *= gust
        if hum > 0.0:
            # округляем частоту до сетки петли, чтобы фаза на стыке совпала
            var h: float = round(hum / loop_f) * loop_f
            s += sin(TAU * h * t) * tone_lvl
            s += sin(TAU * h * 2.0 * t) * tone_lvl * 0.35
        for ev in events:
            var et0 := float(ev["t"])
            var et1 := et0 + float(ev["dur"])
            if t >= et0 and t < et1:
                var k := (t - et0) / float(ev["dur"])
                var f := lerpf(float(ev["f0"]), float(ev["f1"]), k)
                var env := sin(PI * k)  # плавное появление/затухание
                s += sin(TAU * f * (t - et0)) * float(ev["amp"]) * env
        var v := int(clampf(s, -1.0, 1.0) * 32000.0)
        data[i * 2] = v & 0xFF
        data[i * 2 + 1] = (v >> 8) & 0xFF
    var st := AudioStreamWAV.new()
    st.format = AudioStreamWAV.FORMAT_16_BITS
    st.mix_rate = RATE
    st.stereo = false
    st.data = data
    st.loop_mode = AudioStreamWAV.LOOP_FORWARD
    st.loop_begin = 0
    st.loop_end = n
    return st


## Готовый плеер 3D для локации: позиция и громкость — константы класса.
static func make_player(loc_id: String, parent: Node3D) -> AudioStreamPlayer3D:
    var stream := make(loc_id)
    if stream == null:
        return null
    var p := AudioStreamPlayer3D.new()
    p.name = "AmbientAudio"
    p.stream = stream
    p.volume_db = VOLUME_DB
    p.max_distance = MAX_DISTANCE
    p.unit_size = UNIT_SIZE
    p.position = Vector3(0.0, 1.6, 0.0)
    p.autoplay = true
    parent.add_child(p)
    return p

