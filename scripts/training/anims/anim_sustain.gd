class_name TrainAnimSustain
extends TrainAnimBase
## v71q: HOLD — gym/treadmill (бег) и roof/climb (канат).
##
## Бег на дорожке (https://www.mensfitness.com/training/perfect-running-form):
##   корпус чуть вперёд, колено ведёт вперёд, стопа ставится под центром, руки
##   согнуты ~90° и качаются в ПРОТИВОХОД ногам, плечи расслаблены.
## Канат (https://www.climbing.com/skills/walking-the-rope/):
##   вис на прямых руках, попеременная тяга: одна рука тянет (локоть вниз),
##   другая выпрямляется; ноги попеременно подтягиваются/сгибаются.
##
## Цикл: run — 0.46 с, climb — 0.80 с (ускоряется speed_scale).

const RUN_CYCLE := 0.46
const CLIMB_CYCLE := 0.80
const DUR_MISS := 0.40

## Скорость цикла (для бега зависит от множителя пройденного пути/времени).
var speed_scale := 1.0
var _climb := false
var _pose := ""


func start_hold(loc_id: String, station: String, speed: float = 1.0) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _climb = station == "climb"
    speed_scale = clampf(speed, 0.4, 2.5)
    _pose = ""
    var dur := (CLIMB_CYCLE if _climb else RUN_CYCLE) / speed_scale
    if not play("sustain", station, "active", dur, 1.0):
        return false
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    return play_miss(DUR_MISS)


## Прогресс текущего цикла 0..1 (для полосы натяжения/шага).
func cycle_progress() -> float:
    return phase_fraction()


## Для лазания: 0 — захват, 0.5 — подъём, 1 — фиксация (дальше цикл повторяется).
func climb_progress() -> float:
    var r := phase_fraction()
    if r < 0.35:
        return r / 0.35 * 0.5
    if r < 0.80:
        return 0.5 + (r - 0.35) / 0.45 * 0.5
    return 1.0


func is_climb() -> bool:
    return _climb


## v71q: отладочные кадры ставят позу без start_hold — им нужен явный режим
## «канат», иначе train_pose_at отдаёт беговой цикл (боец стоит на полу).
func debug_climb(on: bool) -> void:
    _climb = on


func pose_kind() -> String:
    return _pose

# ---------------------------------------------------------------- моторные ключи
func train_pose_at(t: float) -> Dictionary:
    if _climb:
        return _climb_pose(t)
    return _run_pose(t)


## Канат: висим на прямых руках (shoulder −1.78), одна рука тянет (elbow ~1.9),
## другая выпрямляется; ноги попеременно подтягиваются.
func _climb_pose(t: float) -> Dictionary:
    return interp_pose_keys([
        [0.00, {"hip_height": 0.22, "hip_pitch": 0.02, "torso_pitch": 0.02,
            "thigh_l": -0.05, "thigh_r": -0.02, "knee_l": 0.30, "knee_r": 0.22,
            "foot": 0.10,
            "shoulder_l": -1.78, "shoulder_r": -1.78, "elbow_l": 0.08, "elbow_r": 0.08,
            "head_pitch": -0.05, "body_pitch": 0.02, "support_h": 2.90,
            "support": "hang"}],
        [0.28, {"hip_height": 0.26, "hip_pitch": 0.04, "torso_pitch": 0.04,
            "thigh_l": 0.30, "thigh_r": -0.10, "knee_l": 1.05, "knee_r": 0.24,
            "foot": 0.10,
            "shoulder_l": -1.32, "shoulder_r": -1.60, "elbow_l": 1.85, "elbow_r": 0.30,
            "head_pitch": -0.10, "body_pitch": 0.04, "support_h": 2.90,
            "support": "hang"}],
        [0.56, {"hip_height": 0.26, "hip_pitch": 0.04, "torso_pitch": 0.04,
            "thigh_l": -0.10, "thigh_r": 0.30, "knee_l": 0.24, "knee_r": 1.05,
            "foot": 0.10,
            "shoulder_l": -1.60, "shoulder_r": -1.32, "elbow_l": 0.30, "elbow_r": 1.85,
            "head_pitch": -0.10, "body_pitch": 0.04, "support_h": 2.90,
            "support": "hang"}],
        [1.00, {"hip_height": 0.22, "hip_pitch": 0.02, "torso_pitch": 0.02,
            "thigh_l": -0.05, "thigh_r": -0.02, "knee_l": 0.30, "knee_r": 0.22,
            "foot": 0.10,
            "shoulder_l": -1.78, "shoulder_r": -1.78, "elbow_l": 0.08, "elbow_r": 0.08,
            "head_pitch": -0.05, "body_pitch": 0.02, "support_h": 2.90,
            "support": "hang"}]], t)


## Бег: колено вперёд, стопа под центром, руки ~90° в противоход ногам.
func _run_pose(t: float) -> Dictionary:
    return interp_pose_keys([
        [0.00, {"hip_height": 0.02, "hip_pitch": 0.10, "torso_pitch": 0.22,
            "thigh_l": 0.85, "thigh_r": -0.45, "knee_l": 0.95, "knee_r": 1.25,
            "foot_l": -0.15, "foot_r": 0.25,
            "shoulder_l": 0.55, "shoulder_r": -0.55, "elbow_l": 1.45, "elbow_r": 1.45,
            "head_pitch": 0.04, "support": "floor"}],
        [0.25, {"hip_height": 0.08, "hip_pitch": 0.10, "torso_pitch": 0.22,
            "thigh_l": 0.55, "thigh_r": -0.60, "knee_l": 1.25, "knee_r": 0.90,
            "foot_l": -0.05, "foot_r": 0.30,
            "shoulder_l": 0.30, "shoulder_r": -0.30, "elbow_l": 1.45, "elbow_r": 1.45,
            "head_pitch": 0.04, "support": "floor"}],
        [0.50, {"hip_height": 0.02, "hip_pitch": 0.10, "torso_pitch": 0.22,
            "thigh_l": -0.45, "thigh_r": 0.85, "knee_l": 1.25, "knee_r": 0.95,
            "foot_l": 0.25, "foot_r": -0.15,
            "shoulder_l": -0.55, "shoulder_r": 0.55, "elbow_l": 1.45, "elbow_r": 1.45,
            "head_pitch": 0.04, "support": "floor"}],
        [0.75, {"hip_height": 0.08, "hip_pitch": 0.10, "torso_pitch": 0.22,
            "thigh_l": -0.60, "thigh_r": 0.55, "knee_l": 0.90, "knee_r": 1.25,
            "foot_l": 0.30, "foot_r": -0.05,
            "shoulder_l": -0.30, "shoulder_r": 0.30, "elbow_l": 1.45, "elbow_r": 1.45,
            "head_pitch": 0.04, "support": "floor"}],
        [1.00, {"hip_height": 0.02, "hip_pitch": 0.10, "torso_pitch": 0.22,
            "thigh_l": 0.85, "thigh_r": -0.45, "knee_l": 0.95, "knee_r": 1.25,
            "foot_l": -0.15, "foot_r": 0.25,
            "shoulder_l": 0.55, "shoulder_r": -0.55, "elbow_l": 1.45, "elbow_r": 1.45,
            "head_pitch": 0.04, "support": "floor"}]], t)

