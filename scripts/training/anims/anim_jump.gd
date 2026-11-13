class_name TrainAnimJump
extends TrainAnimBase
## v71q: RHYTHM-ПРЫЖКИ — gym/rope и roof/speedrope (скакалка).
## Источники: https://www.mmastyle.irish/blog/how-to-learn-jump-rope
##            https://rpmtraining.com/blogs/rpm-blog/breaking-through-the-double-under-wall
## Техника: локти близко к корпусу, кисти вращают скакалку (не руки от плеча),
## подскоки маленькие 2–3 см, приземление мягкое на носки, корпус вертикально,
## колени чуть согнуты. Скакалка вращается станцией по rope_angle().
##
## Такт совпадает с окном ритма (impact синхронизируется с долей клипа);
## промах — «запнулся»: скакалка бьёт по ногам (станция дёргается).

const TACT_ROPE := 0.50
const TACT_SPEEDROPE := 0.30
const DUR_MISS := 0.35
## Полный оборот скакалки за такт: угол = TAU * доля такта.
const ROPE_TURNS := 1.0

var _tact := TACT_ROPE
var _pose := ""


func play_jump(loc_id: String, station: String, tact: float = -1.0) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    # T-trainanim: пауза между окнами теперь 3–5 с; прыжок не растягиваем на всю
    # паузу — один подскок в такте 0.30–0.60 с, дальше обычное дыхание до окна.
    _tact = clampf(tact, 0.30, 0.60) if tact > 0.0 else (
            TACT_SPEEDROPE if station == "speedrope" else TACT_ROPE)
    _pose = ""
    if not play("jump", station, "active", _tact, 1.0):
        return false
    sync_external_impact(0.50)
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _pose = ""
    return play_miss(DUR_MISS)


func tact() -> float:
    return _tact


## Угол скакалки/кистей 0..TAU*ROPE_TURNS для текущей доли такта.
func rope_angle() -> float:
    return TAU * ROPE_TURNS * phase_fraction()


func pose_kind() -> String:
    return _pose

# ---------------------------------------------------------------- моторные ключи
## v71q: маленькие подскоки 2–3 см: колени чуть согнуты, локти у корпуса
## (shoulder ≈ 0.10), кисти вращают скакалку (elbow ~0.95), приземление мягкое.
func train_pose_at(t: float) -> Dictionary:
    return interp_pose_keys([
        [0.00, {"hip_height": -0.05, "hip_pitch": 0.04, "torso_pitch": 0.06,
            "thigh": 0.08, "knee": 0.35, "foot": -0.05,
            "shoulder_l": 0.10, "shoulder_r": 0.10, "elbow_l": 0.95, "elbow_r": 0.95,
            "head_pitch": 0.02}],
        [0.30, {"hip_height": 0.03, "hip_pitch": 0.02, "torso_pitch": 0.04,
            "thigh": 0.02, "knee": 0.18, "foot": 0.25,
            "shoulder_l": 0.12, "shoulder_r": 0.12, "elbow_l": 0.92, "elbow_r": 0.92,
            "head_pitch": 0.02}],
        [0.55, {"hip_height": 0.04, "hip_pitch": 0.00, "torso_pitch": 0.02,
            "thigh": -0.02, "knee": 0.14, "foot": 0.20,
            "shoulder_l": 0.10, "shoulder_r": 0.10, "elbow_l": 0.90, "elbow_r": 0.90,
            "head_pitch": 0.02}],
        [0.78, {"hip_height": -0.08, "hip_pitch": 0.06, "torso_pitch": 0.08,
            "thigh": 0.10, "knee": 0.45, "foot": -0.10,
            "shoulder_l": 0.08, "shoulder_r": 0.08, "elbow_l": 0.98, "elbow_r": 0.98,
            "head_pitch": 0.02}],
        [1.00, {"hip_height": -0.05, "hip_pitch": 0.04, "torso_pitch": 0.06,
            "thigh": 0.08, "knee": 0.35, "foot": -0.05,
            "shoulder_l": 0.10, "shoulder_r": 0.10, "elbow_l": 0.95, "elbow_r": 0.95,
            "head_pitch": 0.02}]], t)
