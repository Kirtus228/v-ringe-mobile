extends Node3D
## T8: кровь на тяжёлых попаданиях — только частицы + декали на полу.
## Без текстур/материалов на теле бойца (возрастные рейтинги: OFF по умолчанию).
##
## Уровни (флаг --blood=OFF|LIGHT|FULL):
##   OFF   — ничего не создаётся (по умолчанию, 6+);
##   LIGHT — только тяжёлые попадания (rhook/upper/серия), короткие брызги (12+);
##   FULL  — сильнее и дольше, любые попадания в голову (16+).
##
## Модуль самодостаточен: main.gd только создаёт узел и зовёт spawn/clear/tick.
## Всё живёт физически (гравитация), по таймеру удаляется; clear() на старте боя
## и смене арены — в воздухе ничего не висит.

enum Level { OFF = 0, LIGHT = 1, FULL = 2 }

const PARTICLE_LIFE := {Level.LIGHT: 0.55, Level.FULL: 1.15}
const DECAL_LIFE := {Level.LIGHT: 2.0, Level.FULL: 5.0}
const MAX_DECALS := {Level.LIGHT: 8, Level.FULL: 20}


## v71: фактический лимит декалей с учётом профиля качества.
func _max_decals() -> int:
    return maxi(0, int(float(MAX_DECALS.get(level, 0)) * quality_scale))
const BURST_AMOUNT := {Level.LIGHT: 12, Level.FULL: 34}
const LIGHT_BURST_AMOUNT := {Level.LIGHT: 0, Level.FULL: 14}
const DECAL_SIZE := {Level.LIGHT: 0.32, Level.FULL: 0.46}
const BLOOD_COLOR := Color(0.55, 0.045, 0.05)

var level: int = Level.OFF
## v71: коэффициент количества частиц/декалей от профиля качества (1.0 = как было).
var quality_scale := 1.0
var _bursts: Array = []      # {node, t, life}
var _decals: Array = []      # {node, t, life}
var _spawned_bursts := 0
var _spawned_decals := 0
var _decal_tex: GradientTexture2D = null


func set_level(v: int) -> void:
    level = clampi(int(v), 0, 2)
    if level == Level.OFF:
        clear()


## v71: применить профиль качества (main.gd/Quality: 1.0 HIGH, 0.6 MEDIUM,
## 0.35 LOW). Меньше брызг/декалей — меньше частиц и работы на мобильном.
func set_quality_scale(s: float) -> void:
    quality_scale = clampf(s, 0.0, 1.0)


func level_name() -> String:
    match level:
        Level.LIGHT:
            return "LIGHT"
        Level.FULL:
            return "FULL"
        _:
            return "OFF"


## Очистить всё (старт боя, _reset_fight, смена арены, смена уровня).
func clear() -> void:
    for b in _bursts:
        var n: Node = b.get("node")
        if n != null and is_instance_valid(n):
            n.queue_free()
    _bursts.clear()
    for d in _decals:
        var n2: Node = d.get("node")
        if n2 != null and is_instance_valid(n2):
            n2.queue_free()
    _decals.clear()


## Счётчики для автотеста: эмиттеры частиц и декали на полу.
func counts() -> Dictionary:
    return {"bursts": _bursts.size(), "decals": _decals.size(),
            "particles": _particles_alive(),
            "spawned_bursts": _spawned_bursts, "spawned_decals": _spawned_decals}


func _particles_alive() -> int:
    var n := 0
    for b in _bursts:
        var node: Node = b.get("node")
        if node != null and is_instance_valid(node):
            n += int((node as CPUParticles3D).amount)
    return n


## Брызги + декаль в точке попадания.
## point — точка контакта, dir — направление отталкивания, strength — сила удара
## (базовый урон), heavy — тяжёлый удар/серия, head — попадание в голову,
## lvl >= 0 — разовый уровень вместо текущего.
func spawn(point: Vector3, dir: Vector3, strength: float, heavy: bool = true,
        head: bool = true, lvl: int = -1) -> void:
    var use: int = level if lvl < 0 else clampi(lvl, 0, 2)
    if use == Level.OFF or not head:
        return
    # LIGHT — только тяжёлые попадания; FULL — любые в голову (тяжёлые сильнее)
    if use == Level.LIGHT and not heavy:
        return
    var force := clampf(strength / 15.0, 0.4, 1.6)
    var push := Vector3(dir.x, 0.0, dir.z)
    if push.length() < 0.01:
        push = Vector3(0.0, 0.0, 1.0)
    push = push.normalized()
    _spawn_burst(point + Vector3(0.0, 0.10, 0.0), push, heavy, force, use)
    _spawn_decal(Vector3(point.x, 0.03, point.z), force, use)


func _spawn_burst(at: Vector3, dir: Vector3, heavy: bool, strength: float,
        use: int) -> void:
    if quality_scale <= 0.001:
        return
    var p := CPUParticles3D.new()
    p.position = at
    p.one_shot = true
    p.emitting = true
    p.amount = int(BURST_AMOUNT.get(use, 12) * (1.0 if heavy else 0.5) * quality_scale) \
            if heavy else int(LIGHT_BURST_AMOUNT.get(use, 0) * quality_scale)
    if p.amount <= 0:
        p.queue_free()
        return
    p.lifetime = float(PARTICLE_LIFE.get(use, 0.55)) * (1.0 if heavy else 0.8)
    p.explosiveness = 0.9
    p.randomness = 0.5
    p.direction = (dir * 0.85 + Vector3(0.0, 0.65, 0.0)).normalized()
    p.spread = 32.0
    p.initial_velocity_min = 1.2 * strength
    p.initial_velocity_max = 3.0 * strength
    p.gravity = Vector3(0.0, -9.8, 0.0)
    p.scale_amount_min = 0.015
    p.scale_amount_max = 0.04
    p.damping_min = 0.4
    p.damping_max = 1.2
    var mesh := BoxMesh.new()
    mesh.size = Vector3(1.0, 1.0, 1.0)
    p.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = BLOOD_COLOR
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    p.material_override = mat
    add_child(p)
    _bursts.append({"node": p, "t": 0.0, "life": float(p.lifetime) + 0.15})
    _spawned_bursts += 1


func _spawn_decal(at: Vector3, strength: float, use: int) -> void:
    if _decal_tex == null:
        _decal_tex = _make_decal_texture()
    var d := Decal.new()
    d.position = at
    var s := float(DECAL_SIZE.get(use, 0.32)) * (0.8 + 0.4 * strength)
    d.size = Vector3(s, 0.6, s)
    d.texture_albedo = _decal_tex
    d.albedo_mix = 0.9
    d.modulate = Color(1.0, 1.0, 1.0, 0.85)
    d.cull_mask = 0xFFFFF
    add_child(d)
    _decals.append({"node": d, "t": 0.0, "life": float(DECAL_LIFE.get(use, 2.0))})
    _spawned_decals += 1
    # лимит декалей: старые убираем, чтобы пол не зарастал бесконечно
    var limit := int(float(MAX_DECALS.get(use, 8)) * quality_scale)
    while _decals.size() > limit:
        var old: Dictionary = _decals.pop_front()
        var n: Node = old.get("node")
        if n != null and is_instance_valid(n):
            n.queue_free()


func _make_decal_texture() -> GradientTexture2D:
    var grad := Gradient.new()
    grad.set_color(0, Color(0.30, 0.02, 0.02, 1.0))
    grad.set_color(1, Color(0.30, 0.02, 0.02, 0.0))
    var tex := GradientTexture2D.new()
    tex.gradient = grad
    tex.fill = GradientTexture2D.FILL_RADIAL
    tex.fill_from = Vector2(0.5, 0.5)
    tex.fill_to = Vector2(1.0, 0.5)
    tex.width = 128
    tex.height = 128
    return tex


func tick(delta: float) -> void:
    for i in range(_bursts.size() - 1, -1, -1):
        var b: Dictionary = _bursts[i]
        b["t"] = float(b["t"]) + delta
        if float(b["t"]) >= float(b["life"]):
            var n: Node = b.get("node")
            if n != null and is_instance_valid(n):
                n.queue_free()
            _bursts.remove_at(i)
    for i in range(_decals.size() - 1, -1, -1):
        var d: Dictionary = _decals[i]
        d["t"] = float(d["t"]) + delta
        if float(d["t"]) >= float(d["life"]):
            var n: Node = d.get("node")
            if n != null and is_instance_valid(n):
                n.queue_free()
            _decals.remove_at(i)


## Прокрутить таймеры эффектов (headless-тест).
func debug_advance(seconds: float) -> void:
    var left := maxf(0.0, seconds)
    while left > 0.0001:
        var step := minf(0.05, left)
        tick(step)
        left -= step
