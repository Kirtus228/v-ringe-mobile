class_name ArenaVisual
extends Node3D
## Визуал боевой арены (Этап 6): уникальное окружение по scene_kind ArenaDef
## и видимые environment_modifiers.
##
## Правила модуля:
##  - всё только при visual.visual_on(); при OFF ArenaManager даже не создаёт
##    этот узел — кадр арены остаётся прежним (байт-стабильный гейт);
##  - статика склеена через SurfaceTool в 2 меша (непрозрачный + светящийся),
##    толпа — MultiMesh, поэтому комната добавляет ~4-8 draw вместо ~19;
##  - правила/награды/урон не трогаются: модуль знает только def/visual и env;
##  - модификаторы: dim (свет/ambient), crowd (MultiMesh+огоньки), wind
##    (частицы), rocking (наклон комнаты делает ArenaManager), hazards
##    (частицы+Decal+звук+пульсирующая аура), confined (сетка), obstacles (декор).

const AudioFactory := preload("res://scripts/visual/arena_audio.gd")

var main: Node
var vc = null
var def: ArenaDef
var kind := ""
var built := false

var _st: SurfaceTool = null
var _st_glow: SurfaceTool = null
var _glow_mat: StandardMaterial3D
var _props := 0
## T7: открытый сектор ограждения со стороны камеры — иначе прутья клетки/сетки
## закрывают бой (камера в бою всегда сзади-сбоку от бойца, азимут ≈ 56°).
const CAM_AZ := 0.98
const VIEW_GAP := 1.30


## T7: прут/сегмент ограждения попадает в открытый сектор обзора?
func _in_view_gap(a: float) -> bool:
    var d := wrapf(a - CAM_AZ, -PI, PI)
    return absf(d) < VIEW_GAP
var _lights: Array = []          # {light, base, flicker, phase}
var _sway: Array = []            # {node, amp, phase, axis}
var _hazard_fx: Array = []       # {ring, base_scale, t}
var _audio: AudioStreamPlayer3D = null
var _env: Environment = null
var _env_saved := {}
var _t := 0.0
var _lm := 1.0
var _budget := 0
var _crowd_count := 0
var _decal_count := 0
## v55: высота верхней грани того, на чём стоят бойцы (настил ринга/палуба).
## Боец стоит на y=0, низ ступни ≈+0.005 — выше этого уровня поверхность быть не
## должна, иначе ноги тонут в текстуре. По умолчанию — обычный пол арены (0.0).
var _ground_top := 0.0
var _particle_count := 0
## v71: профиль качества (масштаб частиц/декалей/света/толпы, тени, glow).
var _q: Dictionary = {}
var _decals_left := 99
var _lights_left := 99
var _no_glow := false
var _shadows_on := true

## Палитры арен: базовый пол/стены/акцент/свет + насколько тускло (dim).
const PALETTES := {
    "underground": {"floor": Color(0.17, 0.16, 0.15), "wall": Color(0.11, 0.10, 0.10),
        "accent": Color(0.55, 0.20, 0.16), "light": Color(0.95, 0.74, 0.46),
        "sky": Color(0.02, 0.02, 0.03), "dim": 0.55},
    "club": {"floor": Color(0.19, 0.16, 0.14), "wall": Color(0.13, 0.10, 0.10),
        "accent": Color(0.85, 0.62, 0.22), "light": Color(1.0, 0.76, 0.44),
        "sky": Color(0.03, 0.02, 0.03), "dim": 0.75},
    "street": {"floor": Color(0.16, 0.16, 0.16), "wall": Color(0.10, 0.10, 0.12),
        "accent": Color(0.35, 0.55, 0.75), "light": Color(0.74, 0.80, 0.94),
        "sky": Color(0.04, 0.05, 0.07), "dim": 0.65},
    "cage": {"floor": Color(0.15, 0.16, 0.18), "wall": Color(0.09, 0.10, 0.12),
        "accent": Color(0.55, 0.62, 0.72), "light": Color(0.82, 0.88, 1.0),
        "sky": Color(0.02, 0.02, 0.03), "dim": 0.8},
    "ring": {"floor": Color(0.24, 0.26, 0.30), "wall": Color(0.15, 0.17, 0.21),
        "accent": Color(0.36, 0.58, 0.92), "light": Color(1.0, 0.97, 0.90),
        "sky": Color(0.05, 0.06, 0.08), "dim": 1.0},
    "beach": {"floor": Color(0.34, 0.31, 0.23), "wall": Color(0.24, 0.26, 0.30),
        "accent": Color(0.98, 0.86, 0.52), "light": Color(1.0, 0.94, 0.74),
        "sky": Color(0.42, 0.52, 0.64), "dim": 1.1},
    "roof": {"floor": Color(0.26, 0.27, 0.30), "wall": Color(0.14, 0.15, 0.18),
        "accent": Color(0.42, 0.62, 0.92), "light": Color(0.80, 0.88, 1.0),
        "sky": Color(0.05, 0.06, 0.09), "dim": 0.85},
    "factory": {"floor": Color(0.18, 0.17, 0.16), "wall": Color(0.12, 0.11, 0.10),
        "accent": Color(0.90, 0.50, 0.18), "light": Color(0.96, 0.68, 0.42),
        "sky": Color(0.03, 0.025, 0.02), "dim": 0.7},
    "ship": {"floor": Color(0.20, 0.22, 0.24), "wall": Color(0.12, 0.14, 0.16),
        "accent": Color(0.72, 0.80, 0.92), "light": Color(0.84, 0.92, 1.0),
        "sky": Color(0.05, 0.08, 0.12), "dim": 0.9},
    "boss": {"floor": Color(0.13, 0.11, 0.12), "wall": Color(0.08, 0.07, 0.08),
        "accent": Color(0.95, 0.42, 0.22), "light": Color(1.0, 0.58, 0.36),
        "sky": Color(0.02, 0.01, 0.01), "dim": 0.5},
}


func build(main_ref: Node, vc_ref, arena_def: ArenaDef) -> void:
    main = main_ref
    vc = vc_ref
    def = arena_def
    kind = String(def.scene_kind) if def != null else "ring"
    if vc == null or not vc.visual_on():
        built = false
        return
    _lm = float(vc.light_mult())
    _budget = int(vc.particle_budget())
    _q = vc.quality_profile()
    _decals_left = int(_q.get("decal_budget", 99))
    _lights_left = int(_q.get("light_budget", 99))
    _no_glow = float(_q.get("glow", 1.0)) <= 0.001
    _shadows_on = bool(_q.get("shadows", true))
    if vc.has_method("maybe_apply_quality"):
        vc.maybe_apply_quality(get_viewport(), get_window())
    var pal: Dictionary = PALETTES.get(kind, PALETTES["ring"])
    _build_meshes(pal)
    _build_common(pal)
    _build_kind(pal)
    # T7c: дополнительная детализация окружения (всё в те же 2 склеенных меша,
    # поэтому draw calls почти не растут; толпа/фон — MultiMesh/merged).
    _build_t7c(pal)
    _commit_meshes()
    _build_t7c_live(pal)
    _build_lights(pal)
    _build_ambient_audio()
    _grade_env(pal)
    built = true
    print("ARENAVISUAL ", def.id, " kind=", kind, " props=", _props, " lights=",
            _lights.size(), " crowd=", _crowd_count, " particles=", _particle_count,
            " decals=", _decal_count, " audio=", _audio != null,
            " visual=", vc.level_name())


# ---------------------------------------------------------------- геометрия

func _begin() -> void:
    _st = SurfaceTool.new()
    _st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _st_glow = SurfaceTool.new()
    _st_glow.begin(Mesh.PRIMITIVE_TRIANGLES)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
        col: Color) -> void:
    st.set_color(col)
    st.set_normal(n)
    st.add_vertex(a)
    st.set_color(col)
    st.set_normal(n)
    st.add_vertex(b)
    st.set_color(col)
    st.set_normal(n)
    st.add_vertex(c)


## Бокс: центр/размер/цвет; glow=true — в светящийся меш (unshaded+bloom).
func _box(center: Vector3, size: Vector3, col: Color, glow: bool = false,
        basis: Basis = Basis()) -> void:
    if glow and _no_glow:
        glow = false
    var st := _st_glow if glow else _st
    if st == null:
        return
    _props += 1
    if glow:
        col = Color(col.r * 1.8, col.g * 1.8, col.b * 1.8, 1.0)
    var h := size * 0.5
    var pts := [
        Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
        Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
        Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
        Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
    ]
    for i in pts.size():
        pts[i] = center + (basis * (pts[i] as Vector3))
    var faces := [
        [0, 1, 2, 3, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)],
        [0, 3, 7, 4, Vector3(-1, 0, 0)], [1, 5, 6, 2, Vector3(1, 0, 0)],
        [3, 2, 6, 7, Vector3(0, 1, 0)], [0, 4, 5, 1, Vector3(0, -1, 0)],
    ]
    for f in faces:
        var n: Vector3 = basis * (f[4] as Vector3)
        _tri(st, pts[f[0]], pts[f[1]], pts[f[2]], n, col)
        _tri(st, pts[f[0]], pts[f[2]], pts[f[3]], n, col)


## Цилиндр: центр/радиус/высота/цвет (12 сегментов).
func _cyl(center: Vector3, radius: float, height: float, col: Color,
        glow: bool = false) -> void:
    if glow and _no_glow:
        glow = false
    var st := _st_glow if glow else _st
    if st == null:
        return
    _props += 1
    if glow:
        col = Color(col.r * 1.8, col.g * 1.8, col.b * 1.8, 1.0)
    var segs := 12
    var hy := height * 0.5
    for i in segs:
        var a0 := TAU * float(i) / float(segs)
        var a1 := TAU * float(i + 1) / float(segs)
        var p0 := center + Vector3(cos(a0) * radius, -hy, sin(a0) * radius)
        var p1 := center + Vector3(cos(a1) * radius, -hy, sin(a1) * radius)
        var p2 := p1 + Vector3(0, height, 0)
        var p3 := p0 + Vector3(0, height, 0)
        var n := Vector3(cos(a0), 0, sin(a0))
        _tri(st, p0, p1, p2, n, col)
        _tri(st, p0, p2, p3, n, col)
        _tri(st, center + Vector3(0, hy, 0), p2, p3, Vector3.UP, col)
        _tri(st, center - Vector3(0, hy, 0), p0, p1, Vector3.DOWN, col)


func _commit_meshes() -> void:
    if _st != null:
        var mesh := _st.commit()
        if mesh != null and mesh.get_surface_count() > 0:
            var mi := MeshInstance3D.new()
            mi.name = "ArenaOpaque"
            mi.mesh = mesh
            var m := StandardMaterial3D.new()
            m.vertex_color_use_as_albedo = true
            m.vertex_color_is_srgb = true
            m.roughness = 0.9
            # T7: убираем «пластик» с пола/стен: triplanar-зернистость albedo +
            # вариация шероховатости + очень мягкий bump; UV не нужны.
            # v48: triplanar + шумовые текстуры включаем только на Forward+.
            # На телефоне (mobile/compatibility) шейдер с triplanar может не
            # собраться — и тогда меш арены рисуется чёрным. Без него комната
            # остаётся цветной (цвета заданы вершинными цветами).
            if _rich_materials():
                m.albedo_texture = _noise_tex(0.06, Color(0.82, 0.82, 0.82),
                        Color(1.0, 1.0, 1.0))
                m.uv1_triplanar = true
                m.uv1_scale = Vector3(0.22, 0.22, 0.22)
                m.roughness_texture = _noise_tex(0.14, Color(0.66, 0.66, 0.66),
                        Color(1.0, 1.0, 1.0))
                m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
            mi.material_override = m
            add_child(mi)
    if _st_glow != null:
        var mesh2 := _st_glow.commit()
        if mesh2 != null and mesh2.get_surface_count() > 0:
            var mi2 := MeshInstance3D.new()
            mi2.name = "ArenaGlow"
            mi2.mesh = mesh2
            _glow_mat = StandardMaterial3D.new()
            _glow_mat.vertex_color_use_as_albedo = true
            _glow_mat.vertex_color_is_srgb = true
            _glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mi2.material_override = _glow_mat
            add_child(mi2)
    _st = null
    _st_glow = null


## T7: шумовая текстура (границы материалов арен) — triplanar, без UV.
## v48: на мобильном/совместимом рендерере не используем — см. _rich_materials().
func _rich_materials() -> bool:
    return RenderingServer.get_current_rendering_method() == "forward_plus"


func _noise_tex(freq: float, c0: Color, c1: Color) -> NoiseTexture2D:
    var n := FastNoiseLite.new()
    n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    n.frequency = freq
    n.fractal_octaves = 4
    var ramp := Gradient.new()
    ramp.set_color(0, c0)
    ramp.set_color(1, c1)
    var t := NoiseTexture2D.new()
    t.width = 256
    t.height = 256
    t.seamless = true
    t.noise = n
    t.color_ramp = ramp
    return t


# ---------------------------------------------------------------- общее
func _build_meshes(pal: Dictionary) -> void:
    _begin()
    # пол арены (14×14, как в legacy-комнате)
    _box(Vector3(0, -0.1, 0), Vector3(14.0, 0.2, 14.0), pal["floor"])
    # тёмная окантовка по краю
    _box(Vector3(0, -0.22, 0), Vector3(14.6, 0.1, 14.6), (pal["floor"] as Color).darkened(0.55))
    # бортик/настил в центре
    _box(Vector3(0, 0.01, 0), Vector3(7.6, 0.02, 7.6), (pal["floor"] as Color).lightened(0.08))


func _build_common(pal: Dictionary) -> void:
    var env: Dictionary = def.environment_modifiers
    # толпа: MultiMesh силуэтов + их огоньки/телефоны отдельными точками glow
    if def.crowd:
        _build_crowd(pal)
    # препятствия — видимый декор
    if def.obstacles:
        for i in 4:
            var bx := -4.6 + 3.1 * float(i % 2)
            var bz := -4.4 + 2.9 * float(i)
            _box(Vector3(bx, 0.42, bz), Vector3(0.9, 0.84, 0.9),
                    (pal["wall"] as Color).lightened(0.12), false,
                    Basis(Vector3.UP, 0.2 * float(i)))
            _box(Vector3(bx, 0.9, bz), Vector3(1.0, 0.06, 1.0),
                    (pal["accent"] as Color).darkened(0.25))
    # confined — видимая сетка по границе площадки
    var confined := float(env.get("confined", 0.0))
    if confined > 0.0:
        var r := confined + 0.55
        var bars := 26
        for i in bars:
            var a := TAU * float(i) / float(bars)
            if _in_view_gap(a):
                continue
            var p := Vector3(cos(a) * r, 1.05, sin(a) * r)
            _box(p, Vector3(0.06, 2.1, 0.06), (pal["accent"] as Color).darkened(0.5),
                    false, Basis(Vector3.UP, -a))
        for lvl in [0.45, 1.05, 1.65]:
            for i in bars:
                var a0 := TAU * float(i) / float(bars)
                var a1 := TAU * float(i + 1) / float(bars)
                if _in_view_gap(a0 + PI / float(bars)):
                    continue
                var p0 := Vector3(cos(a0) * r, lvl, sin(a0) * r)
                var p1 := Vector3(cos(a1) * r, lvl, sin(a1) * r)
                _box((p0 + p1) * 0.5, Vector3(0.05, 0.05,
                        p0.distance_to(p1) + 0.02), (pal["accent"] as Color).darkened(0.4), false,
                        Basis.looking_at(p1 - p0, Vector3.UP))
        # стойки-рамки по краям сектора обзора
        for sgn in [-1.0, 1.0]:
            var ae: float = CAM_AZ + sgn * VIEW_GAP
            _box(Vector3(cos(ae) * r, 1.05, sin(ae) * r), Vector3(0.10, 2.2, 0.10),
                    (pal["accent"] as Color).darkened(0.35), false,
                    Basis(Vector3.UP, -ae))
    # hazards: частицы + Decal + пульсирующая аура + звук
    var hazards: Array = env.get("hazards", [])
    for hi in hazards.size():
        var h: Dictionary = hazards[hi]
        _build_hazard(h, pal, hi)
    # wind: видимые частицы-струи по направлению ветра
    var wind = env.get("wind", Vector3.ZERO)
    if wind is Vector3 and (wind as Vector3).length() > 0.05:
        _build_wind(wind as Vector3, pal)


## Ветер: частицы-штрихи, летящие по направлению env.wind (визуал «дует»).
func _build_wind(wind: Vector3, _pal: Dictionary) -> void:
    if _budget <= 0:
        return
    var w := wind.normalized()
    var p := CPUParticles3D.new()
    p.position = Vector3(0, 3.2, 0)
    p.amount = clampi(int(float(_budget) * 0.06 * float(_q.get("particles", 1.0))), 4, 48)
    p.lifetime = 2.2
    p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    p.emission_box_extents = Vector3(12.0, 2.4, 12.0)
    p.direction = w
    p.spread = 6.0
    p.gravity = Vector3.ZERO
    p.initial_velocity_min = 2.5
    p.initial_velocity_max = 6.0
    p.scale_amount_min = 0.03
    p.scale_amount_max = 0.09
    var m := BoxMesh.new()
    m.size = Vector3(0.03, 0.03, 0.5)
    p.mesh = m
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.80, 0.86, 0.95)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    p.material_override = mat
    p.color = Color(0.82, 0.88, 0.98)
    add_child(p)
    _particle_count += p.amount


func _build_crowd(pal: Dictionary) -> void:
    var base_n := 44 if vc.visual_level < VisualConfig.Level.HIGH else 72
    var n := maxi(14, int(float(base_n) * float(_q.get("crowd", 1.0))))
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.46, 1.1, 0.32)
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = n
    var rnd := RandomNumberGenerator.new()
    rnd.seed = hash(String(def.id)) + 77
    var body_mat := StandardMaterial3D.new()
    body_mat.albedo_color = (pal["wall"] as Color).darkened(0.55)
    body_mat.roughness = 1.0
    for i in n:
        var side := i % 4
        var t := rnd.randf_range(-6.2, 6.2)
        var rad := rnd.randf_range(5.6, 6.6)
        var pos := Vector3.ZERO
        match side:
            0:
                pos = Vector3(t, 0.55, rad)
            1:
                pos = Vector3(t, 0.55, -rad)
            2:
                pos = Vector3(rad, 0.55, t)
            _:
                pos = Vector3(-rad, 0.55, t)
        var s := rnd.randf_range(0.9, 1.1)
        mm.set_instance_transform(i, Transform3D(
                Basis.from_scale(Vector3(s, s, 1.0)), pos))
        # огонёк/телефон в толпе (в glow-меш)
        if i % 3 == 0:
            _box(pos + Vector3(rnd.randf_range(-0.2, 0.2), 0.75,
                    rnd.randf_range(-0.2, 0.2)), Vector3(0.06, 0.06, 0.06),
                    Color(0.95, 0.88, 0.62), true)
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = body_mat
    mmi.custom_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 8, 20))
    add_child(mmi)
    _crowd_count = n


func _build_hazard(h: Dictionary, pal: Dictionary, idx: int) -> void:
    var pos: Vector3 = h.get("pos", Vector3.ZERO)
    var rad := float(h.get("radius", 1.0))
    var hname := String(h.get("name", "hazard"))
    var fire := hname.contains("ог") or hname.contains("искр") or hname.contains("fire")
    var col := Color(1.0, 0.45, 0.18) if fire else Color(0.72, 0.82, 0.9)
    # пульсирующая аура на полу
    # аура опасной зоны: тёмное цветное пятно на полу (не пересвечивать)
    _box(pos + Vector3(0, 0.03, 0), Vector3(rad * 1.5, 0.012, rad * 1.5),
            (col as Color).darkened(0.72), false)
    _hazard_fx.append({"pos": pos, "rad": rad, "fire": fire, "t": float(idx) * 0.7})
    # частицы
    if _budget > 0:
        var p := CPUParticles3D.new()
        p.position = pos + Vector3(0, 0.3, 0)
        p.amount = clampi(int(float(_budget) * 0.18 * float(_q.get("particles", 1.0))), 8, 90)
        p.lifetime = 2.2
        p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
        p.emission_sphere_radius = rad * 0.8
        p.direction = Vector3(0, 1, 0)
        p.spread = 18.0
        p.gravity = Vector3(0, 1.2 if fire else 0.4, 0)
        p.initial_velocity_min = 0.8
        p.initial_velocity_max = 2.2
        p.scale_amount_min = 0.12
        p.scale_amount_max = 0.34
        p.color = col
        add_child(p)
        _particle_count += p.amount
    # Decal: процедурное шумовое пятно (v71: только пока есть бюджет декалей)
    if vc.visual_on() and _decals_left > 0:
        _decals_left -= 1
        var dec := Decal.new()
        dec.position = pos + Vector3(0, 1.2, 0)
        dec.size = Vector3(rad * 1.5, 1.0, rad * 1.5)
        # радиальный тёмный след (пар/копоть), а не белый шумовой квадрат
        var grad := Gradient.new()
        grad.set_color(0, Color(0.10, 0.10, 0.11, 1.0))
        grad.set_color(1, Color(0.10, 0.10, 0.11, 0.0))
        var tex := GradientTexture2D.new()
        tex.gradient = grad
        tex.fill = GradientTexture2D.FILL_RADIAL
        tex.fill_from = Vector2(0.5, 0.5)
        tex.fill_to = Vector2(1.0, 0.5)
        tex.width = 128
        tex.height = 128
        dec.texture_albedo = tex
        dec.albedo_mix = 1.0
        dec.modulate = Color(1, 1, 1, 0.85)
        dec.cull_mask = 0xFFFFF
        add_child(dec)
        _decal_count += 1
    # звук зоны
    var stream := AudioFactory.make("fire" if fire else "steam")
    if stream != null:
        _spawn_audio(pos, stream, -22.0, 8.0)


func _spawn_audio(pos: Vector3, stream: AudioStreamWAV, db: float,
        max_dist: float) -> void:
    var p := AudioStreamPlayer3D.new()
    p.stream = stream
    p.position = pos
    p.volume_db = db
    p.max_distance = max_dist
    p.unit_size = 5.0
    p.autoplay = true
    add_child(p)
    p.play()


# ---------------------------------------------------------------- уникальное по типу

func _build_kind(pal: Dictionary) -> void:
    match kind:
        "underground":
            _kind_underground(pal)
        "club":
            _kind_club(pal)
        "street":
            _kind_street(pal)
        "cage":
            _kind_cage(pal)
        "ring":
            _kind_ring(pal)
        "beach":
            _kind_beach(pal)
        "roof":
            _kind_roof(pal)
        "factory":
            _kind_factory(pal)
        "ship":
            _kind_ship(pal)
        "boss":
            _kind_boss(pal)
        _:
            _kind_ring(pal)


func _walls(pal: Dictionary, h: float = 4.6, rad: float = 7.6) -> void:
    var wall: Color = pal["wall"]
    # четыре стены по периметру: +X/-X и +Z/-Z (камера внутри комнаты)
    _box(Vector3(rad, h * 0.5, 0), Vector3(0.4, h, rad * 2.0), wall)
    _box(Vector3(-rad, h * 0.5, 0), Vector3(0.4, h, rad * 2.0), wall)
    _box(Vector3(0, h * 0.5, rad), Vector3(rad * 2.0, h, 0.4), wall)
    _box(Vector3(0, h * 0.5, -rad), Vector3(rad * 2.0, h, 0.4), wall)


func _kind_underground(pal: Dictionary) -> void:
    _walls(pal, 3.6, 7.2)
    # низкий бетонный потолок с балками
    _box(Vector3(0, 3.6, 0), Vector3(15.0, 0.3, 15.0), (pal["wall"] as Color).darkened(0.2))
    for i in 5:
        _box(Vector3(-6.0 + 3.0 * float(i), 3.35, 0), Vector3(0.25, 0.4, 15.0),
                (pal["wall"] as Color).darkened(0.35))
    # свисающие лампы (видимые) + пятна света
    for i in 3:
        var lp := Vector3(-2.6 + 2.6 * float(i), 2.9, 1.0)
        _box(lp, Vector3(0.12, 0.5, 0.12), Color(0.2, 0.2, 0.22))
        _box(lp + Vector3(0, -0.3, 0), Vector3(0.3, 0.16, 0.3),
                Color(1.0, 0.82, 0.5), true)
    # бетонные ступени трибун
    for s in 3:
        _box(Vector3(0, 0.3 + 0.5 * float(s), -6.2 - 0.5 * float(s)),
                Vector3(12.0, 0.5, 0.9), (pal["wall"] as Color).darkened(0.1))


func _kind_club(pal: Dictionary) -> void:
    _walls(pal, 5.2, 7.8)
    # складские стены: вертикальные рёбра
    for i in 8:
        var x := -6.5 + 1.9 * float(i)
        _box(Vector3(x, 2.6, -7.4), Vector3(0.18, 5.2, 0.18),
                (pal["wall"] as Color).lightened(0.12))
    # прожекторы-конусы (видимые балки света)
    for spec in [[Vector3(-4.5, 4.6, -3.0), Color(1.0, 0.82, 0.5)],
            [Vector3(4.5, 4.6, -3.0), Color(1.0, 0.55, 0.35)]]:
        _box(spec[0], Vector3(0.5, 0.26, 0.5), Color(0.12, 0.12, 0.14))
        _box(spec[0] + Vector3(0, -0.2, 0), Vector3(0.42, 0.12, 0.42),
                spec[1], true)
        _box(spec[0] + Vector3(0, -1.6, 1.6), Vector3(0.9, 3.0, 0.9),
                (spec[1] as Color).darkened(0.1), true,
                Basis(Vector3.RIGHT, 0.5))
    # покрышки по углам (ринг из покрышек)
    for i in 4:
        var a := TAU * float(i) / 4.0 + PI * 0.25
        _cyl(Vector3(cos(a) * 4.6, 0.28, sin(a) * 4.6), 0.55, 0.55,
                Color(0.07, 0.07, 0.08))
    # «бар»: стойка и бутылки
    _box(Vector3(0, 0.55, -6.9), Vector3(6.4, 1.1, 0.5), (pal["accent"] as Color).darkened(0.5))
    for i in 6:
        _box(Vector3(-2.4 + 0.95 * float(i), 1.25, -6.9), Vector3(0.12, 0.3, 0.12),
                Color(0.45, 0.62, 0.4), true)


func _kind_street(pal: Dictionary) -> void:
    # стены-обломки и забор
    _box(Vector3(0, 2.0, -7.4), Vector3(14.0, 4.0, 0.35), pal["wall"])
    _box(Vector3(-7.4, 1.6, 0), Vector3(0.35, 3.2, 12.0), (pal["wall"] as Color).lightened(0.06))
    for i in 7:
        _box(Vector3(-6.8 + 2.2 * float(i), 0.7, 7.0), Vector3(0.12, 1.4, 0.12),
                Color(0.28, 0.30, 0.34))
    # фонари
    for i in 2:
        var lp := Vector3(-5.4 + 10.8 * float(i), 3.4, 6.4)
        _box(lp + Vector3(0, -1.7, 0), Vector3(0.14, 3.4, 0.14), Color(0.16, 0.17, 0.2))
        _box(lp, Vector3(0.5, 0.16, 0.5), Color(0.98, 0.86, 0.6), true)
    # лужа-декаль (правило «скользко» читается) + отражение-пятно
    _box(Vector3(1.2, 0.025, -1.6), Vector3(2.6, 0.02, 2.6), Color(0.24, 0.34, 0.46), false)
    _box(Vector3(1.2, 0.03, -1.6), Vector3(1.9, 0.02, 1.9), Color(0.14, 0.22, 0.32))


func _kind_cage(pal: Dictionary) -> void:
    # стальная клетка: каркас + сетка
    var rad := 4.6
    for i in 4:
        var a := TAU * float(i) / 4.0 + PI * 0.25
        if _in_view_gap(a):
            continue
        _cyl(Vector3(cos(a) * rad, 2.1, sin(a) * rad), 0.09, 4.2,
                Color(0.30, 0.32, 0.36))
    var bars := 30
    for i in bars:
        var a := TAU * float(i) / float(bars)
        if _in_view_gap(a):
            continue
        var p := Vector3(cos(a) * rad, 2.1, sin(a) * rad)
        _box(p, Vector3(0.05, 4.2, 0.05), Color(0.32, 0.35, 0.4), false,
                Basis(Vector3.UP, -a))
    for lvl in [0.5, 1.6, 2.7, 3.8]:
        for i in bars:
            var a0 := TAU * float(i) / float(bars)
            var a1 := TAU * float(i + 1) / float(bars)
            if _in_view_gap(a0 + PI / float(bars)):
                continue
            var p0 := Vector3(cos(a0) * rad, lvl, sin(a0) * rad)
            var p1 := Vector3(cos(a1) * rad, lvl, sin(a1) * rad)
            _box((p0 + p1) * 0.5, Vector3(0.05, 0.05, p0.distance_to(p1) + 0.02),
                    Color(0.32, 0.35, 0.4), false, Basis.looking_at(p1 - p0, Vector3.UP))
    # стойки-рамки по краям открытого сектора: срез читается как «вход»
    for sgn in [-1.0, 1.0]:
        var ae: float = CAM_AZ + sgn * VIEW_GAP
        _cyl(Vector3(cos(ae) * rad, 2.1, sin(ae) * rad), 0.11, 4.4,
                Color(0.36, 0.39, 0.44))
    # тёмный потолок-крышка клетки
    _box(Vector3(0, 4.2, 0), Vector3(9.8, 0.2, 9.8), (pal["wall"] as Color).darkened(0.3))


func _kind_ring(pal: Dictionary) -> void:
    # классический ринг: помост, канаты, столбы.
    # v55: верх настила — на уровне пола арены (y≈0.02), а не +0.28, как раньше.
    # Бойцы стоят на y=0 (ступни ~0.09), и на прежнем высоком помосте ноги
    # уходили в настил по колено («проваливаются ноги сквозь текстуры»).
    _box(Vector3(0, -0.25, 0), Vector3(8.6, 0.5, 8.6), (pal["floor"] as Color).lightened(0.1))
    _box(Vector3(0, -0.0075, 0), Vector3(7.4, 0.025, 7.4), Color(0.19, 0.22, 0.28))
    _ground_top = 0.005
    var h := 3.6
    for lvl in [0.62, 1.0, 1.38]:
        for side in 4:
            var sgn := -1.0 if side % 2 == 0 else 1.0
            for seg in 10:
                var t := -h + 2.0 * h * (float(seg) + 0.5) / 10.0
                var p := Vector3(t, lvl, h * sgn) if side < 2 else Vector3(h * sgn, lvl, t)
                var s := Vector3(0.7, 0.04, 0.04) if side < 2 else Vector3(0.04, 0.04, 0.7)
                _box(p, s, pal["accent"])
    for c in [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h)]:
        _cyl(c + Vector3(0, 0.75, 0), 0.1, 1.5, Color(0.16, 0.18, 0.22))
        _cyl(c + Vector3(0, 0.35, 0), 0.2, 0.3, Color(0.55, 0.12, 0.16))
    # рефери-силуэт у края
    _box(Vector3(0.0, 0.9, 4.2), Vector3(0.4, 1.8, 0.3), Color(0.62, 0.62, 0.66))
    _box(Vector3(0.0, 1.9, 4.2), Vector3(0.26, 0.26, 0.26), Color(0.72, 0.66, 0.58))
    # баннеры спонсоров (v71): раньше это были СВЕТЯЩИЕСЯ плиты, которые в игре
    # читались как «большая полупрозрачная голубая плоскость» перед рингом.
    # Теперь — матовые таблички в раме за канатами, без glow, с опорами.
    var banner := (pal["accent"] as Color).darkened(0.55)
    var frame_col := Color(0.16, 0.17, 0.20)
    for i in 4:
        var a := TAU * float(i) / 4.0
        var radial := Vector3(cos(a), 0.0, sin(a))
        var tang := Vector3(-sin(a), 0.0, cos(a))
        var p := radial * 5.75 + Vector3(0.0, 0.36, 0.0)
        var face := Basis.looking_at(-radial, Vector3.UP)
        _box(p, Vector3(1.7, 0.5, 0.05), banner, false, face)
        for s in [-1.0, 1.0]:
            _box(p + tang * (0.86 * s) + Vector3(0.0, 0.02, 0.0),
                    Vector3(0.07, 0.66, 0.07), frame_col)
        _box(p + Vector3(0.0, 0.28, 0.0), Vector3(1.82, 0.06, 0.08),
                frame_col, false, face)


func _kind_beach(pal: Dictionary) -> void:
    # песчаные дюны по краям + море вдали
    for i in 6:
        var a := TAU * float(i) / 6.0
        _cyl(Vector3(cos(a) * 7.2, 0.15, sin(a) * 7.2), 1.6, 0.3,
                (pal["floor"] as Color).lightened(0.05))
    _box(Vector3(0, -0.16, -9.6), Vector3(40.0, 0.1, 8.0), Color(0.15, 0.30, 0.42))
    _box(Vector3(0, 0.06, -8.6), Vector3(40.0, 0.02, 2.0), Color(0.42, 0.62, 0.72), true)
    # солнце в глаза
    _cyl(Vector3(5.5, 6.6, -8.0), 1.4, 0.1, Color(1.0, 0.90, 0.55), true,
            )
    # пальмы
    for i in 2:
        var bx := -6.0 + 12.0 * float(i)
        _cyl(Vector3(bx, 2.0, -5.6), 0.16, 4.0, Color(0.30, 0.24, 0.16))
        for k in 5:
            var a := TAU * float(k) / 5.0
            _box(Vector3(bx + cos(a) * 0.9, 4.1, -5.6 + sin(a) * 0.9),
                    Vector3(1.4, 0.06, 0.4), Color(0.20, 0.36, 0.18), false,
                    Basis(Vector3.UP, -a))


func _kind_roof(pal: Dictionary) -> void:
    # парапет по краю
    var rad := 7.0
    for i in 4:
        var a := TAU * float(i) / 4.0
        _box(Vector3(cos(a) * rad, 0.55, sin(a) * rad),
                Vector3(14.2, 1.1, 0.4) if i % 2 == 0 else Vector3(0.4, 1.1, 14.2),
                (pal["wall"] as Color).lightened(0.12))
    # вентиляция/блоки на крыше
    for i in 3:
        _box(Vector3(-4.8 + 4.8 * float(i), 0.6, -5.2), Vector3(1.3, 1.2, 1.3),
                Color(0.24, 0.25, 0.28))
        _cyl(Vector3(-4.8 + 4.8 * float(i), 1.35, -5.2), 0.5, 0.3,
                Color(0.18, 0.19, 0.22))
    # город вдали: силуэты домов
    var rnd := RandomNumberGenerator.new()
    rnd.seed = 606
    for i in 14:
        var a := -1.4 + 0.2 * float(i)
        var hgt := rnd.randf_range(1.2, 4.5)
        _box(Vector3(cos(a) * 17.0, hgt * 0.5 - 1.0, sin(a) * 17.0),
                Vector3(rnd.randf_range(1.2, 2.4), hgt, 1.4),
                Color(0.07, 0.08, 0.11))
        if i % 3 == 0:
            _box(Vector3(cos(a) * 16.9, hgt - 0.9, sin(a) * 16.9),
                    Vector3(0.25, 0.25, 0.25), Color(1.0, 0.86, 0.55), true)
    # флюгер-антенна (качается в tick)
    var ant := MeshInstance3D.new()
    var am := BoxMesh.new()
    am.size = Vector3(0.08, 3.0, 0.08)
    ant.mesh = am
    ant.position = Vector3(2.6, 2.8, -1.2)
    var amat := StandardMaterial3D.new()
    amat.albedo_color = Color(0.3, 0.32, 0.36)
    ant.material_override = amat
    add_child(ant)
    _sway.append({"node": ant, "amp": 0.12, "phase": 0.0, "axis": Vector3.FORWARD})


func _kind_factory(pal: Dictionary) -> void:
    _walls(pal, 5.4, 7.6)
    # трубы вдоль стен
    for i in 4:
        var y := 1.2 + 0.9 * float(i)
        _cyl(Vector3(0, y, -6.6), 0.22, 13.0, (pal["wall"] as Color).lightened(0.18))
    for i in 3:
        _cyl(Vector3(-6.6, 1.6, -4.0 + 4.0 * float(i)), 0.3, 8.0,
                (pal["wall"] as Color).lightened(0.1))
    # пар: светящиеся струи у вентилей (частицы)
    for i in 2:
        _cyl(Vector3(-4.8 + 9.6 * float(i), 1.0, 5.4), 0.28, 2.0,
                Color(0.24, 0.23, 0.22))
        _box(Vector3(-4.8 + 9.6 * float(i), 2.1, 5.4), Vector3(0.5, 0.2, 0.5),
                Color(0.85, 0.88, 0.92), true)
    # бочка с огнём
    _cyl(Vector3(3.2, 0.55, -2.4), 0.55, 1.1, Color(0.3, 0.12, 0.08))
    _cyl(Vector3(3.2, 1.35, -2.4), 0.2, 0.8, Color(0.8, 0.22, 0.05), true)


func _kind_ship(pal: Dictionary) -> void:
    # палуба: доски
    for i in 10:
        # v55: палуба тоже не выше уровня ступней (было 0.045 — ноги тонули)
        _box(Vector3(-6.3 + 1.4 * float(i), -0.02, 0), Vector3(1.2, 0.05, 13.6),
                (pal["floor"] as Color).lightened(0.06))
    _ground_top = 0.005
    # фальшборт и мачта
    for sx in [-6.6, 6.6]:
        _box(Vector3(sx, 0.5, 0), Vector3(0.25, 1.0, 13.0),
                (pal["wall"] as Color).lightened(0.12))
    _cyl(Vector3(0, 3.0, -5.5), 0.16, 6.0, Color(0.28, 0.26, 0.22))
    for lvl in [1.4, 2.4]:
        _box(Vector3(0, lvl, -5.5), Vector3(4.2, 0.06, 0.06), Color(0.28, 0.26, 0.22))
    # вода за бортом
    _box(Vector3(0, -0.7, 0), Vector3(46.0, 0.1, 46.0), Color(0.05, 0.12, 0.18))
    _box(Vector3(0, -0.6, 7.4), Vector3(30.0, 0.05, 2.2), Color(0.25, 0.45, 0.55), true)
    # фонарь
    _cyl(Vector3(4.8, 1.4, 4.6), 0.07, 2.8, Color(0.2, 0.2, 0.22))
    _box(Vector3(4.8, 2.9, 4.6), Vector3(0.24, 0.24, 0.24), Color(1.0, 0.84, 0.5), true)


func _kind_boss(pal: Dictionary) -> void:
    _walls(pal, 5.8, 7.4)
    # тёмный зал: балки и занавес
    for i in 5:
        _box(Vector3(-6.0 + 3.0 * float(i), 4.6, 0), Vector3(0.3, 0.5, 15.0),
                Color(0.06, 0.05, 0.05))
    for i in 4:
        _box(Vector3(-4.8 + 3.2 * float(i), 2.8, -7.2), Vector3(0.9, 5.0, 0.1),
                Color(0.32, 0.06, 0.06))
    # столбы с огнём по углам ринга
    for c in [Vector3(-3.6, 0, -3.6), Vector3(3.6, 0, -3.6),
            Vector3(-3.6, 0, 3.6), Vector3(3.6, 0, 3.6)]:
        _cyl(c + Vector3(0, 0.9, 0), 0.14, 1.8, Color(0.16, 0.12, 0.1))
        _box(c + Vector3(0, 1.95, 0), Vector3(0.4, 0.35, 0.4), Color(1.0, 0.42, 0.15), true)
    # «глаза» публики в темноте
    var rnd := RandomNumberGenerator.new()
    rnd.seed = 13
    for i in 24:
        var a := TAU * float(i) / 24.0
        _box(Vector3(cos(a) * 6.4, rnd.randf_range(1.2, 2.0), sin(a) * 6.4),
                Vector3(0.09, 0.05, 0.05), Color(1.0, 0.35, 0.2), true)


# ---------------------------------------------------------------- свет

func _can_add_light() -> bool:
    return _lights.size() < _lights_left


func _build_lights(pal: Dictionary) -> void:
    var dim := float(pal.get("dim", 1.0))
    var lc: Color = pal["light"]
    var energy := float(def.light_energy) * 0.85 * dim * _lm
    # основной наклонный свет зала (v71: тени по профилю качества)
    var dir := DirectionalLight3D.new()
    dir.light_color = lc
    dir.light_energy = energy * 0.6
    dir.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
    dir.shadow_enabled = _shadows_on
    add_child(dir)
    _lights.append({"light": dir, "base": dir.light_energy, "flicker": 0.0,
            "phase": 0.0})
    # практические лампы над рингом (v71: лимит источников по профилю)
    for i in 3:
        if not _can_add_light():
            break
        var pos := Vector3(-3.2 + 3.2 * float(i), 4.2, 1.6)
        var om := OmniLight3D.new()
        om.position = pos
        om.light_color = lc
        om.light_energy = energy * (0.45 if i != 1 else 0.65)
        om.omni_range = 12.0
        add_child(om)
        _lights.append({"light": om, "base": om.light_energy,
                "flicker": 0.12 if (i % 2 == 0 and dim < 0.8) else 0.0,
                "phase": float(i) * 1.7})
    # акцентный цветной прожектор
    if _can_add_light():
        var spot := SpotLight3D.new()
        spot.position = Vector3(0, 5.4, -1.0)
        spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
        spot.light_color = pal["accent"]
        spot.light_energy = energy * 0.4
        spot.spot_range = 15.0
        spot.spot_angle = 40.0
        spot.shadow_enabled = _shadows_on
        add_child(spot)
        _lights.append({"light": spot, "base": spot.light_energy, "flicker": 0.0,
                "phase": 0.4})


# ---------------------------------------------------------------- аудио/грейд

func _build_ambient_audio() -> void:
    if vc == null or not vc.visual_on():
        return
    var amb := "crowd"
    match kind:
        "street", "cage":
            amb = "city" if kind == "street" else "metal"
        "beach", "ship":
            amb = "sea"
        "roof":
            amb = "wind"
        "factory":
            amb = "steam"
        "underground":
            amb = "crowd"
        "boss":
            amb = "metal"
        "ring":
            return
    var stream := AudioFactory.make(amb)
    if stream == null:
        return
    _audio = AudioStreamPlayer3D.new()
    _audio.stream = stream
    _audio.position = Vector3(0, 2.4, 0)
    _audio.volume_db = AudioFactory.VOLUME_DB
    _audio.max_distance = AudioFactory.MAX_DISTANCE
    _audio.unit_size = 6.0
    add_child(_audio)
    _audio.play()


func _grade_env(pal: Dictionary) -> void:
    var world := get_viewport().world_3d if get_viewport() != null else null
    if world == null:
        return
    _env = world.environment
    if _env == null:
        return
    _env_saved = {"glow": _env.glow_intensity, "fog": _env.fog_density,
            "ambient": _env.ambient_light_energy,
            "bg": _env.background_color}
    var dim := float(pal.get("dim", 1.0))
    _env.ambient_light_energy = clampf(_env.ambient_light_energy * (0.55 + 0.45 * dim),
            0.0, 4.0)
    _env.background_color = Color(pal["sky"])
    _env.glow_intensity = clampf(_env.glow_intensity * (0.8 + 0.4 * dim), 0.0, 8.0)
    if vc != null:
        vc.apply_environment(_env)


func _restore_env() -> void:
    if _env == null or _env_saved.is_empty():
        return
    _env.glow_intensity = float(_env_saved.get("glow", _env.glow_intensity))
    _env.fog_density = float(_env_saved.get("fog", _env.fog_density))
    _env.ambient_light_energy = float(_env_saved.get("ambient",
            _env.ambient_light_energy))
    _env.background_color = _env_saved.get("bg", _env.background_color)
    _env_saved = {}


# ---------------------------------------------------------------- кадр

func tick(delta: float) -> void:
    if not built:
        return
    _t += delta
    # мерцание практического света
    for l in _lights:
        var f := float(l.get("flicker", 0.0))
        if f <= 0.0:
            continue
        var light: Light3D = l["light"]
        var base := float(l["base"])
        var noise := sin(_t * 13.7 + float(l["phase"])) * 0.6 \
                + sin(_t * 31.1 + float(l["phase"]) * 2.0) * 0.4
        light.light_energy = base * (1.0 + f * noise)
    # покачивание антенн/флагов
    for s in _sway:
        var node: Node3D = s["node"]
        var axis: Vector3 = s["axis"]
        var amp := float(s["amp"])
        node.rotate(axis, sin(_t * 1.4 + float(s["phase"])) * amp * delta * 8.0)
    # пульс аур опасных зон
    for h in _hazard_fx:
        var t := float(h["t"]) + delta
        h["t"] = t
    # анимированный glow-материал: общий пульс яркости
    if _glow_mat != null:
        var pulse := 0.9 + 0.1 * sin(_t * 2.3)
        _glow_mat.albedo_color = Color(pulse, pulse, pulse)


func restore() -> void:
    _restore_env()


func _exit_tree() -> void:
    _restore_env()


func stats() -> Dictionary:
    return {"built": built, "kind": kind, "props": _props, "lights": _lights.size(),
            "crowd": _crowd_count, "particles": _particle_count,
            "decals": _decal_count, "audio": _audio != null,
            "ground_top": _ground_top,
            "visual": vc.level_name() if vc != null else "OFF"}


# ---------------------------------------------------------------- T7c: детализация
## T7c: больше окружения по теме арены. Всё, что можно, добавляется в общий
## opaque/glow-меш (0 лишних draw calls); отдельными узлами идут только Decal,
## одна система частиц и 2 praktических источника света.

const T7_PART := {
    "underground": [Color(0.62, 0.57, 0.50), 40, 0.10, -0.01, 6.0],
    "club": [Color(0.60, 0.52, 0.58), 34, 0.14, 0.03, 5.0],
    "street": [Color(0.58, 0.56, 0.50), 44, 0.16, -0.02, 5.0],
    "cage": [Color(0.78, 0.76, 0.70), 36, 0.12, -0.01, 4.0],
    "ring": [Color(0.72, 0.68, 0.60), 32, 0.10, -0.01, 5.0],
    "beach": [Color(0.82, 0.74, 0.56), 52, 0.35, -0.18, 5.0],
    "roof": [Color(0.62, 0.66, 0.72), 40, 0.24, -0.04, 5.0],
    "factory": [Color(0.82, 0.82, 0.84), 48, 0.30, 0.06, 4.0],
    "ship": [Color(0.66, 0.74, 0.78), 46, 0.20, -0.02, 5.0],
    "boss": [Color(1.0, 0.58, 0.28), 40, 0.55, -0.35, 2.5],
}

var _t7_rng := RandomNumberGenerator.new()


func _t7c_seg(a: Vector3, b: Vector3, thick: float, col: Color,
        glow: bool = false) -> void:
    var d := b - a
    if d.length() < 0.01:
        return
    var basis := Basis.looking_at(d.normalized(), Vector3.UP)
    _box((a + b) * 0.5, Vector3(thick, thick, d.length()), col, glow, basis)


func _t7c_crate(x: float, z: float, s: float, col: Color, y: float = 0.0) -> void:
    _box(Vector3(x, y + s * 0.5, z), Vector3(s, s, s), col)
    _box(Vector3(x, y + s + 0.02, z), Vector3(s * 0.92, 0.05, s * 0.92),
            col.lightened(0.16))
    _box(Vector3(x, y + s * 0.5, z), Vector3(s * 0.10, s * 0.94, s * 1.01),
            col.darkened(0.25))


func _t7c_barrel(x: float, z: float, col: Color) -> void:
    _cyl(Vector3(x, 0.42, z), 0.30, 0.84, col)
    _cyl(Vector3(x, 0.76, z), 0.315, 0.06, col.darkened(0.25))
    _cyl(Vector3(x, 0.10, z), 0.315, 0.05, col.darkened(0.30))


func _t7c_post(x: float, z: float, h: float, col: Color, lamp: Color) -> void:
    _box(Vector3(x, h * 0.5, z), Vector3(0.14, h, 0.14), col)
    _box(Vector3(x, h + 0.10, z), Vector3(0.34, 0.10, 0.34), col.darkened(0.3))
    _box(Vector3(x, h + 0.02, z), Vector3(0.24, 0.06, 0.24), lamp, true)


func _build_t7c(pal: Dictionary) -> void:
    _t7_rng.seed = absi(hash(kind))
    var wall := Color(pal["wall"])
    var accent := Color(pal["accent"])
    var floor := Color(pal["floor"])
    # 1) дальний фон: силуэты построек/конструкций, чтобы не было пустой коробки
    for i in 64:
        var ang := _t7_rng.randf_range(0.0, TAU)
        var rad := _t7_rng.randf_range(9.5, 13.5)
        var h := _t7_rng.randf_range(1.0, 8.5)
        var w := _t7_rng.randf_range(0.7, 2.6)
        var d := _t7_rng.randf_range(0.7, 2.6)
        _box(Vector3(cos(ang) * rad, h * 0.5 - 0.15, sin(ang) * rad),
                Vector3(w, h, d), wall.darkened(_t7_rng.randf_range(0.30, 0.65)))
    # 2) видимые практические лампы: корпус + светящееся пятно (glow-меш)
    for i in 6:
        var a2 := TAU * float(i) / 6.0 + 0.35
        var p := Vector3(cos(a2) * 6.5, 3.5, sin(a2) * 6.5)
        _box(p, Vector3(0.24, 0.30, 0.24), Color(0.10, 0.10, 0.11))
        _box(p + Vector3(0.0, 0.22, 0.0), Vector3(0.12, 0.05, 0.12),
                accent.lightened(0.15), true)
        _t7c_seg(p + Vector3(0.0, 0.30, 0.0), Vector3(0.0, 5.6, 0.0), 0.03,
                wall.darkened(0.2))
    # 3) вывеска/баннер на дальней стене + подсветка
    _box(Vector3(0.0, 3.7, -6.86), Vector3(3.8, 1.0, 0.10),
            accent.darkened(0.30), true)
    _box(Vector3(0.0, 2.95, -6.90), Vector3(4.6, 0.06, 0.06), accent, true)
    _box(Vector3(0.0, 3.7, -6.78), Vector3(3.4, 0.62, 0.04),
            Color(0.03, 0.03, 0.04))
    # 4) пол: следы, царапины, разметка (тонкие боксы — 0 draw)
    for i in 18:
        var px := _t7_rng.randf_range(-6.0, 6.0)
        var pz := _t7_rng.randf_range(-6.0, 6.0)
        if absf(px) < 4.0 and absf(pz) < 4.0:
            continue
        _box(Vector3(px, 0.012, pz),
                Vector3(_t7_rng.randf_range(0.25, 1.1), 0.02,
                _t7_rng.randf_range(0.22, 0.9)), floor.darkened(0.32))
    match kind:
        "underground":
            for i in 4:
                _t7c_crate(-5.7, -2.0 + 2.6 * float(i), 0.75,
                        wall.lightened(0.10))
            for i in 3:
                _t7c_crate(5.8, -1.4 + 2.2 * float(i), 0.62,
                        wall.lightened(0.06), 0.0)
            _t7c_barrel(-5.4, 5.0, Color(0.32, 0.24, 0.18))
            _t7c_barrel(-4.9, 5.6, Color(0.28, 0.22, 0.17))
            # трубы под потолком и кабели по стенам
            _t7c_seg(Vector3(-6.9, 4.2, -6.6), Vector3(-6.9, 4.2, 6.6), 0.18,
                    Color(0.24, 0.22, 0.20))
            _t7c_seg(Vector3(6.9, 3.6, -6.6), Vector3(6.9, 3.6, 6.6), 0.12,
                    Color(0.20, 0.18, 0.16))
            for i in 5:
                _t7c_seg(Vector3(-6.85, 4.2, -5.0 + 2.5 * float(i)),
                        Vector3(-6.0, 4.7, -5.0 + 2.5 * float(i)), 0.04,
                        Color(0.14, 0.12, 0.10))
            for i in 3:
                _box(Vector3(-6.2 + 2.0 * float(i), 2.9, 6.7),
                        Vector3(0.26, 0.26, 0.05), accent.darkened(0.2), true)
        "club":
            # барная стойка, столики, колонки, диско-шар
            _box(Vector3(-6.0, 0.55, 1.0), Vector3(0.8, 1.1, 3.4),
                    Color(0.24, 0.15, 0.10))
            for i in 3:
                _t7c_barrel(-4.9, -1.8 + 1.8 * float(i), Color(0.30, 0.20, 0.12))
            for i in 4:
                var tx := 5.7
                var tz := -4.2 + 2.6 * float(i)
                _cyl(Vector3(tx, 0.52, tz), 0.22, 1.04, Color(0.16, 0.12, 0.10))
                _cyl(Vector3(tx, 1.06, tz), 0.46, 0.05,
                        Color(0.34, 0.24, 0.14))
            for i in 4:
                _box(Vector3(-6.7, 0.9 + 0.7 * float(i), -4.4),
                        Vector3(0.5, 1.6, 0.5), Color(0.12, 0.12, 0.14))
            _cyl(Vector3(0.0, 5.2, 0.0), 0.30, 0.30, accent.lightened(0.4), true)
            for i in 5:
                _box(Vector3(-7.0, 3.2, -4.6 + 2.2 * float(i)),
                        Vector3(0.06, 0.9, 0.30), accent, true)
        "street":
            _t7c_crate(-5.6, -5.2, 1.15, Color(0.20, 0.30, 0.22))
            _t7c_crate(-4.3, -5.6, 0.85, Color(0.22, 0.24, 0.22))
            _t7c_crate(5.6, 4.6, 0.75, Color(0.25, 0.22, 0.18))
            for i in 7:
                _box(Vector3(_t7_rng.randf_range(-5.8, 5.8), 0.12,
                        _t7_rng.randf_range(-5.8, 5.8)),
                        Vector3(0.28, 0.24, 0.24), Color(0.16, 0.16, 0.15))
            for i in 3:
                _t7c_post(-6.4 + 6.4 * float(i), 6.2, 3.2,
                        Color(0.20, 0.20, 0.22), Color(1.0, 0.86, 0.55))
            for i in 4:
                _box(Vector3(-7.0, 1.7 + 0.9 * float(i), -3.0),
                        Vector3(0.05, 0.7, 2.2), Color(0.35, 0.24, 0.30))
            _t7c_seg(Vector3(6.6, 3.0, -6.2), Vector3(6.6, 3.0, 6.2), 0.10,
                    Color(0.18, 0.18, 0.20))
        "cage":
            for i in 4:
                var cx: float = -2.9 + 1.95 * float(i)
                _box(Vector3(cx, 3.6, -5.6), Vector3(0.16, 0.16, 5.2),
                        Color(0.26, 0.26, 0.28))
                _t7c_post(cx, 5.2, 3.6, Color(0.24, 0.24, 0.26),
                        Color(0.86, 0.92, 1.0))
            _t7c_seg(Vector3(-6.4, 4.4, -6.2), Vector3(6.4, 4.4, -6.2), 0.14,
                    Color(0.30, 0.30, 0.32))
            _t7c_seg(Vector3(-6.4, 4.4, 6.2), Vector3(6.4, 4.4, 6.2), 0.14,
                    Color(0.30, 0.30, 0.32))
            _box(Vector3(0.0, 5.0, 0.0), Vector3(1.2, 0.18, 1.2),
                    Color(0.22, 0.22, 0.24))
            for i in 3:
                _box(Vector3(-0.6 + 0.6 * float(i), 4.9, 0.0),
                        Vector3(0.12, 0.06, 0.12), Color(1.0, 0.92, 0.72), true)
        "ring":
            for i in 4:
                var sx: float = -3.6 if i % 2 == 0 else 3.6
                var sz: float = -3.6 if i < 2 else 3.6
                _cyl(Vector3(sx, 0.30, sz), 0.26, 0.60, Color(0.22, 0.14, 0.10))
                _box(Vector3(sx, 0.62, sz), Vector3(0.56, 0.08, 0.56),
                        accent.darkened(0.25))
            for i in 6:
                _box(Vector3(0.0, 5.4, -5.0 + 2.0 * float(i)),
                        Vector3(0.10, 0.10, 0.10), Color(0.85, 0.82, 0.74), true)
            for i in 3:
                _box(Vector3(-5.0 + 5.0 * float(i), 4.1, -6.4),
                        Vector3(1.6, 0.9, 0.06), accent.darkened(0.15), true)
            _box(Vector3(0.0, 5.6, 0.0), Vector3(2.2, 0.08, 0.08),
                    Color(0.30, 0.28, 0.24))
        "beach":
            for i in 3:
                var ux: float = -4.8 + 4.8 * float(i)
                var uz: float = 5.0 if i % 2 == 0 else -5.0
                _cyl(Vector3(ux, 1.3, uz), 0.06, 2.6, Color(0.35, 0.28, 0.18))
                _box(Vector3(ux, 2.6, uz), Vector3(2.4, 0.10, 2.4),
                        Color(0.78, 0.34, 0.26) if i % 2 == 0 else
                        Color(0.28, 0.52, 0.62))
            for i in 4:
                _t7c_crate(-5.8 + 3.7 * float(i), -5.8, 0.7,
                        Color(0.42, 0.34, 0.22))
            # пальмы-силуэты
            for i in 4:
                var px2: float = -7.0 + 4.7 * float(i)
                _cyl(Vector3(px2, 2.2, 7.2), 0.10, 4.4, Color(0.16, 0.14, 0.10))
                for k in 5:
                    var aa := TAU * float(k) / 5.0
                    _t7c_seg(Vector3(px2, 4.4, 7.2),
                            Vector3(px2 + cos(aa) * 1.5, 4.0, 7.2 + sin(aa) * 1.5),
                            0.10, Color(0.14, 0.26, 0.16))
            _box(Vector3(0.0, 0.18, 8.6), Vector3(18.0, 0.36, 1.2),
                    Color(0.18, 0.30, 0.36))
        "roof":
            for i in 3:
                _box(Vector3(-5.6, 0.55, -3.4 + 3.0 * float(i)),
                        Vector3(1.2, 1.1, 0.9), Color(0.30, 0.30, 0.32))
                _box(Vector3(-5.6, 0.55, -3.4 + 3.0 * float(i)),
                        Vector3(1.24, 0.08, 0.94), Color(0.18, 0.18, 0.20))
                for k in 4:
                    _box(Vector3(-6.1 + 0.34 * float(k), 1.15,
                            -3.4 + 3.0 * float(i)), Vector3(0.04, 0.05, 0.7),
                            Color(0.62, 0.64, 0.68), true)
            for i in 3:
                _box(Vector3(5.8, 1.7, -4.6 + 4.4 * float(i)),
                        Vector3(0.08, 3.4, 0.08), Color(0.26, 0.26, 0.28))
                _box(Vector3(5.8, 3.45, -4.6 + 4.4 * float(i)),
                        Vector3(0.14, 0.14, 0.14), Color(1.0, 0.25, 0.18), true)
            _cyl(Vector3(4.2, 1.0, 4.6), 0.9, 2.0, Color(0.24, 0.26, 0.28))
            _cyl(Vector3(4.2, 2.1, 4.6), 0.96, 0.2, Color(0.18, 0.20, 0.22))
            _box(Vector3(0.0, 0.10, 7.8), Vector3(16.0, 0.20, 0.8),
                    Color(0.30, 0.30, 0.32))
        "factory":
            for i in 3:
                _box(Vector3(-5.4, 0.7, -3.6 + 3.2 * float(i)),
                        Vector3(1.5, 1.4, 1.2), Color(0.26, 0.26, 0.24))
                _box(Vector3(-5.4, 1.42, -3.6 + 3.2 * float(i)),
                        Vector3(0.9, 0.12, 0.8), Color(0.16, 0.16, 0.15))
            _box(Vector3(4.8, 0.45, 0.0), Vector3(1.4, 0.9, 7.0),
                    Color(0.20, 0.20, 0.19))
            for i in 6:
                _cyl(Vector3(4.8, 0.95, -3.2 + 1.28 * float(i)), 0.14, 0.12,
                        Color(0.34, 0.34, 0.32))
            for i in 4:
                _t7c_barrel(-6.2, -2.0 + 2.4 * float(i), Color(0.30, 0.24, 0.16))
            # трубы и пар
            _t7c_seg(Vector3(-6.8, 3.4, -6.4), Vector3(-6.8, 3.4, 6.4), 0.22,
                    Color(0.28, 0.24, 0.18))
            _t7c_seg(Vector3(-6.4, 3.4, 5.4), Vector3(-5.2, 1.2, 5.4), 0.16,
                    Color(0.26, 0.22, 0.16))
            for i in 3:
                _box(Vector3(-6.9, 3.4, -3.0 + 3.0 * float(i)),
                        Vector3(0.10, 0.36, 0.10), Color(0.85, 0.66, 0.18), true)
            for i in 4:
                _box(Vector3(-3.4 + 2.2 * float(i), 0.03, 5.9),
                        Vector3(1.2, 0.04, 0.40), Color(0.82, 0.72, 0.16))
        "ship":
            for i in 3:
                var stack_h: float = 1.4 + 0.7 * float(i)
                _box(Vector3(-5.8, stack_h * 0.5, -4.6 + 3.4 * float(i)),
                        Vector3(2.0, stack_h, 1.3),
                        Color(0.16, 0.28, 0.34) if i % 2 == 0 else
                        Color(0.42, 0.20, 0.16))
            for i in 3:
                _box(Vector3(5.6, 1.1, -4.4 + 3.9 * float(i)),
                        Vector3(1.2, 2.2, 0.9), Color(0.20, 0.30, 0.34))
            _box(Vector3(0.0, 3.0, -6.8), Vector3(0.10, 6.0, 0.10),
                    Color(0.28, 0.28, 0.30))
            _t7c_seg(Vector3(0.0, 5.6, -6.8), Vector3(6.0, 1.0, 6.0), 0.04,
                    Color(0.22, 0.22, 0.24))
            _t7c_seg(Vector3(0.0, 5.6, -6.8), Vector3(-6.0, 1.0, 6.0), 0.04,
                    Color(0.22, 0.22, 0.24))
            for i in 3:
                _box(Vector3(-6.2, 0.6, -2.4 + 2.4 * float(i)),
                        Vector3(0.10, 1.2, 0.10), Color(0.30, 0.30, 0.32))
            _box(Vector3(0.0, 0.20, 8.4), Vector3(18.0, 0.40, 2.0),
                    Color(0.06, 0.12, 0.16))
        "boss":
            for i in 4:
                var bx: float = -3.2 + 2.1 * float(i)
                _box(Vector3(bx, 2.6, -7.0), Vector3(0.14, 5.2, 0.14),
                        Color(0.20, 0.18, 0.16))
                _box(Vector3(bx, 5.15, -7.0), Vector3(0.20, 0.20, 0.16),
                        Color(0.90, 0.72, 0.32), true)
            for i in 4:
                _box(Vector3(-5.9 + 3.9 * float(i), 4.2, 6.8),
                        Vector3(1.4, 2.2, 0.08), Color(0.10, 0.10, 0.12))
                _box(Vector3(-5.9 + 3.9 * float(i), 4.2, 6.72),
                        Vector3(1.1, 1.7, 0.04),
                        Color(0.32, 0.44, 0.62) if i % 2 == 0 else
                        Color(0.52, 0.36, 0.20), true)
            for i in 4:
                _cyl(Vector3(-6.0 + 4.0 * float(i), 1.6, -2.0), 0.34, 3.2,
                        Color(0.42, 0.34, 0.20))
                _box(Vector3(-6.0 + 4.0 * float(i), 3.3, -2.0),
                        Vector3(0.86, 0.16, 0.86), Color(0.55, 0.42, 0.20))
            _t7c_seg(Vector3(-7.0, 5.6, -6.6), Vector3(7.0, 5.6, -6.6), 0.10,
                    Color(0.26, 0.22, 0.18))
    # 5) дальняя толпа/зрители: статичные силуэты за стенами (0 draw)
    if def.crowd:
        for i in 70:
            var a3 := _t7_rng.randf_range(0.0, TAU)
            var r3 := _t7_rng.randf_range(8.2, 9.6)
            var hh := _t7_rng.randf_range(1.4, 2.0)
            _box(Vector3(cos(a3) * r3, 0.7 + _t7_rng.randf_range(0.0, 1.2),
                    sin(a3) * r3), Vector3(0.42, hh, 0.42),
                    wall.darkened(_t7_rng.randf_range(0.35, 0.6)))


func _build_t7c_live(pal: Dictionary) -> void:
    # 5) Decal: пятна/царапины на полу (очищаются вместе с комнатой)
    _t7_rng.seed = absi(hash(kind)) + 17
    var stain: Color = pal["accent"]
    stain = stain.darkened(0.55)
    for i in 3:
        var dec := Decal.new()
        var grad := Gradient.new()
        grad.set_color(0, Color(stain.r, stain.g, stain.b, 1.0))
        grad.set_color(1, Color(stain.r, stain.g, stain.b, 0.0))
        var tex := GradientTexture2D.new()
        tex.gradient = grad
        tex.fill = GradientTexture2D.FILL_RADIAL
        tex.fill_from = Vector2(0.5, 0.5)
        tex.fill_to = Vector2(1.0, 0.5)
        tex.width = 96
        tex.height = 96
        dec.texture_albedo = tex
        dec.albedo_mix = 0.55
        dec.modulate = Color(0.45, 0.42, 0.38, 0.55)
        dec.size = Vector3(_t7_rng.randf_range(1.0, 1.9), 0.7,
                _t7_rng.randf_range(1.0, 1.9))
        dec.position = Vector3(_t7_rng.randf_range(-5.6, 5.6), 0.02,
                _t7_rng.randf_range(-5.6, 5.6))
        add_child(dec)
        _decal_count += 1
    # 6) частицы по теме арены (одна система на арену)
    var pp: Array = T7_PART.get(kind, T7_PART["ring"])
    var cp := CPUParticles3D.new()
    cp.name = "T7cParticles"
    cp.amount = int(pp[1])
    cp.lifetime = float(pp[4])
    cp.preprocess = 2.0
    cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    cp.emission_box_extents = Vector3(5.5, 1.6, 5.5)
    cp.direction = Vector3(0.0, 1.0, 0.0)
    cp.spread = 35.0
    cp.gravity = Vector3(0.0, float(pp[3]), 0.0)
    cp.initial_velocity_min = float(pp[2]) * 0.4
    cp.initial_velocity_max = float(pp[2])
    cp.scale_amount_min = 0.012
    cp.scale_amount_max = 0.045
    var pcol: Color = pp[0]
    cp.color = pcol
    cp.position = Vector3(0.0, 1.8, 0.0)
    cp.emitting = true
    add_child(cp)
    _particle_count += 1
    # 7) praktический свет: 2 мягких источника без теней (бойцов не пересвечиваем)
    for p in [Vector3(-5.2, 3.3, 3.2), Vector3(5.2, 3.3, -3.2)]:
        var om := OmniLight3D.new()
        om.position = p
        var lcol: Color = pal["light"]
        om.light_color = lcol
        om.light_energy = 0.55 * _lm
        om.omni_range = 7.0
        om.shadow_enabled = false
        add_child(om)
