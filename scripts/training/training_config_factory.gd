class_name TrainingConfigFactory
extends RefCounted
## Собирает дефолтный TrainingConfig Этапа 3: 5 локаций и все станции.
## Здесь только данные: цифры станций — поля StationDef, бонусы локаций —
## множители прироста статов (TrainingLocationDef.stat_bonus), условия
## разблокировки — TrainingLocationDef.unlock.

const DURABILITY_MAX := 100.0
const WEAR_PER_USE := 5.0


static func create_default() -> TrainingConfig:
    var cfg := TrainingConfig.new()
    cfg.locations = _locations()
    cfg.use_location_unlocks = true
    cfg.use_equipment_wear = true
    cfg.durability_max = DURABILITY_MAX
    cfg.repair_restore = DURABILITY_MAX
    cfg.hide_locked = false
    return cfg


static func _locations() -> Array[TrainingLocationDef]:
    var locs: Array[TrainingLocationDef] = []
    locs.append(_gym())
    locs.append(_park())
    locs.append(_dojo())
    locs.append(_roof())
    locs.append(_basement())
    return locs


## ГРУША / ШТАНГА(QTE) / БЕГОВАЯ ДОРОЖКА(hold). Открыт всегда.
static func _gym() -> TrainingLocationDef:
    var l := TrainingLocationDef.new()
    l.id = "gym"
    l.title = "ЗАЛ"
    l.description = "Тяжёлый зал: сила, снаряды и беговая дорожка. Тренировка принимает всех."
    l.stat_bonus = {"strength": 1.2, "stamina": 1.0, "speed": 0.9}
    l.unlock = {}
    l.floor_color = Color(0.30, 0.28, 0.26)
    l.light_color = Color(1.0, 0.88, 0.68)
    l.light_energy = 1.2
    l.ambient_energy = 0.35
    l.brightness = 0.65
    var stations: Array[StationDef] = []
    stations.append(_station("bag", "ГРУША", "Мешок стоит не двигается — бей по нему.",
            StationDef.Kind.BAG, {"strength": 0.10}, {
                "cooldown": 0.5, "reps": 0,
                "sfx_hit": "hit", "sfx_fail": "whoosh"}))
    stations.append(_station("barbell", "ШТАНГА", "Жми в момент подсказки: окно 0.35 с, пауза между окнами 3–5 с.",
            StationDef.Kind.QTE, {"strength": 0.20, "stamina": 0.05}, {
                "reps": 3, "perfect_window": 0.35, "interval": 4.2,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    # v69: вместо скакалки — бег на беговой дорожке (HOLD: держи E и беги)
    stations.append(_station("treadmill", "ДОРОЖКА",
            "Бег на дорожке: держи E, 3 подхода по 1 секунде.",
            StationDef.Kind.HOLD, {"stamina": 0.12, "speed": 0.10}, {
                "reps": 3, "hold_time": 1.0,
                "sfx_hit": "step", "sfx_fail": "gasp"}))
    l.stations = stations
    return l


## ПАРК: БРУСЬЯ(ритм) / ТУРНИК(QTE) / ОТЖИМАНИЯ(ритм). Открыт после первого визита в зал.
static func _park() -> TrainingLocationDef:
    var l := TrainingLocationDef.new()
    l.id = "park"
    l.title = "ПАРК"
    l.description = "Утренний парк: брусья, турник и отжимания на траве."
    l.stat_bonus = {"strength": 0.8, "stamina": 1.3, "speed": 1.0}
    l.unlock = {"visited": ["gym"]}
    l.floor_color = Color(0.24, 0.32, 0.20)
    l.light_color = Color(0.82, 0.92, 0.78)
    l.light_energy = 1.4
    l.ambient_energy = 0.45
    l.brightness = 0.85
    var stations: Array[StationDef] = []
    # v69: вместо бега — отжимания на брусьях (ритм, как у отжиманий на траве)
    stations.append(_station("dips", "БРУСЬЯ",
            "Отжимания на брусьях: ритм на 6 повторов, окно 0.35 с, 3 промаха.",
            StationDef.Kind.RHYTHM, {"strength": 0.14, "stamina": 0.08}, {
                "reps": 6, "interval": 4.2, "perfect_window": 0.35,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "mistakes_allowed": 3,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    stations.append(_station("bar", "ТУРНИК", "Подтягивание: жми в окно 0.35 с, пауза ~1,5 с.",
            StationDef.Kind.QTE, {"strength": 0.12, "stamina": 0.08}, {
                "reps": 5, "perfect_window": 0.35, "interval": 4.2,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    stations.append(_station("pushups", "ОТЖИМАНИЯ", "Ритм на 6 повторов, окно 0.35 с, 3 промаха.",
            StationDef.Kind.RHYTHM, {"strength": 0.10, "stamina": 0.10}, {
                "reps": 6, "interval": 4.2, "perfect_window": 0.35,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "mistakes_allowed": 3,
                "sfx_hit": "step", "sfx_fail": "whoosh"}))
    l.stations = stations
    return l


## ДОДЗЁ: МАНЕКЕН / БОЙ С ТЕНЬЮ / СКОРОСТНАЯ ГРУША. Сила >= 20.
static func _dojo() -> TrainingLocationDef:
    var l := TrainingLocationDef.new()
    l.id = "dojo"
    l.title = "ДОДЗЁ"
    l.description = "Татами, манекен и скорость рук. Нужна сила 20."
    l.stat_bonus = {"strength": 1.0, "stamina": 1.0, "speed": 1.2}
    l.unlock = {"stat": "strength", "min": 20.0}
    l.floor_color = Color(0.44, 0.38, 0.26)
    l.light_color = Color(1.0, 0.84, 0.56)
    l.light_energy = 1.1
    l.ambient_energy = 0.35
    l.brightness = 0.6
    var stations: Array[StationDef] = []
    stations.append(_station("dummy", "МАНЕКЕН", "Деревянный манекен: точность и сила.",
            StationDef.Kind.BAG, {"strength": 0.08, "speed": 0.06}, {
                "cooldown": 0.4, "reps": 0,
                "sfx_hit": "hit", "sfx_fail": "whoosh"}))
    stations.append(_station("shadow", "БОЙ С ТЕНЬЮ", "Ритм 7 повторов, окно 0.35 с, 2 промаха.",
            StationDef.Kind.RHYTHM, {"speed": 0.12, "stamina": 0.06}, {
                "reps": 7, "interval": 4.2, "perfect_window": 0.35,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "mistakes_allowed": 2,
                "sfx_hit": "whoosh", "sfx_fail": "gasp"}))
    stations.append(_station("speedbag", "СКОРОСТНАЯ ГРУША", "Окно 0.35 с, пауза ~1,5 с.",
            StationDef.Kind.QTE, {"speed": 0.14, "strength": 0.04}, {
                "reps": 6, "perfect_window": 0.35, "interval": 4.2,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "sfx_hit": "hit", "sfx_fail": "whoosh"}))
    l.stations = stations
    return l


## КРЫША: БЁРПИ(QTE) / СКОРОСТНАЯ СКАКАЛКА(ритм) / КАНАТ(hold). Скорость >= 20.
static func _roof() -> TrainingLocationDef:
    var l := TrainingLocationDef.new()
    l.id = "roof"
    l.title = "КРЫША"
    l.description = "Крыша дома: ветер, бёрпи, скакалка и канат. Нужна скорость 20."
    l.stat_bonus = {"strength": 0.9, "stamina": 1.1, "speed": 1.3}
    l.unlock = {"stat": "speed", "min": 20.0}
    l.floor_color = Color(0.30, 0.30, 0.34)
    l.light_color = Color(0.78, 0.86, 1.0)
    l.light_energy = 1.3
    l.ambient_energy = 0.30
    l.brightness = 0.55
    var stations: Array[StationDef] = []
    stations.append(_station("burpee", "БЁРПИ", "Взрывная работа: окно 0.35 с, пауза ~1,5 с.",
            StationDef.Kind.QTE, {"stamina": 0.12, "strength": 0.08}, {
                "reps": 5, "perfect_window": 0.35, "interval": 4.2,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    stations.append(_station("speedrope", "СКОРОСТНАЯ СКАКАЛКА", "Ритм 9 повторов, окно 0.35 с, 4 промаха.",
            StationDef.Kind.RHYTHM, {"speed": 0.14, "stamina": 0.06}, {
                "reps": 9, "interval": 4.2, "perfect_window": 0.35,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "mistakes_allowed": 4,
                "sfx_hit": "step", "sfx_fail": "whoosh"}))
    stations.append(_station("climb", "КАНАТ", "Держи E 1 секунду, 2 подхода.",
            StationDef.Kind.HOLD, {"strength": 0.12, "stamina": 0.10}, {
                "reps": 2, "hold_time": 1.0,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    l.stations = stations
    return l


## ПОДВАЛ: МЕШОК / ПОКРЫШКИ(QTE 0.3) / САМОДЕЛЬНАЯ ШТАНГА(QTE 5 повторов).
## Самодельное железо изнашивается: wear_per_use=5, ломается — чинить QTE.
static func _basement() -> TrainingLocationDef:
    var l := TrainingLocationDef.new()
    l.id = "basement"
    l.title = "ПОДВАЛ"
    l.description = "Тесный подвал: мешок, покрышки и самодельная штанга. Выносливость 30."
    l.stat_bonus = {"strength": 1.4, "stamina": 1.1, "speed": 0.7}
    l.unlock = {"stat": "stamina", "min": 30.0}
    l.floor_color = Color(0.16, 0.15, 0.15)
    l.light_color = Color(1.0, 0.70, 0.42)
    l.light_energy = 0.9
    l.ambient_energy = 0.22
    l.brightness = 0.35
    var stations: Array[StationDef] = []
    stations.append(_station("bag", "МЕШОК", "Старый мешок: бей, пока не сломаешь.",
            StationDef.Kind.BAG, {"strength": 0.15}, {
                "cooldown": 0.45, "reps": 0,
                "wear_per_use": WEAR_PER_USE,
                "sfx_hit": "hit", "sfx_fail": "whoosh"}))
    stations.append(_station("tires", "ПОКРЫШКИ", "Покрышки: окно 0.35 с, 4 повтора, пауза ~1,5 с.",
            StationDef.Kind.QTE, {"strength": 0.12, "stamina": 0.10}, {
                "reps": 4, "perfect_window": 0.35, "interval": 4.2,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "wear_per_use": WEAR_PER_USE,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    stations.append(_station("homemade_bar", "САМОДЕЛЬНАЯ ШТАНГА",
            "Блин из покрышки: окно 0.35 с, 3 повтора, пауза ~1,5 с.",
            StationDef.Kind.QTE, {"strength": 0.22}, {
                "reps": 3, "perfect_window": 0.35, "interval": 4.2,
                "qte_gap_seconds": 1.6, "qte_gap_jitter": 0.35,
                "wear_per_use": WEAR_PER_USE,
                "sfx_hit": "shove", "sfx_fail": "gasp"}))
    l.stations = stations
    return l


static func _station(id: String, title: String, description: String,
        kind: StationDef.Kind, bonus: Dictionary, opts: Dictionary) -> StationDef:
    var s := StationDef.new()
    s.id = id
    s.title = title
    s.description = description
    s.kind = kind
    s.stat_bonus = bonus
    for k in opts:
        s.set(String(k), opts[k])
    return s


# ---------------------------------------------------------------- EN-тексты
## Английские названия/описания локаций и станций (RU живёт в конфигах выше).
## Ключи: "loc/<id>" и "station/<location>/<station>", поля title/desc.
const TEXT_EN := {
    "loc/gym": {"title": "GYM", "desc": "A hard gym: strength, weights and a treadmill."},
    "loc/park": {"title": "PARK", "desc": "Morning park: parallel bars, a pull-up bar and push-ups."},
    "loc/dojo": {"title": "DOJO", "desc": "Tatami, a dummy and hand speed. Needs strength 20."},
    "loc/roof": {"title": "ROOF", "desc": "Rooftop: wind, burpees, speed rope and a climbing rope."},
    "loc/basement": {"title": "BASEMENT", "desc": "Cramped basement: bag, tires and a homemade barbell."},
    "station/gym/bag": {"title": "HEAVY BAG", "desc": "The bag does not move — just hit it."},
    "station/gym/barbell": {"title": "BARBELL", "desc": "Press when the cue appears: 0.35 s window, ~1.5 s gap."},
    "station/gym/treadmill": {"title": "TREADMILL", "desc": "Run on the treadmill: hold E, 3 sets of 1 second."},
    "station/park/dips": {"title": "PARALLEL BARS", "desc": "Dips: rhythm for 6 reps, 0.35 s window, 3 misses allowed."},
    "station/park/bar": {"title": "PULL-UP BAR", "desc": "Pull up in the 0.35 s window, ~1.5 s gap."},
    "station/park/pushups": {"title": "PUSH-UPS", "desc": "Rhythm for 6 reps, 0.35 s window, 3 misses allowed."},
    "station/dojo/dummy": {"title": "WOODEN DUMMY", "desc": "Precision and power on the dummy."},
    "station/dojo/shadow": {"title": "SHADOW BOXING", "desc": "Rhythm for 7 reps, 0.35 s window, 2 misses."},
    "station/dojo/speedbag": {"title": "SPEED BAG", "desc": "0.35 s window, ~1.5 s gap."},
    "station/roof/burpee": {"title": "BURPEES", "desc": "Explosive work: 0.35 s window, ~1.5 s gap."},
    "station/roof/speedrope": {"title": "SPEED ROPE", "desc": "Rhythm for 9 reps, 0.35 s window, 4 misses."},
    "station/roof/climb": {"title": "CLIMBING ROPE", "desc": "Hold E for 1 second, 2 sets."},
    "station/basement/bag": {"title": "OLD BAG", "desc": "Beat the old bag until it wears out."},
    "station/basement/tires": {"title": "TIRES", "desc": "Tires: 0.35 s window, 4 reps, ~1.5 s gap."},
    "station/basement/homemade_bar": {"title": "HOMEMADE BAR", "desc": "Tire plate: 0.35 s window, 3 reps."},
}


## Английский текст по ключу с фолбэком на русский из конфига.
static func en_text(key: String, field: String, fallback: String) -> String:
    var d: Dictionary = TEXT_EN.get(key, {})
    return String(d.get(field, fallback))

