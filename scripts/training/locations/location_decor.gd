extends Node3D
## Этап 5 визуального промта: декор пяти тренировочных локаций.
##
## Модуль живёт под `location_root` тренировки и строит всё, что делает локацию
## «настоящей»: hero-props из примитивов, практический свет с видимыми лампами,
## процедурный ambient-звук, MultiMesh-декор, Decal-пятна, один уникальный
## эффект на локацию и цветовой грейд WorldEnvironment.
##
## Жёсткие правила (важно для гейта):
##  * при `visual_level = OFF` модуль НИЧЕГО не создаёт и не трогает — кадр
##    локации обязан остаться побайтово прежним;
##  * геометрия станций, их подписи и кольца не меняются; декор ставится вне
##    зоны ходьбы (|x| > 4.2, z < -3.0 или z > 3.7) и не перекрывает станции;
##  * все числа — константы ниже или поля VisualConfig; разбросанного хардкода нет.
##
## Точки входа: `build()`, `tick()`, `update_focus()`, `restore()`,
## `debug_camera()`, `stats()`.

const AudioFactory := preload("res://scripts/training/locations/location_audio.gd")

# ---------------------------------------------------------------- бюджеты/константы
## Энергия практических ламп локации (умножается на VisualConfig.light_mult()).
const PRACTICAL_ENERGY := 0.85
## Энергия подсветки активной станции.
const ACCENT_ENERGY := 1.35
## Цвет подсветки активной станции (тёплый акцент, чтобы кольцо читалось).
const ACCENT_COLOR := Color(1.0, 0.78, 0.34)
## Свечение «ламп/окон» (эмиссия меша): базовая энергия.
const GLOW_ENERGY := 2.1
## Сколько частиц на локацию (урезается VisualConfig.particle_budget()).
const PARTICLES := {"gym": 36, "park": 64, "dojo": 30, "roof": 52, "basement": 44}
## Размер пятен/царапин (Decal), м.
const DECAL_SIZE := Vector3(2.2, 0.55, 2.2)
## Прозрачность пятен: мягко, чтобы не забивать пол.
const DECAL_ALPHA := 0.55
## Плавность подсветки станции, 1/с.
const FOCUS_LERP := 5.0
## Дальность и громкость ambient-звука — в location_audio.gd.

## Палитры локаций: цвет материалов пропсов. Меняются только визуально.
const PALETTES := {
    "gym": {
        "wood": Color(0.46, 0.30, 0.17), "wood2": Color(0.60, 0.42, 0.24),
        "metal": Color(0.43, 0.46, 0.52), "dark": Color(0.10, 0.11, 0.13),
        "fabric": Color(0.55, 0.18, 0.15), "canvas": Color(0.16, 0.30, 0.46),
        "paper": Color(0.86, 0.82, 0.70), "stone": Color(0.30, 0.30, 0.31),
        "glow": Color(1.0, 0.80, 0.52), "accent": Color(0.82, 0.16, 0.14),
        "ambient": Color(0.30, 0.28, 0.24), "fog": Color(0.06, 0.055, 0.05),
        "fog_density": 0.004, "sat": 1.02, "contrast": 1.02, "bright": 1.0, "ambient_e": 0.30,
    },
    "park": {
        "wood": Color(0.34, 0.26, 0.17), "wood2": Color(0.46, 0.34, 0.20),
        "metal": Color(0.28, 0.31, 0.29), "dark": Color(0.09, 0.14, 0.09),
        "grass": Color(0.24, 0.44, 0.20), "grass2": Color(0.31, 0.52, 0.24),
        "leaf": Color(0.66, 0.54, 0.16), "paper": Color(0.88, 0.86, 0.74),
        "glow": Color(0.98, 0.92, 0.74), "accent": Color(0.95, 0.63, 0.20),
        "ambient": Color(0.55, 0.68, 0.72), "fog": Color(0.62, 0.74, 0.78),
        "fog_density": 0.004, "sat": 1.02, "contrast": 0.99, "bright": 0.88,
        "sky": Color(0.38, 0.56, 0.75), "ambient_e": 0.26,
    },
    "dojo": {
        "wood": Color(0.36, 0.24, 0.14), "wood2": Color(0.52, 0.36, 0.20),
        "paper": Color(0.93, 0.90, 0.80), "dark": Color(0.13, 0.10, 0.08),
        "straw": Color(0.72, 0.64, 0.44), "straw2": Color(0.62, 0.55, 0.38),
        "metal": Color(0.40, 0.38, 0.33), "ink": Color(0.10, 0.09, 0.08),
        "glow": Color(1.0, 0.86, 0.58), "accent": Color(0.92, 0.72, 0.30),
        "ambient": Color(0.36, 0.30, 0.22), "fog": Color(0.09, 0.075, 0.06),
        "fog_density": 0.005, "sat": 1.0, "contrast": 1.0, "bright": 1.0, "ambient_e": 0.26,
    },
    "roof": {
        "stone": Color(0.34, 0.35, 0.38), "stone2": Color(0.26, 0.27, 0.30),
        "metal": Color(0.30, 0.34, 0.40), "dark": Color(0.10, 0.11, 0.14),
        "rust": Color(0.34, 0.20, 0.13), "canvas": Color(0.26, 0.30, 0.38),
        "city": Color(0.20, 0.23, 0.32), "city2": Color(0.28, 0.31, 0.40),
        "glow": Color(0.72, 0.84, 1.0), "accent": Color(0.62, 0.78, 1.0),
        "ambient": Color(0.34, 0.42, 0.58), "fog": Color(0.10, 0.13, 0.20),
        "fog_density": 0.010, "sat": 0.96, "contrast": 1.03, "bright": 1.0,
        "sky": Color(0.09, 0.13, 0.20), "ambient_e": 0.36,
    },
    "basement": {
        "stone": Color(0.20, 0.20, 0.20), "stone2": Color(0.15, 0.15, 0.15),
        "dark": Color(0.07, 0.07, 0.08), "metal": Color(0.30, 0.30, 0.32),
        "rust": Color(0.36, 0.20, 0.13), "tire": Color(0.08, 0.08, 0.09),
        "wood": Color(0.30, 0.24, 0.18), "glow": Color(1.0, 0.74, 0.40),
        "accent": Color(0.98, 0.62, 0.26), "ambient": Color(0.20, 0.17, 0.14),
        "fog": Color(0.05, 0.045, 0.04), "fog_density": 0.014,
        "sat": 0.95, "contrast": 1.03, "bright": 1.06, "ambient_e": 0.20,
    },
}

## Камеры демо-кадров: hero — на главный снаряд локации, stations — линия станций.
const HERO_CAM := {
    "gym": {"pos": Vector3(-1.15, 1.62, -1.95), "look": Vector3(-3.0, 1.28, -3.50), "fov": 60.0},
    "park": {"pos": Vector3(-1.75, 1.75, -1.95), "look": Vector3(-4.55, 1.75, -3.45), "fov": 58.0},
    "dojo": {"pos": Vector3(-2.05, 1.55, -2.10), "look": Vector3(-4.55, 1.15, -1.05), "fov": 55.0},
    "roof": {"pos": Vector3(2.25, 1.85, -2.05), "look": Vector3(4.60, 1.35, -3.55), "fov": 58.0},
    "basement": {"pos": Vector3(-2.30, 1.35, -1.75), "look": Vector3(-4.60, 0.85, 1.15), "fov": 56.0},
}
const WIDE_CAM := {"pos": Vector3(0.10, 2.30, 3.45), "look": Vector3(0.10, 0.85, -3.30), "fov": 78.0}
const STATIONS_CAM := {"pos": Vector3(2.45, 2.30, 4.35), "look": Vector3(1.90, 0.95, -1.40), "fov": 55.0}

var visual = null
var loc_def: TrainingLocationDef = null
var built := false

var _st: SurfaceTool = null
var _st_glow: SurfaceTool = null
var _pal: Dictionary = {}
var _lm := 1.0
var _particles_budget := 0
var _t := 0.0
## v71: профиль качества и бюджеты (свет/декали/троттлинг анимаций).
var _q: Dictionary = {}
var _decals_left := 99
var _lights_left := 99
var _low_quality := false
var _tick_acc := 0.0

var _lights: Array = []
var _flicker: Array = []
var _sway: Array = []
## Качающиеся лампы: {light, base_pos, amp, freq, phase}.
var _swing: Array = []
var _accent: SpotLight3D = null
var _accent_base := 0.0
var _focus_target := Vector3(0.0, 0.0, -1.4)
var _focus_on := false

var _main: Node = null
var _env: Environment = null
var _env_saved := {}
var _env_applied := false


# ---------------------------------------------------------------- публичный API

## Построить декор локации. При OFF не делает вообще ничего (гейт байт-в-байт).
func build(main_ref: Node, vc, loc: TrainingLocationDef) -> void:
    _main = main_ref
    visual = vc
    loc_def = loc
    if visual == null or not visual.visual_on() or loc == null:
        return
    _lm = float(visual.light_mult())
    _particles_budget = int(visual.particle_budget())
    _q = visual.quality_profile()
    _decals_left = int(_q.get("decal_budget", 99))
    _lights_left = int(_q.get("light_budget", 99))
    _low_quality = int(_q.get("quality", 1)) >= VisualConfig.Quality.MEDIUM
    if visual.has_method("maybe_apply_quality"):
        visual.maybe_apply_quality(get_viewport(), get_window())
    _pal = PALETTES.get(loc.id, PALETTES["gym"])
    _st = SurfaceTool.new()
    _st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _st_glow = SurfaceTool.new()
    _st_glow.begin(Mesh.PRIMITIVE_TRIANGLES)
    match loc.id:
        "park":
            _build_park()
        "dojo":
            _build_dojo()
        "roof":
            _build_roof()
        "basement":
            _build_basement()
        _:
            _build_gym()
    _commit_meshes()
    _build_lights()
    _trim_lights()
    _build_ambient_audio()
    _grade()
    built = true
    print("DECOR локация=", loc.id, " props=", _prop_count, " lights=", _lights.size(),
            " mm=", _mm_count, " decals=", _decal_count, " particles=", _particle_amount,
            " audio=", _audio_ok, " env=", _env_applied,
            " quality=", String(_q.get("name", "?")),
            " light_budget=", _lights_left, " decal_budget=", _decals_left)


## Нужны ли локации стены «коробкой» (0 — полные, 1 — парапет крыши, 2 — открытый парк).
## При OFF всегда 0 — комната строится как раньше.
static func shell_mode(vc, loc_id: String) -> int:
    if vc == null or not vc.visual_on():
        return 0
    match loc_id:
        "roof":
            return 1
        "park":
            return 2
        _:
            return 0


## Кадр: анимация уникального эффекта локации (качание лампы, листья, пар…).
func tick(delta: float) -> void:
    if not built:
        return
    # v71: на среднем/низком профиле анимации декора обновляем 20 Гц вместо 60 —
    # меньше работы главного потока, визуально незаметно (мерцание/качание).
    if _low_quality:
        _tick_acc += delta
        if _tick_acc < 0.05:
            return
        delta = _tick_acc
        _tick_acc = 0.0
    _t += delta
    for f in _flicker:
        var l: Light3D = f["light"]
        var base := float(f["base"])
        var flick := 0.82 + 0.18 * sin(_t * float(f["freq"]) + float(f["phase"]))
        if f.has("blink"):
            var blink := sin(_t * 7.3) * sin(_t * 2.9)
            flick *= 1.0 - 0.35 * maxf(0.0, blink - 0.6)
        l.light_energy = base * flick
    for s in _sway:
        var n: Node3D = s["node"]
        n.rotation_degrees = Vector3(0.0, 0.0, sin(_t * float(s["freq"]) + float(s["phase"]))
                * float(s["amp"]))
    for w in _swing:
        var l: Light3D = w["light"]
        var base: Vector3 = w["base_pos"]
        l.position = base + Vector3(sin(_t * float(w["freq"]) + float(w["phase"]))
                * float(w["amp"]), 0.0, 0.0)
    if _accent != null:
        var target := _focus_target if _focus_on else Vector3(0.0, 2.9, -1.4)
        _accent.global_position = _accent.global_position.lerp(target,
                clampf(delta * FOCUS_LERP, 0.0, 1.0))
        var e := _accent_base * (1.0 if _focus_on else 0.45)
        _accent.light_energy = lerpf(_accent.light_energy, e, clampf(delta * 3.0, 0.0, 1.0))


## Подсветка активной станции: позиция над станцией и включение/выключение.
func update_focus(pos: Vector3, on: bool) -> void:
    if _accent == null:
        return
    _focus_target = pos + Vector3(0.0, 2.35, 0.0)
    _focus_on = on


## Вернуть окружение к состоянию до входа в локацию (при OFF ничего не делал).
func restore() -> void:
    if not _env_applied or _env == null:
        return
    _env.ambient_light_energy = float(_env_saved.get("ambient", _env.ambient_light_energy))
    _env.ambient_light_color = _env_saved.get("ambient_color", _env.ambient_light_color)
    _env.background_color = _env_saved.get("bg", _env.background_color)
    _env.fog_enabled = bool(_env_saved.get("fog", _env.fog_enabled))
    _env.fog_light_color = _env_saved.get("fog_color", _env.fog_light_color)
    _env.fog_density = float(_env_saved.get("fog_density", _env.fog_density))
    _env.glow_intensity = float(_env_saved.get("glow", _env.glow_intensity))
    _env.adjustment_enabled = bool(_env_saved.get("adj", false))
    _env.adjustment_contrast = float(_env_saved.get("contrast", 1.0))
    _env.adjustment_saturation = float(_env_saved.get("sat", 1.0))
    _env.adjustment_brightness = float(_env_saved.get("bright", 1.0))
    _env_applied = false


## Позиция камеры демо-кадра: "hero" / "wide" / "stations".
func debug_camera(kind: String) -> Dictionary:
    if kind == "hero" and loc_def != null:
        return HERO_CAM.get(loc_def.id, HERO_CAM["gym"])
    if kind == "stations":
        return STATIONS_CAM
    return WIDE_CAM


## Сводка для отчёта/лога (сколько чего построено).
func stats() -> Dictionary:
    return {"loc": loc_def.id if loc_def != null else "",
            "props": _prop_count, "lights": _lights.size(),
            "multimesh": _mm_count, "decals": _decal_count,
            "particles": _particle_amount, "audio": _audio_ok,
            "env": _env_applied}


var _prop_count := 0
var _mm_count := 0
var _decal_count := 0
var _particle_amount := 0
var _audio_ok := false


# ---------------------------------------------------------------- примитивы

func _col(key: String, fallback: Color = Color.GRAY) -> Color:
    return _pal.get(key, fallback)


## Коробка (кубический стиль игры): центр, размер, цвет, свечение, поворот вокруг Y.
func _box(center: Vector3, size: Vector3, color: Color, glow: bool = false,
        yaw_deg: float = 0.0) -> void:
    var b := Basis.IDENTITY
    if not is_zero_approx(yaw_deg):
        b = Basis(Vector3.UP, deg_to_rad(yaw_deg))
    _box_b(center, size, b, color, glow)


func _box_b(center: Vector3, size: Vector3, basis: Basis, color: Color,
        glow: bool = false) -> void:
    var h := size * 0.5
    var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
            Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
            Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
            Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
    for i in c.size():
        var p: Vector3 = c[i]
        c[i] = center + basis * p
    var nb := basis.inverse().transposed()
    # 6 граней: (0,1,2,3) — передняя по -Z и т.д.
    _face(c[4], c[5], c[6], c[7], nb * Vector3(0, 0, 1), color, glow)
    _face(c[1], c[0], c[3], c[2], nb * Vector3(0, 0, -1), color, glow)
    _face(c[5], c[1], c[2], c[6], nb * Vector3(1, 0, 0), color, glow)
    _face(c[0], c[4], c[7], c[3], nb * Vector3(-1, 0, 0), color, glow)
    _face(c[3], c[7], c[6], c[2], nb * Vector3(0, 1, 0), color, glow)
    _face(c[4], c[0], c[1], c[5], nb * Vector3(0, -1, 0), color, glow)
    _prop_count += 1 if not glow else 0


## Цилиндр вдоль произвольной оси (блины, трубы, стволы, свечи). Крышки — веером.
func _cyl(center: Vector3, radius: float, height: float, color: Color,
        segs: int = 8, axis: Vector3 = Vector3.UP, glow: bool = false) -> void:
    var q := Quaternion(Vector3.UP, axis.normalized())
    var b := Basis(q)
    var hh := height * 0.5
    var top := center + b * Vector3(0, hh, 0)
    var bot := center - b * Vector3(0, hh, 0)
    var pts: Array = []
    for i in segs:
        var a := TAU * float(i) / float(segs)
        pts.append(b * Vector3(cos(a) * radius, 0.0, sin(a) * radius))
    for i in segs:
        var j := (i + 1) % segs
        var p0: Vector3 = bot + pts[i]
        var p1: Vector3 = bot + pts[j]
        var p2: Vector3 = top + pts[j]
        var p3: Vector3 = top + pts[i]
        var n: Vector3 = (b * (Vector3(cos(TAU * (float(i) + 0.5) / float(segs)), 0.0,
                sin(TAU * (float(i) + 0.5) / float(segs))))).normalized()
        _face(p0, p1, p2, p3, n, color, glow)
        _tri(bot + pts[j], bot + pts[i], bot, -(b * Vector3.UP), color, glow)
        _tri(top + pts[i], top + pts[j], top, b * Vector3.UP, color, glow)
    _prop_count += 1 if not glow else 0


func _face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color,
        glow: bool) -> void:
    _tri(a, b, c, n, color, glow)
    _tri(a, c, d, n, color, glow)


func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color, glow: bool) -> void:
    var st := _st_glow if glow else _st
    for p in [a, b, c]:
        st.set_color(color)
        st.set_normal(n)
        st.add_vertex(p)


func _commit_meshes() -> void:
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.vertex_color_is_srgb = true
    mat.roughness = 0.88
    mat.metallic = 0.0
    mat.cull_mode = BaseMaterial3D.CULL_BACK
    # T7: зернистость/вариация шероховатости — поверхности локации не «пластик»
    mat.albedo_texture = _noise_tex(0.05, Color(0.84, 0.84, 0.84), Color(1.0, 1.0, 1.0))
    mat.uv1_triplanar = true
    mat.uv1_scale = Vector3(0.24, 0.24, 0.24)
    mat.roughness_texture = _noise_tex(0.13, Color(0.70, 0.70, 0.70),
            Color(1.0, 1.0, 1.0))
    mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    var mi := MeshInstance3D.new()
    mi.name = "Props"
    mi.mesh = _st.commit()
    mi.material_override = mat
    add_child(mi)
    var gmat := StandardMaterial3D.new()
    gmat.albedo_color = Color(0.10, 0.09, 0.07)
    gmat.emission_enabled = true
    gmat.emission = _col("glow")
    gmat.emission_energy_multiplier = GLOW_ENERGY * _lm
    gmat.roughness = 0.6
    var gi := MeshInstance3D.new()
    gi.name = "GlowProps"
    gi.mesh = _st_glow.commit()
    gi.material_override = gmat
    add_child(gi)


## T7: шумовая текстура (triplanar) — убирает «пластик» с поверхностей локации.
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


# ---------------------------------------------------------------- свет
func _add_omni(pos: Vector3, color: Color, energy: float, rng: float,
        flicker: float = 0.0) -> OmniLight3D:
    var l := OmniLight3D.new()
    l.name = "Practical"
    l.light_color = color
    l.light_energy = energy * _lm
    l.omni_range = rng
    l.shadow_enabled = false
    l.position = pos
    add_child(l)
    _lights.append(l)
    if flicker > 0.0:
        _flicker.append({"light": l, "base": l.light_energy, "freq": flicker,
                "phase": 1.7, "blink": true})
    return l


func _add_spot(pos: Vector3, look: Vector3, color: Color, energy: float, rng: float,
        angle: float = 46.0) -> SpotLight3D:
    var l := SpotLight3D.new()
    l.name = "PracticalSpot"
    l.light_color = color
    l.light_energy = energy * _lm
    l.spot_range = rng
    l.spot_angle = angle
    l.shadow_enabled = false
    l.position = pos
    add_child(l)
    l.look_at(look, Vector3.UP)
    _lights.append(l)
    return l


func _build_lights() -> void:
    var warm := _col("glow")
    match loc_def.id:
        "gym":
            # лампы качаются (уникальный эффект зала): позиция света ходит по X
            for i in 2:
                var lp := Vector3(-2.6 + float(i) * 5.5, 3.15, -2.4 + float(i) * 1.2)
                var ll := _add_omni(lp, warm, PRACTICAL_ENERGY * (1.65 - 0.15 * float(i)), 7.0)
                _swing.append({"light": ll, "base_pos": lp, "amp": 0.16,
                        "freq": 1.15 + 0.12 * float(i), "phase": 0.4 * float(i)})
            _add_spot(Vector3(0.4, 3.4, 1.6), Vector3(1.9, 0.0, -1.4), warm,
                    PRACTICAL_ENERGY * 1.1, 9.0, 50.0)
        "park":
            _add_spot(Vector3(-2.4, 4.6, 2.6), Vector3(-0.4, 0.0, -2.2),
                    Color(1.0, 0.97, 0.86), PRACTICAL_ENERGY * 0.85, 14.0, 42.0)
            _add_omni(Vector3(4.6, 2.35, 2.8), warm, PRACTICAL_ENERGY * 0.7, 6.0)
        "dojo":
            _add_omni(Vector3(0.0, 2.9, -2.6), warm, PRACTICAL_ENERGY * 1.45, 8.0)
            _add_omni(Vector3(-4.3, 1.35, -1.0), Color(1.0, 0.86, 0.58),
                    PRACTICAL_ENERGY * 0.7, 3.6)
            _add_spot(Vector3(0.4, 3.2, 2.2), Vector3(1.2, 0.0, -2.0), warm,
                    PRACTICAL_ENERGY * 0.9, 10.0, 44.0)
        "roof":
            _add_spot(Vector3(-3.4, 5.2, 3.4), Vector3(0.8, 0.0, -2.4),
                    Color(0.82, 0.88, 1.0), PRACTICAL_ENERGY * 1.00, 16.0, 40.0)
            _add_omni(Vector3(4.7, 1.15, -3.4), Color(1.0, 0.72, 0.34),
                    PRACTICAL_ENERGY * 0.9, 4.5)
            # холодный заполняющий: ночная крыша не должна быть чёрной
            _add_omni(Vector3(0.0, 2.4, 1.6), Color(0.55, 0.66, 0.92),
                    PRACTICAL_ENERGY * 0.70, 7.5)
        "basement":
            var l := _add_omni(Vector3(0.6, 2.55, 0.4), warm,
                    PRACTICAL_ENERGY * 1.40, 7.0, 5.1)
            l.light_energy = PRACTICAL_ENERGY * 1.40 * _lm
            _add_omni(Vector3(-4.2, 1.0, 1.2), Color(1.0, 0.62, 0.32),
                    PRACTICAL_ENERGY * 0.6, 3.2)
    # акцент на активной станции: пятно сверху, позиция ведётся из tick()
    _accent = SpotLight3D.new()
    _accent.name = "StationAccent"
    _accent.light_color = ACCENT_COLOR
    _accent_base = ACCENT_ENERGY * _lm
    _accent.light_energy = _accent_base * 0.45
    _accent.spot_range = 6.0
    _accent.spot_angle = 44.0
    _accent.shadow_enabled = false
    _accent.position = Vector3(0.0, 2.9, -1.4)
    add_child(_accent)
    _accent.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    _lights.append(_accent)


# ---------------------------------------------------------------- звук

func _build_ambient_audio() -> void:
    var p := AudioFactory.make_player(loc_def.id, self)
    _audio_ok = p != null


# ---------------------------------------------------------------- грейд

func _grade() -> void:
    if _main == null:
        return
    var we := _main.find_child("WorldEnvironment", true, false) as WorldEnvironment
    if we == null:
        # запасной путь: WorldEnvironment — прямой ребёнок игрового корня
        for ch in _main.get_children():
            if ch is WorldEnvironment:
                we = ch as WorldEnvironment
                break
    if we == null or we.environment == null:
        return
    _env = we.environment
    _env_saved = {
        "ambient": _env.ambient_light_energy,
        "ambient_color": _env.ambient_light_color,
        "bg": _env.background_color,
        "fog": _env.fog_enabled,
        "fog_color": _env.fog_light_color,
        "fog_density": _env.fog_density,
        "glow": _env.glow_intensity,
        "adj": _env.adjustment_enabled,
        "contrast": _env.adjustment_contrast,
        "sat": _env.adjustment_saturation,
        "bright": _env.adjustment_brightness,
    }
    _env.background_mode = Environment.BG_COLOR
    if _pal.has("sky"):
        _env.background_color = _pal["sky"]
    _env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    _env.ambient_light_color = _col("ambient")
    _env.ambient_light_energy = maxf(0.16, float(_pal.get("ambient_e", loc_def.ambient_energy)))
    _env.fog_enabled = true
    _env.fog_light_color = _col("fog")
    _env.fog_density = float(_pal.get("fog_density", 0.005))
    var g := float(visual.glow_factor())
    _env.glow_intensity = clampf(_env_saved["glow"] * g, 0.0, 8.0)
    _env.adjustment_enabled = true
    _env.adjustment_contrast = float(_pal.get("contrast", 1.0))
    _env.adjustment_saturation = float(_pal.get("sat", 1.0))
    _env.adjustment_brightness = float(_pal.get("bright", 1.0)) \
            * (0.85 + 0.30 * clampf(loc_def.brightness, 0.0, 1.0))
    _env_applied = true


# ---------------------------------------------------------------- MultiMesh / Decal / частицы

## Один MultiMesh на тип декора: листья, гравий, трава, пыль на полу.
func _add_multimesh(name: String, size: Vector3, count: int, area: Vector3,
        center: Vector3, colors: Array, rng_seed: int, yaw_random: bool = true) -> void:
    if count <= 0:
        return
    var mesh := BoxMesh.new()
    mesh.size = size
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.mesh = mesh
    mm.instance_count = count
    var rng := RandomNumberGenerator.new()
    rng.seed = rng_seed
    for i in count:
        var p := center + Vector3(rng.randf_range(-area.x, area.x),
                rng.randf_range(0.0, area.y), rng.randf_range(-area.z, area.z))
        var yaw := rng.randf_range(0.0, TAU) if yaw_random else 0.0
        var s := rng.randf_range(0.7, 1.4)
        var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, rng.randf_range(0.6, 1.1), s))
        mm.set_instance_transform(i, Transform3D(b, p))
        mm.set_instance_color(i, colors[i % colors.size()])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = name
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.vertex_color_is_srgb = true
    mat.roughness = 0.9
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mmi.material_override = mat
    add_child(mmi)
    _mm_count += 1


## Мягкое пятно/царапина: текстура генерируется кодом (внешних ассетов нет).
## v71: лишние источники света сверх бюджета профиля удаляем после сборки.
func _trim_lights() -> void:
    var keep: Array = []
    for l in _lights:
        if keep.size() < _lights_left:
            keep.append(l)
        elif is_instance_valid(l):
            (l as Node).queue_free()
    _lights = keep
    var fk: Array = []
    for f in _flicker:
        if is_instance_valid(f["light"]) and _lights.has(f["light"]):
            fk.append(f)
    _flicker = fk
    var sw: Array = []
    for w in _swing:
        if is_instance_valid(w["light"]) and _lights.has(w["light"]):
            sw.append(w)
    _swing = sw


func _add_decal(pos: Vector3, size: Vector3, col: Color, seedv: int,
        rot: Vector3 = Vector3.ZERO) -> void:
    # v71: декали — только пока есть бюджет профиля качества
    if _decal_count >= _decals_left:
        return
    var tex := _blob_texture(col, seedv)
    var d := Decal.new()
    d.name = "SoftSpot"
    d.texture_albedo = tex
    d.size = size
    d.position = pos
    d.rotation_degrees = rot
    d.albedo_mix = 0.85
    d.modulate = Color(1.0, 1.0, 1.0, DECAL_ALPHA)
    d.upper_fade = 0.35
    d.lower_fade = 0.35
    d.cull_mask = 0xFFFFF
    add_child(d)
    _decal_count += 1


func _blob_texture(col: Color, seedv: int) -> ImageTexture:
    var n := 48
    var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
    var rng := RandomNumberGenerator.new()
    rng.seed = seedv
    var ph := rng.randf_range(0.0, TAU)
    for y in n:
        for x in n:
            var u := (float(x) / float(n)) * 2.0 - 1.0
            var v := (float(y) / float(n)) * 2.0 - 1.0
            var r := sqrt(u * u + v * v)
            var edge := 0.72 + 0.18 * sin(ph + u * 5.0) + 0.10 * sin(ph * 2.0 + v * 7.0)
            var a := clampf((edge - r) * 2.6, 0.0, 1.0)
            a *= 0.65 + 0.35 * rng.randf()
            img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
    return ImageTexture.create_from_image(img)


## Частицы локации: тип задаёт поведение, количество урезается бюджетом.
func _add_particles(kind: String, amount: int, center: Vector3, area: Vector3,
        col: Color, size: float) -> void:
    var budget := _particles_budget if _particles_budget > 0 else 300
    var n := mini(int(float(amount) * float(_q.get("particles", 1.0))), budget)
    if n <= 0:
        return
    var p := GPUParticles3D.new()
    p.name = "LocationFX"
    p.amount = n
    p.lifetime = 6.0
    p.preprocess = 2.0
    p.explosiveness = 0.0
    p.randomness = 0.6
    p.visibility_aabb = AABB(Vector3(-9.0, -2.0, -7.0), Vector3(18.0, 9.0, 14.0))
    var m := ParticleProcessMaterial.new()
    m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    m.emission_box_extents = area
    m.color = col
    match kind:
        "dust":  # пыль в свете: медленно всплывает и висит
            m.direction = Vector3(0.2, 1.0, 0.1)
            m.spread = 35.0
            m.initial_velocity_min = 0.02
            m.initial_velocity_max = 0.10
            m.gravity = Vector3(0.0, 0.012, 0.0)
            m.scale_min = 0.6
            m.scale_max = 1.5
        "leaves":  # листья: падают и уезжают ветром
            m.direction = Vector3(0.8, -0.5, 0.25)
            m.spread = 45.0
            m.initial_velocity_min = 0.25
            m.initial_velocity_max = 0.65
            m.gravity = Vector3(0.35, -0.22, 0.10)
            m.scale_min = 0.8
            m.scale_max = 1.8
            m.angular_velocity_min = -180.0
            m.angular_velocity_max = 180.0
        "steam":  # пар/капли в подвале: поднимается вверх и рассеивается
            m.direction = Vector3(0.0, 1.0, 0.0)
            m.spread = 18.0
            m.initial_velocity_min = 0.10
            m.initial_velocity_max = 0.28
            m.gravity = Vector3(0.0, 0.05, 0.0)
            m.scale_min = 0.8
            m.scale_max = 2.0
        "streaks":  # ветер на крыше: быстрые горизонтальные штрихи
            m.direction = Vector3(-0.9, 0.05, 0.2)
            m.spread = 12.0
            m.initial_velocity_min = 1.2
            m.initial_velocity_max = 2.6
            m.gravity = Vector3(0.0, -0.02, 0.0)
            m.scale_min = 1.0
            m.scale_max = 2.2
        _:
            pass
    p.process_material = m
    var quad := QuadMesh.new()
    # лист — вытянутый, остальное — мягкое круглое пятно (иначе в кадре квадраты)
    if kind == "leaves":
        quad.size = Vector2(size, size * 0.55)
    else:
        quad.size = Vector2(size, size)
    p.draw_pass_1 = quad
    var mat := StandardMaterial3D.new()
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_texture = _leaf_texture() if kind == "leaves" else _round_texture()
    mat.vertex_color_use_as_albedo = true
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    p.material_override = mat
    p.position = center
    add_child(p)
    _particle_amount += n


## Мягкое круглое пятно для пыли/пара/ветра (генерируется один раз).
static var _tex_round: ImageTexture = null
static func _round_texture() -> ImageTexture:
    if _tex_round != null:
        return _tex_round
    var n := 32
    var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
    for y in n:
        for x in n:
            var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
            var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
            var r := sqrt(u * u + v * v)
            var a := clampf(1.0 - r, 0.0, 1.0)
            a = a * a  # мягкий край
            img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
    _tex_round = ImageTexture.create_from_image(img)
    return _tex_round


## Вытянутый лист с прожилкой: альфа-эллипс, чуть темнее к краю.
static var _tex_leaf: ImageTexture = null
static func _leaf_texture() -> ImageTexture:
    if _tex_leaf != null:
        return _tex_leaf
    var n := 32
    var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
    for y in n:
        for x in n:
            var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
            var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
            var r := sqrt(u * u * 1.0 + v * v * 3.2)
            var a := clampf((1.0 - r) * 2.2, 0.0, 1.0)
            var shade := 0.82 + 0.18 * (1.0 - absf(v))
            if absf(u) < 0.06:
                shade *= 0.75  # прожилка
            img.set_pixel(x, y, Color(shade, shade, shade, a))
    _tex_leaf = ImageTexture.create_from_image(img)
    return _tex_leaf


# ---------------------------------------------------------------- локации

func _build_gym() -> void:
    var wood := _col("wood")
    var wood2 := _col("wood2")
    var metal := _col("metal")
    var dark := _col("dark")
    var fabric := _col("fabric")
    var canvas := _col("canvas")
    var paper := _col("paper")
    var accent := _col("accent")
    # пол: разметка ринга и дорожка для скакалки
    _box(Vector3(0.0, 0.012, -0.6), Vector3(5.6, 0.02, 0.06), Color(0.85, 0.82, 0.72))
    _box(Vector3(0.0, 0.012, -3.4), Vector3(5.6, 0.02, 0.06), Color(0.85, 0.82, 0.72))
    _box(Vector3(-2.8, 0.012, -2.0), Vector3(0.06, 0.02, 2.8), Color(0.85, 0.82, 0.72))
    _box(Vector3(2.8, 0.012, -2.0), Vector3(0.06, 0.02, 2.8), Color(0.85, 0.82, 0.72))
    _box(Vector3(3.6, 0.013, 1.9), Vector3(0.9, 0.02, 0.05), accent)
    # потолочные балки: зал перестаёт быть коробкой
    for z in [-3.4, -1.6, 0.2, 2.0, 3.8]:
        _box(Vector3(0.0, 3.28, float(z)), Vector3(11.0, 0.16, 0.16), dark)
    _box(Vector3(-5.2, 3.28, 0.0), Vector3(0.16, 0.16, 9.0), dark)
    _box(Vector3(5.2, 3.28, 0.0), Vector3(0.16, 0.16, 9.0), dark)
    # штанга на стойке (hero): стойка + гриф + блины
    var bx := -3.0
    var bz := -3.45
    _box(Vector3(bx - 0.75, 0.75, bz), Vector3(0.14, 1.5, 0.14), metal)
    _box(Vector3(bx + 0.75, 0.75, bz), Vector3(0.14, 1.5, 0.14), metal)
    _box(Vector3(bx, 0.06, bz), Vector3(1.9, 0.12, 0.30), metal)
    _cyl(Vector3(bx, 1.42, bz), 0.035, 1.95, Color(0.72, 0.74, 0.78),
            10, Vector3.RIGHT)
    for side in [-1.0, 1.0]:
        _cyl(Vector3(bx + side * 0.78, 1.42, bz), 0.26, 0.07, accent, 12, Vector3.RIGHT)
        _cyl(Vector3(bx + side * 0.66, 1.42, bz), 0.20, 0.07, dark, 12, Vector3.RIGHT)
        _cyl(Vector3(bx + side * 0.90, 1.42, bz), 0.14, 0.06, metal, 12, Vector3.RIGHT)
    # вторая штанга на полу с блинами
    _cyl(Vector3(-4.35, 0.16, -1.9), 0.04, 1.5, Color(0.70, 0.72, 0.76), 10, Vector3.FORWARD)
    for side in [-1.0, 1.0]:
        _cyl(Vector3(-4.35, 0.16, -1.9 + side * 0.55), 0.30, 0.08, accent, 12, Vector3.FORWARD)
    # мешок на цепи у правой стены (hero)
    var bag := Vector3(4.72, 0.0, -2.55)
    _box(Vector3(bag.x, 3.05, bag.z), Vector3(0.24, 0.12, 0.24), dark)
    for i in 5:
        _cyl(Vector3(bag.x, 2.30 + float(i) * 0.15, bag.z), 0.02, 0.14, metal, 5)
    _cyl(Vector3(bag.x, 1.32, bag.z), 0.30, 0.95, fabric, 10)
    _cyl(Vector3(bag.x, 1.82, bag.z), 0.24, 0.18, fabric.darkened(0.15), 10)
    _cyl(Vector3(bag.x, 0.82, bag.z), 0.20, 0.14, fabric.darkened(0.2), 10)
    _box(Vector3(bag.x, 1.45, bag.z - 0.28), Vector3(0.20, 0.34, 0.03), paper)
    # стойка со скакалками (hero)
    var rx := 4.62
    var rz := 1.25
    _box(Vector3(rx - 0.45, 0.8, rz), Vector3(0.12, 1.6, 0.12), wood2)
    _box(Vector3(rx + 0.45, 0.8, rz), Vector3(0.12, 1.6, 0.12), wood2)
    _box(Vector3(rx, 1.58, rz), Vector3(1.0, 0.10, 0.12), wood2)
    for i in 3:
        var off := -0.28 + float(i) * 0.28
        _box(Vector3(rx + off, 1.16, rz), Vector3(0.03, 0.75, 0.03), Color(0.20, 0.20, 0.22))
        _box(Vector3(rx + off, 0.79, rz), Vector3(0.16, 0.05, 0.05), Color(0.20, 0.20, 0.22))
    # скамья и маты
    _box(Vector3(4.35, 0.42, 3.15), Vector3(1.5, 0.10, 0.42), wood)
    _box(Vector3(3.75, 0.20, 3.15), Vector3(0.10, 0.40, 0.34), metal)
    _box(Vector3(4.95, 0.20, 3.15), Vector3(0.10, 0.40, 0.34), metal)
    _box(Vector3(-2.4, 0.035, -3.55), Vector3(2.2, 0.07, 1.2), canvas)
    _box(Vector3(0.9, 0.035, -3.60), Vector3(2.2, 0.07, 1.2), canvas.darkened(0.2))
    # зеркало на задней стене + рама
    _box(Vector3(2.1, 1.72, -4.08), Vector3(2.4, 1.3, 0.05), Color(0.62, 0.70, 0.78))
    _box(Vector3(0.85, 1.72, -4.06), Vector3(0.08, 1.42, 0.08), dark)
    _box(Vector3(3.35, 1.72, -4.06), Vector3(0.08, 1.42, 0.08), dark)
    # постеры
    _box(Vector3(-1.4, 1.85, -4.06), Vector3(1.0, 1.3, 0.03), paper)
    _box(Vector3(-0.2, 1.85, -4.06), Vector3(0.8, 1.1, 0.03), fabric)
    _box(Vector3(-4.2, 1.75, -4.06), Vector3(1.2, 0.9, 0.03), canvas)
    # лампы под потолком: видимый меш + плафон
    for lx in [-2.6, 2.9]:
        _box(Vector3(lx, 3.34, -1.8), Vector3(0.6, 0.08, 0.6), dark)
        _box(Vector3(lx, 3.24, -1.8), Vector3(0.46, 0.14, 0.46), _col("glow"), true)
        _cyl(Vector3(lx, 3.16, -1.8), 0.02, 0.20, dark, 4)
    # окно на левой стене: рама + светящееся стекло + решётка
    _box(Vector3(-5.42, 2.0, 1.2), Vector3(0.06, 1.3, 2.2), dark)
    _box(Vector3(-5.38, 2.0, 1.2), Vector3(0.04, 1.1, 2.0), Color(0.78, 0.86, 0.96), true)
    for i in 4:
        _box(Vector3(-5.34, 2.0, 0.35 + float(i) * 0.56), Vector3(0.03, 1.1, 0.05), dark)
    # декор MM: мел и гравий у стены
    _add_multimesh("ChalkSpecks", Vector3(0.05, 0.012, 0.05), 40,
            Vector3(4.6, 0.0, 3.4), Vector3(0.0, 0.01, 0.0),
            [Color(0.85, 0.84, 0.78), Color(0.70, 0.69, 0.64)], 501)
    _add_decal(Vector3(0.9, 0.09, -0.4), DECAL_SIZE, Color(0.10, 0.10, 0.10), 511)
    _add_decal(Vector3(-3.2, 0.09, 0.6), DECAL_SIZE * 0.8, Color(0.18, 0.12, 0.08), 512)
    _add_particles("dust", int(PARTICLES["gym"]), Vector3(0.6, 2.0, -0.6),
            Vector3(3.6, 1.2, 2.6), Color(1.0, 0.92, 0.76, 0.50), 0.04)


func _build_park() -> void:
    var grass := _col("grass")
    var grass2 := _col("grass2")
    var wood := _col("wood")
    var metal := _col("metal")
    var leaf := _col("leaf")
    var paper := _col("paper")
    # газонные «кочки» и дорожка
    _box(Vector3(0.0, 0.012, 1.6), Vector3(9.0, 0.02, 1.6), grass2)
    for i in 5:
        _box(Vector3(-3.6 + float(i) * 1.8, 0.014, -2.4), Vector3(0.10, 0.02, 3.2),
                Color(0.80, 0.78, 0.66))
    # турник (hero): стойки, перекладина, раскосы
    var px := -3.0
    var pz := -3.50
    _box(Vector3(px - 1.15, 1.25, pz), Vector3(0.14, 2.5, 0.14), metal)
    _box(Vector3(px + 1.15, 1.25, pz), Vector3(0.14, 2.5, 0.14), metal)
    _cyl(Vector3(px, 2.42, pz), 0.045, 2.5, Color(0.42, 0.45, 0.43), 10, Vector3.RIGHT)
    _box_b(Vector3(px - 0.95, 1.30, pz), Vector3(0.10, 1.5, 0.10),
            Basis(Vector3.BACK, deg_to_rad(28.0)), metal)
    _box_b(Vector3(px + 0.95, 1.30, pz), Vector3(0.10, 1.5, 0.10),
            Basis(Vector3.BACK, deg_to_rad(-28.0)), metal)
    # брусья (hero): две перекладины на стойках, уведены к дальней стене
    var qx := 4.55
    for side in [-1.0, 1.0]:
        _box(Vector3(qx, 0.65, -3.20 + side * 0.32), Vector3(0.12, 1.3, 0.12), metal)
        _cyl(Vector3(qx, 1.22, -3.20 + side * 0.32), 0.05, 2.0,
                Color(0.42, 0.45, 0.43), 10, Vector3.FORWARD)
    _box_b(Vector3(qx, 0.62, -2.30), Vector3(0.10, 1.2, 0.10),
            Basis(Vector3.RIGHT, deg_to_rad(-30.0)), metal)
    # деревья: ствол + чанковая крона (кубический стиль)
    var trees := [[-4.55, 0.6], [4.75, -3.4], [-4.7, -3.7]]
    for ti in trees.size():
        var tx := float(trees[ti][0])
        var tz := float(trees[ti][1])
        var h: float = 2.1 + 0.35 * float(ti % 2)
        _cyl(Vector3(tx, h * 0.5, tz), 0.16, h, wood, 8)
        var cy := h + 0.55
        _box(Vector3(tx, cy, tz), Vector3(1.7, 1.0, 1.6), grass.darkened(0.08))
        _box(Vector3(tx - 0.55, cy + 0.55, tz + 0.15), Vector3(1.0, 0.8, 1.0), grass2)
        _box(Vector3(tx + 0.60, cy + 0.45, tz - 0.25), Vector3(0.9, 0.7, 0.9), leaf)
    # скамейка (hero) и фонарь
    _box(Vector3(-4.35, 0.45, 2.65), Vector3(1.6, 0.10, 0.5), wood)
    _box(Vector3(-4.35, 0.72, 2.92), Vector3(1.6, 0.45, 0.08), wood)
    for side in [-1.0, 1.0]:
        _box(Vector3(-4.35 + side * 0.62, 0.22, 2.65), Vector3(0.10, 0.44, 0.44), metal)
    _cyl(Vector3(4.62, 1.15, 2.75), 0.06, 2.3, metal, 6)
    _box(Vector3(4.62, 2.38, 2.75), Vector3(0.42, 0.14, 0.42), metal)
    _box(Vector3(4.62, 2.28, 2.75), Vector3(0.32, 0.08, 0.32), _col("glow"), true)
    # дальние силуэты деревьев за «открытым» краем
    for i in 6:
        var dx: float = -6.4 + float(i) * 2.6
        var hh: float = 2.4 + 0.4 * float(i % 3)
        _box(Vector3(dx, hh * 0.5, -6.6), Vector3(0.36, hh, 0.36), wood.darkened(0.25))
        _box(Vector3(dx, hh, -6.6), Vector3(2.3, 1.5, 2.0), grass.darkened(0.30))
        _box(Vector3(dx + 0.5, hh + 0.9, -6.5), Vector3(1.3, 1.0, 1.2), grass.darkened(0.18))
    # трава MM и опавшие листья
    _add_multimesh("GrassTufts", Vector3(0.05, 0.20, 0.04), 54,
            Vector3(3.6, 0.0, 3.2), Vector3(0.0, 0.0, -1.2),
            [grass2.darkened(0.18), grass.darkened(0.10), grass2.darkened(0.28)], 601)
    _add_multimesh("FallenLeaves", Vector3(0.11, 0.015, 0.07), 34,
            Vector3(3.4, 0.0, 3.0), Vector3(0.0, 0.02, -0.8),
            [leaf.darkened(0.18), Color(0.45, 0.30, 0.12), Color(0.52, 0.24, 0.10)], 602)
    _add_decal(Vector3(-1.2, 0.10, 1.4), DECAL_SIZE, Color(0.16, 0.20, 0.10), 611)
    _add_decal(Vector3(2.6, 0.10, 2.4), DECAL_SIZE * 0.9, Color(0.22, 0.18, 0.08), 612)
    _add_particles("leaves", int(PARTICLES["park"]), Vector3(1.0, 2.4, 0.0),
            Vector3(4.4, 1.4, 3.4), Color(0.72, 0.56, 0.18, 0.95), 0.11)
    # дальняя земля: парк открыт, за газоном тоже должна быть трава, а не пустота
    _box(Vector3(0.0, -0.15, -13.0), Vector3(70.0, 0.30, 40.0), grass.darkened(0.28))


func _build_dojo() -> void:
    var wood := _col("wood")
    var wood2 := _col("wood2")
    var paper := _col("paper")
    var straw := _col("straw")
    var straw2 := _col("straw2")
    var dark := _col("dark")
    var ink := _col("ink")
    # татами: 2 ряда матов с тёмными швами
    for row in 2:
        for i in 3:
            var cx := -3.2 + float(i) * 2.1
            var cz := -3.45 + float(row) * 1.15
            _box(Vector3(cx, 0.035, cz), Vector3(2.0, 0.07, 1.1),
                    straw if (i + row) % 2 == 0 else straw2)
            _box(Vector3(cx, 0.072, cz), Vector3(0.06, 0.02, 1.1), ink)
    # сёдзи на задней стене: рама + светящаяся бумага
    for i in 3:
        var sx := -2.6 + float(i) * 2.6
        _box(Vector3(sx, 1.75, -4.10), Vector3(2.2, 2.2, 0.06), wood)
        _box(Vector3(sx, 1.75, -4.05), Vector3(2.0, 2.0, 0.04), paper, true)
        for k in 3:
            _box(Vector3(sx - 0.66 + float(k) * 0.66, 1.75, -4.04),
                    Vector3(0.05, 2.0, 0.03), wood2)
        for k in 2:
            _box(Vector3(sx, 1.30 + float(k) * 0.90, -4.04),
                    Vector3(2.0, 0.05, 0.03), wood2)
    # деревянный манекен (hero): столб + три перекладины
    var dx := -4.55
    var dz := -1.05
    _cyl(Vector3(dx, 0.85, dz), 0.13, 1.7, wood, 8)
    _box(Vector3(dx, 1.52, dz), Vector3(0.16, 0.16, 0.9), wood2)
    _box(Vector3(dx, 1.18, dz + 0.22), Vector3(0.14, 0.14, 0.55), wood2)
    _box(Vector3(dx, 0.92, dz - 0.20), Vector3(0.14, 0.14, 0.55), wood2)
    _box(Vector3(dx, 1.95, dz), Vector3(0.30, 0.30, 0.30), wood)
    _box(Vector3(dx, 0.10, dz), Vector3(0.6, 0.2, 0.6), straw2)
    # стойка с боккенами (hero)
    var bx := 4.55
    var bz := -2.2
    _box(Vector3(bx, 0.55, bz), Vector3(0.5, 1.1, 0.5), wood)
    for i in 3:
        _box_b(Vector3(bx - 0.30 + float(i) * 0.30, 1.30, bz), Vector3(0.07, 1.3, 0.07),
                Basis(Vector3.RIGHT, deg_to_rad(-18.0)), wood2)
    # свеча-подставка и свечи (hero-деталь у стены)
    _box(Vector3(-4.5, 0.55, 1.35), Vector3(0.5, 0.10, 0.5), wood)
    _box(Vector3(-4.5, 0.35, 1.35), Vector3(0.18, 0.40, 0.18), wood2)
    for i in 3:
        var cx := -4.62 + float(i) * 0.24
        _cyl(Vector3(cx, 0.66, 1.35), 0.055, 0.16, paper, 8)
        _box(Vector3(cx, 0.80, 1.35), Vector3(0.05, 0.12, 0.05), Color(1.0, 0.75, 0.35), true)
    # свиток на стене + низкая скамья
    _box(Vector3(0.0, 2.55, -4.06), Vector3(1.3, 1.1, 0.04), paper)
    _box(Vector3(0.0, 3.12, -4.05), Vector3(1.5, 0.06, 0.06), dark)
    _box(Vector3(0.0, 1.98, -4.05), Vector3(1.5, 0.06, 0.06), dark)
    _box(Vector3(3.9, 0.22, 3.20), Vector3(1.3, 0.10, 0.4), wood)
    # декор MM: соломенная крошка, пыль в свете, пятна
    _add_multimesh("TatamiDust", Vector3(0.03, 0.012, 0.03), 30,
            Vector3(3.0, 0.0, 1.8), Vector3(0.0, 0.02, -0.2), [straw, straw2], 701)
    _add_decal(Vector3(1.2, 0.10, -2.6), DECAL_SIZE * 0.8, Color(0.20, 0.16, 0.10), 711)
    _add_decal(Vector3(-2.8, 0.10, -0.2), DECAL_SIZE * 0.6, Color(0.16, 0.14, 0.10), 712)
    _add_particles("dust", int(PARTICLES["dojo"]), Vector3(0.4, 1.9, -1.6),
            Vector3(2.6, 1.1, 1.8), Color(1.0, 0.90, 0.68, 0.45), 0.04)


func _build_roof() -> void:
    var stone := _col("stone")
    var stone2 := _col("stone2")
    var metal := _col("metal")
    var rust := _col("rust")
    var canvas := _col("canvas")
    var dark := _col("dark")
    # парапет по «открытому» краю и бортик
    _box(Vector3(0.0, 0.55, -4.05), Vector3(11.0, 1.1, 0.25), stone)
    _box(Vector3(0.0, 1.12, -4.05), Vector3(11.0, 0.08, 0.35), stone2)
    for sx in [-5.42, 5.42]:
        _box(Vector3(sx, 0.55, 0.0), Vector3(0.25, 1.1, 9.0), stone2)
    # маты на полу
    _box(Vector3(3.1, 0.045, 0.2), Vector3(2.4, 0.09, 1.5), canvas)
    _box(Vector3(0.2, 0.045, -2.3), Vector3(2.2, 0.09, 1.4), canvas.darkened(0.18))
    # венттрубы (hero): труба с коленом и вентилятор-гриб
    var vx := 4.55
    var vz := -3.50
    _cyl(Vector3(vx, 1.10, vz), 0.22, 2.2, metal, 10)
    _cyl(Vector3(vx, 2.22, vz), 0.30, 0.16, rust, 10)
    _box(Vector3(vx, 2.40, vz), Vector3(0.7, 0.10, 0.7), metal)
    _cyl(Vector3(vx, 1.35, vz + 0.55), 0.16, 0.9, metal, 8, Vector3.FORWARD)
    _cyl(Vector3(vx - 0.9, 0.75, vz + 0.2), 0.14, 1.5, rust, 8)
    _cyl(Vector3(vx - 0.9, 1.55, vz + 0.2), 0.22, 0.12, metal, 8)
    # антенна и кабель
    _cyl(Vector3(-4.6, 1.55, -3.3), 0.03, 3.1, dark, 5)
    for i in 3:
        _box(Vector3(-4.6, 2.6 + float(i) * 0.35, -3.3),
                Vector3(0.7 - float(i) * 0.15, 0.03, 0.03), dark)
    # ящик вентиляции, стойка с канатом, бочка с дождевой водой
    _box(Vector3(4.55, 0.55, 2.55), Vector3(1.2, 1.1, 0.9), metal)
    for i in 3:
        _box(Vector3(4.55, 0.25 + float(i) * 0.32, 3.02), Vector3(1.0, 0.06, 0.03), dark)
    _box(Vector3(-4.65, 0.05, 2.7), Vector3(0.9, 0.1, 0.9), stone2)
    _cyl(Vector3(-4.65, 0.55, 2.7), 0.40, 0.9, rust, 10)
    # «город» за парапетом: силуэты домов и огни
    for i in 9:
        var cx := -9.0 + float(i) * 2.1
        var h: float = 1.3 + 0.45 * float((i * 7) % 5)
        _box(Vector3(cx, h * 0.5, -7.4), Vector3(1.5, h, 1.2), _col("city"))
        _box(Vector3(cx, h + 0.10, -7.4), Vector3(1.1, 0.20, 1.0), _col("city2"))
        if i % 3 == 0:
            _box(Vector3(cx + 0.3, h * 0.7, -6.78), Vector3(0.12, 0.12, 0.03),
                    Color(1.0, 0.86, 0.56), true)
    # гравий MM и лужи
    _add_multimesh("Gravel", Vector3(0.07, 0.05, 0.07), 80,
            Vector3(4.8, 0.02, 3.6), Vector3(0.0, 0.02, -0.6),
            [stone, stone2, stone.lightened(0.12)], 801)
    _add_decal(Vector3(-1.4, 0.11, 1.9), DECAL_SIZE, Color(0.10, 0.13, 0.18), 811)
    _add_decal(Vector3(2.4, 0.11, 2.9), DECAL_SIZE * 0.9, Color(0.08, 0.10, 0.14), 812)
    _add_particles("streaks", int(PARTICLES["roof"]), Vector3(0.5, 2.3, 0.4),
            Vector3(4.2, 1.2, 3.2), Color(0.80, 0.88, 1.0, 0.35), 0.10)
    # «земля» под городом за парапетом, иначе силуэты висят в пустоте
    _box(Vector3(0.0, -0.15, -14.0), Vector3(80.0, 0.30, 44.0), _col("city").darkened(0.35))


func _build_basement() -> void:
    var stone := _col("stone")
    var stone2 := _col("stone2")
    var dark := _col("dark")
    var metal := _col("metal")
    var rust := _col("rust")
    var tire := _col("tire")
    var wood := _col("wood")
    # низкий потолок и трубы под ним
    _box(Vector3(0.0, 3.56, 0.0), Vector3(11.0, 0.14, 9.0), stone2)
    for i in 4:
        _cyl(Vector3(0.0, 3.16, -3.2 + float(i) * 2.0), 0.11, 10.6, rust, 8, Vector3.RIGHT)
    for side in [-1.0, 1.0]:
        _cyl(Vector3(4.9, 2.70 + (0.25 if side > 0.0 else 0.0), 0.0), 0.09, 9.0,
                metal, 8, Vector3.FORWARD)
    # мешок на цепи (hero)
    var bx := -4.60
    var bz := 1.15
    _box(Vector3(bx, 3.10, bz), Vector3(0.22, 0.12, 0.22), dark)
    for i in 5:
        _cyl(Vector3(bx, 2.42 + float(i) * 0.13, bz), 0.02, 0.12, metal, 5)
    _cyl(Vector3(bx, 1.42, bz), 0.32, 1.1, Color(0.30, 0.20, 0.14), 10)
    _cyl(Vector3(bx, 0.86, bz), 0.22, 0.16, Color(0.24, 0.16, 0.11), 10)
    # покрышки (hero) стопкой и россыпью
    for i in 3:
        _cyl(Vector3(4.65, 0.16 + float(i) * 0.30, -2.9), 0.52, 0.28, tire, 12)
    _cyl(Vector3(4.30, 0.16, -1.10), 0.52, 0.28, tire, 12, Vector3(0.25, 1.0, 0.1))
    _cyl(Vector3(3.40, 0.14, -2.10), 0.46, 0.26, tire.darkened(0.1), 12)
    # самодельная штанга (hero): гриф + блины из покрышек
    _cyl(Vector3(3.60, 0.30, -3.55), 0.04, 1.9, metal, 10, Vector3.RIGHT)
    for side in [-1.0, 1.0]:
        _cyl(Vector3(3.60 + side * 0.72, 0.30, -3.55), 0.34, 0.12, tire, 12, Vector3.RIGHT)
    # верстак, ящик, бутылки
    _box(Vector3(-4.55, 0.45, -3.10), Vector3(1.6, 0.12, 0.7), wood)
    for side in [-1.0, 1.0]:
        _box(Vector3(-4.55 + side * 0.65, 0.22, -3.10), Vector3(0.12, 0.44, 0.6), wood)
    _box(Vector3(-4.55, 0.70, -3.10), Vector3(0.5, 0.40, 0.4), stone)
    for i in 3:
        _cyl(Vector3(-4.85 + float(i) * 0.28, 0.92, -3.10), 0.05, 0.36,
                Color(0.20, 0.34, 0.22), 6)
    # лампочка на проводе: меш + плафон
    _cyl(Vector3(0.6, 3.02, 0.4), 0.012, 0.70, dark, 4)
    _box(Vector3(0.6, 2.62, 0.4), Vector3(0.30, 0.10, 0.30), metal)
    _box(Vector3(0.6, 2.54, 0.4), Vector3(0.14, 0.14, 0.14), _col("glow"), true)
    # бетонные швы и вентиляционная решётка на стене
    for i in 4:
        _box(Vector3(-3.3 + float(i) * 2.2, 1.7, -4.12), Vector3(0.05, 3.2, 0.03), dark)
    _box(Vector3(1.6, 2.70, -4.10), Vector3(1.0, 0.7, 0.04), metal)
    for i in 5:
        _box(Vector3(1.6, 2.45 + float(i) * 0.13, -4.08), Vector3(0.9, 0.03, 0.05), dark)
    # бетонные пятна/лужи
    _add_multimesh("ConcreteBits", Vector3(0.05, 0.03, 0.05), 50,
            Vector3(4.6, 0.0, 3.2), Vector3(0.0, 0.02, -0.4),
            [stone, stone2, stone.lightened(0.10)], 901)
    _add_decal(Vector3(1.4, 0.11, 1.2), DECAL_SIZE, Color(0.06, 0.08, 0.10), 911)
    _add_decal(Vector3(-2.6, 0.11, 2.6), DECAL_SIZE * 0.9, Color(0.08, 0.06, 0.04), 912)
    _add_decal(Vector3(2.2, 1.35, -4.12), Vector3(1.8, 1.2, 0.4),
            Color(0.14, 0.10, 0.07), 913, Vector3(90.0, 0.0, 0.0))
    _add_particles("steam", int(PARTICLES["basement"]), Vector3(-1.0, 0.5, 1.0),
            Vector3(2.2, 0.4, 1.6), Color(0.82, 0.84, 0.88, 0.16), 0.20)


# ---------------------------------------------------------------- служебное

func _last_child() -> Node3D:
    for i in range(get_child_count() - 1, -1, -1):
        var ch := get_child(i)
        if ch is Node3D:
            return ch as Node3D
    return self















