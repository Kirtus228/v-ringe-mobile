class_name TrainAnimStrike
extends TrainAnimBase
## v71q: QTE-УДАР — dojo/speedbag и basement/tires.
##   speedbag — скоростная груша: короткие прямые удары (поза jab/cross), локоть
##   поднят, кисть работает по груше; здесь моторных ключей нет — работают
##   punch-позы рига.
##   tires — выбираем КУВАЛДУ по покрышке (sledgehammer slap):
##     https://mattime.app/exercises/conditioning/sledgehammer-slam/
##     https://www.boxrox.com/tire-flip-workouts/
##     Фазы: замах двумя руками над головой → резкий удар вниз по покрышке
##     (корпус вперёд, локти выпрямляются) → возврат.
## Пик синхронизируется с окном QTE через sync_external_impact().

const STATION_PUNCH := {
    "speedbag": "jab",
    "tires": "upper",
    "dummy": "cross",
}
const DUR_SPEEDBAG_FULL := 0.30
const DUR_SPEEDBAG_BASIC := 0.24
const DUR_TIRES_FULL := 0.52
const DUR_TIRES_BASIC := 0.40
const DUR_MISS := 0.40

var _pose_kind := "jab"
var _heavy := false


func play_hit(loc_id: String, station: String, window_frac: float = 0.5) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _pose_kind = punch_for(loc_id, station)
    _heavy = station == "tires"
    var dur := DUR_MISS
    if _heavy:
        dur = DUR_TIRES_FULL if level == Level.FULL else DUR_TIRES_BASIC
    else:
        dur = DUR_SPEEDBAG_FULL if level == Level.FULL else DUR_SPEEDBAG_BASIC
    if not play("strike", station, "anticipation", dur, 1.0):
        return false
    # v71s2: у кувалды удар приходится на низ замаха — пик ближе к 0.50 клипа
    # (раньше impact был на 0.30–0.45, т.е. до касания покрышки).
    if _heavy:
        sync_external_impact(lerpf(0.48, 0.54, clampf(window_frac, 0.0, 1.0)))
    else:
        sync_external_impact(lerpf(0.30, 0.45, clampf(window_frac, 0.0, 1.0)))
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _pose_kind = punch_for(loc_id, station)
    _heavy = station == "tires"
    return play_miss(DUR_MISS)


func punch_for(loc_id: String, station: String) -> String:
    if STATION_PUNCH.has(station):
        return String(STATION_PUNCH[station])
    return "jab"


func is_heavy() -> bool:
    return _heavy


## v71s2: отладочные кадры вызывают train_pose_at без play_hit — сообщаем станцию,
## иначе у покрышек рисуется пустая punch-поза вместо замаха кувалдой.
func debug_station(sid: String) -> void:
    station_id = sid
    _heavy = sid == "tires"
    _pose_kind = punch_for("", sid)


func pose_kind() -> String:
    return _pose_kind


## v71q: у покрышек — замах кувалдой и удар; у груши — обычные punch-позы.
func train_pose_at(t: float) -> Dictionary:
    if not _heavy:
        return {}
    # v71s2: кувалда. Замах — обе руки вверх-назад над головой, корпус разогнут
    # (грудь вверх, лёгкий прогиб), вес на пятках. Удар — руки вниз к покрышке,
    # корпус наклоняется вперёд, колени сгибаются, вес уходит вперёд.
    var ph := OS.get_environment("VRINGE_ANIM_SHOT").strip_edges().to_lower()
    var tt := t
    if ph == "windup" or ph == "up":
        tt = 0.32
    elif ph == "impact" or ph == "hit" or ph == "down":
        tt = 0.52
    elif ph == "follow" or ph == "recoil":
        tt = 0.68
    return interp_pose_keys([
        [0.00, {"hip_height": -0.04, "hip_pitch": 0.18, "torso_pitch": 0.30,
            "thigh": 0.20, "knee": 0.45,
            "shoulder_l": -0.85, "shoulder_r": -0.85, "elbow_l": 0.45, "elbow_r": 0.45,
            "head_pitch": 0.05}],
        [0.32, {"hip_height": 0.06, "hip_pitch": -0.10, "torso_pitch": -0.22,
            "thigh": -0.10, "knee": 0.25, "foot": 0.15,
            "shoulder_l": -1.80, "shoulder_r": -1.80, "elbow_l": 0.22, "elbow_r": 0.22,
            "head_pitch": -0.18}],
        [0.52, {"hip_height": -0.20, "hip_pitch": 0.55, "torso_pitch": 1.05,
            "thigh": 0.45, "knee": 0.85, "foot": -0.15,
            "shoulder_l": 0.30, "shoulder_r": 0.30, "elbow_l": 0.10, "elbow_r": 0.10,
            "head_pitch": 0.26}],
        [0.68, {"hip_height": -0.16, "hip_pitch": 0.45, "torso_pitch": 0.85,
            "thigh": 0.40, "knee": 0.75, "foot": -0.10,
            "shoulder_l": 0.05, "shoulder_r": 0.05, "elbow_l": 0.35, "elbow_r": 0.35,
            "head_pitch": 0.22}],
        [1.00, {"hip_height": -0.04, "hip_pitch": 0.18, "torso_pitch": 0.30,
            "thigh": 0.20, "knee": 0.45,
            "shoulder_l": -0.85, "shoulder_r": -0.85, "elbow_l": 0.45, "elbow_r": 0.45,
            "head_pitch": 0.05}]], tt)
