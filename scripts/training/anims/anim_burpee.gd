class_name TrainAnimBurpee
extends TrainAnimBase
## v71q: QTE-БЁРПИ — roof/burpee.
## Источники: https://generationiron.com/how-perform-burpee/
##            https://razfit.app/exercises/burpees/
## Фазы как в жизни: стойка → присед, ладони на пол → прыжком планка →
## отжимание (грудь к полу, локти назад) → прыжком ноги к рукам → прыжок вверх
## с хлопком/выпрямлением → мягкое приземление.
## Длина цикла = интервал станции (1.2–1.5 с), пик прыжка синхронизирован
## с окном через sync_external_impact.

const DUR_MIN := 1.2
const DUR_MAX := 1.5
const DUR_MISS := 0.5
const POSE_CROUCH := "body_upper"
const POSE_JUMP := "upper"

var _pose := POSE_CROUCH


func play_hit(loc_id: String, station: String, window_frac: float = 0.5,
        interval: float = 1.35) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    var dur := clampf(interval, DUR_MIN, DUR_MAX)
    if not play("burpee", station, "anticipation", dur, 1.0):
        return false
    sync_external_impact(lerpf(0.18, 0.32, clampf(window_frac, 0.0, 1.0)))
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    return play_miss(DUR_MISS)


## Поза: в прыжке — «апперкот» (корпус вверх), в остальных фазах — корпусной удар.
func pose_kind() -> String:
    if running:
        var r := phase_fraction()
        if r > 0.78 and r < 0.94:
            return POSE_JUMP
    return POSE_CROUCH


## Прогресс прыжка 0..1 для снаряда/камеры (станция может подпрыгнуть).
func jump_progress() -> float:
    var r := phase_fraction()
    if r <= 0.70:
        return 0.0
    if r < 0.84:
        return (r - 0.70) / 0.14
    if r < 0.96:
        return 1.0 - (r - 0.84) / 0.12
    return 0.0

# ---------------------------------------------------------------- моторные ключи
## Присед с ладонями на полу → планка → отжимание → ноги к рукам → прыжок.
func train_pose_at(t: float) -> Dictionary:
    # v71s2: отладочные фазы кадра (VRINGE_ANIM_SHOT=start|jump|pushup|land|feet)
    # маппятся на НАШИ доли клипа (в игре env пуст — обычная интерполяция).
    var ph := OS.get_environment("VRINGE_ANIM_SHOT").strip_edges().to_lower()
    var tt := t
    match ph:
        "start", "stand":
            tt = 0.02
        "anticipation", "squat":
            tt = 0.14
        "pushup", "down":
            tt = 0.42
        "plank", "up":
            tt = 0.32
        "feet", "tuck":
            tt = 0.70
        "jump", "air":
            tt = 0.84
        "land":
            tt = 0.94
    return interp_pose_keys([
        [0.00, {"hip_height": 0.0, "hip_pitch": 0.05, "torso_pitch": 0.10,
            "thigh": 0.05, "knee": 0.15, "shoulder": -0.35, "elbow": 0.55}],
        [0.12, {"hip_height": -0.30, "hip_pitch": 0.55, "torso_pitch": 0.70,
            "thigh": 0.55, "knee": 1.35, "shoulder": -1.05, "elbow": 0.35,
            "head_pitch": 0.10}],
        [0.26, {"hip_height": -0.05, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh": 0.02, "knee": 0.10, "foot": -0.28,
            "shoulder_l": -0.15, "shoulder_r": -0.15, "elbow_l": 0.12, "elbow_r": 0.12,
            "head_pitch": 0.20, "body_pitch": -1.45,
            "support": "plank"}],
        [0.42, {"hip_height": -0.18, "hip_pitch": 0.12, "torso_pitch": 0.14,
            "thigh": 0.02, "knee": 0.14, "foot": -0.30,
            "shoulder_l": -0.08, "shoulder_r": -0.08, "elbow_l": 1.55, "elbow_r": 1.55,
            "head_pitch": 0.18, "body_pitch": -1.45,
            "support": "plank"}],
        [0.56, {"hip_height": -0.05, "hip_pitch": 0.06, "torso_pitch": 0.10,
            "thigh": 0.02, "knee": 0.10, "foot": -0.28,
            "shoulder_l": -0.15, "shoulder_r": -0.15, "elbow_l": 0.12, "elbow_r": 0.12,
            "head_pitch": 0.20, "body_pitch": -1.45,
            "support": "plank"}],
        [0.70, {"hip_height": -0.26, "hip_pitch": 0.85, "torso_pitch": 0.85,
            "thigh": 0.95, "knee": 1.55, "foot": -0.10,
            "shoulder": -1.00, "elbow": 0.45, "head_pitch": 0.05}],
        [0.84, {"hip_height": 0.22, "hip_pitch": -0.06, "torso_pitch": 0.02,
            "thigh": -0.10, "knee": 0.15, "foot": -0.35,
            "shoulder_l": -1.55, "shoulder_r": -1.55, "elbow_l": 0.20, "elbow_r": 0.20,
            "head_pitch": -0.05}],
        [0.94, {"hip_height": -0.10, "hip_pitch": 0.20, "torso_pitch": 0.30,
            "thigh": 0.25, "knee": 0.65, "foot": 0.05,
            "shoulder": -0.85, "elbow": 0.40}],
        [1.00, {"hip_height": 0.0, "hip_pitch": 0.05, "torso_pitch": 0.10,
            "thigh": 0.05, "knee": 0.15, "shoulder": -0.35, "elbow": 0.55}]], tt)
