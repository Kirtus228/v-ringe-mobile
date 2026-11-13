class_name TrainAnimBag
extends TrainAnimBase
## Этап 3, волна 1: анимация BAG-станций (gym/bag, dojo/dummy, basement/bag).
##
## Удар: антиципация → удар → impact frame → follow-through → возврат.
##  - поза бойца берётся из существующего fighter.freeze_pose(kind, phase);
##  - снаряд (груша/манекен/мешок) качается затухающей синусоидой от вектора
##    удара — этим занимается TrainingStation, здесь только тайминг и событие
##    impact, которое владелец превращает в «толчок снаряда»;
##  - промах — отдельный клип «сорвался» (снаряд не трогаем);
##  - «встряска» после серии — TrainingStation по счётчику попаданий.
##
## Ничего не двигает сам и при train_anim_level=OFF не запускается.

## Разные станции — разные удары, чтобы визуал не был одинаковым.
const STATION_PUNCH := {
    "bag": "jab",
    "dummy": "cross",
    "homemade_bag": "upper",
    "speedbag": "jab",
    "tires": "upper",
}
## Длительности клипов по уровням (доли/секунды — конфиг класса, не хардкод в логике).
const DUR_BASIC := 0.34
const DUR_FULL := 0.46
const DUR_MISS := 0.42


func play_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    var pk := punch_for(loc_id, station)
    station_id = station
    var dur := DUR_FULL if level == Level.FULL else DUR_BASIC
    if not play("bag", station, "anticipation", dur, 1.0):
        return false
    _pose_kind = pk
    return true


func play_miss_hit(loc_id: String, station: String) -> bool:
    if level == Level.OFF:
        return false
    station_id = station
    _pose_kind = punch_for(loc_id, station)
    return play_miss(DUR_MISS)


## Какой удар показывать для станции локации (fallback — джеб).
func punch_for(loc_id: String, station: String) -> String:
    if STATION_PUNCH.has(station):
        return String(STATION_PUNCH[station])
    if STATION_PUNCH.has(loc_id):
        return String(STATION_PUNCH[loc_id])
    return "jab"


func pose_kind() -> String:
    return _pose_kind


var _pose_kind := "jab"
