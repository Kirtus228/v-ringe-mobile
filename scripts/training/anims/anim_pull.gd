class_name TrainAnimPull
extends TrainAnimBase
## v71q: QTE-ПОДТЯГИВАНИЕ — park/bar.
## Источники: https://centr.com/blog/show/34447/how-to-do-a-pull-up
##            https://mattime.app/exercises/strength/pull-up/
## Фазы: вис на прямых руках (лопатки вниз, тело вытянуто, ноги чуть согнуты) →
## тяга «локтями вниз» (гриф к верху груди) → подбородок над перекладиной →
## контролируемое опускание в вис.
## При частых нажатиях клип НЕ перезапускается: pending/chain сохраняем.

const DUR_FULL := 1.10
const DUR_BASIC := 0.85
const DUR_MISS := 0.48
## Поза фаз: вис/подъём — корпусной апперкот (руки тянутся вверх), спуск — кросс.
const POSE_PULL := "upper"

var _pose_kind := POSE_PULL
## Есть ли отложенное нажатие (клип уже играл).
var pending := false
var chain := 0


func play_hit(loc_id: String, station: String, window_frac: float = 0.5) -> bool:
    if level == Level.OFF:
        return false
    if running:
        # не рвём цикл: доигрываем текущий, следующее нажатие подхватим в конце
        pending = true
        chain += 1
        return false
    station_id = station
    _pose_kind = POSE_PULL
    pending = false
    chain = 0
    var dur := DUR_FULL if level == Level.FULL else DUR_BASIC
    if not play("pull", station, "hang", dur, 1.0):
        return false
    sync_external_impact(lerpf(0.45, 0.55, clampf(window_frac, 0.0, 1.0)))
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    running = false
    pending = false
    chain = 0
    return play_miss(DUR_MISS)


## Прогресс подтягивания 0..1 (0 — вис, 1 — подбородок над перекладиной).
func pull_progress() -> float:
    var ratio := phase_fraction()
    if ratio < 0.12:
        return 0.0
    if ratio < 0.46:
        return (ratio - 0.12) / 0.34
    if ratio < 0.58:
        return 1.0
    if ratio < 0.88:
        return 1.0 - (ratio - 0.58) / 0.30
    return 0.0


func pose_kind() -> String:
    return _pose_kind


# ---------------------------------------------------------------- моторные ключи
## Вис: руки над головой почти прямые (shoulder ≈ −1.78), тело вертикально,
## ноги слегка согнуты и скрещены. Тяга: локти вниз (elbow ~2.0), плечи
## «подтягивают» корпус к грифу, подбородок вверх (head_pitch −).
func train_pose_at(t: float) -> Dictionary:
    # v71s2: отладочные фазы кадра (VRINGE_ANIM_SHOT=hang|chin|lower) — т.к.
    # демо-хелпер в training_mode для pull передаёт фиксированный t. В игре env пуст.
    var ph := OS.get_environment("VRINGE_ANIM_SHOT").strip_edges().to_lower()
    var tt := t
    if ph == "hang":
        tt = 0.0
    elif ph == "chin" or ph == "pull":
        tt = 0.50
    elif ph == "lower":
        tt = 0.86
    return interp_pose_keys([
        [0.00, {"hip_height": 0.26, "hip_pitch": 0.02, "torso_pitch": 0.02,
            "thigh_l": -0.06, "thigh_r": -0.02, "knee_l": 0.34, "knee_r": 0.20,
            "foot": 0.15,
            "shoulder_l": -1.78, "shoulder_r": -1.78, "elbow_l": 0.06, "elbow_r": 0.06,
            "head_pitch": 0.04, "body_pitch": 0.02, "support_h": 2.30,
            "support": "hang"}],
        [0.34, {"hip_height": 0.28, "hip_pitch": 0.02, "torso_pitch": 0.00,
            "thigh_l": -0.08, "thigh_r": -0.04, "knee_l": 0.40, "knee_r": 0.24,
            "foot": 0.15,
            "shoulder_l": -1.42, "shoulder_r": -1.42, "elbow_l": 1.10, "elbow_r": 1.10,
            "head_pitch": 0.00, "body_pitch": 0.00, "support_h": 2.30,
            "support": "hang"}],
        [0.50, {"hip_height": 0.30, "hip_pitch": 0.02, "torso_pitch": -0.05,
            "thigh_l": -0.10, "thigh_r": -0.06, "knee_l": 0.44, "knee_r": 0.28,
            "foot": 0.15,
            "shoulder_l": -1.10, "shoulder_r": -1.10, "elbow_l": 2.05, "elbow_r": 2.05,
            "head_pitch": -0.16, "body_pitch": -0.04, "support_h": 2.30,
            "support": "hang"}],
        [0.72, {"hip_height": 0.28, "hip_pitch": 0.02, "torso_pitch": 0.00,
            "thigh_l": -0.08, "thigh_r": -0.04, "knee_l": 0.40, "knee_r": 0.24,
            "foot": 0.15,
            "shoulder_l": -1.42, "shoulder_r": -1.42, "elbow_l": 1.10, "elbow_r": 1.10,
            "head_pitch": 0.00, "body_pitch": 0.00, "support_h": 2.30,
            "support": "hang"}],
        [1.00, {"hip_height": 0.26, "hip_pitch": 0.02, "torso_pitch": 0.02,
            "thigh_l": -0.06, "thigh_r": -0.02, "knee_l": 0.34, "knee_r": 0.20,
            "foot": 0.15,
            "shoulder_l": -1.78, "shoulder_r": -1.78, "elbow_l": 0.06, "elbow_r": 0.06,
            "head_pitch": 0.04, "body_pitch": 0.02, "support_h": 2.30,
            "support": "hang"}]], tt)

