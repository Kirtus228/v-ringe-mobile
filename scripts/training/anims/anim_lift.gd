class_name TrainAnimLift
extends TrainAnimBase
## v71q: QTE-ЖИМ ЛЁЖА — gym/barbell и basement/homemade_bar.
## Источники: https://humankinetics.com/AcuCustom/Sitename/DAM/018/Barbell_and_Bench_Chest_Press.pdf
##            https://www.mensfitness.com/training/how-bench-press
## Фазы: штанга у груди (локти под ~45°, лопатки сведены, стопы на полу) →
## жим вверх до прямых рук над грудью → контролируемое опускание.
## homemade_bar — та же техника, но тяжелее/дольше (больше тряски, см. vibration).
##
## v71q: «лёжа» = таз развёрнут почти горизонтально (hip_pitch ~1.18), корпус
## догоризонталивается (torso_pitch), бёдра поднимаются к полу-«мостику»,
## локти сгибаются к груди. Для API task-44: support="bench", body_y.

const DUR_BARBELL_FULL := 0.58
const DUR_BARBELL_BASIC := 0.46
const DUR_HOMEMADE_FULL := 0.78
const DUR_HOMEMADE_BASIC := 0.62
const DUR_MISS := 0.45

## Поза бойца на фазах: наклон/захват — корпусной удар (низко), подъём — кросс вверх.
const POSE_APPROACH := "body_upper"
const POSE_LIFT := "upper"

var _homemade := false
var _pose_kind := POSE_LIFT


func play_hit(loc_id: String, station: String, window_frac: float = 0.5) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _homemade = station == "homemade_bar"
    _pose_kind = POSE_LIFT
    var dur := DUR_BARBELL_FULL
    if _homemade:
        dur = DUR_HOMEMADE_FULL if level == Level.FULL else DUR_HOMEMADE_BASIC
    else:
        dur = DUR_BARBELL_FULL if level == Level.FULL else DUR_BARBELL_BASIC
    if not play("lift", station, "approach", dur, 1.0):
        return false
    sync_external_impact(lerpf(0.52, 0.64, clampf(window_frac, 0.0, 1.0)))
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _homemade = station == "homemade_bar"
    return play_miss(DUR_MISS)


## Прогресс подъёма снаряда 0..1 для текущей доли клипа (для TrainingStation).
func lift_progress() -> float:
    var ratio := phase_fraction()
    if ratio <= 0.24:
        return 0.0
    if ratio >= 0.72:
        return 0.0
    if ratio <= 0.46:
        return (ratio - 0.24) / 0.22
    if ratio <= 0.60:
        return 1.0
    return 1.0 - (ratio - 0.60) / 0.12


## Тряска под нагрузкой: 0..1, максимальна на lockout.
func vibration() -> float:
    var ratio := phase_fraction()
    if ratio < 0.40 or ratio > 0.66:
        return 0.0
    var v := sin((ratio - 0.40) / 0.26 * PI)
    return clampf(v, 0.0, 1.0) * (1.6 if _homemade else 1.0)


func is_homemade() -> bool:
    return _homemade


func pose_kind() -> String:
    return _pose_kind


# ---------------------------------------------------------------- моторные ключи
## Жим лёжа: спина на скамье (горизонтально), стопы на полу, локти у груди в
## нижней точке; в верхней — руки выпрямлены над грудью.
func train_pose_at(t: float) -> Dictionary:
    # v71s2: отладочные фазы кадра (VRINGE_ANIM_SHOT=lift|lockout|lower) — демо
    # передаёт фиксированный t; в игре env пуст и работает обычная интерполяция.
    var ph := OS.get_environment("VRINGE_ANIM_SHOT").strip_edges().to_lower()
    var tt := t
    if ph == "lift" or ph == "press":
        tt = 0.36
    elif ph == "lockout" or ph == "top":
        tt = 0.50
    elif ph == "lower" or ph == "bottom":
        tt = 0.80
    var keys := [
        [0.00, {"hip_height": -0.10, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh_l": -0.30, "thigh_r": -0.30, "knee_l": 1.10, "knee_r": 1.10,
            "foot": 0.24,
            "shoulder_l": -1.45, "shoulder_r": -1.45, "elbow_l": 1.55, "elbow_r": 1.55,
            "head_pitch": 0.10, "body_pitch": 1.45, "support_h": 0.45,
            "support": "bench"}],
        [0.30, {"hip_height": -0.10, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh_l": -0.30, "thigh_r": -0.30, "knee_l": 1.10, "knee_r": 1.10,
            "foot": 0.24,
            "shoulder_l": -1.50, "shoulder_r": -1.50, "elbow_l": 0.95, "elbow_r": 0.95,
            "head_pitch": 0.10, "body_pitch": 1.45, "support_h": 0.45,
            "support": "bench"}],
        [0.50, {"hip_height": -0.10, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh_l": -0.30, "thigh_r": -0.30, "knee_l": 1.10, "knee_r": 1.10,
            "foot": 0.24,
            "shoulder_l": -1.55, "shoulder_r": -1.55, "elbow_l": 0.18, "elbow_r": 0.18,
            "head_pitch": 0.08, "body_pitch": 1.45, "support_h": 0.45,
            "support": "bench"}],
        [0.78, {"hip_height": -0.10, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh_l": -0.30, "thigh_r": -0.30, "knee_l": 1.10, "knee_r": 1.10,
            "foot": 0.24,
            "shoulder_l": -1.50, "shoulder_r": -1.50, "elbow_l": 0.95, "elbow_r": 0.95,
            "head_pitch": 0.10, "body_pitch": 1.45, "support_h": 0.45,
            "support": "bench"}],
        [1.00, {"hip_height": -0.10, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh_l": -0.30, "thigh_r": -0.30, "knee_l": 1.10, "knee_r": 1.10,
            "foot": 0.24,
            "shoulder_l": -1.45, "shoulder_r": -1.45, "elbow_l": 1.55, "elbow_r": 1.55,
            "head_pitch": 0.10, "body_pitch": 1.45, "support_h": 0.45,
            "support": "bench"}]]
    return interp_pose_keys(keys, tt)
