class_name TrainAnimDips
extends TrainAnimBase
## v71q: RHYTHM-ОТЖИМАНИЯ НА БРУСЬЯХ — park/dips.
## Источники: https://startingstrength.com/resources/forum/printthread.php?t=33320
##            https://www.decathlon.com.gr/en/9270-dips-bars
## Фазы: упор на прямых руках (корпус вертикально, ноги сзади и согнуты) →
## опускание до локтей ~90° (не ниже, плечи не «проваливаются») → жим вверх.
## Корпус держим вертикально: не «присед» и не «наклон к полу».

const DUR_FULL := 0.85
const DUR_BASIC := 0.70
const DUR_MISS := 0.40


func play_hit(loc_id: String, station: String, beat: float = -1.0) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    var dur := DUR_FULL if level == Level.FULL else DUR_BASIC
    if beat > 0.0:
        dur = clampf(beat, 0.30, 1.40)
    if not play("dips", station, "active", dur, 1.0):
        return false
    sync_external_impact(0.50)
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    return play_miss(DUR_MISS)


## Прогресс отжимания на брусьях 0..1 (0 — вверху на прямых, 1 — внизу).
func dips_progress() -> float:
    var r := phase_fraction()
    if r < 0.5:
        return r * 2.0
    return (1.0 - r) * 2.0


# ---------------------------------------------------------------- моторные ключи
## Верх: руки прямые вниз (упор на брусьях), таз поднят, ноги сзади согнуты.
## Низ: тело опускается, локти сгибаются до ~90°, корпус почти вертикален.
func train_pose_at(t: float) -> Dictionary:
    return interp_pose_keys([
        [0.00, {"hip_height": 0.26, "hip_pitch": 0.04, "torso_pitch": 0.05,
            "thigh_l": -0.34, "thigh_r": -0.30, "knee_l": 0.95, "knee_r": 0.85,
            "foot": 0.10,
            "shoulder_l": 0.02, "shoulder_r": 0.02, "elbow_l": 0.10, "elbow_r": 0.10,
            "head_pitch": 0.05, "body_pitch": 0.0, "support_h": 1.15,
            "support": "hang"}],
        [0.50, {"hip_height": -0.06, "hip_pitch": 0.10, "torso_pitch": 0.10,
            "thigh_l": -0.20, "thigh_r": -0.16, "knee_l": 1.15, "knee_r": 1.05,
            "foot": 0.10,
            "shoulder_l": 0.22, "shoulder_r": 0.22, "elbow_l": 1.45, "elbow_r": 1.45,
            "head_pitch": 0.05, "body_pitch": 0.0, "support_h": 1.15,
            "support": "hang"}],
        [1.00, {"hip_height": 0.26, "hip_pitch": 0.04, "torso_pitch": 0.05,
            "thigh_l": -0.34, "thigh_r": -0.30, "knee_l": 0.95, "knee_r": 0.85,
            "foot": 0.10,
            "shoulder_l": 0.02, "shoulder_r": 0.02, "elbow_l": 0.10, "elbow_r": 0.10,
            "head_pitch": 0.05, "body_pitch": 0.0, "support_h": 1.15,
            "support": "hang"}]], t)

