class_name ArenaConfigFactory
extends RefCounted
## Каталог боевых локаций (Этап 4): 10 арен из приложения мастер-промта.
## Данные — поля ArenaDef/EnemyDef (Lead'овские Resource-классы). Все 10 арен
## играбельные: разница в правилах/среде/сложности, а не в «заглушках».

const ENEMY_NAMES := ["ГРИЗЛИ", "ТЕНЬ", "МОЛОТ", "КЛИНЧ", "СНАЙПЕР", "ТАНК",
        "ВЬЮН", "КАПКАН", "ГРОМ", "ФИНАЛИСТ"]

## T2: EN-имена. Ключ — id арены/противника. Дубли RU-имён убраны:
## у завода "ПРЕСС" (был второй ТАНК), у корабля "ШТОРМ" (был второй МОЛОТ).
const TITLES_EN := {
    "underground": "UNDERGROUND",
    "club": "FIGHT CLUB",
    "street": "STREET FIGHT",
    "cage": "THE CAGE",
    "ring": "TRAINING RING",
    "beach": "BEACH",
    "roof": "ROOFTOP",
    "factory": "FACTORY",
    "ship": "SHIP",
    "boss": "FINAL",
}
const ENEMIES_EN := {
    "u1": "GRIZZLY", "u2": "SHADOW", "c1": "HAMMER", "s1": "TRAP",
    "k1": "TANK", "t1": "WEAVER", "b1": "THUNDER", "r1": "SNIPER",
    "r2": "CLINCH", "f1": "PRESS", "h1": "STORM", "x1": "FINALIST",
}


static func create_default() -> Array[ArenaDef]:
    var list: Array[ArenaDef] = []
    list.append(_underground())
    list.append(_club())
    list.append(_street())
    list.append(_cage())
    list.append(_training_ring())
    list.append(_beach())
    list.append(_roof())
    list.append(_factory())
    list.append(_ship())
    list.append(_boss())
    return list


static func _enemy(id: String, title: String, arch: String, hp: float, dmg: float,
        spd: float, aggr: float, stamina: float, specials: Array[String]) -> EnemyDef:
    var e := EnemyDef.new()
    e.id = id
    e.title = title
    e.title_en = String(ENEMIES_EN.get(id, ""))
    e.archetype = arch
    e.max_hp = hp
    e.damage_mult = dmg
    e.speed_mult = spd
    e.aggression = aggr
    e.stamina = stamina
    e.specials = specials
    e.skin_color = Color(0.62, 0.46, 0.34)
    e.shorts_color = Color(0.55, 0.12, 0.12)
    return e


static func _arena(id: String, title: String, desc: String, scene: String,
        difficulty: int, rounds: int, round_time: float, money: int, rep: int,
        stats: Dictionary, unlock: Dictionary, env: Dictionary, rules: Dictionary,
        floor: Color, light: Color, energy: float, crowd: bool, obstacles: bool,
        pool: Array[EnemyDef]) -> ArenaDef:
    var a := ArenaDef.new()
    a.id = id
    a.title = title
    a.title_en = String(TITLES_EN.get(id, ""))
    a.description = desc
    a.scene_kind = scene
    a.difficulty = difficulty
    a.rounds = rounds
    a.round_time = round_time
    a.money_reward = money
    a.reputation_reward = rep
    a.stat_bonus_on_win = stats
    a.unlock_condition = unlock
    a.environment_modifiers = env
    a.rules_modifiers = rules
    a.floor_color = floor
    a.light_color = light
    a.light_energy = energy
    a.crowd = crowd
    a.obstacles = obstacles
    a.apply_ranked_penalty = false
    a.opponent_pool = pool
    return a


static func _underground() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("u1", "ГРИЗЛИ", "aggressor", 110.0, 1.05, 1.0, 0.6, 100.0,
            ["pressure"]))
    pool.append(_enemy("u2", "ТЕНЬ", "counter", 105.0, 1.0, 1.1, 0.45, 100.0,
            ["counter_hook"]))
    return _arena("underground", "ПОДПОЛЬЕ",
            "Бетонный подвал, тусклый свет, публика нависает над рингом.",
            "underground", 2, 1, 94.0, 120, 5, {"strength": 0.5},
            {}, {"surface_friction": 1.2, "stamina_drain": 1.0},
            {}, Color(0.22, 0.21, 0.20), Color(0.95, 0.72, 0.42), 0.85, true, false, pool)


static func _club() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("c1", "МОЛОТ", "puncher", 125.0, 1.15, 0.95, 0.7, 105.0,
            ["body_focus"]))
    return _arena("club", "БОЙЦОВСКИЙ КЛУБ",
            "Заведение со ставками: победитель забирает банк.",
            "club", 2, 2, 100.0, 180, 8, {"stamina": 0.5},
            {"arena": "underground"}, {"rocking": 0.0},
            {"betting": true, "rounds_to_win": 2},
            Color(0.20, 0.16, 0.14), Color(1.0, 0.72, 0.40), 1.0, true, false, pool)


static func _street() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("s1", "КАПКАН", "aggressor", 100.0, 1.0, 1.15, 0.8, 90.0,
            ["pressure"]))
    var hazards: Array = [{"name": "лужа", "pos": Vector3(2.1, 0.0, -0.9),
            "radius": 1.0, "dps": 2.0}]
    return _arena("street", "УЛИЧНАЯ ДРАКА",
            "Асфальт, скользко, вокруг опасный мусор.",
            "street", 1, 1, 88.0, 60, 3, {"speed": 0.5},
            {}, {"surface_friction": 0.65, "hazards": hazards, "confined": 3.0},
            {"no_healing": true},
            Color(0.18, 0.18, 0.17), Color(0.72, 0.78, 0.92), 0.7, false, true, pool)


static func _cage() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("k1", "ТАНК", "tank", 140.0, 1.2, 0.9, 0.75, 110.0,
            ["body_focus", "pressure"]))
    return _arena("cage", "КЛЕТКА",
            "Тесная клетка: отступать некуда, раунд короткий.",
            "cage", 3, 2, 75.0, 260, 12, {"strength": 1.0},
            {"wins": 3}, {"confined": 2.2, "edge_hazard": 3.0, "fall_defeat": false,
            "surface_friction": 1.1},
            {"no_healing": true, "time_limit": 75.0},
            Color(0.16, 0.17, 0.19), Color(0.80, 0.86, 1.0), 1.0, true, false, pool)


static func _training_ring() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("t1", "ВЬЮН", "speedster", 110.0, 0.95, 1.2, 0.4, 100.0,
            []))
    return _arena("ring", "ТРЕНИРОВОЧНЫЙ РИНГ",
            "Спокойный ринг: без публики, хорошее освещение.",
            # v71: было 1 раунд — заказчик справедливо спросил «почему снова 1 раунд».
            # Теперь 3 раунда по 75 с: полноценные перерывы, полное здоровье и
            # счётчик нокдаунов с нуля в каждом раунде.
            "ring", 1, 3, 75.0, 30, 1, {"stamina": 0.2},
            {"visited_training": "gym"}, {}, {},
            Color(0.24, 0.26, 0.30), Color(1.0, 0.96, 0.88), 1.2, false, false, pool)


static func _beach() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("b1", "ГРОМ", "puncher", 120.0, 1.1, 1.0, 0.6, 100.0,
            ["counter_hook"]))
    return _arena("beach", "ПЛЯЖ",
            "Песок вязкий, ветер с моря, драться тяжело.",
            "beach", 2, 1, 113.0, 150, 6, {"stamina": 0.8},
            {"arena": "street"}, {"surface_friction": 1.6, "stamina_drain": 2.0,
            "wind": Vector3(2.4, 0.0, 1.3)},
            {}, Color(0.32, 0.30, 0.22), Color(1.0, 0.92, 0.70), 1.3, false, false, pool)


static func _roof() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("r1", "СНАЙПЕР", "sniper", 115.0, 1.05, 1.1, 0.5, 100.0,
            ["counter_hook"]))
    pool.append(_enemy("r2", "КЛИНЧ", "clincher", 130.0, 1.0, 0.95, 0.55, 110.0,
            ["pressure"]))
    return _arena("roof", "КРЫША",
            "Ветер и парапет: за краем крыши — падение и поражение.",
            "roof", 3, 2, 113.0, 280, 14, {"speed": 1.0},
            {"arena": "cage"}, {"wind": Vector3(1.6, 0.0, 0.9), "edge_hazard": 2.5,
            # v71m: край = парапет (стены на радиусе 7), а не середина крыши.
            # Раньше «падение» срабатывало на 3.45 м от центра — на вид посреди
            # площадки, и бой заканчивался сразу после старта.
            "fall_defeat": true, "fall_radius": 7.2, "gravity": 1.3},
            {"rounds_to_win": 2},
            Color(0.28, 0.29, 0.33), Color(0.78, 0.86, 1.0), 1.1, true, false, pool)


static func _factory() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("f1", "ПРЕСС", "tank", 150.0, 1.2, 0.9, 0.8, 115.0,
            ["pressure", "body_focus"]))
    var hazards: Array = [{"name": "пар", "pos": Vector3(2.2, 0.0, 0.0),
            "radius": 1.1, "dps": 3.0}]
    return _arena("factory", "ЗАВОД",
            "Цех с паром: зоны ожога, тяжёлый пол.",
            "factory", 4, 2, 100.0, 340, 18, {"strength": 1.0, "stamina": 0.5},
            {"wins": 6}, {"hazards": hazards, "gravity": 1.1, "surface_friction": 1.2},
            {"no_healing": true},
            Color(0.20, 0.19, 0.17), Color(0.95, 0.66, 0.40), 0.9, true, true, pool)


static func _ship() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("h1", "ШТОРМ", "puncher", 145.0, 1.2, 1.0, 0.85, 110.0,
            ["pressure", "counter_hook"]))
    return _arena("ship", "КОРАБЛЬ",
            "Палуба качается, ветер и вода за бортом.",
            "ship", 4, 3, 94.0, 420, 22, {"stamina": 1.0, "speed": 0.5},
            {"arena": "roof"}, {"rocking": 1.0, "surface_friction": 0.9,
            "wind": Vector3(1.8, 0.0, 0.8)},
            {"rounds_to_win": 2},
            Color(0.20, 0.22, 0.24), Color(0.82, 0.90, 1.0), 1.1, true, false, pool)


static func _boss() -> ArenaDef:
    var pool: Array[EnemyDef] = []
    pool.append(_enemy("x1", "ФИНАЛИСТ", "defender", 190.0, 1.3, 1.05, 0.9, 130.0,
            ["counter_hook", "pressure", "body_focus"]))
    var hazards: Array = [{"name": "искры", "pos": Vector3(-2.2, 0.0, 0.4),
            "radius": 1.1, "dps": 3.0}]
    return _arena("boss", "ФИНАЛ",
            "Финальная арена: тесно, больно, пощады нет.",
            "boss", 5, 3, 75.0, 600, 35, {"strength": 2.0, "stamina": 1.0, "speed": 1.0},
            {"arena": "ship"}, {"confined": 2.0, "hazards": hazards, "gravity": 1.1},
            {"no_knockdown": true, "rounds_to_win": 2, "time_limit": 75.0},
            Color(0.14, 0.12, 0.13), Color(1.0, 0.55, 0.35), 1.0, true, true, pool)
