class_name TrainingStation
extends Node3D
## Одна переиспользуемая станция тренировки (эквивалент station_*.tscn, но
## собран процедурно — в проекте нет сцен). Визуал: тумба + Label3D + Area3D
## (задел под подход «подойди и нажми E»), поведение выбирается по StationDef.kind.
## Логику прироста статов/износа/мастерства ведёт TrainingMode: станция только
## сообщает об успешных повторах.

var def: StationDef
var location: TrainingLocationDef
var mode

var durability := 100.0
var durability_max := 100.0

var active := false
var finished := false
var ok := false
var reps_done := 0
var mistakes := 0
## накопленный прирост статов за подход (уже с бонусом локации)
var gain: Dictionary = {}

var t := 0.0
var _cool := 0.0
var _prompt_t := -1.0
var _next_prompt := 0.0
## T-trainanim: текущая пауза между окнами (3–5 с), пересчитывается на каждом окне.
var _gap_now := 3.5
var _holding := false
var _hold_t := 0.0
## v59: отладка для скриншота — держать окно нажатия открытым (кадр с «ЖМИ!»)
var debug_hold_prompt := false
var _label: Label3D
## T7b: высота подписи над самым высоким мешем снаряда (считается в _build_visual).
var _label_y_base := 2.02
var _ring: MeshInstance3D
## v71o: тумба и её «блин» — у напольных снарядов (беговая дорожка) прячутся:
## беговая дорожка стоит на полу, а не на метровом постаменте.
var _body_mi: MeshInstance3D
var _top_mi: MeshInstance3D
## v71q: отдельный узел грифа для жима лёжа — animate_lift поднимает только гриф,
## а скамья и стойки остаются на месте (раньше поднималась вся тумба).
var _bar_node: Node3D

# --- Этап 3, волна 1: анимация снаряда (BAG). Выключено при train_anim_level=OFF,
# тогда ни один трансформ не меняется (кадр остаётся базлайновым).
## Включена ли анимация (ставит TrainingMode из VisualConfig.train_anim_level).
var anim_on := false
## Амплитуда качания снаряда от удара, градусы.
@export var swing_amp_deg := 15.0
## Затухание качания, 1/с (чем больше — тем быстрее успокаивается).
@export var swing_damping := 5.5
## Частота качания, Гц.
@export var swing_freq := 2.6
## После скольких попаданий подряд — «встряска» всей станции.
@export var shake_after := 4
## Амплитуда встряски, градусы.
@export var shake_amp_deg := 4.0
## Затухание/частота встряски.
@export var shake_damping := 9.0
@export var shake_freq := 7.0
## Ниже этого веса качание считается затихшим.
const SWING_EPS := 0.015

## Контейнер визуала станции: качаем его целиком (тумба + блин), кольцо и
## подпись остаются на месте.
var _prop: Node3D = null
## v71s: узел, который реально качается. Для висящего мешка/каната это пивот
## в точке подвеса; для напольного инвентаря — сам _prop.
var _swing_node: Node3D = null
var _swing_base_y := 0.0
## v71s: покрышки деформируются отдельной группой, а не всей станцией.
var _deform_node: Node3D = null
## v71s: кувалда — отдельный узел. На станции лежит, на подходе бойца station.gd
## отдаёт её в правую руку (set_holder) и возвращает обратно при выходе.
var _hammer_node: Node3D = null
var _hammer_holder: Node3D = null
var _hammer_rest_parent: Node3D = null
var _hammer_rest_xform := Transform3D.IDENTITY
var _swinging := false
var _swing_t := 0.0
var _swing_amp := 0.0
var _swing_axis := Vector3.RIGHT
var _shaking := false
var _shake_t := 0.0
var _shake_amp := 0.0
var _hits_in_row := 0
var _debug_hold := ""
## Этап 3.3/3.4: ход снаряда, деформация шины, бюджет частиц пыли.
@export var lift_height := 0.55
@export var pull_sag := 0.10
@export var tire_deform := 0.12
@export var particle_budget := 300
@export var dust_amount := 24
## Этап 4: поломка-«отшатнулся» — наклон/провисание/дрожь и маркер сломанного.
@export var break_tilt_deg := 12.0
@export var break_sag := 0.06
@export var break_tremble_deg := 1.5
var _prop_base_y := 0.0
var _dust: GPUParticles3D = null
var _vib_phase := 0.0
var _body_mat: StandardMaterial3D = null
var _broken_visual_on := false
var _broken_t := 0.0
## Отладочный форс «сломан» для кадров (в игре false).
var _debug_broken := false
var _lift_prev := 0.0
var _rope_angle := 0.0
var _rope_speed := 0.0
var _cur_freq := 0.0
var _cur_damp := 0.0
## Деформация шины от удара (3.2), затухает в anim_tick.
var _deform := 0.0


## Подсветка ближайшей станции: кольцо на полу + подпись ТОЛЬКО у станции в фокусе.
## T7: раньше подписи висели у всех станций и наезжали друг на друга / уходили
## за край экрана. Теперь подпись показывает только станция в фокусе (ближайшая),
## её размер подстраивается под расстояние до камеры, чтобы влезала в кадр.
var _label_focus := false


func set_highlight(on: bool) -> void:
    _label_focus = on
    if _ring != null:
        _ring.visible = on
    if _label != null:
        _label.visible = on
        _label.modulate = Color(1.0, 1.0, 0.62) if on else Color(1.0, 0.94, 0.78)


## T7b: подпись в фокусе — постоянный размер на экране, ВСЕГДА поверх геометрии
## своего снаряда (сдвиг к камере + render_priority), но без режима «сквозь стены»:
## depth-тест остаётся, поэтому стены локации подпись по-прежнему перекрывают.
func tick_label(cam: Camera3D) -> void:
    if _label == null:
        return
    if not _label_focus:
        _label.visible = false
        return
    _label.visible = true
    var base := Vector3(0.0, _label_y_base, 0.0)
    if cam != null:
        var d := global_position.distance_to(cam.global_position)
        _label.pixel_size = clampf(d * 0.00062, 0.0016, 0.0034)
        _label.font_size = 48
        # сдвигаем подпись к камере на ~0.55 м: голова манекена/цепь мешка
        # оказываются ЗА текстом, а стены при этом всё ещё перекрывают подпись
        var to_cam := (cam.global_position - (global_position + base)).normalized()
        var local := global_transform.basis.inverse() * to_cam
        _label.position = base + local * 0.55
    else:
        _label.position = base


## Перевести подпись станции (EN/RU при смене языка).
func set_label_text(t: String) -> void:
    if _label != null:
        _label.text = t


func setup(st: StationDef, loc: TrainingLocationDef, m) -> void:
    def = st
    location = loc
    mode = m
    name = "Station_" + st.id
    _build_visual()
    update_label()


func _build_visual() -> void:
    # Этап 3: снаряд станции кладём в отдельный контейнер — его качаем от удара
    # (тумба+блин), а кольцо подсветки/подпись остаются на месте.
    _prop = Node3D.new()
    _prop.name = "Prop"
    add_child(_prop)
    _prop_base_y = _prop.position.y
    # v71s: никакой тумбы-куба и «блина» — весь инвентарь строится от пола
    # или подвешивается к раме. Старые _body_mi/_top_mi оставлены как null,
    # _hide_pedestal() — no-op, чтобы не ломать внешние вызовы.
    _build_prop_detail()
    _body_mat = _detail()
    _label_y_base = _compute_label_y()
    # кольцо подсветки: показывается, когда игрок подошёл ближе всех
    _ring = MeshInstance3D.new()
    var rm := TorusMesh.new()
    rm.inner_radius = 0.78
    rm.outer_radius = 0.98
    rm.rings = 24
    rm.ring_segments = 8
    _ring.mesh = rm
    var rmat := StandardMaterial3D.new()
    rmat.albedo_color = Color(0.98, 0.86, 0.45)
    rmat.emission_enabled = true
    rmat.emission = Color(0.98, 0.82, 0.35)
    rmat.emission_energy_multiplier = 1.6
    rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _ring.material_override = rmat
    _ring.position = Vector3(0.0, 0.03, 0.0)
    _ring.visible = false
    add_child(_ring)
    _label = Label3D.new()
    _label.text = String(def.title)
    _label.font_size = 48
    _label.pixel_size = 0.0026
    _label.position = Vector3(0.0, _label_y_base, 0.0)
    _label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _label.modulate = Color(1.0, 0.94, 0.78)
    _label.outline_size = 10
    _label.outline_modulate = Color(0.05, 0.05, 0.07, 0.95)
    # T7b: подпись рисуется поверх мешей снаряда (render_priority), но depth-тест
    # оставлен — стены локации её по-прежнему перекрывают.
    # v36: приоритет 200 выходил за допустимый диапазон движка и спамил ERROR —
    # используем верхнюю допустимую границу 127.
    _label.no_depth_test = false
    _label.render_priority = 127
    _label.double_sided = true
    # T7: подписи не висят у всех станций — только у станции в фокусе
    _label.visible = false
    add_child(_label)
    var area := Area3D.new()
    area.name = "Area"
    var cs := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.7, 1.8, 1.7)
    cs.shape = shape
    cs.position = Vector3(0.0, 0.9, 0.0)
    area.add_child(cs)
    add_child(area)


## T7b: верхняя точка снаряда (по AABB мешей) + отступ — подпись не пересекает
## голову манекена, цепь мешка и т.п.
func _compute_label_y() -> float:
    var top := 1.55
    if _prop != null:
        top = maxf(top, _max_part_y(_prop))
    return top + 0.22


## v71s: рекурсивно ищем верхнюю точку мешей, включая подвешенные пивоты.
func _max_part_y(n: Node3D) -> float:
    var top := -100.0
    for c in n.get_children():
        if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
            var mi := c as MeshInstance3D
            var a := mi.get_aabb()
            top = maxf(top, mi.position.y + a.position.y + a.size.y)
        elif c is Node3D:
            top = maxf(top, (c as Node3D).position.y + _max_part_y(c as Node3D))
    return top


## T7: шумовая текстура для «не пластиковых» материалов (triplanar).
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


var _metal_mat: StandardMaterial3D = null
var _detail_mat: StandardMaterial3D = null


func _metal() -> StandardMaterial3D:
    if _metal_mat == null:
        _metal_mat = StandardMaterial3D.new()
        _metal_mat.albedo_color = Color(0.52, 0.54, 0.58)
        _metal_mat.metallic = 0.75
        _metal_mat.roughness = 0.38
        _metal_mat.roughness_texture = _noise_tex(0.2, Color(0.7, 0.7, 0.7),
                Color(1.0, 1.0, 1.0))
        _metal_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
        _metal_mat.uv1_triplanar = true
        _metal_mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
    return _metal_mat


func _detail() -> StandardMaterial3D:
    if _detail_mat == null:
        _detail_mat = StandardMaterial3D.new()
        _detail_mat.albedo_color = _kind_color().darkened(0.18)
        _detail_mat.roughness = 0.82
        _detail_mat.albedo_texture = _noise_tex(0.08, Color(0.78, 0.78, 0.78),
                Color(1.0, 1.0, 1.0))
        _detail_mat.uv1_triplanar = true
        _detail_mat.uv1_scale = Vector3(0.9, 0.9, 0.9)
        # v71s: материал деталей — единая точка для «сломан»-подсветки.
        _detail_mat.emission_enabled = true
        _detail_mat.emission = Color(0.0, 0.0, 0.0)
    return _detail_mat


## v71s: простой материал инвентаря (дерево/резина/бетон/зеркало).
func _paint(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.metallic = metallic
    m.roughness = rough
    m.albedo_texture = _noise_tex(0.22, c.darkened(0.16), c.lightened(0.10))
    m.uv1_triplanar = true
    m.uv1_scale = Vector3(1.2, 1.2, 1.2)
    return m


## v71s: пустой узел-пивот для подвеса/группы.
func _node(nm: String, pos: Vector3, parent: Node3D = null) -> Node3D:
    var n := Node3D.new()
    n.name = nm
    n.position = pos
    (parent if parent != null else _prop).add_child(n)
    return n


func _add_part(mesh: Mesh, mat: Material, pos: Vector3,
        rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    mi.rotation = rot
    (parent if parent != null else _prop).add_child(mi)
    return mi


func _cyl_mesh(r_top: float, r_bot: float, h: float, segs: int = 16) -> CylinderMesh:
    var m := CylinderMesh.new()
    m.top_radius = r_top
    m.bottom_radius = r_bot
    m.height = h
    m.radial_segments = segs
    return m


func _sph_mesh(r: float) -> SphereMesh:
    var m := SphereMesh.new()
    m.radius = r
    m.height = r * 2.0
    m.radial_segments = 14
    m.rings = 8
    return m


func _box_mesh(size: Vector3) -> BoxMesh:
    var m := BoxMesh.new()
    m.size = size
    return m


## v71s: покрышка — тор, а не «диск»; читается как резина с отверстием.
func _torus_mesh(inner: float, outer: float) -> TorusMesh:
    var m := TorusMesh.new()
    m.inner_radius = inner
    m.outer_radius = outer
    m.rings = 18
    m.ring_segments = 10
    return m


## v71s: реальный инвентарь без тумбы. Всё строится от пола или подвешивается
## к раме; у висящих снарядов есть пивот в точке подвеса (`_swing_node`).
func _build_prop_detail() -> void:
    var id := String(def.id)
    _swing_node = _prop
    _swing_base_y = 0.0
    _deform_node = null
    var met := _metal()
    var det := _detail()
    var rust := _paint(Color(0.30, 0.16, 0.11), 0.55, 0.78)
    var wood := _paint(Color(0.40, 0.25, 0.14), 0.0, 0.86)
    var rubber := _paint(Color(0.20, 0.20, 0.21), 0.0, 0.92)
    var concrete := _paint(Color(0.52, 0.52, 0.50), 0.0, 0.95)
    var mat := _paint(Color(0.20, 0.34, 0.24), 0.0, 0.90)
    var strap := _paint(Color(0.09, 0.09, 0.10), 0.0, 0.95)
    # v71s: в комнате нет reflection probe, поэтому metallic 1.0 давал чёрную
    # дыру вместо зеркала. Держим «полированную панель»: низкая шероховатость,
    # умеренный металл и заметная засветка — читается как зеркало.
    var mirror := _paint(Color(0.86, 0.90, 0.94), 0.25, 0.10)
    mirror.emission_enabled = true
    mirror.emission = Color(0.42, 0.46, 0.52)
    match id:
        "bag":
            # стальная рама 2.75 м + висящий мешок: низ 0.35, Ø0.36, h1.10
            var old_bag := String(location.id) == "basement"
            var frame_mat: Material = rust if old_bag else met
            var bag_mat: Material = _paint(Color(0.26, 0.18, 0.13), 0.0, 0.92) if old_bag else det
            for sx in [-0.75, 0.75]:
                _add_part(_cyl_mesh(0.08, 0.08, 2.75), frame_mat,
                        Vector3(sx, 1.375, 0))
                _add_part(_box_mesh(Vector3(0.42, 0.05, 0.42)), frame_mat,
                        Vector3(sx, 0.025, 0))
            _add_part(_cyl_mesh(0.06, 0.06, 1.6), frame_mat,
                    Vector3(0, 2.75, 0), Vector3(0, 0, PI * 0.5))
            # пивот ровно на перекладине: качание идёт вокруг точки подвеса
            var bag_piv := _node("BagPivot", Vector3(0, 2.75, 0))
            _swing_node = bag_piv
            _swing_base_y = 2.75
            # от перекладины до свайвела — стропа, дальше цепь 0.25 до мешка
            _add_part(_box_mesh(Vector3(0.07, 1.05, 0.02)), strap,
                    Vector3(0, -0.525, 0), Vector3.ZERO, bag_piv)
            _add_part(_sph_mesh(0.035), met,
                    Vector3(0, -1.08, 0), Vector3.ZERO, bag_piv)
            _add_part(_cyl_mesh(0.02, 0.02, 0.25), met,
                    Vector3(0, -1.205, 0), Vector3.ZERO, bag_piv)
            _add_part(_cyl_mesh(0.18, 0.18, 1.10), bag_mat,
                    Vector3(0, -1.85, 0), Vector3.ZERO, bag_piv)
            _add_part(_cyl_mesh(0.02, 0.02, 0.18), met,
                    Vector3(0, -1.76, 0), Vector3.ZERO, bag_piv)
        "dummy":
            # деревянный манекен: база Ø0.7 h0.08, ствол Ø0.22 h1.4, 3 руки
            _add_part(_cyl_mesh(0.35, 0.35, 0.08), wood, Vector3(0, 0.04, 0))
            _add_part(_cyl_mesh(0.11, 0.11, 1.4), wood, Vector3(0, 0.78, 0))
            _add_part(_sph_mesh(0.12), wood, Vector3(0, 1.54, 0))
            for ay in [1.15, 1.05, 0.95]:
                _add_part(_cyl_mesh(0.03, 0.03, 0.8), wood,
                        Vector3(0, ay, 0), Vector3(0, 0, PI * 0.5))
            _add_part(_cyl_mesh(0.06, 0.06, 0.5), wood, Vector3(0, 0.30, 0))
        "speedbag":
            # напольная стойка: площадка Ø0.5 на полу, штанга 1.72, груша 1.44
            _add_part(_cyl_mesh(0.25, 0.25, 0.05), met, Vector3(0, 0.025, 0))
            _add_part(_cyl_mesh(0.045, 0.045, 1.72), met, Vector3(0, 0.86, 0))
            _add_part(_cyl_mesh(0.15, 0.15, 0.05), met, Vector3(0, 1.72, 0))
            _add_part(_cyl_mesh(0.03, 0.03, 0.22), met, Vector3(0, 1.60, 0))
            _add_part(_sph_mesh(0.17), det, Vector3(0, 1.44, 0))
        "barbell", "homemade_bar":
            # жим лёжа: скамья верх 0.45, стойки 1.05, гриф в `_bar_node` на 0.92
            var home := id == "homemade_bar"
            var bench_mat: Material = wood if home else det
            var steel: Material = rust if home else met
            var plate_mat: Material = concrete if home else det
            _add_part(_box_mesh(Vector3(0.55, 0.12, 1.70)), bench_mat,
                    Vector3(0, 0.39, 0))
            for sz in [-0.62, 0.62]:
                _add_part(_box_mesh(Vector3(0.5, 0.40, 0.08)), steel,
                        Vector3(0, 0.20, sz))
            for sx in [-0.62, 0.62]:
                _add_part(_box_mesh(Vector3(0.08, 1.05, 0.08)), steel,
                        Vector3(sx, 0.525, -0.30))
                _add_part(_box_mesh(Vector3(0.34, 0.04, 0.34)), steel,
                        Vector3(sx, 0.02, -0.30))
            _bar_node = Node3D.new()
            _bar_node.name = "Bar"
            add_child(_bar_node)
            _add_part(_cyl_mesh(0.03, 0.03, 1.70), steel, Vector3(0, 0.92, 0),
                    Vector3(0, 0, PI * 0.5), _bar_node)
            for sx in [-0.78, 0.78]:
                _add_part(_cyl_mesh(0.25, 0.25, 0.08), plate_mat,
                        Vector3(sx, 0.92, 0), Vector3(0, 0, PI * 0.5), _bar_node)
        "tires":
            # 3 покрышки прямо на полу + кувалда, прислонённая рядом
            var tg := _node("Tires", Vector3.ZERO)
            _deform_node = tg
            for k in 3:
                var tire := _add_part(_torus_mesh(0.27, 0.40), rubber,
                        Vector3(0, 0.08 + k * 0.16, 0), Vector3.ZERO, tg)
                tire.scale = Vector3(1.0, 1.25, 1.0)
            var hh := _node("Hammer", Vector3(0.85, 0.28, 0.05))
            hh.rotation = Vector3(0, 0, -0.5)
            # локальная геометрия: хват в (0,0,0), рукоять -0.30…+0.55,
            # боёк на +0.55 (0.55 м от кулака), как у кувалды 4–5 кг.
            _add_part(_cyl_mesh(0.0225, 0.0225, 0.85), wood,
                    Vector3(0, 0.125, 0), Vector3.ZERO, hh)
            _add_part(_cyl_mesh(0.05, 0.05, 0.24), met,
                    Vector3(0, 0.55, 0), Vector3(0, 0, PI * 0.5), hh)
            _add_part(_cyl_mesh(0.03, 0.03, 0.05), met,
                    Vector3(0, -0.30, 0), Vector3.ZERO, hh)
            _hammer_node = hh
            _hammer_rest_parent = _prop
            _hammer_rest_xform = hh.transform
        "rope", "speedrope":
            # мат + стойка с двумя скакалками на крючках h1.6
            _add_part(_box_mesh(Vector3(1.2, 0.06, 0.8)), mat, Vector3(0, 0.03, 0))
            _add_part(_box_mesh(Vector3(0.5, 0.05, 0.4)), met, Vector3(0, 0.025, 0))
            _add_part(_cyl_mesh(0.04, 0.04, 1.6), met, Vector3(0, 0.8, 0))
            _add_part(_cyl_mesh(0.03, 0.03, 0.9), met,
                    Vector3(0, 1.6, 0), Vector3(0, 0, PI * 0.5))
            var rope_piv := _node("RopePivot", Vector3(0, 1.6, 0))
            _swing_node = rope_piv
            _swing_base_y = 1.6
            for sx in [-0.25, 0.25]:
                _add_part(_cyl_mesh(0.01, 0.01, 1.15), det,
                        Vector3(sx, -0.575, 0), Vector3.ZERO, rope_piv)
                _add_part(_cyl_mesh(0.025, 0.025, 0.16), wood,
                        Vector3(sx, -1.2, 0), Vector3.ZERO, rope_piv)
        "shadow":
            # стальная рама + зеркало 1.1×1.8 на 0.15…1.95 + мат
            for sx in [-0.62, 0.62]:
                _add_part(_cyl_mesh(0.05, 0.05, 2.0), met, Vector3(sx, 1.0, 0))
            for sy in [0.15, 1.95]:
                _add_part(_cyl_mesh(0.04, 0.04, 1.3), met,
                        Vector3(0, sy, 0), Vector3(0, 0, PI * 0.5))
            _add_part(_box_mesh(Vector3(1.1, 1.8, 0.03)), mirror,
                    Vector3(0, 1.05, 0.02))
            _add_part(_box_mesh(Vector3(1.4, 0.05, 1.0)), mat, Vector3(0, 0.025, 0.35))
        "pushups":
            # мат + две упор-ручки по бокам
            _add_part(_box_mesh(Vector3(1.45, 0.06, 1.0)), mat, Vector3(0, 0.03, 0))
            for sx in [-0.35, 0.35]:
                _add_part(_box_mesh(Vector3(0.04, 0.18, 0.04)), met,
                        Vector3(sx, 0.09, -0.15))
                _add_part(_box_mesh(Vector3(0.04, 0.18, 0.04)), met,
                        Vector3(sx, 0.09, 0.15))
                _add_part(_cyl_mesh(0.025, 0.025, 0.34), wood,
                        Vector3(sx, 0.18, 0), Vector3(PI * 0.5, 0, 0))
        "bar":
            # напольный турник: стойки 2.3, перекладина 1.44 на 2.3
            for sx in [-0.62, 0.62]:
                _add_part(_cyl_mesh(0.05, 0.05, 2.3), met, Vector3(sx, 1.15, 0))
                _add_part(_box_mesh(Vector3(0.3, 0.04, 0.3)), met,
                        Vector3(sx, 0.02, 0))
            _add_part(_cyl_mesh(0.04, 0.04, 1.44), met,
                    Vector3(0, 2.3, 0), Vector3(0, 0, PI * 0.5))
        "climb":
            # канат подвешен к раме 3.4 м; низ каната 0.45, узлы через 0.6
            for sx in [-0.62, 0.62]:
                _add_part(_cyl_mesh(0.05, 0.05, 3.4), met, Vector3(sx, 1.7, 0))
                _add_part(_box_mesh(Vector3(0.3, 0.04, 0.3)), met,
                        Vector3(sx, 0.02, 0))
            _add_part(_cyl_mesh(0.04, 0.04, 1.44), met,
                    Vector3(0, 3.4, 0), Vector3(0, 0, PI * 0.5))
            var climb_piv := _node("RopePivot", Vector3(0, 3.4, 0))
            _swing_node = climb_piv
            _swing_base_y = 3.4
            _add_part(_cyl_mesh(0.025, 0.025, 2.95), det,
                    Vector3(0, -1.475, 0), Vector3.ZERO, climb_piv)
            for ky in [-0.6, -1.2, -1.8, -2.4]:
                _add_part(_sph_mesh(0.055), met,
                        Vector3(0, ky, 0), Vector3.ZERO, climb_piv)
        "burpee":
            _add_part(_box_mesh(Vector3(1.2, 0.06, 0.7)), mat, Vector3(0, 0.03, 0))
        "run", "treadmill":
            # дорожка: полотно на полу + поручень 1.02 и пульт
            _add_part(_box_mesh(Vector3(1.6, 0.08, 0.72)), det, Vector3(0, 0.06, 0))
            for sz in [-0.38, 0.38]:
                _add_part(_box_mesh(Vector3(1.6, 0.14, 0.06)), met,
                        Vector3(0, 0.14, sz))
            for sx in [-0.74, 0.74]:
                _add_part(_box_mesh(Vector3(0.06, 0.95, 0.06)), met,
                        Vector3(sx, 0.55, -0.34))
            _add_part(_box_mesh(Vector3(1.53, 0.06, 0.06)), met,
                    Vector3(0, 1.02, -0.34))
            _add_part(_box_mesh(Vector3(0.5, 0.12, 0.22)), det,
                    Vector3(0, 0.94, -0.30))
        "dips":
            # напольные брусья: 4 стойки 1.15, жерди Ø0.04 длиной 1.5 вдоль Z
            for sx in [-0.34, 0.34]:
                for sz in [-0.7, 0.7]:
                    _add_part(_cyl_mesh(0.04, 0.04, 1.15), met,
                            Vector3(sx, 0.575, sz))
            for sx in [-0.34, 0.34]:
                _add_part(_cyl_mesh(0.04, 0.04, 1.5), met,
                        Vector3(sx, 1.15, 0), Vector3(PI * 0.5, 0, 0))
            _add_part(_box_mesh(Vector3(1.5, 0.04, 1.8)), det, Vector3(0, 0.02, 0))
        _:
            return


## v71s: тумбы больше нет — оставлено no-op для старых вызовов.
func _hide_pedestal() -> void:
    pass


## v71s: отдать/вернуть кувалду бойцу. Вызывает training_mode.gd на начале/конце
## станции «покрышки». p — боец (Fighter), кувалда цепляется к правому
## предплечью `el_r`, хват — в центре перчатки.
func set_holder(p: Node3D) -> void:
    if def == null or String(def.id) != "tires" or _hammer_node == null:
        return
    if p == null:
        if _hammer_holder != null and _hammer_rest_parent != null:
            _hammer_node.reparent(_hammer_rest_parent, false)
            _hammer_node.transform = _hammer_rest_xform
        _hammer_holder = null
        return
    var hand: Node3D = null
    var v: Variant = p.get("el_r")
    if v is Node3D:
        hand = v as Node3D
    if hand == null:
        hand = p
    if _hammer_holder == hand:
        _update_hammer_hand()
        return
    _hammer_holder = hand
    _hammer_node.reparent(hand, false)
    _update_hammer_hand()


## v71s: отладочный захват кувалды для кадров (в игре training_mode вызывает
## set_holder сам). Env VRINGE_HAMMER_HAND=1.
func _debug_attach_hammer() -> void:
    if _hammer_holder != null or _hammer_node == null \
            or OS.get_environment("VRINGE_HAMMER_HAND") == "":
        return
    var n := get_parent()
    while n != null:
        if n.has_method("_player"):
            var pl: Node3D = n.call("_player")
            if pl != null:
                set_holder(pl)
            return
        n = n.get_parent()


## Держим рукоять от кулака вниз-вперёд (к покрышкам), боёк на 0.55 м.
## v71s: обновляем молот после того, как training_mode применил позу текущего
## кадра (tick может идти до позы, тогда молот отставал на кадр).
func _process(_delta: float) -> void:
    _update_hammer_hand()


## Боёк — продолжение кулака вдоль оси руки (плечо → кулак), поэтому в замахе
## молот смотрит вверх, в ударе — вниз. Рукоять не идёт сквозь корпус.
func _update_hammer_hand() -> void:
    if _hammer_node == null or _hammer_holder == null \
            or not is_instance_valid(_hammer_holder) \
            or not is_instance_valid(_hammer_node):
        return
    var fist: Vector3 = _hammer_holder.to_global(Vector3(0.0, -0.42, 0.0))
    # плечо ищем по sh_r, иначе — родитель предплечья.
    var shoulder: Node3D = null
    var p := _hammer_holder.get_parent()
    while p != null:
        var v: Variant = p.get("sh_r")
        if v is Node3D:
            shoulder = v as Node3D
            break
        p = p.get_parent()
    if shoulder == null:
        var par := _hammer_holder.get_parent()
        if par is Node3D:
            shoulder = par as Node3D
    var axis: Vector3
    if shoulder != null:
        axis = fist - shoulder.global_position
    else:
        axis = _hammer_holder.global_transform.basis.y
    if axis.length() < 0.02:
        axis = Vector3.DOWN
    axis = axis.normalized()
    var x_axis: Vector3 = axis.cross(Vector3.UP)
    if x_axis.length() < 0.01:
        x_axis = axis.cross(Vector3.RIGHT)
    x_axis = x_axis.normalized()
    var z_axis: Vector3 = x_axis.cross(axis).normalized()
    _hammer_node.global_transform = Transform3D(Basis(x_axis, axis, z_axis), fist)


func _kind_color() -> Color:
    match def.kind:
        StationDef.Kind.BAG:
            return Color(0.42, 0.24, 0.20)
        StationDef.Kind.QTE:
            return Color(0.24, 0.30, 0.42)
        StationDef.Kind.RHYTHM:
            return Color(0.24, 0.40, 0.30)
        StationDef.Kind.HOLD:
            return Color(0.40, 0.26, 0.42)
    return Color(0.30, 0.30, 0.30)


## Подпись станции на сцене: только название, чтобы подписи не наезжали.
## Мастерство и прочность видны в списке станций слева.
func update_label() -> void:
    if _label == null:
        return
    _label.text = String(def.title)


func kind() -> StationDef.Kind:
    return def.kind


func is_broken() -> bool:
    return durability <= 0.0


## Начать подход. false — станция сломана или уже идёт подход.
func begin() -> bool:
    if active or is_broken():
        return false
    active = true
    finished = false
    ok = false
    reps_done = 0
    mistakes = 0
    gain = {}
    t = 0.0
    _cool = 0.0
    _prompt_t = -1.0
    # первое окно — быстро (0.6 с), чтобы подход не начинался с пустой паузы;
    # дальше между окнами 3–5 с по ТЗ.
    _gap_now = _roll_gap()
    _next_prompt = 0.6
    _holding = false
    _hold_t = 0.0
    return true


## v36: окно нажатия 3 с (время НА нажатие), пауза между окнами короткая —
## per-station база + разброс, clamp 0.6–2.5 с.
func _roll_gap() -> float:
    var base := float(def.qte_gap_seconds) if def != null else 1.0
    var j := float(def.qte_gap_jitter) if def != null else 0.2
    return clampf(randf_range(base - j, base + j), 0.6, 2.5)


## Текущая пауза между окнами (для синхронизации анимации упражнения).
func interval_now() -> float:
    return _gap_now


## Сколько секунд до следующего окна (0 — окно уже открыто).
func time_to_prompt() -> float:
    if _prompt_t >= 0.0:
        return 0.0
    return maxf(0.0, _next_prompt)


## Нажатие действия (E/Space). Возвращает "hit"/"miss"/"early"/"wait"/"start"/"ignored".
func press() -> String:
    if not active:
        return "ignored"
    match def.kind:
        StationDef.Kind.BAG:
            if _cool > 0.0:
                return "wait"
            _cool = float(def.cooldown)
            _success()
            return "hit"
        StationDef.Kind.HOLD:
            if _holding:
                return "ignored"
            _holding = true
            _hold_t = 0.0
            return "start"
        _:
            if _prompt_t >= 0.0 and _prompt_t <= float(def.perfect_window):
                _prompt_t = -1.0
                _success()
                # следующее окно — через новую паузу
                _gap_now = _roll_gap()
                _next_prompt = _gap_now
                return "hit"
            # v59: нажатие ДО подсказки — не промах. Раньше любое лишнее нажатие
            # записывалось в промахи, и было непонятно, «когда жать, чтобы
            # засчиталось»: игрок жал, когда казалось пора, и портил подход.
            # Теперь такой тычок просто игнорируется (с подсказкой «рано»),
            # а промах — это только пропущенное окно (истечение без нажатия).
            return "early"
    return "ignored"


## Покадровое обновление: таймеры подсказок, удержание, кулдаун.
func tick(delta: float, held: bool) -> void:
    _debug_attach_hammer()
    _update_hammer_hand()
    if not active:
        return
    t += delta
    _cool = maxf(0.0, _cool - delta)
    if def.kind == StationDef.Kind.BAG:
        return
    if def.kind == StationDef.Kind.HOLD:
        if _holding:
            if held:
                _hold_t += delta
                if _hold_t >= float(def.hold_time):
                    _holding = false
                    _hold_t = 0.0
                    _success()
            else:
                _holding = false
                _hold_t = 0.0
                _miss()
        return
    # QTE / ритм: подсказки идут с паузой, окно — perfect_window
    if _prompt_t >= 0.0:
        if not debug_hold_prompt:
            _prompt_t += delta
            if _prompt_t > float(def.perfect_window):
                _prompt_t = -1.0
                _miss()
                _gap_now = _roll_gap()
                _next_prompt = _gap_now
        return
    _next_prompt -= delta
    if _next_prompt <= 0.0:
        _prompt_t = 0.0


## Подсказка открыта (для UI и тестов).
func prompt_open() -> bool:
    return active and _prompt_t >= 0.0


## Насколько глубоко в окне QTE было нажатие (0 — в начале окна, 1 — в конце).
## Нужно для синхронизации пика анимации с окном (Этап 3, волна 2).
func prompt_frac() -> float:
    if _prompt_t < 0.0 or def == null:
        return 0.5
    var w := float(def.perfect_window)
    if w <= 0.0001:
        return 0.5
    return clampf(_prompt_t / w, 0.0, 1.0)


func prompt_left() -> float:
    if _prompt_t < 0.0:
        return 0.0
    return maxf(0.0, float(def.perfect_window) - _prompt_t)


func hold_progress() -> float:
    if not _holding:
        return 0.0
    return clampf(_hold_t / maxf(0.01, float(def.hold_time)), 0.0, 1.0)


func _success() -> void:
    reps_done += 1
    if mode != null:
        mode.station_gain(self)
        mode.consume_wear(self)
    if float(def.reps) > 0.0 and reps_done >= int(def.reps):
        _finish(true)


func _miss() -> String:
    mistakes += 1
    if mode != null:
        mode.play_fail(self)
    if mistakes > int(def.mistakes_allowed):
        _finish(false)
    return "miss"


func _finish(win: bool) -> void:
    if finished:
        return
    active = false
    finished = true
    ok = win
    if mode != null:
        mode.on_station_finished(self)


## Принудительно закончить подход (Esc): результат не засчитывается.
func abort() -> void:
    if not active:
        return
    active = false
    finished = true
    ok = false
    if mode != null:
        mode.on_station_finished(self)


# ---------------------------------------------------------------- Этап 3: качание снаряда

## Попадание: толчок снаряда в направлении удара (dir — от игрока к станции).
## При anim_on=false (train_anim_level=OFF) не меняет ни одного трансформа.
func animate_hit(dir: Vector3) -> void:
    if not anim_on or _swing_node == null:
        return
    _debug_hold = ""
    _swing_axis = _hit_axis(dir)
    var rp := _reaction_profile()
    _swing_amp = deg_to_rad(swing_amp_deg) * float(rp["amp"])
    _cur_freq = float(rp["freq"])
    _cur_damp = float(rp["damp"])
    _swing_t = 0.0
    _swinging = true
    # 3.2: покрышки «промнутся» от удара (визуальная деформация, затухает)
    if def != null and String(def.id) == "tires":
        _deform = tire_deform
    _hits_in_row += 1
    if _hits_in_row >= maxi(1, shake_after):
        _hits_in_row = 0
        _shake_amp = deg_to_rad(shake_amp_deg)
        _shake_t = 0.0
        _shaking = true


## Промах: снаряд не трогаем — визуал «сорвался» делает боец (поза miss).
func animate_miss() -> void:
    pass


## Этап 4: профиль реакции снаряда (амплитуда/частота/затухание по типу станции).
## BAG — мягкое качание; dummy — жёсткое и быстрое; speedbag — мелкая быстрая
## вибрация; tires — тяжёлое; homemade_bar — рваное (чуть больше тряски).
func _reaction_profile() -> Dictionary:
    var id := String(def.id) if def != null else ""
    match id:
        "dummy":
            return {"amp": 0.55, "freq": 1.7, "damp": 1.5}
        "speedbag":
            return {"amp": 0.35, "freq": 3.2, "damp": 2.4}
        "tires":
            return {"amp": 0.75, "freq": 1.1, "damp": 0.9}
        "homemade_bar":
            return {"amp": 0.6, "freq": 1.8, "damp": 1.4}
        "barbell":
            return {"amp": 0.7, "freq": 1.6, "damp": 1.3}
        _:
            return {"amp": 1.0, "freq": 1.0, "damp": 1.0}


## Этап 4: поломка «отшатнулся» (наклон + провисание + дрожь + красный маркер).
## Только визуал: логика износа/ремонта не меняется.
func set_broken_visual(on: bool) -> void:
    if not anim_on or _swing_node == null:
        return
    _broken_visual_on = on
    if on:
        _swing_node.rotation = Vector3(0.0, 0.0, deg_to_rad(break_tilt_deg))
        _swing_node.position.y = _swing_base_y - break_sag
        if _body_mat != null:
            _body_mat.emission = Color(0.85, 0.20, 0.12)
        if _label != null:
            _label.modulate = Color(1.0, 0.45, 0.40)
    else:
        _swing_node.rotation = Vector3.ZERO
        _swing_node.position.y = _swing_base_y
        if _body_mat != null:
            _body_mat.emission = _kind_color() * 0.45
        if _label != null:
            _label.modulate = Color(1.0, 0.94, 0.78)


func debug_set_broken(on: bool) -> void:
    _debug_broken = on
    set_broken_visual(on)


## Этап 4: скакалка — вращение с затуханием после остановки.
func animate_rope_stop(power: float = 8.0) -> void:
    if not anim_on or _swing_node == null:
        return
    _rope_speed = clampf(power, 1.0, 20.0)


## Ось качания: горизонтальный перпендикуляр к вектору удара.
func _hit_axis(dir: Vector3) -> Vector3:
    var d := Vector3(dir.x, 0.0, dir.z)
    if d.length() < 0.001:
        d = Vector3(0.0, 0.0, -1.0)
    var axis := Vector3.UP.cross(d.normalized())
    if axis.length() < 0.001:
        axis = Vector3.RIGHT
    return axis.normalized()


## Покадровое затухание качания/встряски. При anim_on=false — no-op.
func anim_tick(delta: float) -> void:
    _debug_attach_hammer()
    _update_hammer_hand()
    if not anim_on or _swing_node == null:
        return
    if _debug_hold != "":
        return
    # Этап 4: поломка — маркер + дрожь «отшатнулся» (только визуал)
    var broken: bool = is_broken() or _debug_broken
    if broken != _broken_visual_on:
        set_broken_visual(broken)
    if _broken_visual_on:
        _broken_t += delta
        _swing_node.rotation.z = deg_to_rad(break_tilt_deg) \
                + deg_to_rad(break_tremble_deg) * sin(_broken_t * 11.0)
    # Этап 4: скакалка после остановки докручивается с затуханием
    if _rope_speed > 0.02:
        _rope_angle += _rope_speed * delta
        _rope_speed *= exp(-2.6 * delta)
        _swing_node.basis = Basis(Vector3.RIGHT, _rope_angle)
    var ang := 0.0
    var fr := swing_freq if _cur_freq <= 0.0 else _cur_freq
    var dp := swing_damping if _cur_damp <= 0.0 else _cur_damp
    if _swinging:
        _swing_t += delta
        var e := exp(-dp * _swing_t)
        ang += _swing_amp * e * sin(TAU * fr * _swing_t)
        if e < SWING_EPS:
            _swinging = false
            _swing_t = 0.0
    if _shaking:
        _shake_t += delta
        var e2 := exp(-shake_damping * _shake_t)
        ang += _shake_amp * e2 * sin(TAU * shake_freq * _shake_t)
        if e2 < SWING_EPS:
            _shaking = false
            _shake_t = 0.0
    _swing_node.basis = Basis(_swing_axis, ang)
    # Этап 3.2: лёгкая деформация шины от удара (затухает)
    if _deform > 0.0001:
        _deform = maxf(0.0, _deform - delta * 0.9)
        var dn: Node3D = _deform_node if _deform_node != null else _prop
        if dn != null:
            dn.scale = Vector3(1.0 + _deform * 0.5, 1.0 - _deform,
                    1.0 + _deform * 0.5)


# ---------------------------------------------------------------- Этап 3.2-3.4

## 3.3 Жим: снаряд поднимается по прогрессу 0..1 (0 — внизу, 1 — lockout),
## vibr — тряска под нагрузкой 0..1.
func animate_lift(progress: float, vibr: float = 0.0) -> void:
    if not anim_on:
        return
    # v71q: у жима лёжа двигаем ТОЛЬКО гриф (_bar_node), скамья и стойки стоят.
    var target: Node3D = _bar_node if _bar_node != null else _prop
    if target == null:
        return
    var base := 0.0 if target == _bar_node else _prop_base_y
    _vib_phase += 0.18
    var shake := sin(_vib_phase * 9.0) * 0.012 * vibr
    target.position.y = base + lift_height * clampf(progress, 0.0, 1.0) + shake
    target.basis = Basis(Vector3.RIGHT, deg_to_rad(1.6) * vibr
            * sin(_vib_phase * 7.0))


## 3.4 Подтягивание: перекладина проседает под весом (progress 0..1).
func animate_pull(progress: float) -> void:
    if not anim_on or _swing_node == null:
        return
    _swing_node.position.y = _swing_base_y - pull_sag * clampf(progress, 0.0, 1.0)


## 3.6 Прыжки: вращение скакалки/кистей (угол в радианах).
func animate_rope(angle: float) -> void:
    if not anim_on or _swing_node == null:
        return
    _swing_node.basis = Basis(Vector3.RIGHT, angle)


## 3.3 Промах: штанга падает/бросается — короткий провал вниз и стук.
func animate_drop() -> void:
    if not anim_on or _swing_node == null:
        return
    _swing_node.position.y = _swing_base_y - 0.05
    _shake_amp = deg_to_rad(shake_amp_deg * 1.5)
    _shake_t = 0.0
    _shaking = true


## 3.2 Пыль от удара по покрышкам. Лимит — min(dust_amount, particle_budget);
## при OFF узел частиц не создаётся вообще (кадр базлайновый).
func emit_dust(dir: Vector3) -> void:
    if not anim_on or _prop == null:
        return
    var n := mini(dust_amount, particle_budget)
    if n <= 0:
        return
    if _dust == null:
        _make_dust()
    _dust.amount = n
    _dust.restart()


func _make_dust() -> void:
    _dust = GPUParticles3D.new()
    _dust.name = "Dust"
    _dust.amount = dust_amount
    _dust.lifetime = 0.6
    _dust.one_shot = true
    _dust.explosiveness = 0.9
    _dust.emitting = false
    _dust.position = Vector3(0.0, 0.55, 0.0)
    var pm := ParticleProcessMaterial.new()
    pm.direction = Vector3(0.0, 1.0, 0.0)
    pm.spread = 65.0
    pm.initial_velocity_min = 0.8
    pm.initial_velocity_max = 2.2
    pm.gravity = Vector3(0.0, -2.2, 0.0)
    pm.scale_min = 0.6
    pm.scale_max = 1.5
    pm.color = Color(0.72, 0.66, 0.55)
    _dust.process_material = pm
    var qm := QuadMesh.new()
    qm.size = Vector2(0.06, 0.06)
    var dm := StandardMaterial3D.new()
    dm.albedo_color = Color(0.72, 0.66, 0.55)
    dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    qm.material = dm
    _dust.draw_pass_1 = qm
    add_child(_dust)


## Сброс анимации (при закрытии комнаты/переодевании/выходе из локации).
func reset_anim() -> void:
    if _hammer_holder != null:
        set_holder(null)
    _swinging = false
    _shaking = false
    _swing_t = 0.0
    _shake_t = 0.0
    _hits_in_row = 0
    _debug_hold = ""
    _deform = 0.0
    if _prop != null:
        _prop.basis = Basis.IDENTITY
        _prop.position.y = _prop_base_y
        _prop.scale = Vector3.ONE
    if _swing_node != null and _swing_node != _prop:
        _swing_node.basis = Basis.IDENTITY
        _swing_node.position.y = _swing_base_y
        _swing_node.scale = Vector3.ONE
    if _deform_node != null:
        _deform_node.scale = Vector3.ONE
    if _bar_node != null:
        _bar_node.basis = Basis.IDENTITY
        _bar_node.position = Vector3.ZERO
    if _dust != null:
        _dust.emitting = false


## Отладочный статичный кадр фазы (только для скриншотов Этапа 3; в игре не
## вызывается). Фазы: impact / follow / series / idle.
func debug_hold(phase_name: String, dir: Vector3 = Vector3(0.0, 0.0, -1.0)) -> void:
    if _swing_node == null:
        return
    _swinging = false
    _shaking = false
    _debug_hold = phase_name
    _swing_axis = _hit_axis(dir)
    var amp := deg_to_rad(swing_amp_deg)
    var ang := 0.0
    match phase_name:
        "impact":
            ang = amp
        "follow":
            ang = amp * 0.45
        "series":
            ang = amp * 0.6 + deg_to_rad(shake_amp_deg)
        _:
            ang = 0.0
    _swing_node.basis = Basis(_swing_axis, ang)


var _debug_angle := 0.0

