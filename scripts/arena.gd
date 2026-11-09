extends Node3D
## Арена: настил ринга, канаты, столбы, ступенчатые трибуны с толпой (MultiMesh).

const RING_HALF := 3.5

var crowd_meshes: Array = []
var ropes: Array = []
var _energy := 0.0
var _time := 0.0


func build() -> void:
    _floor()
    _ring()
    _stands()


func _mat(c: Color, rough: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    m.metallic = metallic
    return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    add_child(mi)
    return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    add_child(mi)
    return mi


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

    # канаты — не цельные балки, а сегменты: тело влетает, канат прогибается
    # и пружиной выстреливает обратно (rope_hit + _animate_ropes)
    var segs := 14
    var sl := 2.0 * h / float(segs)
    for level in [0.62, 1.0, 1.38]:
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
                var mi := _box(size, pos, rope_mat)
                ropes.append({"mi": mi, "base": pos, "axis": axis,
                        "off": Vector3.ZERO, "vel": Vector3.ZERO})


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
        var mi: MeshInstance3D = r["mi"]
        mi.position = (r["base"] as Vector3) + off

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
            # ступень
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
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = mat
    add_child(mmi)
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
