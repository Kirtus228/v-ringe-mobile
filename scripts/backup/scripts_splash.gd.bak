extends Node
## Заставка (v15): кадр боя двух боксёров.
##
## Отдельная сцена собирается в SubViewport, рендерится один раз и отдаётся
## меню готовой картинкой. Никаких внешних файлов: только процедурная
## геометрия, свет и «фотография» момента удара.

const FighterScript = preload("res://scripts/fighter.gd")

const W := 1280
const H := 720

## Боец слева — бьёт джеб, «светлая» форма.
const LOOK_ATK := {
    "hair": "buzz", "hair_color": "brown", "skin": "tan",
    "build": "normal", "gloves": "twelve", "gloves_color": "red",
    "shorts": "short", "shorts_color": "red",
    "boots": "hi", "boots_color": "black",
}
## Боец справа — пропускает удар, тяжёлая фигура.
const LOOK_DEF := {
    "hair": "bald", "hair_color": "black", "skin": "dark",
    "build": "heavy", "gloves": "fourteen", "gloves_color": "blue",
    "shorts": "short", "shorts_color": "white",
    "boots": "hi", "boots_color": "white",
}

var view: SubViewport
var cam: Camera3D
var atk: Node3D
var dfn: Node3D
var contact := Vector3.ZERO


# ------------------------------------------------------------------ мелочи

func _mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    m.metallic = metal
    return m


func _glow(c: Color, energy: float = 2.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.emission_enabled = true
    m.emission = c
    m.emission_energy_multiplier = energy
    m.roughness = 0.3
    return m


func _mesh(parent: Node, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)
    return mi


func _ball(r: float) -> SphereMesh:
    var m := SphereMesh.new()
    m.radius = r
    m.height = r * 2.0
    m.radial_segments = 16
    m.rings = 8
    return m


func _cyl(r: float, h: float) -> CylinderMesh:
    var m := CylinderMesh.new()
    m.top_radius = r
    m.bottom_radius = r
    m.height = h
    m.radial_segments = 16
    return m


func _cube(s: Vector3) -> BoxMesh:
    var m := BoxMesh.new()
    m.size = s
    return m


func _spot(pos: Vector3, target: Vector3, col: Color, energy: float, angle: float,
        rng: float) -> SpotLight3D:
    var s := SpotLight3D.new()
    s.light_color = col
    s.light_energy = energy
    s.spot_angle = angle
    s.spot_range = rng
    s.spot_attenuation = 1.1
    s.shadow_enabled = true
    view.add_child(s)
    s.position = pos
    s.look_at(target, Vector3.UP)
    return s


# ------------------------------------------------------------------ сборка

func render() -> Texture2D:
    _build()
    _pose_fighters()
    _frame_camera()
    # несколько кадров на построение сцены и стабилизацию теней
    for i in 3:
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var img := view.get_texture().get_image()
    var tex := ImageTexture.create_from_image(img)
    view.queue_free()
    view = null
    return tex


func _build() -> void:
    view = SubViewport.new()
    view.size = Vector2i(W, H)
    view.own_world_3d = true
    view.msaa_3d = Viewport.MSAA_4X
    view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(view)

    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.008, 0.011, 0.022)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.30, 0.36, 0.54)
    env.ambient_light_energy = 0.48
    env.glow_enabled = true
    env.glow_intensity = 0.34
    env.glow_bloom = 0.07
    env.glow_hdr_threshold = 1.15
    env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 0.92
    env.fog_enabled = true
    env.fog_light_color = Color(0.06, 0.08, 0.14)
    env.fog_density = 0.018
    env.fog_sky_affect = 0.5
    env.ssao_enabled = true
    env.ssao_radius = 0.8
    env.ssao_intensity = 1.1
    we.environment = env
    view.add_child(we)

    cam = Camera3D.new()
    cam.fov = 36.0
    cam.near = 0.05
    cam.far = 60.0
    view.add_child(cam)
    cam.current = true

    _ring()
    _crowd()
    _lights()


func _ring() -> void:
    # пол зала и настил ринга
    var hall := _mesh(view, _cube(Vector3(40, 0.2, 30)), _mat(Color(0.012, 0.015, 0.025), 0.92),
            Vector3(0, -1.25, -3))
    hall.name = "Hall"
    var canvas := _mesh(view, _cube(Vector3(9.2, 0.12, 9.2)), _mat(Color(0.10, 0.13, 0.28), 0.78),
            Vector3(0, -0.06, -0.6))
    canvas.name = "Canvas"

    # канаты за бойцами: дают глубину и сразу читаются как ринг
    var rope_cols := [Color(0.62, 0.10, 0.14), Color(0.88, 0.90, 0.95), Color(0.12, 0.26, 0.66)]
    for i in 3:
        var rope := _mesh(view, _cyl(0.035, 8.6), _mat(rope_cols[i], 0.45),
                Vector3(0, 0.58 + float(i) * 0.38, -3.35))
        rope.rotation_degrees = Vector3(0, 0, 90)
        rope.name = "Rope%d" % i
    # угловая стойка сзади справа
    var post := _mesh(view, _cyl(0.10, 1.75), _mat(Color(0.55, 0.10, 0.12), 0.5),
            Vector3(3.55, 0.82, -3.35))
    post.name = "Post"

    # полотнище-задник: тёмное, чтобы силуэты бойцов отделялись
    var back := _mesh(view, _cube(Vector3(26, 12, 0.2)), _mat(Color(0.02, 0.025, 0.045), 0.95),
            Vector3(0, 4.0, -8.0))
    back.name = "Backdrop"


func _crowd() -> void:
    # толпа в темноте: только силуэты голов и плеч, на них играет блик
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261110
    var head_m := _mat(Color(0.03, 0.032, 0.045), 0.95)
    var sh_m := _mat(Color(0.022, 0.024, 0.035), 0.95)
    for row in 3:
        var z := -4.9 - float(row) * 0.85
        var y := 1.05 + float(row) * 0.32
        var x := -6.4
        while x < 6.4:
            var jx := x + rng.randf_range(-0.12, 0.12)
            var jy := y + rng.randf_range(-0.05, 0.05)
            var scale := 1.0 + rng.randf_range(-0.12, 0.12)
            var sh := _mesh(view, _ball(0.30), sh_m, Vector3(jx, jy - 0.18, z))
            sh.scale = Vector3(1.25, 0.85, 0.9) * scale
            var hd := _mesh(view, _ball(0.145), head_m, Vector3(jx, jy + 0.08, z))
            hd.scale = Vector3(0.95, 1.05, 1.0) * scale
            x += rng.randf_range(0.34, 0.46)
    # блики-огоньки в глубине: блум превращает их в боке
    for i in 22:
        var p := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(1.2, 3.2),
                -6.5 + rng.randf_range(-1.5, 0.4))
        var pal: Array = [Color(1.0, 0.82, 0.55), Color(0.55, 0.75, 1.0),
                Color(1.0, 0.55, 0.45)]
        var col: Color = pal[rng.randi() % 3]
        var b := _mesh(view, _ball(rng.randf_range(0.025, 0.05)), _glow(col, 1.1), p)
        b.name = "Bokeh%d" % i


func _lights() -> void:
    # жёсткий верхний ключевой свет
    _spot(Vector3(-1.4, 5.2, 2.6), Vector3(0.0, 1.62, 0.0), Color(1.0, 0.93, 0.82), 9.0, 46.0, 22.0)
    # холодный заполняющий сбоку
    _spot(Vector3(3.6, 3.4, 3.4), Vector3(0.0, 1.55, 0.0), Color(0.55, 0.72, 1.0), 4.5, 52.0, 20.0)
    # контровой из-за спины — обводит силуэты
    _spot(Vector3(1.2, 3.0, -4.4), Vector3(0.0, 1.72, 0.0), Color(0.72, 0.85, 1.0), 13.0, 34.0, 18.0)
    # задний боковой — подсвечивает бойца слева
    _spot(Vector3(-4.2, 2.8, -2.6), Vector3(-0.5, 1.5, 0.0), Color(1.0, 0.55, 0.42), 7.0, 40.0, 16.0)
    _spot(Vector3(2.3, 2.7, -2.0), Vector3(0.55, 1.86, 0.0), Color(0.68, 0.82, 1.0), 11.0, 24.0, 12.0)
    # «вспышка фотографа» перед лицами
    var flash := OmniLight3D.new()
    flash.light_color = Color(1.0, 0.96, 0.9)
    flash.light_energy = 1.5
    flash.omni_range = 3.4
    view.add_child(flash)
    flash.position = Vector3(0.2, 1.95, 1.5)


# ------------------------------------------------------------------ бойцы

func _pose_fighters() -> void:
    # фиксируем генератор: поза, капли и толпа должны быть одинаковыми
    # при каждом запуске, иначе кадр каждый раз разный
    seed(20261110)
    # бьющий слева, пропускающий справа: камера стоит чуть со стороны
    # пропустившего, поэтому видно и лицо бьющего, и момент попадания
    atk = FighterScript.new()
    atk.name = "Atk"
    view.add_child(atk)
    atk.setup(true, LOOK_ATK)
    atk.position = Vector3(-0.66, 0.0, 0.02)

    dfn = FighterScript.new()
    dfn.name = "Def"
    view.add_child(dfn)
    dfn.setup(true, LOOK_DEF)
    dfn.position = Vector3(0.60, 0.0, -0.02)

    _face(atk, dfn.position)
    _face(dfn, atk.position)
    atk.freeze_pose("", 0.0)
    dfn.freeze_pose("", 0.0)

    # джеб левой: рука вытянута, контакт читается прямо
    atk.punch_aim = dfn.head.global_position + Vector3(0.18, 0.22, 0.02)
    atk.freeze_pose("jab", 0.52)
    dfn.freeze_pose("", 0.0)
    var g0: Vector3 = atk.glove_point("l")
    var h0: Vector3 = dfn.head.global_position
    var dir0 := h0 - g0
    dir0.y = 0.0
    dir0 = dir0.normalized()
    dfn.position -= dir0 * clampf(g0.distance_to(h0) - 0.27, -0.20, 0.55)
    _face(dfn, atk.position)
    atk.punch_aim = dfn.head.global_position + Vector3(0.18, 0.22, 0.02)
    atk.freeze_pose("jab", 0.52)
    dfn.freeze_pose("", 0.0)

    # руки падают: защита сбита, лицо и корпус открыты
    dfn.sh_l.rotation = Vector3(0.10, 0.12, 0.22)
    dfn.sh_r.rotation = Vector3(-0.05, -0.12, -0.20)
    dfn.el_l.rotation = Vector3(0.25, 0.0, 0.30)
    dfn.el_r.rotation = Vector3(0.15, 0.0, -0.26)
    # голова уходит вбок и вверх, корпус откидывается от удара
    dfn.head.rotation += Vector3(0.02, 0.58, 0.18)
    dfn.torso.rotation += Vector3(-0.16, 0.28, 0.12)

    # бьющий: вес вперёд, корпус разворачивается за ударом
    atk.torso.rotation += Vector3(-0.12, -0.10, 0.0)
    atk.head.rotation += Vector3(0.02, -0.14, 0.0)

    # оба чуть развернуты к камере — видны лица, а не затылки
    atk.rotation.y -= 0.30
    dfn.rotation.y += 0.26

    # подгоняем контакт после реакции, чтобы перчатка легла в челюсть
    var g2: Vector3 = atk.glove_point("l")
    var h2: Vector3 = dfn.head.global_position
    var dd := g2.distance_to(h2)
    var dir2 := h2 - g2
    dir2.y = 0.0
    dir2 = dir2.normalized()
    dfn.position -= dir2 * clampf(dd - 0.27, -0.10, 0.12)
    contact = (atk.glove_point("l") + dfn.head.global_position) * 0.5
    print("SPLASH поза: перчатка=", atk.glove_point("l").snapped(Vector3(0.01, 0.01, 0.01)),
            " голова=", dfn.head.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
            " дистанция=", snappedf(atk.glove_point("l").distance_to(dfn.head.global_position), 0.01),
            " корни=", snappedf(atk.position.distance_to(dfn.position), 0.01))

    _mouthguard(dfn)
    _sweat(dfn.head.global_position, 28)
    _sweat(atk.head.global_position, 7)
    _impact()
    randomize()
func _face(f: Node3D, p: Vector3) -> void:
    f.look_at(Vector3(p.x, f.position.y, p.z), Vector3.UP)


func _mouthguard(f: Node3D) -> void:
    # белый кап на зубах — читается как «пропустил удар»
    var m := _mesh(f, _cube(Vector3(0.082, 0.028, 0.022)),
            _mat(Color(0.94, 0.95, 0.98), 0.25), Vector3(0.008, 0.025, -0.188))
    m.rotation_degrees = Vector3(8, 0, -4)


func _sweat(center: Vector3, count: int) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 7711 + count
    var mat := _glow(Color(0.86, 0.94, 1.0), 0.45)
    for i in count:
        var r := rng.randf_range(0.008, 0.017)
        var b := _mesh(view, _ball(r), mat, center + Vector3(
                rng.randf_range(0.06, 0.55), rng.randf_range(-0.10, 0.26),
                rng.randf_range(-0.26, 0.26)))
        b.name = "Drop%d" % i


func _impact() -> void:
    # искра в точке попадания + короткий световой всполох
    _mesh(view, _ball(0.05), _glow(Color(1.0, 0.93, 0.72), 1.8), contact)
    var l := OmniLight3D.new()
    l.light_color = Color(1.0, 0.9, 0.7)
    l.light_energy = 2.4
    l.omni_range = 1.1
    view.add_child(l)
    l.position = contact


# ------------------------------------------------------------------ камера

func _frame_camera() -> void:
    var ha: Vector3 = atk.head.global_position
    var hb: Vector3 = dfn.head.global_position
    var mid := (ha + hb) * 0.5
    var sep := ha.distance_to(hb)
    var tan_v := tan(deg_to_rad(cam.fov * 0.5))
    # головы занимают примерно половину ширины кадра
    var dist := clampf(0.36 / (2.0 * tan_v * 0.20), 2.4, 3.6)
    var cam_dir := Vector3(0.22, 0.03, 1.0).normalized()
    cam.position = mid + cam_dir * dist
    # смотрим чуть ниже голов: бойцы уходят в верхнюю половину кадра,
    # снизу остаётся место под текст меню
    cam.look_at(mid - Vector3(0.0, 0.18, 0.0), Vector3.UP)
