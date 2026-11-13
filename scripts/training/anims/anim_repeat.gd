class_name TrainAnimRepeat
extends TrainAnimBase
## v71q: RHYTHM-ПОВТОРЫ — park/pushups и dojo/shadow.
##
## pushups — техника отжиманий по источникам:
##   https://sweat.com/blogs/fitness/how-to-do-a-pushup
##   https://read.womenshealthmag.co.uk/2025/07/25/struggling-to-nail-your-first-full-push-up-a-strength-coach-reveals-3-tips-to-achieving-it/content.html
##   Фазы: планка (руки прямые, ладони под плечами, тело одной линией, пресс/ягодицы
##   напряжены) → опускание (локти назад ~45° к корпусу, грудь к полу, голову не
##   «клюём») → жим вверх, толкая пол.
## shadow — бой с тенью: punch-позы (jab/cross/hook/upper); здесь ключей нет.
##
## v71q: «лежачее» тело теперь задаётся большим наклоном таза (hip_pitch ~1.2) и
## корпуса (torso_pitch), ноги прямые, носки на полу; руки выпрямлены вниз
## (shoulder ≈ −1.35), а в нижней точке локти сгибаются назад (elbow ~1.5).
## Для API рига task-44 добавлены support="plank" и body_y (подъём над полом).

const DUR_PUSHUP_FULL := 0.60
const DUR_PUSHUP_BASIC := 0.50
const DUR_SHADOW_FULL := 0.45
const DUR_SHADOW_BASIC := 0.38
const DUR_MISS := 0.35
const SHADOW_KINDS := ["jab", "cross", "lhook", "rhook", "upper"]

var _shadow := false
var _combo := 0


func play_hit(loc_id: String, station: String, beat: float = -1.0) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _shadow = station == "shadow"
    var dur := 0.0
    if _shadow:
        dur = DUR_SHADOW_FULL if level == Level.FULL else DUR_SHADOW_BASIC
        _combo = (_combo + 1) % SHADOW_KINDS.size()
    else:
        dur = DUR_PUSHUP_FULL if level == Level.FULL else DUR_PUSHUP_BASIC
    if beat > 0.0:
        dur = clampf(beat, 0.22, 1.4)
    if not play("repeat", station, "active", dur, 1.0):
        return false
    sync_external_impact(0.50)
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    return play_miss(DUR_MISS)


func pose_kind() -> String:
    if _shadow:
        return String(SHADOW_KINDS[_combo])
    return "body_upper"


## Прогресс отжимания 0..1 (0 — вверху, 1 — внизу).
func pushup_progress() -> float:
    var r := phase_fraction()
    if r < 0.5:
        return r * 2.0
    return (1.0 - r) * 2.0

# ---------------------------------------------------------------- моторные ключи
## Планка: таз/корпус почти горизонтально, ноги прямые, носки на полу, руки
## выпрямлены вниз; опускание — локти назад, грудь к полу; жим — возврат.
func train_pose_at(t: float) -> Dictionary:
    if _shadow:
        return {}
    return interp_pose_keys([
        [0.00, {"hip_height": -0.05, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh": 0.02, "knee": 0.10, "foot": -0.28,
            "shoulder_l": -0.15, "shoulder_r": -0.15, "elbow_l": 0.12, "elbow_r": 0.12,
            "head_pitch": 0.20, "body_pitch": -1.45,
            "support": "plank"}],
        [0.24, {"hip_height": -0.12, "hip_pitch": 0.10, "torso_pitch": 0.12,
            "thigh": 0.02, "knee": 0.12, "foot": -0.28,
            "shoulder_l": -0.12, "shoulder_r": -0.12, "elbow_l": 0.80, "elbow_r": 0.80,
            "head_pitch": 0.20, "body_pitch": -1.45,
            "support": "plank"}],
        [0.50, {"hip_height": -0.18, "hip_pitch": 0.12, "torso_pitch": 0.14,
            "thigh": 0.02, "knee": 0.14, "foot": -0.30,
            "shoulder_l": -0.08, "shoulder_r": -0.08, "elbow_l": 1.55, "elbow_r": 1.55,
            "head_pitch": 0.18, "body_pitch": -1.45,
            "support": "plank"}],
        [0.78, {"hip_height": -0.12, "hip_pitch": 0.10, "torso_pitch": 0.12,
            "thigh": 0.02, "knee": 0.12, "foot": -0.28,
            "shoulder_l": -0.12, "shoulder_r": -0.12, "elbow_l": 0.80, "elbow_r": 0.80,
            "head_pitch": 0.20, "body_pitch": -1.45,
            "support": "plank"}],
        [1.00, {"hip_height": -0.05, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh": 0.02, "knee": 0.10, "foot": -0.28,
            "shoulder_l": -0.15, "shoulder_r": -0.15, "elbow_l": 0.12, "elbow_r": 0.12,
            "head_pitch": 0.20, "body_pitch": -1.45,
            "support": "plank"}]], t)
