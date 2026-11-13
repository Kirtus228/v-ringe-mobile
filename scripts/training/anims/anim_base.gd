class_name TrainAnimBase
extends RefCounted
## Каркас процедурных анимаций тренировки (Этап 3, волна 1; база — Этап 1).
##
## В проекте НЕТ AnimationPlayer/AnimationTree: бойцы и станции строятся кодом.
## Поэтому анимация — процедурные ключи на узлах: антиципация → рабочая фаза →
## impact → follow-through → возврат + дыхание в простое.
##
## Этот класс НИЧЕГО не двигает сам: он считает фазу/вес и шлёт события, а позы
## применяет владелец (training_mode/station) через fighter.freeze_pose() и
## трансформы станции.
##
## Уровни (из VisualConfig.train_anim_level):
##   OFF   — «как до правок»: play() = false, tick() = 0.0, событий нет;
##   BASIC — короткий клип: антиципация → активная фаза → возврат;
##   FULL  — полный: антиципация → active → impact → follow-through → recover
##           + дыхание в простое.
##
## Плавные переходы: при старте клипа выставляется blend 0→1 (CLIP_BLEND с),
## при остановке/финише владелец возвращает позу в idle через freeze_pose(""),
## и пружины рига доводят её сами — «телепорта костей» нет.
##
## Никаких хардкодов амплитуд: длительность/амплитуду задаёт владелец аргументами
## play(), доли фаз — общие константы ниже (единый конфиг каркаса).

enum Level { OFF = 0, BASIC = 1, FULL = 2 }
enum Phase { IDLE = 0, ANTICIPATION = 1, ACTIVE = 2, IMPACT = 3, FOLLOW = 4, RECOVER = 5, MISS = 6 }

const PHASE_NAMES := ["idle", "anticipation", "active", "impact", "follow", "recover", "miss"]

## Доли клипа для BASIC: антиципация → активная фаза → возврат.
const KEYS_BASIC := [0.0, 0.26, 0.46, 1.0]
## Доли для FULL: антиципация → active → impact → follow → recover → конец.
const KEYS_FULL := [0.0, 0.16, 0.34, 0.44, 0.62, 1.0]
## Дыхание в простое: период, с.
const BREATH_PERIOD := 3.2
## Время смешивания старта клипа, с (плавный вход без рывка).
const CLIP_BLEND := 0.10

## Сигналы-хуки (владелец подписывается; при OFF не приходят).
signal phase_changed(phase_name: String)
signal impact_reached()
signal follow_through()
signal missed()
signal finished()

var level: int = Level.OFF
var kind := ""
var station_id := ""
var phase: int = Phase.IDLE
var duration := 0.0
var amplitude := 0.0
var running := false
var t := 0.0
var loops := 0
var blend := 0.0
## Внешняя синхронизация пика: доля клипа, где должен случиться impact
## (-1 — по умолчанию из KEYS_*). Станции могут передать своё окно QTE/такта.
var impact_override := -1.0
var _impact_fired := false
var _phase_fired := {}


## Уровень анимации. OFF жёстко останавливает всё, чтобы поведение было как раньше.
func set_level(value: int) -> void:
    level = clampi(value, Level.OFF, Level.FULL)
    if level == Level.OFF:
        stop()


func is_on() -> bool:
    return level != Level.OFF


func is_playing() -> bool:
    return running


func is_missing() -> bool:
    return running and phase == Phase.MISS


## Запуск клипа. false — если уровень OFF (или плохие аргументы): владелец обязан
## трактовать false как «ничего не делай».
## kind — тип клипа (например "bag"), station_id — кто анимируется, phase — старт.
func play(clip_kind: String, station: String = "", start_phase: String = "anticipation",
        dur: float = -1.0, amp: float = 1.0) -> bool:
    if level == Level.OFF:
        return false
    if clip_kind == "":
        return false
    kind = clip_kind
    station_id = station
    phase = _phase_from_name(start_phase)
    duration = dur if dur > 0.0 else _default_duration()
    amplitude = amp
    t = 0.0
    running = true
    loops = 0
    _impact_fired = false
    _phase_fired = {}
    blend = 0.0
    impact_override = -1.0
    phase_changed.emit(phase_name())
    return true


## Отдельный клип промаха («сорвался»): без эффекта на снаряд.
func play_miss(dur: float = 0.42) -> bool:
    if level == Level.OFF:
        return false
    var ok := play("miss", station_id, "miss", dur, 1.0)
    if ok:
        phase = Phase.MISS
        missed.emit()
    return ok


func stop() -> void:
    if running:
        finished.emit()
    running = false
    t = 0.0
    phase = Phase.IDLE
    blend = 0.0
    kind = ""
    impact_override = -1.0


## Внешняя синхронизация пика: доля клипа (0..1), где должен произойти impact.
func sync_external_impact(fraction: float) -> void:
    impact_override = clampf(fraction, 0.01, 0.98)


## Шаг времени. Вес 0..1 — сколько «включён» клип (0 при OFF/остановке).
func tick(delta: float) -> float:
    if level == Level.OFF or not running:
        return 0.0
    t += delta
    var ratio := clampf(t / maxf(0.0001, duration), 0.0, 1.0)
    blend = clampf(blend + delta / maxf(0.001, CLIP_BLEND), 0.0, 1.0)
    _advance_phase(ratio)
    if t >= duration:
        t = duration
        running = false
        loops += 1
        phase = Phase.IDLE
        finished.emit()
        return 0.0
    return ratio


## Текущий вес без шага времени.
func weight() -> float:
    if level == Level.OFF or not running or duration <= 0.0:
        return 0.0
    return clampf(t / duration, 0.0, 1.0)


## Поза для fighter.freeze_pose: 0..1 вдоль удара (0 — замах/стойка, 1 — возврат).
func pose_phase() -> float:
    if not running and phase == Phase.IDLE:
        return 0.0
    return clampf(t / maxf(0.0001, duration), 0.0, 1.0)


## Какая поза удара соответствует фазе (владелец может переопределить).
func pose_kind() -> String:
    return ""


func phase_name() -> String:
    return PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)]


func phase_fraction() -> float:
    return clampf(t / maxf(0.0001, duration), 0.0, 1.0)


## Ключи фаз для текущего уровня (OFF — пусто).
func key_fractions() -> Array:
    if level == Level.OFF:
        return []
    return KEYS_FULL if level == Level.FULL else KEYS_BASIC


## Доля клипа, где наступает impact (с учётом внешней синхронизации).
func impact_fraction() -> float:
    if impact_override > 0.0:
        return impact_override
    return 0.40 if level == Level.FULL else 0.45


## Дыхание в простое: -1..1, только при FULL и когда клип не играет.
func breath(clock: float) -> float:
    if level != Level.FULL or running:
        return 0.0
    return sin(TAU * clock / maxf(0.01, BREATH_PERIOD))


func describe() -> String:
    var names := ["OFF", "BASIC", "FULL"]
    return "train_anim=%s kind=%s station=%s phase=%s t=%.2f/%.2f amp=%.2f run=%s" % [
        names[clampi(level, 0, 2)], kind, station_id, phase_name(),
        t, duration, amplitude, str(running)]


# ---------------------------------------------------------------- внутреннее

func _default_duration() -> float:
    return 0.42


func _phase_from_name(n: String) -> int:
    match n:
        "anticipation":
            return Phase.ANTICIPATION
        "active":
            return Phase.ACTIVE
        "impact":
            return Phase.IMPACT
        "follow":
            return Phase.FOLLOW
        "recover":
            return Phase.RECOVER
        "miss":
            return Phase.MISS
        _:
            return Phase.ANTICIPATION


## Раздаёт фазовые события по долям клипа (один раз за клип) и сигнал impact.
func _advance_phase(ratio: float) -> void:
    var fracs := key_fractions()
    if fracs.is_empty():
        return
    # границы: anticipation -> active -> impact -> follow -> recover
    var bounds := [0.0, 1.0, 1.0, 1.0, 1.0]
    if level == Level.FULL:
        bounds = [float(fracs[1]), float(fracs[2]), float(fracs[3]), float(fracs[4]),
                float(fracs[5])]
    else:
        bounds = [float(fracs[1]), float(fracs[2]), float(fracs[2]), float(fracs[3]),
                float(fracs[3])]
    var new_phase := Phase.ANTICIPATION
    if ratio >= bounds[1]:
        new_phase = Phase.ACTIVE
    if ratio >= bounds[2]:
        new_phase = Phase.IMPACT
    if ratio >= bounds[3]:
        new_phase = Phase.FOLLOW
    if ratio >= bounds[4]:
        new_phase = Phase.RECOVER
    if new_phase != phase:
        phase = new_phase
        phase_changed.emit(phase_name())
        if phase == Phase.FOLLOW and not _phase_fired.get("follow", false):
            _phase_fired["follow"] = true
            follow_through.emit()
    # impact — по доле не зависящей от «ширины» phase-таблицы
    if not _impact_fired and ratio >= impact_fraction():
        _impact_fired = true
        impact_reached.emit()

# ---------------------------------------------------------------- тренировочные ключи
## Ключи позы текущего кадра: пусто — клип использует обычные punch-позы.
func train_pose() -> Dictionary:
    if level == Level.OFF or not running:
        return {}
    return train_pose_at(phase_fraction())


## Ключи позы на произвольной доле клипа 0..1 (переопределяют клипы).
func train_pose_at(_t: float) -> Dictionary:
    return {}


## Линейная интерполяция набора ключей позы: keys = [[t, {..}], ...].
func interp_pose_keys(keys: Array, t: float) -> Dictionary:
    if keys.is_empty():
        return {}
    var tv := clampf(t, 0.0, 1.0)
    var prev: Dictionary = keys[0][1]
    for i in range(1, keys.size()):
        var kt := float(keys[i][0])
        var cur: Dictionary = keys[i][1]
        if tv <= kt:
            var t0 := float(keys[i - 1][0])
            var a := 0.0 if kt <= t0 else (tv - t0) / (kt - t0)
            var out := {}
            for key in prev.keys():
                # v71q: строковые ключи (support) НЕ интерполируем числом —
                # иначе float("plank") превращался в 0.0 и риг терял режим опоры.
                var pv: Variant = prev[key]
                var cv: Variant = cur.get(key, pv)
                if typeof(pv) == TYPE_STRING or typeof(cv) == TYPE_STRING:
                    out[key] = cv
                else:
                    out[key] = lerpf(float(pv), float(cv), a)
            for key in cur.keys():
                if not out.has(key):
                    var cv2: Variant = cur[key]
                    out[key] = cv2 if typeof(cv2) == TYPE_STRING else lerpf(
                            float(cv2), float(cv2), a)
            return out
        prev = cur
    return prev.duplicate()
