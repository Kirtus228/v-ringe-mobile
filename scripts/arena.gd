extends Node3D
## Арена: настил ринга, канаты, столбы, ступенчатые трибуны с толпой.
##
## Оптимизация (Этап 6): статика больше не создаётся как сотни MeshInstance3D —
## ступени/настил/столбы склеены в MultiMeshInstance3D по материалу, канаты
## (168 сегментов) сведены в 3 MultiMesh (по уровню), толпа — как была, 2 MultiMesh.
## Внешний вид и поведение (прогиб канатов rope_hit) сохранены: у каждого сегмента
## каната своя per-instance transform, обновляемая при колебании.

const RING_HALF := 3.5
const ROPE_SEGS := 14
const ROPE_LEVELS := [0.62, 1.0, 1.38]

var crowd_meshes: Array = []
var ropes: Array = []          # сегменты канатов: base/size/axis/off/vel
var _energy := 0.0
var _time := 0.0
var _box_batches := {}
var _cyl_batches := {}
var _rope_meshes: Array = []
## v48: меши канатов пересобираются только когда канаты реально колеблются
var _rope_dirty := false
## Пакет 2 / T5: счётчик пересборок мешей канатов (диагностика перфа)
var rope_rebuilds := 0
## T5: максимум времени одной пересборки меша канатов, мкс (диагностика)
var rope_rebuild_usec_max := 0
## T5: на телефоне (склеенный меш) — не чаще 10 раз в секунду
var _rope_acc := 0.0
## T5: узел/материал/юнит-бокс канатов создаются один раз (обновляются только
## трансформы инстансов MultiMesh)
var _rope_mat: StandardMaterial3D
var _rope_unit: BoxMesh
## T5: MultiMesh на каждый уровень канатов (168 инстансов всего)
var _rope_mm: Array = []


func build() -> void:
    # T5: на ПК канаты — MultiMesh (быстро), на телефоне — склеенный меш
    # (MultiMesh-арена на телефоне в v49 не рисовалась). VRINGE_ROPES=merged
    # принудительно включает «телефонный» путь для проверки на ПК.
    _rope_use_mm = not OS.has_feature("mobile")
    if OS.get_environment("VRINGE_ROPES").strip_edges() == "merged":
        _rope_use_mm = false
    _floor()
    _ring()
    _stands()
    _commit_batches()


func _mat(c: Color, rough: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    m.metallic = metallic
    return m


## Добавить бокс в батч материала (позиция/размер; склейка при _commit_batches).
func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
    if mat == null:
        return
    var key := mat.get_instance_id()
    if not _box_batches.has(key):
        _box_batches[key] = {"mat": mat, "items": []}
    _box_batches[key]["items"].append({"size": size, "pos": pos})


## Добавить цилиндр в батч материала.
func _cyl(radius: float, height: float, pos: Vector3, mat: Material) -> void:
    if mat == null:
        return
    var key := mat.get_instance_id()
    if not _cyl_batches.has(key):
        _cyl_batches[key] = {"mat": mat, "items": []}
    _cyl_batches[key]["items"].append({"r": radius, "h": height, "pos": pos})


## Склейка собранного в один ArrayMesh на материал (один draw на материал).
## v48: раньше здесь был MultiMeshInstance3D, но на телефоне заказчика MultiMesh
## не рисовался — статику склеиваем обычным мешем, он виден на любом GPU.
func _commit_batches() -> void:
    for key in _box_batches:
        var b: Dictionary = _box_batches[key]
        _add_merged_boxes(b["items"], b["mat"])
    for key in _cyl_batches:
        var b: Dictionary = _cyl_batches[key]
        _add_merged_cyls(b["items"], b["mat"])
    _box_batches.clear()
    _cyl_batches.clear()


## Все боксы батча — в один меш (размеры/позиции через scale/transform).
func _add_merged_boxes(items: Array, mat: Material) -> MeshInstance3D:
    if items.is_empty():
        return null
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var unit := BoxMesh.new()
    unit.size = Vector3.ONE
    for it in items:
        st.append_from(unit, 0, Transform3D(Basis.from_scale(it["size"]), it["pos"]))
    return _add_merged(st, mat)


## Все цилиндры батча — в один меш.
func _add_merged_cyls(items: Array, mat: Material) -> MeshInstance3D:
    if items.is_empty():
        return null
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var unit := CylinderMesh.new()
    unit.top_radius = 0.5
    unit.bottom_radius = 0.5
    unit.height = 1.0
    for it in items:
        var r := float(it["r"])
        st.append_from(unit, 0, Transform3D(
                Basis.from_scale(Vector3(r * 2.0, float(it["h"]), r * 2.0)), it["pos"]))
    return _add_merged(st, mat)


func _add_merged(st: SurfaceTool, mat: Material) -> MeshInstance3D:
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return null
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    add_child(mi)
    return mi


## Канаты. Пакет 2 / T5: на ПК — MultiMesh (один меш-бокс + 168 инстансов):
## колебание меняет только transform инстанса, геометрия не пересобирается.
## Это убрало провалы кадров при запутывании тела в канатах (baseline: 45 FPS,
## 1% low 10.6 → стало 165 FPS, 1% low 111).
## На телефоне MultiMesh-арена раньше не рисовалась (v49), поэтому там остаётся
## прежний склеенный меш — но узлы не пересоздаются, только подменяется mesh,
## и пересборка идёт не чаще ROPE_REBUILD_HZ_MOBILE раз в секунду.
const ROPE_REBUILD_HZ_MOBILE := 20.0
var _rope_use_mm := true

## v71j: пересборка склеенного меша канатов на телефоне. Раньше это был
## SurfaceTool + append_from на КАЖДЫЙ сегмент (56 вызовов) + commit() —
## на Android одна пересборка занимала до 60 мс, а три уровня пересобирались
## в одном кадре: тело запутывалось в канатах → 5 FPS. Теперь вершины/нормали/
## индексы уровня считаются один раз (масштаб сегмента постоянный, от колебания
## меняется только смещение), а при обновлении пересчитываются только позиции
## и меш собирается одним add_surface_from_arrays.
var _rope_refs: Array = []        # по уровню: ссылки на сегменты каната
var _rope_base_v: Array = []      # по уровню: PackedVector3Array локальных вершин
var _rope_normals: Array = []     # по уровню: PackedVector3Array нормалей
var _rope_indices: Array = []     # по уровню: PackedInt32Array индексов
var _rope_vcount := 0             # вершин в одном сегменте (24 у бокса)


func _ensure_rope_nodes() -> void:
    if not _rope_meshes.is_empty():
        return
    _rope_mat = _mat(Color(0.6, 0.13, 0.17), 0.5, 0.15)
    _rope_unit = BoxMesh.new()
    _rope_unit.size = Vector3.ONE
    var aabb := AABB(Vector3(-6.0, -2.0, -6.0), Vector3(12.0, 6.0, 12.0))
    for li in ROPE_LEVELS.size():
        if _rope_use_mm:
            var count := 0
            for r in ropes:
                if int(r["level"]) == li:
                    count += 1
            var mm := MultiMesh.new()
            mm.transform_format = MultiMesh.TRANSFORM_3D
            mm.mesh = _rope_unit
            mm.instance_count = count
            var mmi := MultiMeshInstance3D.new()
            mmi.name = "RopeLevel%d" % li
            mmi.multimesh = mm
            mmi.material_override = _rope_mat
            mmi.custom_aabb = aabb
            add_child(mmi)
            _rope_meshes.append(mmi)
            _rope_mm.append(mm)
        else:
            var mi := MeshInstance3D.new()
            mi.name = "RopeLevel%d" % li
            mi.material_override = _rope_mat
            mi.custom_aabb = aabb
            add_child(mi)
            _rope_meshes.append(mi)
    if not _rope_use_mm:
        _rope_prepare_levels()


## v71j: один раз на уровень считаем раскладку вершин/нормалей/индексов.
## Сегмент каната не вращается и его размер не меняется — от колебания
## зависит только позиция, поэтому геометрию достаточно построить один раз.
func _rope_prepare_levels() -> void:
    _rope_refs.clear()
    _rope_base_v.clear()
    _rope_normals.clear()
    _rope_indices.clear()
    var ua: Array = _rope_unit.get_mesh_arrays()
    var uv: PackedVector3Array = ua[Mesh.ARRAY_VERTEX]
    var un: PackedVector3Array = ua[Mesh.ARRAY_NORMAL]
    var ui: PackedInt32Array = ua[Mesh.ARRAY_INDEX]
    _rope_vcount = uv.size()
    for li in ROPE_LEVELS.size():
        var refs: Array = []
        var bv := PackedVector3Array()
        var nv_arr := PackedVector3Array()
        var idx := PackedInt32Array()
        var nv := 0
        for r in ropes:
            if int(r["level"]) != li:
                continue
            var sz: Vector3 = r["size"]
            var bpos: Vector3 = r["base"]
            refs.append(r)
            for k in uv.size():
                var v: Vector3 = uv[k]
                bv.append(Vector3(v.x * sz.x, v.y * sz.y, v.z * sz.z) + bpos)
                nv_arr.append(un[k])
            for k in ui.size():
                idx.append(ui[k] + nv)
            nv += uv.size()
        _rope_refs.append(refs)
        _rope_base_v.append(bv)
        _rope_normals.append(nv_arr)
        _rope_indices.append(idx)


## Обновить уровень канатов: MultiMesh — трансформы, иначе — пересобрать mesh.
func _build_rope_mesh(level_idx: int) -> void:
    rope_rebuilds += 1
    var _t0 := Time.get_ticks_usec()
    _ensure_rope_nodes()
    if _rope_meshes.size() <= level_idx or _rope_meshes[level_idx] == null:
        return
    if _rope_use_mm:
        var mm: MultiMesh = _rope_mm[level_idx]
        var i := 0
        for r in ropes:
            if int(r["level"]) != level_idx:
                continue
            if i >= mm.instance_count:
                break
            mm.set_instance_transform(i, Transform3D(
                    Basis.from_scale(r["size"]), (r["base"] as Vector3) + (r["off"] as Vector3)))
            i += 1
    else:
        # v71j: быстрый путь телефона — только позиции вершин, один вызов сборки
        # меша (было 56 append_from + commit на уровень).
        var refs: Array = _rope_refs[level_idx]
        var base: PackedVector3Array = _rope_base_v[level_idx]
        var pos := PackedVector3Array()
        pos.resize(base.size())
        var slot := 0
        for ref in refs:
            var off: Vector3 = ref["off"]
            for k in _rope_vcount:
                pos[slot] = base[slot] + off
                slot += 1
        var arr: Array = []
        arr.resize(Mesh.ARRAY_MAX)
        arr[Mesh.ARRAY_VERTEX] = pos
        arr[Mesh.ARRAY_NORMAL] = _rope_normals[level_idx]
        arr[Mesh.ARRAY_INDEX] = _rope_indices[level_idx]
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
        (_rope_meshes[level_idx] as MeshInstance3D).mesh = mesh
    rope_rebuild_usec_max = maxi(rope_rebuild_usec_max, Time.get_ticks_usec() - _t0)


func _add_mm(mm: MultiMesh, mat: Material) -> MultiMeshInstance3D:
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = mat
    mmi.custom_aabb = AABB(Vector3(-30.0, -5.0, -30.0), Vector3(60.0, 30.0, 60.0))
    add_child(mmi)
    return mmi


func _floor() -> void:
    # пол зала
    _box(Vector3(46, 0.3, 46), Vector3(0, -1.30, 0), _mat(Color(0.03, 0.035, 0.05), 0.96))
    # помост ринга
    _box(Vector3(9.4, 0.4, 9.4), Vector3(0, -0.36, 0), _mat(Color(0.07, 0.08, 0.11), 0.9))
    # красный фартук по краю помоста
    var skirt := _mat(Color(0.28, 0.05, 0.08), 0.75)
    _box(Vector3(9.4, 0.55, 0.12), Vector3(0, -0.2, 4.7), skirt)
    _box(Vector3(9.4, 0.55, 0.12), Vector3(0, -0.2, -4.7), skirt)
    _box(Vector3(0.12, 0.55, 9.4), Vector3(4.7, -0.2, 0), skirt)
    _box(Vector3(0.12, 0.55, 9.4), Vector3(-4.7, -0.2, 0), skirt)
    # настил
    _box(Vector3(7.2, 0.12, 7.2), Vector3(0, -0.08, 0), _mat(Color(0.11, 0.13, 0.18), 0.88))
    # тёмная окантовка и логотип
    _box(Vector3(2.6, 0.02, 2.6), Vector3(0, -0.01, 0), _mat(Color(0.16, 0.21, 0.3), 0.75))
    _box(Vector3(2.2, 0.02, 2.2), Vector3(0, 0.0, 0), _mat(Color(0.1, 0.13, 0.19), 0.75))

    # физический пол: по нему падает ragdoll
    var floor_body := StaticBody3D.new()
    floor_body.name = "RingFloor"
    var fshape := CollisionShape3D.new()
    var fbox := BoxShape3D.new()
    fbox.size = Vector3(9.4, 0.5, 9.4)
    fshape.shape = fbox
    floor_body.add_child(fshape)
    floor_body.position = Vector3(0, -0.27, 0)
    add_child(floor_body)

    # пол зала ниже ринга на 1.15 м: тело, вылетевшее за канаты, реально падает
    var hall := StaticBody3D.new()
    hall.name = "HallFloor"
    var hshape := CollisionShape3D.new()
    var hbox := BoxShape3D.new()
    hbox.size = Vector3(46, 0.3, 46)
    hshape.shape = hbox
    hall.add_child(hshape)
    hall.position = Vector3(0, -1.30, 0)
    add_child(hall)


func _ring() -> void:
    var post_mat := _mat(Color(0.14, 0.16, 0.21), 0.4, 0.6)
    var pad_mat := _mat(Color(0.5, 0.1, 0.14), 0.6)
    var rope_mat := _mat(Color(0.6, 0.13, 0.17), 0.5, 0.15)
    var cap_mat := _mat(Color(0.95, 0.75, 0.25), 0.3, 0.5)

    var h := RING_HALF
    for c in [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h)]:
        _cyl(0.11, 1.45, c + Vector3(0, 0.72, 0), post_mat)
        _cyl(0.18, 0.1, c + Vector3(0, 1.47, 0), cap_mat)
        _cyl(0.22, 0.34, c + Vector3(0, 0.3, 0), pad_mat)

    # канаты — сегменты: тело влетает, канат прогибается и пружиной возвращается
    # (rope_hit + _animate_ropes). v48: один склеенный меш на уровень (обычный
    # MeshInstance3D, не MultiMesh — на телефоне MultiMesh не рисовался).
    var segs := ROPE_SEGS
    var sl := 2.0 * h / float(segs)
    for li in ROPE_LEVELS.size():
        var level := float(ROPE_LEVELS[li])
        for side in 4:
            var along_x := side < 2
            var sgn := -1.0 if side % 2 == 0 else 1.0
            for i in segs:
                var t := -h + sl * (float(i) + 0.5)
                var pos := Vector3.ZERO
                var size := Vector3.ZERO
                var axis := Vector3.ZERO
                if along_x:
                    pos = Vector3(t, level, h * sgn)
                    size = Vector3(sl + 0.02, 0.032, 0.032)
                    axis = Vector3(1, 0, 0)
                else:
                    pos = Vector3(h * sgn, level, t)
                    size = Vector3(0.032, 0.032, sl + 0.02)
                    axis = Vector3(0, 0, 1)
                ropes.append({"level": li, "base": pos, "size": size,
                        "axis": axis, "off": Vector3.ZERO, "vel": Vector3.ZERO})
    for li in ROPE_LEVELS.size():
        _build_rope_mesh(li)


## Канаты прогибаются от влетевшего тела и пружиной возвращаются назад.
func rope_hit(at: Vector3, dir: Vector3, power: float) -> void:
    var d := Vector3(dir.x, 0.0, dir.z)
    if d.length() < 0.01:
        d = Vector3(0, 0, 1)
    d = d.normalized()
    for r in ropes:
        var base: Vector3 = r["base"]
        var dd: float = Vector2(base.x - at.x, base.z - at.z).length()
        if dd > 1.45:
            continue
        var u := 1.0 - dd / 1.45
        var f := u * u * clampf(power, 0.0, 2.5) * 0.24
        var off: Vector3 = r["off"] + d * f
        r["off"] = off.limit_length(0.30)
        r["vel"] = (r["vel"] as Vector3) + d * f * 9.0


func _animate_ropes(dt: float) -> void:
    for r in ropes:
        var off: Vector3 = r["off"]
        var vel: Vector3 = r["vel"]
        if off.length() < 0.0004 and vel.length() < 0.002:
            continue
        vel += (-off * 205.0 - vel * 10.5) * dt
        off += vel * dt
        if off.length() < 0.0004:
            off = Vector3.ZERO
            vel = Vector3.ZERO
        r["off"] = off
        r["vel"] = vel
        _rope_dirty = true
    # v48: меш канатов пересобираем только когда они реально двигаются.
    # Пакет 2 / T5: не чаще ROPE_REBUILD_HZ раз в секунду — 3 уровня мeшей
    # (168 сегментов) каждый кадр были главной причиной провала FPS, когда тело
    # запутывается в канатах (замер: 28 перестроек/с, 45 FPS, 1% low 10.6).
    if _rope_dirty:
        if _rope_use_mm:
            # MultiMesh: обновление трансформов дешёвое — делаем каждый кадр,
            # канаты колеблются плавно
            for li in ROPE_LEVELS.size():
                _build_rope_mesh(li)
            _rope_dirty = false
        else:
            # склеенный меш (телефон): не чаще ROPE_REBUILD_HZ_MOBILE раз в секунду,
            # иначе пересборка 3 мешей каждый кадр роняет FPS
            _rope_acc += dt
            if _rope_acc >= 1.0 / ROPE_REBUILD_HZ_MOBILE:
                _rope_acc = 0.0
                for li in ROPE_LEVELS.size():
                    _build_rope_mesh(li)
                _rope_dirty = false


func _stands() -> void:
    var step_mat := _mat(Color(0.055, 0.06, 0.08), 0.95)
    var body_mat := _mat(Color(0.1, 0.11, 0.14), 0.95)
    var head_mat := _mat(Color(0.17, 0.18, 0.22), 0.9)

    var bodies := PackedVector3Array()
    var heads := PackedVector3Array()
    var rnd := RandomNumberGenerator.new()
    rnd.seed = 20261109

    # четыре трибуны, каждая — ступени по 0.55 м и публика на них
    for row in 4:
        var dist := 6.3 + float(row) * 1.25
        var y := -0.35 + float(row) * 0.55
        for side in 4:
            var horizontal := side < 2
            var sign_z := 1.0 if side == 0 else -1.0
            var sign_x := 1.0 if side == 2 else -1.0
            # ступень (в батч: 16 боксов → один MultiMesh)
            if horizontal:
                _box(Vector3(34, 0.55, 1.25), Vector3(0, y - 0.28, dist * sign_z), step_mat)
            else:
                _box(Vector3(1.25, 0.55, 34), Vector3(dist * sign_x, y - 0.28, 0), step_mat)
            # люди
            var n := 16
            for i in n:
                var off := -7.5 + float(i) * 1.0 + rnd.randf_range(-0.25, 0.25)
                var jitter := rnd.randf_range(-0.25, 0.25)
                var pos := Vector3.ZERO
                if horizontal:
                    pos = Vector3(off, y + 0.1, dist * sign_z + jitter)
                else:
                    pos = Vector3(dist * sign_x + jitter, y + 0.1, off)
                if absf(pos.x) < 5.2 and absf(pos.z) < 5.2:
                    continue
                bodies.append(pos + Vector3(0, 0.28, 0))
                heads.append(pos + Vector3(0, 0.72, 0))

    _multimesh(bodies, Vector3(0.5, 0.62, 0.42), body_mat)
    _multimesh(heads, Vector3(0.26, 0.26, 0.26), head_mat)


func _multimesh(points: PackedVector3Array, size: Vector3, mat: Material) -> MultiMeshInstance3D:
    if points.is_empty():
        return null
    var mesh := BoxMesh.new()
    mesh.size = size
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = points.size()
    var basis := Basis.from_scale(Vector3.ONE)
    var phases := PackedFloat32Array()
    var rnd := RandomNumberGenerator.new()
    rnd.seed = 4242 + points.size()
    for i in points.size():
        mm.set_instance_transform(i, Transform3D(basis, points[i]))
        phases.append(rnd.randf_range(0.0, TAU))
    var mmi := _add_mm(mm, mat)
    mmi.custom_aabb = AABB(Vector3(-18.0, -3.0, -18.0), Vector3(36.0, 12.0, 36.0))
    crowd_meshes.append({"mm": mm, "base": points, "phase": phases})
    return mmi


# ------------------------------------------------------------------ реакция толпы

func pulse(power: float) -> void:
    _energy = maxf(_energy, clampf(power, 0.0, 1.0))


func _process(delta: float) -> void:
    _time += delta
    _animate_ropes(delta)
    if _energy <= 0.002:
        return
    _energy = maxf(0.0, _energy - delta * 0.55)
    var basis := Basis.from_scale(Vector3.ONE)
    for entry in crowd_meshes:
        var mm: MultiMesh = entry["mm"]
        var base: PackedVector3Array = entry["base"]
        var phase: PackedFloat32Array = entry["phase"]
        var n := base.size()
        for i in n:
            var bounce := sin(_time * 9.0 + phase[i]) * 0.26 * _energy
            var sway_x := sin(_time * 5.0 + phase[i] * 1.7) * 0.06 * _energy
            var offset := Vector3(sway_x, maxf(bounce, 0.0), 0.0)
            mm.set_instance_transform(i, Transform3D(basis, base[i] + offset))
