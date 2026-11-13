extends RefCounted
## Каталог кастомизации бойца: фасоны и отдельные палитры цветов.
## Один источник данных для гардероба (HUD), меню и сборки тела.
##
## Раздел — либо «модель» (форма/фасон), либо «цвет» (палитра). В look
## хранится id варианта по каждому разделу: {"hair": "buzz", "hair_color": "blond", ...}.

const CATALOG := [
    {"id": "hair", "name": "ПРИЧЁСКА", "items": [
        {"id": "bald", "name": "бритый", "price": 0, "hair": "bald"},
        {"id": "buzz", "name": "ёжик", "price": 120, "hair": "buzz"},
        {"id": "mohawk", "name": "ирокез", "price": 260, "hair": "mohawk"},
        {"id": "tail", "name": "хвост", "price": 220, "hair": "tail"},
        {"id": "afro", "name": "афро", "price": 300, "hair": "afro"},
        {"id": "pompadour", "name": "помпадур", "price": 340, "hair": "pompadour"},
        {"id": "undercut", "name": "андеркат", "price": 300, "hair": "undercut"},
        {"id": "bun", "name": "пучок", "price": 280, "hair": "bun"},
        {"id": "dreads", "name": "дреды", "price": 360, "hair": "dreads"},
        {"id": "long", "name": "длинные", "price": 320, "hair": "long"},
        {"id": "curls", "name": "кудри", "price": 300, "hair": "curls"},
        {"id": "flat", "name": "площадка", "price": 260, "hair": "flat"},
    ]},
    {"id": "hair_color", "name": "ЦВЕТ ВОЛОС", "items": [
        {"id": "black", "name": "чёрный", "price": 0, "col": Color(0.09, 0.08, 0.07)},
        {"id": "brown", "name": "тёмно-русый", "price": 80, "col": Color(0.24, 0.15, 0.08)},
        {"id": "blond", "name": "блонд", "price": 120, "col": Color(0.85, 0.70, 0.38)},
        {"id": "red", "name": "рыжий", "price": 140, "col": Color(0.72, 0.32, 0.12)},
        {"id": "crimson", "name": "красный", "price": 160, "col": Color(0.86, 0.16, 0.22)},
        {"id": "gray", "name": "седой", "price": 180, "col": Color(0.78, 0.79, 0.82)},
        {"id": "blue", "name": "синий", "price": 220, "col": Color(0.18, 0.42, 0.95)},
    ]},
    {"id": "skin", "name": "КОЖА", "items": [
        {"id": "light", "name": "светлая", "price": 0,
            "skin": Color(0.89, 0.72, 0.55), "dark": Color(0.71, 0.55, 0.41)},
        {"id": "pale", "name": "бледная", "price": 120,
            "skin": Color(0.94, 0.80, 0.68), "dark": Color(0.76, 0.62, 0.52)},
        {"id": "tan", "name": "загорелая", "price": 140,
            "skin": Color(0.78, 0.59, 0.41), "dark": Color(0.60, 0.43, 0.29)},
        {"id": "olive", "name": "смуглая", "price": 180,
            "skin": Color(0.68, 0.51, 0.36), "dark": Color(0.51, 0.36, 0.24)},
        {"id": "dark", "name": "тёмная", "price": 240,
            "skin": Color(0.44, 0.31, 0.23), "dark": Color(0.31, 0.21, 0.15)},
        {"id": "deep", "name": "очень тёмная", "price": 280,
            "skin": Color(0.30, 0.20, 0.14), "dark": Color(0.20, 0.13, 0.09)},
    ]},
    {"id": "build", "name": "ФИГУРА", "items": [
        {"id": "normal", "name": "обычная", "price": 0,
            "chest": 1.0, "arm": 1.0, "leg": 1.0, "shoulder": 1.0},
        {"id": "lean", "name": "сухая", "price": 160,
            "chest": 0.92, "arm": 0.88, "leg": 0.93, "shoulder": 0.97},
        {"id": "heavy", "name": "тяжёлая", "price": 500,
            "chest": 1.13, "arm": 1.2, "leg": 1.11, "shoulder": 1.06},
    ]},
    {"id": "gloves", "name": "ПЕРЧАТКИ", "items": [
        {"id": "ten", "name": "10 oz", "price": 0, "r": 0.15},
        {"id": "twelve", "name": "12 oz", "price": 150, "r": 0.158},
        {"id": "fourteen", "name": "14 oz", "price": 200, "r": 0.168},
    ]},
    {"id": "gloves_color", "name": "ЦВЕТ ПЕРЧАТОК", "items": [
        {"id": "blue", "name": "синие", "price": 0, "col": Color(0.20, 0.75, 1.0)},
        {"id": "red", "name": "красные", "price": 120, "col": Color(0.95, 0.20, 0.24)},
        {"id": "white", "name": "белые", "price": 140, "col": Color(0.93, 0.93, 0.95)},
        {"id": "black", "name": "чёрные", "price": 160, "col": Color(0.07, 0.07, 0.09)},
        {"id": "pink", "name": "розовые", "price": 180, "col": Color(0.97, 0.42, 0.70)},
        {"id": "green", "name": "салатовые", "price": 200, "col": Color(0.55, 0.95, 0.30)},
        {"id": "gold", "name": "золотые", "price": 220, "col": Color(0.95, 0.76, 0.25)},
        {"id": "neon", "name": "неон", "price": 280,
            "col": Color(0.25, 1.0, 0.78), "glow": Color(0.10, 0.85, 0.62)},
    ]},
    {"id": "shorts", "name": "ШОРТЫ", "items": [
        {"id": "short", "name": "короткие", "price": 0, "long": false},
        {"id": "long", "name": "до колена", "price": 220, "long": true},
    ]},
    {"id": "shorts_color", "name": "ЦВЕТ ШОРТ", "items": [
        {"id": "blue", "name": "синие", "price": 0,
            "col": Color(0.10, 0.22, 0.66), "trim": Color(0.24, 0.55, 0.98)},
        {"id": "red", "name": "красные", "price": 150,
            "col": Color(0.72, 0.10, 0.13), "trim": Color(0.97, 0.35, 0.35)},
        {"id": "white", "name": "белые", "price": 170,
            "col": Color(0.90, 0.92, 0.95), "trim": Color(0.20, 0.35, 0.75)},
        {"id": "black", "name": "чёрные", "price": 190,
            "col": Color(0.06, 0.06, 0.08), "trim": Color(0.95, 0.76, 0.25)},
        {"id": "gold", "name": "золотые", "price": 240,
            "col": Color(0.55, 0.42, 0.12), "trim": Color(0.98, 0.92, 0.60)},
        {"id": "stripes", "name": "полосатые", "price": 210,
            "col": Color(0.86, 0.88, 0.93), "trim": Color(0.12, 0.28, 0.72)},
    ]},
    {"id": "boots", "name": "БОТИНКИ", "items": [
        {"id": "hi", "name": "высокие", "price": 0, "style": "hi"},
        {"id": "low", "name": "низкие", "price": 160, "style": "low"},
        {"id": "bare", "name": "босиком с тейпом", "price": 240, "style": "bare"},
        {"id": "mid", "name": "полувысокие", "price": 200, "style": "mid"},
        {"id": "pro", "name": "профи (липучки)", "price": 320, "style": "pro"},
        {"id": "classic", "name": "классические", "price": 360, "style": "classic"},
        {"id": "speed", "name": "скоростные", "price": 300, "style": "speed"},
        {"id": "wrestle", "name": "борцовки", "price": 340, "style": "wrestle"},
    ]},
    {"id": "boots_color", "name": "ЦВЕТ БОТИНОК", "items": [
        {"id": "black", "name": "чёрные", "price": 0, "col": Color(0.06, 0.07, 0.10)},
        {"id": "red", "name": "красные", "price": 140, "col": Color(0.62, 0.08, 0.10)},
        {"id": "white", "name": "белые", "price": 160, "col": Color(0.90, 0.91, 0.94)},
        {"id": "blue", "name": "синие", "price": 180, "col": Color(0.12, 0.28, 0.62)},
        {"id": "gold", "name": "золотые", "price": 220, "col": Color(0.85, 0.66, 0.20)},
    ]},
]


static func default_look() -> Dictionary:
    var d := {}
    for cat in CATALOG:
        d[String(cat["id"])] = String(cat["items"][0]["id"])
    return d


static func default_owned() -> Array:
    var a: Array = []
    for cat in CATALOG:
        a.append("%s:%s" % [cat["id"], cat["items"][0]["id"]])
    return a


static func cat_index(cat_id: String) -> int:
    for i in CATALOG.size():
        if String(CATALOG[i]["id"]) == cat_id:
            return i
    return 0


static func items(cat_id: String) -> Array:
    return CATALOG[cat_index(cat_id)]["items"]


static func item_count(cat_id: String) -> int:
    return items(cat_id).size()


static func item_index(cat_id: String, item_id: String) -> int:
    var arr := items(cat_id)
    for i in arr.size():
        if String(arr[i]["id"]) == item_id:
            return i
    return 0


static func find_item(cat_id: String, item_id: String) -> Dictionary:
    var arr := items(cat_id)
    for it in arr:
        if String(it["id"]) == item_id:
            return it
    return arr[0]


## Раздел — палитра цветов? (у первого варианта есть цвет)
static func is_color_section(cat_id: String) -> bool:
    return (items(cat_id)[0] as Dictionary).has("col")


## look: {"hair": "buzz", ...} -> {"hair": {вариант}, ...}
static func resolved(look: Dictionary) -> Dictionary:
    var out := {}
    for cat in CATALOG:
        var cid := String(cat["id"])
        var arr: Array = cat["items"]
        var want := String(look.get(cid, String(arr[0]["id"])))
        out[cid] = find_item(cid, want)
    return out


## Итоговый вид бойца: форма + цвета, без ссылок на разделы.
static func outfit(look: Dictionary) -> Dictionary:
    var v := resolved(look)
    var skin: Dictionary = v["skin"]
    var bd: Dictionary = v["build"]
    var gl: Dictionary = v["gloves"]
    var gc: Dictionary = v["gloves_color"]
    var sh: Dictionary = v["shorts"]
    var sc: Dictionary = v["shorts_color"]
    var bt: Dictionary = v["boots"]
    var bc: Dictionary = v["boots_color"]
    var o := {
        "hair": String(v["hair"]["hair"]),
        "hair_col": v["hair_color"]["col"],
        "skin": skin["skin"],
        "skin_dark": skin["dark"],
        "chest": float(bd["chest"]),
        "arm": float(bd["arm"]),
        "leg": float(bd["leg"]),
        "shoulder": float(bd["shoulder"]),
        "glove_r": float(gl["r"]),
        "glove_col": gc["col"],
        "glove_tinge": Color(gc["col"]).darkened(0.35),
        "shorts_long": bool(sh["long"]),
        "shorts_col": sc["col"],
        "shorts_trim": sc["trim"],
        "boot_style": String(bt["style"]),
        "boot_col": bc["col"],
    }
    if gc.has("glow"):
        o["glove_glow"] = gc["glow"]
    return o


# ---------------------------------------------------------------- v71k: разнообразие
## v71k: детерминированно собрать РАЗНООБРАЗНЫЙ look бойца по номеру n из всех
## существующих id каталога CATALOG. Один и тот же n всегда даёт один и тот же вид.
## base (если задан) накладывается сверху — явно заданные ключи главнее, поэтому
## в карьере цвета стиля соперника сохраняются, а варьируются только недостающие.
##
## Свойства (проверяются variation_test):
##  - причёска: шаг 5 по 12 вариантам (5 взаимно просто с 12) → все 12 встречаются,
##    и в любых 12 подряд n нет повторов;
##  - кожа: шаг 5 по 6 → соседние n всегда разной кожи;
##  - фигура: шаг 2 по 3 → соседние n всегда разной фигуры, все 3 сбалансированы;
##  - цвета/перчатки/шорты/ботинки идут своими шагами (взаимно простыми с числом
##    вариантов), поэтому разнообразие не «залипает» на одном id.
static func varied_look(n: int, base: Dictionary = {}) -> Dictionary:
    var i := absi(n)
    var d := {
        "hair": String(items("hair")[posmod(i * 5 + 3, item_count("hair"))]["id"]),
        "hair_color": String(items("hair_color")[posmod(i * 3 + 2,
                item_count("hair_color"))]["id"]),
        "skin": String(items("skin")[posmod(i * 5 + 2, item_count("skin"))]["id"]),
        "build": String(items("build")[posmod(i * 2 + 1, item_count("build"))]["id"]),
        "gloves": String(items("gloves")[posmod(i + 1, item_count("gloves"))]["id"]),
        "gloves_color": String(items("gloves_color")[posmod(i * 3 + 1,
                item_count("gloves_color"))]["id"]),
        "shorts": String(items("shorts")[posmod(i * 1, item_count("shorts"))]["id"]),
        "shorts_color": String(items("shorts_color")[posmod(i * 5 + 2,
                item_count("shorts_color"))]["id"]),
        "boots": String(items("boots")[posmod(i * 5 + 4, item_count("boots"))]["id"]),
        "boots_color": String(items("boots_color")[posmod(i * 2 + 1,
                item_count("boots_color"))]["id"]),
    }
    # base главнее: если там валидный id — берём его, иначе оставляем наш вариант
    for k in base.keys():
        var cid := String(k)
        if not d.has(cid):
            continue
        var wanted := String(base[k])
        if item_index(cid, wanted) != 0 or wanted == String(items(cid)[0]["id"]):
            d[cid] = wanted
        else:
            # невалидный id в base — не подставляем «первый» случайно, оставляем varied
            d[cid] = String(d[cid])
    return d


## v71k: проверка разнообразия на наборе n. Возвращает статистику для stdout/теста.
## Проверяет: все причёски покрыты, в любых 12 подряд нет повторов причёски,
## все фигуры встречаются, соседние n отличаются причёской/кожей/фигурой,
## все id валидны.
static func variation_test(ns: Array) -> Dictionary:
    var hairs: Array = []
    var builds: Array = []
    var invalid := 0
    var adjacent_ok := 0
    var prev: Dictionary = {}
    for n in ns:
        var l := varied_look(int(n))
        # валидность всех id
        for cat in CATALOG:
            var cid := String(cat["id"])
            var found := false
            for it in cat["items"]:
                if String(it["id"]) == String(l.get(cid, "")):
                    found = true
                    break
            if not found:
                invalid += 1
        var h := String(l["hair"])
        var b := String(l["build"])
        var s := String(l["skin"])
        hairs.append(h)
        builds.append(b)
        if not prev.is_empty():
            if String(prev["hair"]) != h and String(prev["skin"]) != s \
                    and String(prev["build"]) != b:
                adjacent_ok += 1
        prev = l
    # покрытие причёсок
    var uniq_hair := {}
    for h in hairs:
        uniq_hair[h] = true
    # повторы причёски внутри любых 12 подряд
    var window_repeats := 0
    for start in range(0, maxi(0, hairs.size() - 11)):
        var seen := {}
        for i in range(start, mini(start + 12, hairs.size())):
            var h2 := String(hairs[i])
            if seen.has(h2):
                window_repeats += 1
            seen[h2] = true
    var uniq_build := {}
    for b2 in builds:
        uniq_build[b2] = true
    return {"n": ns.size(), "hairs": uniq_hair.size(), "hair_unique": uniq_hair.keys(),
            "builds": uniq_build.size(), "build_unique": uniq_build.keys(),
            "repeats_in_12": window_repeats, "invalid_ids": invalid,
            "adjacent_different": adjacent_ok, "pairs": maxi(0, ns.size() - 1)}

