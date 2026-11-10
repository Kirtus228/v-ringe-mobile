extends Node3D
## Боксёр: артикулированный скелет (плечо-локоть, бедро-колено-стопа),
## процедурная анимация ударов/блока/уклона/шага, «пьяный» баланс
## и физический ragdoll на RigidBody3D при нокдауне.

signal impact(kind)
signal footstep(power)
signal knocked_down

const LookScript = preload("res://scripts/look.gd")

## Внешность соперника: красный угол.
const LOOK_ENEMY := {
    "hair": "buzz", "hair_color": "black",
    "skin": "tan", "build": "heavy",
    "gloves": "twelve", "gloves_color": "red",
    "shorts": "short", "shorts_color": "red",
    "boots": "hi", "boots_color": "black",
}

const PUNCHES := {
    "jab": {
        "stam": 9.0, "dmg": 7.0, "reach": 1.45, "dur": 0.28, "hit_at": 0.13,
        "score": 10, "push": 0.30, "stun": 0.18, "arm": "l",
        "sh": Vector3(1.55, 0.05, -0.08), "el": 0.10,
        "twist": -0.14, "hip": Vector2(0.03, 0.05),
    },
    "lhook": {
        "stam": 14.0, "dmg": 11.0, "reach": 1.30, "dur": 0.38, "hit_at": 0.19,
        "score": 20, "push": 0.42, "stun": 0.26, "arm": "l",
        "sh": Vector3(1.15, -0.95, -0.30), "el": 1.40,
        "twist": 0.70, "hip": Vector2(0.17, 0.09),
    },
    "rhook": {
        "stam": 16.0, "dmg": 13.0, "reach": 1.28, "dur": 0.42, "hit_at": 0.21,
        "score": 26, "push": 0.48, "stun": 0.30, "arm": "r",
        "sh": Vector3(1.10, 0.95, 0.10), "el": 1.50,
        "twist": -0.80, "hip": Vector2(-0.20, 0.11),
    },
    "upper": {
        "stam": 22.0, "dmg": 15.0, "reach": 1.25, "dur": 0.50, "hit_at": 0.24,
        "score": 30, "push": 0.55, "stun": 0.35, "arm": "r",
        "sh": Vector3(1.28, 0.0, 0.12), "el": 1.15,
        "twist": -0.32, "hip": Vector2(-0.04, 0.18),
    },
    "cross": {
        "stam": 15.0, "dmg": 12.0, "reach": 1.52, "dur": 0.36, "hit_at": 0.17,
        "score": 22, "push": 0.40, "stun": 0.24, "arm": "r",
        "sh": Vector3(1.52, 0.02, 0.02), "el": 0.08,
        "twist": -0.55, "hip": Vector2(-0.12, 0.08),
    },
}

## Удары в корпус: то же движение, но цель ниже и урон/выносливость другие.
## "base" — какой удар анимируется, "stam_hit" — сколько выносливости снимает
## чистый корпусной удар (в дополнение к обычному урону).
const BODY_PUNCHES := {
    "body_jab": {"base": "jab", "dmg": 6.5, "reach": 1.42, "dur": 0.30, "hit_at": 0.14,
        "score": 8, "push": 0.22, "stun": 0.12, "stam": 8.0, "stam_hit": 12.0},
    "body_cross": {"base": "cross", "dmg": 10.0, "reach": 1.50, "dur": 0.38, "hit_at": 0.18,
        "score": 18, "push": 0.34, "stun": 0.18, "stam": 13.0, "stam_hit": 16.0},
    "body_lhook": {"base": "lhook", "dmg": 9.5, "reach": 1.28, "dur": 0.40, "hit_at": 0.20,
        "score": 18, "push": 0.38, "stun": 0.20, "stam": 13.0, "stam_hit": 15.0},
    "body_rhook": {"base": "rhook", "dmg": 11.0, "reach": 1.26, "dur": 0.44, "hit_at": 0.22,
        "score": 22, "push": 0.42, "stun": 0.22, "stam": 15.0, "stam_hit": 17.0},
    "body_upper": {"base": "upper", "dmg": 12.0, "reach": 1.24, "dur": 0.52, "hit_at": 0.25,
        "score": 26, "push": 0.48, "stun": 0.26, "stam": 20.0, "stam_hit": 20.0},
}

## Траектория перчатки для каждого удара. Координаты локальные, от точки
## попадания: x — вправо, y — вверх, z — назад (цель впереди бойца).
## wind — куда перчатка уходит на замахе, mid — контрольная точка дуги
## (прямые удары идут почти по нитке, крюки — по дуге сбоку, апперкот — снизу),
## pole — куда смотрит локоть, dip — насколько проседают колени на замахе,
## drive — насколько корпус идёт вперёд на выносе.
const PUNCH_PATH := {
    "jab": {"wind": Vector3(-0.11, 0.02, 0.30), "mid": Vector3(-0.04, 0.0, 0.03),
        "pole": Vector3(0.30, -0.90, 0.20), "dip": 0.05, "drive": 0.30},
    "cross": {"wind": Vector3(0.15, -0.01, 0.34), "mid": Vector3(0.06, 0.0, 0.04),
        "pole": Vector3(0.35, -0.90, 0.25), "dip": 0.08, "drive": 0.55},
    "lhook": {"wind": Vector3(-0.50, -0.20, 0.26), "mid": Vector3(-0.40, -0.03, 0.02),
        "pole": Vector3(-0.85, -0.45, 0.15), "dip": 0.22, "drive": 0.40},
    "rhook": {"wind": Vector3(0.50, -0.20, 0.26), "mid": Vector3(0.40, -0.03, 0.02),
        "pole": Vector3(0.85, -0.45, 0.15), "dip": 0.22, "drive": 0.40},
    "upper": {"wind": Vector3(0.16, -0.55, 0.22), "mid": Vector3(0.07, -0.22, -0.04),
        "pole": Vector3(0.20, -1.0, 0.50), "dip": 0.34, "drive": 0.55},
}

const SH_GUARD_L := Vector3(0.50, 0.0, 0.0)
const SH_GUARD_R := Vector3(0.56, 0.0, 0.0)
const EL_GUARD_L := 2.40
const EL_GUARD_R := 2.34
const SH_BLOCK_L := Vector3(0.64, -0.10, -0.10)
const SH_BLOCK_R := Vector3(0.68, 0.10, 0.10)
const EL_BLOCK_L := 2.58
const EL_BLOCK_R := 2.54
const SH_UPPER_BACK := Vector3(-0.45, 0.0, 0.0)
# вторая рука при ударе: поджимается к подбородку и чуть назад
const SH_OFF_R := Vector3(0.34, 0.10, 0.16)
const EL_OFF_R := 2.62
const SH_OFF_L := Vector3(0.30, -0.10, -0.16)
const EL_OFF_L := 2.66

var is_player := true
var hp := 100.0
var max_hp := 100.0
var stamina := 100.0
var max_stamina := 100.0

# прокачка: уровни 0..4, множители пересчитываются в set_upgrades()
var upg := {"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0}
var dmg_mult := 1.0
var dur_mult := 1.0
var stam_mult := 1.0
var taken_mult := 1.0
var hp_mult := 1.0
var blocking := false
var evading := false
var dodge_t := 0.0
var stun := 0.0
var flash := 0.0
var ko := false
var ko_fall := 0.0
var punch_kind := ""
var punch_t := 0.0
var punch_dur := 0.3
var punch_hit_at := 0.13
var hit_done := false
var punch_aim := Vector3.ZERO
## где перчатка была в момент старта удара, относительно точки попадания
## (локально): с этого места начинается замах, поэтому рука не прыгает.
var _punch_guard_off := Vector3.ZERO
var telegraph := false
var hits := 0
var taken := 0.0

var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var sh_l_base := Vector3.ZERO
var sh_r_base := Vector3.ZERO
var el_l: Node3D
var el_r: Node3D
var th_l: Node3D
var th_r: Node3D
var kn_l: Node3D
var kn_r: Node3D
var ft_l: Node3D
var ft_r: Node3D

var mats: Array[StandardMaterial3D] = []
var glove_mat: StandardMaterial3D
var look: Dictionary = {}

var ragdoll: Node3D
var ragdoll_parts: Dictionary = {}

var c_skin := Color(0.89, 0.72, 0.55)
var c_skin_dark := Color(0.71, 0.55, 0.41)
var c_body := Color(0.16, 0.42, 0.95)
var c_trunks := Color(0.10, 0.22, 0.66)
var c_glove := Color(0.2, 0.75, 1.0)
var c_band := Color(0.85, 0.93, 1.0)

var _clock := 0.0
var _last_pos := Vector3.ZERO
var _walk_phase := 0.0
var _walk_speed := 0.0
var _hit_t := 0.0
var _balance := Vector2.ZERO
var _balance_vel := Vector2.ZERO
var _hip_y := 1.01
var _crouch := 0.0
var _prev_step := 0.0
var _step_dip := 0.0


## Пружина вторичного движения: кость отстаёт от цели, перелетает и дрожит.
class Wob:
    var a := Vector3.ZERO
    var v := Vector3.ZERO

    func kick(d: Vector3) -> void:
        v += d

    func step(dt: float, k: float, damp: float) -> Vector3:
        v += (-a * k - v * damp) * dt
        a += v * dt
        a = a.limit_length(1.3)
        return a

    func clear() -> void:
        a = Vector3.ZERO
        v = Vector3.ZERO


var _dt := 0.016
var _crouch_vel := 0.0
var wob_sh_l := Wob.new()
var wob_sh_r := Wob.new()
var wob_el_l := Wob.new()
var wob_el_r := Wob.new()
var wob_torso := Wob.new()
var wob_head := Wob.new()
var wob_body := Wob.new()
var _t_l_sh := SH_GUARD_L
var _t_r_sh := SH_GUARD_R
var _t_l_el := EL_GUARD_L
var _t_r_el := EL_GUARD_R
# кватернионные цели ударной руки: без перевода в углы Эйлера поза не рвётся
var _pq_l := Quaternion.IDENTITY
var _pq_r := Quaternion.IDENTITY
var _pq_l_on := false
var _pq_r_on := false
var _prot_l := 0.0
var _prot_r := 0.0

# --- физика тела: скорость, наклон, падение
var vel := Vector3.ZERO
var tilt := Vector2.ZERO          # наклон корпуса (рад): x — вбок, y — вперёд
var tilt_vel := Vector2.ZERO
var fallen := false
var down_t := 0.0
const MAX_SPEED := 3.2
const ACCEL := 12.0
const FALL_TILT := 0.95

# --- активный ragdoll: точки-массы + мышцы-пружины + физические шаги
## Тело больше не «рисует» позу: таз, корпус, голова и стопы — это точки с
## массой и скоростью. Мышцы тянут их к желаемому положению, инерция тянет
## назад, ноги переставляются от растяжения. Кости — уже IK от этих точек.
const FOOT_Y := 0.09
const LEG_UP := 0.46
const LEG_LO := 0.42
const LEG_MAX := 0.845


class Pt:
    var p := Vector3.ZERO
    var v := Vector3.ZERO
    var tgt := Vector3.ZERO
    var k := 200.0
    var damp := 20.0

    func spring(dt: float) -> void:
        # Подшаги: явный Эйлер с жёсткой пружиной (k=520) на длинном кадре
        # (просадка FPS, тяжёлый кадр на телефоне) разлетается — тело улетает
        # за пределы ринга. Дробим шаг, чтобы интегрирование оставалось устойчивым.
        var n := maxi(1, int(ceil(dt * 120.0)))
        var h := dt / float(n)
        for i in n:
            v += ((tgt - p) * k - v * damp) * h
            p += v * h

    func reset(at: Vector3) -> void:
        p = at
        v = Vector3.ZERO
        tgt = at


var rj_pelvis := Pt.new()
var rj_chest := Pt.new()
var rj_head := Pt.new()
var rj_foot_l := Pt.new()
var rj_foot_r := Pt.new()
var _lean := Vector2.ZERO
var _lean_vel := Vector2.ZERO
var _feet_planted := [true, true]
var _feet_anchor := [Vector3.ZERO, Vector3.ZERO]
var _feet_swing_t := [0.0, 0.0]
var _feet_swing_dur := [0.2, 0.2]
var _feet_swing_from := [Vector3.ZERO, Vector3.ZERO]
var _feet_swing_to := [Vector3.ZERO, Vector3.ZERO]
var _hip_h_dyn := 0.95
var _step_gate := 0.0
var _chest_prev := Vector3.ZERO
var _idle_t := 0.0
var _ph := 0.0
var _rig_live := false
var steps := 0
var preview := false
## тренировочный манекен: не падает от ударов
var no_fall := false


## Сложность соперника: 0 — первый бой, 1 — последний пояс.
var diff := 0.0

## Сопротивление падению: у поздних поясов и тяжёлых стилей сбить с ног
## труднее — иначе вылет за канаты превращается в лёгкую победу без прокачки.
var fall_resist := 0.0


func set_difficulty(v: float) -> void:
    diff = clampf(v, 0.0, 1.0)
    dmg_mult = 0.88 + 0.92 * diff
    dur_mult = 1.0 - 0.16 * diff


## Прокачка: пересчитывает множители под уровень из профиля.
func set_upgrades(d: Dictionary) -> void:
    for k in upg.keys():
        upg[k] = clampi(int(d.get(k, 0)), 0, 4)
    dmg_mult = 1.0 + 0.10 * float(upg["power"])
    dur_mult = 1.0 - 0.07 * float(upg["speed"])
    stam_mult = 1.0 + 0.15 * float(upg["stamina"])
    taken_mult = 1.0 - 0.08 * float(upg["guard"])
    hp_mult = 1.0 + 0.10 * float(upg["health"])
    max_stamina = 100.0 * stam_mult
    stamina = minf(stamina, max_stamina)


func setup(as_player: bool, look_data: Dictionary = {}) -> void:
    is_player = as_player
    if look_data.is_empty():
        look = LookScript.default_look() if is_player else LOOK_ENEMY.duplicate()
    else:
        look = look_data.duplicate()
    _build()


# ------------------------------------------------------------------ материалы

func _mat(c: Color, rough: float = 0.8) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    mats.append(m)
    return m


func _node(parent: Node3D, pos: Vector3, node_name: String) -> Node3D:
    var n := Node3D.new()
    n.name = node_name
    n.position = pos
    parent.add_child(n)
    return n


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    parent.add_child(mi)
    return mi


func _caps(radius: float, height: float) -> CapsuleMesh:
    var m := CapsuleMesh.new()
    m.radius = radius
    m.height = height
    return m


func _ball(radius: float) -> SphereMesh:
    var m := SphereMesh.new()
    m.radius = radius
    m.height = radius * 2.0
    return m


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
    var m := CylinderMesh.new()
    m.top_radius = top
    m.bottom_radius = bottom
    m.height = height
    return m


func _cube(size: Vector3) -> BoxMesh:
    var m := BoxMesh.new()
    m.size = size
    return m


# ------------------------------------------------------------------ сборка тела

func _build() -> void:
    var v := LookScript.outfit(look)

    c_skin = v["skin"]
    c_skin_dark = v["skin_dark"]
    c_trunks = v["shorts_col"]
    c_body = v["shorts_col"]
    c_glove = v["glove_col"]
    c_band = v["shorts_trim"]

    var wide := float(v["chest"])
    var aw := float(v["arm"])
    var lw := float(v["leg"])
    var shx := float(v["shoulder"])
    var glove_r := float(v["glove_r"])

    body = _node(self, Vector3.ZERO, "Body")
    _last_pos = position

    var skin := _mat(c_skin, 0.8)
    var skin_d := _mat(c_skin_dark, 0.8)
    var trunks := _mat(c_trunks, 0.65)
    var band := _mat(c_band, 0.6)
    var boot := _mat(v["boot_col"], 0.55)
    var belt := _mat(c_trunks.darkened(0.45), 0.5)
    var lace := _mat(Color(0.95, 0.95, 0.98), 0.35)
    glove_mat = _mat(c_glove, 0.4)
    if v.has("glove_glow"):
        glove_mat.emission_enabled = true
        glove_mat.emission = v["glove_glow"]
        glove_mat.emission_energy_multiplier = 1.7

    hips = _node(body, Vector3(0, _hip_y, 0), "Hips")
    var hip_mesh := _mesh(hips, _caps(0.215, 0.28), trunks, Vector3(0, 0.01, 0))
    hip_mesh.scale = Vector3(wide, 1.0, wide * 0.95)
    _mesh(hips, _cyl(0.236 * wide, 0.236 * wide, 0.045), belt, Vector3(0, 0.17, 0))

    torso = _node(hips, Vector3(0, 0.14, 0), "Torso")
    var waist := _mesh(torso, _caps(0.19, 0.34), skin, Vector3(0, 0.18, 0))
    waist.scale = Vector3(wide * 0.98, 1.0, wide * 0.98)
    var chest := _mesh(torso, _caps(0.255, 0.5), skin, Vector3(0, 0.5, 0))
    chest.scale = Vector3(wide, 1.0, wide * 0.95)
    _mesh(torso, _ball(0.11 * wide), skin, Vector3(-0.11 * shx, 0.58, -0.13))
    _mesh(torso, _ball(0.11 * wide), skin, Vector3(0.11 * shx, 0.58, -0.13))
    _mesh(torso, _ball(0.115 * aw), skin, Vector3(-0.24 * shx, 0.68, 0))
    _mesh(torso, _ball(0.115 * aw), skin, Vector3(0.24 * shx, 0.68, 0))

    head = _node(torso, Vector3(0, 0.82, 0), "Head")
    _mesh(head, _cyl(0.085, 0.095, 0.12), skin_d, Vector3(0, -0.03, 0))
    _mesh(head, _ball(0.185), skin, Vector3(0, 0.13, 0))
    _mesh(head, _caps(0.095, 0.15), skin, Vector3(0, 0.03, 0))
    _mesh(head, _ball(0.042), skin, Vector3(0, 0.11, -0.18))
    _mesh(head, _ball(0.047), skin_d, Vector3(-0.178, 0.13, 0))
    _mesh(head, _ball(0.047), skin_d, Vector3(0.178, 0.13, 0))
    for side in [-1.0, 1.0]:
        # белок глаза слегка утоплен и сплюснут: не «шарик», а глаз
        var eye := _mesh(head, _ball(0.040), _mat(Color(0.97, 0.97, 0.99), 0.3),
                Vector3(0.07 * side, 0.155, -0.164))
        eye.scale = Vector3(1.0, 0.80, 0.42)
        var pupil := _mesh(head, _ball(0.018), _mat(Color(0.06, 0.06, 0.08), 0.3),
                Vector3(0.07 * side, 0.152, -0.183))
        pupil.scale = Vector3(1.0, 0.90, 0.50)
        # брови сведены к переносице — взгляд злой
        var brow := _mesh(head, _cube(Vector3(0.085, 0.015, 0.02)),
                _mat(Color(0.1, 0.08, 0.08), 0.6), Vector3(0.07 * side, 0.215, -0.164))
        brow.rotation_degrees = Vector3(0.0, 0.0, 12.0 * side)
    _mesh(head, _cube(Vector3(0.085, 0.012, 0.02)), _mat(Color(0.32, 0.13, 0.13), 0.6), Vector3(0, 0.04, -0.175))
    _mesh(head, _cyl(0.188, 0.188, 0.058), band, Vector3(0, 0.212, 0))
    _mesh(head, _cyl(0.05, 0.05, 0.028), band, Vector3(0, 0.208, 0.178))
    _hair(head, String(v["hair"]), v["hair_col"])

    sh_l = _arm_node(torso, Vector3(-0.32 * shx, 0.6, 0), skin, aw)
    sh_r = _arm_node(torso, Vector3(0.32 * shx, 0.6, 0), skin, aw)
    sh_l_base = sh_l.position
    sh_r_base = sh_r.position
    el_l = _node(sh_l, Vector3(0, -0.34, 0), "ElbowL")
    el_r = _node(sh_r, Vector3(0, -0.34, 0), "ElbowR")
    _forearm(el_l, skin, lace, aw, glove_r)
    _forearm(el_r, skin, lace, aw, glove_r)

    th_l = _node(hips, Vector3(-0.15 * wide, -0.05, 0), "ThighL")
    th_r = _node(hips, Vector3(0.15 * wide, -0.05, 0), "ThighR")
    var long_shorts := bool(v["shorts_long"])
    for th in [th_l, th_r]:
        if long_shorts:
            _mesh(th, _caps(0.137 * lw, 0.5), trunks, Vector3(0, -0.2, 0))
        else:
            _mesh(th, _caps(0.138 * lw, 0.28), trunks, Vector3(0, -0.08, 0))
        _mesh(th, _caps(0.125 * lw, 0.46), skin, Vector3(0, -0.23, 0))
    kn_l = _node(th_l, Vector3(0, -0.46, 0), "KneeL")
    kn_r = _node(th_r, Vector3(0, -0.46, 0), "KneeR")
    for kn in [kn_l, kn_r]:
        _mesh(kn, _caps(0.1 * lw, 0.42), skin, Vector3(0, -0.21, 0))
    ft_l = _node(kn_l, Vector3(0, -0.42, 0), "FootL")
    ft_r = _node(kn_r, Vector3(0, -0.42, 0), "FootR")
    var boot_style := String(v["boot_style"])
    for ft in [ft_l, ft_r]:
        if boot_style == "bare":
            _mesh(ft, _cube(Vector3(0.175, 0.075, 0.33)), skin, Vector3(0, -0.05, -0.05))
            _mesh(ft, _ball(0.08), skin, Vector3(0, -0.02, -0.205))
            _mesh(ft, _cyl(0.102, 0.102, 0.07), band, Vector3(0, 0.02, 0.0))
        elif boot_style == "low":
            _mesh(ft, _cube(Vector3(0.19, 0.09, 0.33)), boot, Vector3(0, -0.035, -0.055))
            _mesh(ft, _ball(0.085), boot, Vector3(0, -0.01, -0.205))
            _mesh(ft, _cube(Vector3(0.17, 0.012, 0.07)), lace, Vector3(0, 0.012, -0.15))
        else:
            _mesh(ft, _cube(Vector3(0.19, 0.11, 0.34)), boot, Vector3(0, -0.03, -0.06))
            _mesh(ft, _ball(0.085), boot, Vector3(0, -0.005, -0.21))
            _mesh(ft, _cyl(0.1, 0.1, 0.09), boot, Vector3(0, 0.04, 0.01))
            _mesh(ft, _cube(Vector3(0.17, 0.012, 0.07)), lace, Vector3(0, 0.03, -0.16))

    _apply_pose(SH_GUARD_L, EL_GUARD_L, SH_GUARD_R, EL_GUARD_R, 10.0)


func _hair(h: Node3D, style: String, col: Color) -> void:
    if style == "bald":
        return
    var hm := _mat(col, 0.72)
    if style == "mohawk":
        var fin := _mesh(h, _cube(Vector3(0.06, 0.24, 0.36)), hm, Vector3(0, 0.4, 0.0))
        fin.rotation_degrees = Vector3(-5, 0, 0)
        return
    var cap := _mesh(h, _ball(0.185), hm, Vector3(0, 0.245, 0.005))
    cap.scale = Vector3(1.04, 0.75, 1.04)
    if style == "tail":
        _mesh(h, _cyl(0.055, 0.055, 0.04), _mat(Color(0.86, 0.16, 0.22), 0.6),
                Vector3(0, 0.17, 0.185))
        var tail := _mesh(h, _caps(0.06, 0.26), hm, Vector3(0, 0.03, 0.22))
        tail.rotation_degrees = Vector3(14, 0, 0)
    elif style == "afro":
        var puff := _mesh(h, _ball(0.225), hm, Vector3(0, 0.35, 0.02))
        puff.scale = Vector3(1.06, 0.95, 1.06)


func _arm_node(parent: Node3D, pos: Vector3, skin: Material, aw: float = 1.0) -> Node3D:
    var sh := _node(parent, pos, "Shoulder")
    _mesh(sh, _ball(0.125 * aw), skin, Vector3(0, -0.02, 0))
    _mesh(sh, _caps(0.1 * aw, 0.34), skin, Vector3(0, -0.18, 0))
    return sh


func _forearm(elbow: Node3D, skin: Material, lace: Material, aw: float = 1.0,
        gr: float = 0.15) -> void:
    _mesh(elbow, _caps(0.085 * aw, 0.3), skin, Vector3(0, -0.16, 0))
    _mesh(elbow, _cyl(0.1 * aw, 0.095 * aw, 0.06), lace, Vector3(0, -0.32, 0))
    _mesh(elbow, _ball(gr), glove_mat, Vector3(0, -0.42, 0))
    _mesh(elbow, _ball(gr * 0.5), glove_mat,
            Vector3(0, -0.47, -0.09 * (gr / 0.15)))


## Гасим пружины и ставим кости в стойку без рывков при переодевании.
func _settle_pose() -> void:
    wob_sh_l.clear()
    wob_sh_r.clear()
    wob_el_l.clear()
    wob_el_r.clear()
    wob_torso.clear()
    wob_head.clear()
    wob_body.clear()
    _t_l_sh = SH_GUARD_L
    _t_r_sh = SH_GUARD_R
    _t_l_el = EL_GUARD_L
    _t_r_el = EL_GUARD_R
    _pq_l = Quaternion.IDENTITY
    _pq_r = Quaternion.IDENTITY
    _pq_l_on = false
    _pq_r_on = false
    _prot_l = 0.0
    _prot_r = 0.0
    _apply_pose(SH_GUARD_L, EL_GUARD_L, SH_GUARD_R, EL_GUARD_R, 1.0)


## Переодевание: пересобираем тело с новой внешностью (в бою не вызывать).
func set_look(d: Dictionary) -> void:
    look = d.duplicate()
    if body == null or not is_inside_tree():
        return
    clear_ragdoll()
    body.free()
    mats.clear()
    _build()
    _settle_pose()
    _rig_reset()


# ------------------------------------------------------------------ API

## Кэш определений ударов: базовые + корпусные варианты (base + переопределения).
var _punch_cache: Dictionary = {}


func punch_info(kind: String) -> Dictionary:
    if _punch_cache.is_empty():
        for k in PUNCHES:
            _punch_cache[k] = PUNCHES[k]
        for k in BODY_PUNCHES:
            var b: Dictionary = BODY_PUNCHES[k]
            var d: Dictionary = PUNCHES[String(b["base"])].duplicate(true)
            d["body"] = true
            d["anim"] = String(b["base"])
            for f in b:
                d[f] = b[f]
            _punch_cache[k] = d
    return _punch_cache.get(kind, PUNCHES["jab"])


func start_punch(kind: String, aim: Vector3 = Vector3.ZERO) -> bool:
    if ko or fallen or stun > 0.0 or punch_kind != "" or blocking or evading:
        return false
    var p: Dictionary = punch_info(kind)
    if stamina < float(p["stam"]):
        return false
    stamina -= float(p["stam"])
    punch_kind = kind
    punch_t = 0.0
    punch_dur = float(p["dur"]) * dur_mult
    punch_hit_at = float(p["hit_at"]) * dur_mult
    hit_done = false
    punch_aim = aim
    _punch_guard_off = Vector3.ZERO
    if aim != Vector3.ZERO:
        # стартовая точка замаха — текущее положение перчатки в системе цели
        _punch_guard_off = global_transform.basis.inverse() \
                * (glove_point(str(p["arm"])) - aim)
    _idle_t = 0.0
    # шаг вперёд под удар: иначе перчатка не достаёт до цели
    var fwd: Vector3 = -global_transform.basis.z
    vel += fwd * 0.9
    vel = vel.limit_length(MAX_SPEED)
    return true


func try_dodge() -> bool:
    if ko or stun > 0.0 or dodge_t > 0.0 or punch_kind != "":
        return false
    if stamina < 12.0:
        return false
    stamina -= 12.0
    dodge_t = 0.45
    wob_body.kick(Vector3(randf_range(-0.6, 0.6), 0.35, -0.5))
    wob_torso.kick(Vector3(0.9, randf_range(-0.6, 0.6), randf_range(-0.8, 0.8)))
    return true


func take_hit(dmg: float, push: Vector3) -> void:
    dmg *= taken_mult
    hp = maxf(0.0, hp - dmg)
    taken += dmg
    flash = 0.2
    stun = maxf(stun, 0.24)
    blocking = false
    dodge_t = 0.0
    _hit_t = 0.35
    _idle_t = 0.0
    var pdir := Vector3(push.x, 0.0, push.z)
    if pdir.length() < 0.01:
        pdir = -global_transform.basis.z
    pdir = pdir.normalized()
    knock(pdir * maxf(push.length(), 0.25), clampf(dmg * 0.18, 0.6, 2.8))
    # вторичное движение: голову и корпус отбрасывает, потом догоняет
    var power := clampf(dmg / 12.0, 0.4, 1.8)
    wob_head.kick(Vector3(-4.6, randf_range(-2.4, 2.4), randf_range(-3.0, 3.0)) * power)
    wob_torso.kick(Vector3(-2.7, randf_range(-1.4, 1.4), randf_range(-2.0, 2.0)) * power)
    wob_body.kick(Vector3(pdir.x, randf_range(0.4, 1.1), pdir.z) * power * 2.4)
    if power > 0.85:
        _stumble()


## Удар по телу: корпус и голова получают скорость, стопы остаются на месте —
## тело проносит над ногами, и оно само делает ловящий шаг.
func knock(dir: Vector3, power: float) -> void:
    if not _rig_live:
        return
    var d := Vector3(dir.x, 0.0, dir.z)
    if d.length() < 0.001:
        d = -global_transform.basis.z
    d = d.normalized()
    var ld: Vector3 = global_transform.basis.inverse() * d
    _lean_vel += Vector2(ld.x, -ld.z) * power * 2.0
    _lean_vel += Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)) * power * 0.8
    vel += d * power * 0.55
    rj_chest.v += d * power * 1.9 + Vector3(0.0, 0.35, 0.0) * power
    rj_head.v += d * power * 2.4 + Vector3(0.0, 0.55, 0.0) * power
    wob_body.kick(Vector3(d.x, 0.7, d.z) * power * 0.9)


func push_impulse(dir: Vector3, power: float) -> void:
    if not _rig_live:
        return
    var d := Vector3(dir.x, 0.0, dir.z)
    if d.length() < 0.001:
        return
    d = d.normalized()
    var ld: Vector3 = global_transform.basis.inverse() * d
    _lean_vel += Vector2(ld.x, -ld.z) * power * 0.55
    rj_chest.v += d * power * 0.4
    if power > 2.0:
        _stumble()


## Резкий разворот на скорости заносит корпус — его приходится ловить ногами.
func turn_lean(v: Vector2) -> void:
    _lean_vel += v


## Принудительное падение (нокдаун от удара): тело улетает физически.
func force_fall(dir: Vector3, power: float) -> void:
    if ko or fallen:
        return
    var d := Vector3(dir.x, 0.0, dir.z)
    if d.length() < 0.01:
        d = -global_transform.basis.z
    d = d.normalized()
    vel += d * power * 0.6
    rj_chest.v += d * power * 2.2 + Vector3(0.0, 1.2, 0.0)
    rj_head.v += d * power * 2.6
    var ld: Vector3 = global_transform.basis.inverse() * d
    _lean_vel += Vector2(ld.x, -ld.z) * power * 3.0
    stun = maxf(stun, 1.0)
    _fall_down(d * power + Vector3(0.0, 1.2 + power * 0.5, 0.0))


func look_at_target(p: Vector3) -> void:
    var flat := Vector3(p.x, position.y, p.z)
    if flat.distance_to(position) > 0.08:
        look_at(flat, Vector3.UP)


func reset(spawn: Vector3, hp_value: float) -> void:
    clear_ragdoll()
    position = spawn
    _last_pos = spawn
    max_hp = hp_value * hp_mult
    hp = max_hp
    stamina = max_stamina
    blocking = false
    evading = false
    dodge_t = 0.0
    stun = 0.0
    flash = 0.0
    ko = false
    ko_fall = 0.0
    punch_kind = ""
    punch_t = 0.0
    punch_aim = Vector3.ZERO
    _punch_guard_off = Vector3.ZERO
    hit_done = false
    telegraph = false
    hits = 0
    taken = 0.0
    _hit_t = 0.0
    _walk_speed = 0.0
    _crouch = 0.0
    _crouch_vel = 0.0
    vel = Vector3.ZERO
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    fallen = false
    down_t = 0.0
    wob_sh_l.clear()
    wob_sh_r.clear()
    wob_el_l.clear()
    wob_el_r.clear()
    wob_torso.clear()
    wob_head.clear()
    wob_body.clear()
    _t_l_sh = SH_GUARD_L
    _t_r_sh = SH_GUARD_R
    _t_l_el = EL_GUARD_L
    _t_r_el = EL_GUARD_R
    _pq_l = Quaternion.IDENTITY
    _pq_r = Quaternion.IDENTITY
    _pq_l_on = false
    _pq_r_on = false
    _prot_l = 0.0
    _prot_r = 0.0
    _balance = Vector2.ZERO
    _balance_vel = Vector2.ZERO
    _rig_live = false
    _apply_pose(SH_GUARD_L, EL_GUARD_L, SH_GUARD_R, EL_GUARD_R, 10.0)
    if body:
        body.rotation = Vector3.ZERO
        body.position = Vector3.ZERO
        body.scale = Vector3.ONE
        body.visible = true
    if hips:
        hips.position = Vector3(0.0, _hip_h_dyn, 0.0)
    _rig_reset()


func freeze_pose(kind: String, phase: float, settle: bool = true) -> void:
    punch_kind = kind
    if kind != "":
        var fp: Dictionary = punch_info(kind)
        punch_dur = float(fp["dur"])
        punch_hit_at = float(fp["hit_at"])
        punch_t = punch_dur * phase
        if punch_aim != Vector3.ZERO:
            _punch_guard_off = global_transform.basis.inverse() \
                    * (glove_point(str(fp["arm"])) - punch_aim)
    else:
        punch_t = 0.0
        _punch_guard_off = Vector3.ZERO
    _walk_speed = 0.0
    if not ko and not fallen and settle:
        for i in 12:
            _rig_tick(1.0 / 60.0)
    _animate(100.0)


# ------------------------------------------------------------------ шаг

func tick(dt: float) -> void:
    _clock += dt
    stun = maxf(0.0, stun - dt)
    flash = maxf(0.0, flash - dt)
    _hit_t = maxf(0.0, _hit_t - dt)
    if dodge_t > 0.0:
        dodge_t = maxf(0.0, dodge_t - dt)
    evading = dodge_t > 0.0
    var regen := -4.0 if blocking else 22.0
    if evading:
        regen = 6.0
    stamina = clampf(stamina + regen * stam_mult * dt, 0.0, max_stamina)

    if fallen:
        down_t -= dt
        # тело «приезжает» туда, где осел ragdoll, чтобы не телепортироваться
        if ragdoll_parts.has("pelvis"):
            var prb: RigidBody3D = ragdoll_parts["pelvis"]
            position.x = prb.global_position.x
            position.z = prb.global_position.z
        if down_t <= 0.0 and not ko:
            _get_up()

    if not ko and not fallen:
        _body_physics(dt)

    if dt > 0.0001 and dt < 0.5:
        var v := (position - _last_pos) / dt
        v.y = 0.0
        _walk_speed = lerpf(_walk_speed, clampf(v.length(), 0.0, 6.0), clampf(dt * 8.0, 0.0, 1.0))
    _last_pos = position

    if punch_kind != "":
        punch_t += dt
        var p: Dictionary = punch_info(punch_kind)
        if not hit_done and punch_t >= punch_hit_at:
            hit_done = true
            impact.emit(punch_kind)
            # отдача удара: рука отпружинивает назад
            var arm: Wob = wob_sh_l if str(p["arm"]) == "l" else wob_sh_r
            arm.kick(Vector3(-7.5, 0.0, 0.0))
            wob_torso.kick(Vector3(-1.9, 0.0, 0.0))
        if punch_t >= punch_dur:
            punch_kind = ""
            punch_aim = Vector3.ZERO

    if ko:
        ko_fall = minf(1.0, ko_fall + dt * 2.0)

    _animate(dt)


# ------------------------------------------------------------------ корневая физика

func drive(dir: Vector3, dt: float) -> void:
    if ko or fallen or stun > 0.0:
        return
    if dir.length() < 0.01:
        return
    dir = Vector3(dir.x, 0.0, dir.z).normalized()
    var accel := ACCEL
    if blocking:
        accel *= 0.5
    vel += dir * accel * dt
    if vel.length() > MAX_SPEED:
        vel = vel.normalized() * MAX_SPEED


func _body_physics(dt: float) -> void:
    var friction := 4.0 if vel.length() > 0.3 else 7.5
    vel *= exp(-friction * dt)
    if vel.length() < 0.02:
        vel = Vector3.ZERO
    position += vel * dt
    _rig_tick(dt)


# ------------------------------------------------------------ физический риг

func _hip_world(i: int) -> Vector3:
    var side := -1.0 if i == 0 else 1.0
    return rj_pelvis.p + global_transform.basis.x * (0.15 * side) - Vector3(0.0, 0.05, 0.0)


func _foot_pt(i: int) -> Pt:
    return rj_foot_l if i == 0 else rj_foot_r


func _rig_reset() -> void:
    _ph = randf() * TAU
    _lean = Vector2.ZERO
    _lean_vel = Vector2.ZERO
    _hip_h_dyn = 0.95
    _idle_t = 0.0
    _step_dip = 0.0
    _walk_speed = 0.0
    rj_pelvis.reset(to_global(Vector3(0.0, _hip_h_dyn, 0.0)))
    rj_chest.reset(to_global(Vector3(0.0, _hip_h_dyn + 0.62, 0.0)))
    rj_head.reset(to_global(Vector3(0.0, _hip_h_dyn + 1.09, 0.0)))
    for i in 2:
        var side := -1.0 if i == 0 else 1.0
        _feet_planted[i] = true
        _feet_anchor[i] = to_global(Vector3(0.17 * side, FOOT_Y, 0.0))
        _feet_swing_t[i] = 0.0
        var fp := _foot_pt(i)
        fp.reset(_feet_anchor[i])
    _chest_prev = rj_chest.p
    _rig_live = true


## Шаг: стопа стоит на месте, пока нога не растянется до предела, —
## тогда она срывается и переставляется туда, куда тело уже уехало.
func _foot_release(i: int, extra: float) -> void:
    if not _rig_live:
        return
    var fp := _foot_pt(i)
    _step_gate = 0.075
    _feet_planted[i] = false
    _feet_swing_t[i] = 0.0
    _feet_swing_dur[i] = clampf(0.22 - vel.length() * 0.022, 0.12, 0.26)
    _feet_swing_from[i] = fp.p
    var pre: Vector3 = position + vel * (float(_feet_swing_dur[i]) * 0.9)
    var side := -1.0 if i == 0 else 1.0
    var tgt: Vector3 = pre + global_transform.basis.x * (0.17 * side)
    tgt += global_transform.basis.x * randf_range(-0.06, 0.06)
    tgt += (-global_transform.basis.z) * randf_range(-0.04, 0.08 + extra * 0.12)
    tgt.y = FOOT_Y
    _feet_swing_to[i] = tgt


func _feet_tick(i: int, dt: float) -> void:
    if not _rig_live:
        return
    var fp := _foot_pt(i)
    if _feet_planted[i]:
        fp.p = _feet_anchor[i]
        fp.v = Vector3.ZERO
        if _hip_world(i).distance_to(fp.p) > LEG_MAX and _step_gate <= 0.0:
            _foot_release(i, 0.0)
        return
    _feet_swing_t[i] += dt
    var dur: float = maxf(float(_feet_swing_dur[i]), 0.05)
    var u := clampf(float(_feet_swing_t[i]) / dur, 0.0, 1.0)
    var e := u * u * (3.0 - 2.0 * u)
    var from: Vector3 = _feet_swing_from[i]
    var to: Vector3 = _feet_swing_to[i]
    fp.p = from.lerp(to, e)
    fp.p.y = FOOT_Y + sin(u * PI) * clampf(0.05 + dur * 0.35, 0.06, 0.17)
    fp.v = (to - from) / dur
    if u >= 1.0:
        _feet_planted[i] = true
        _feet_anchor[i] = Vector3(to.x, FOOT_Y, to.z)
        fp.p = _feet_anchor[i]
        steps += 1
        footstep.emit(clampf(vel.length() + 0.4, 0.3, 3.2))
        _step_dip = 0.045
        wob_body.kick(Vector3(randf_range(-0.5, 0.5), 1.1, randf_range(-0.3, 0.3)))
        wob_torso.kick(Vector3(0.7, randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)))


func _stumble() -> void:
    if not _rig_live:
        return
    var i := 0 if randf() < 0.5 else 1
    if _feet_planted[i]:
        _foot_release(i, 0.7)


func _rig_targets(dt: float) -> void:
    var spd := Vector2(vel.x, vel.z).length()
    var t := _clock + _ph
    var idle_amp := 1.0 + clampf(_idle_t - 0.7, 0.0, 3.0) * 0.5

    # баланс: пружина, при оглушении почти отпускает — бойца ведёт и качает
    var lean_k := 52.0
    var lean_d := 9.0
    if stun > 0.0:
        lean_k = 7.0
        lean_d = 2.2
    elif blocking:
        lean_k = 80.0
        lean_d = 13.0
    _lean_vel += (-_lean * lean_k - _lean_vel * lean_d) * dt
    _lean_vel += Vector2(sin(t * 0.83 + 1.1), cos(t * 1.17 + 0.4)) * (2.3 * idle_amp * dt)
    _lean = (_lean + _lean_vel * dt).limit_length(1.35)

    # механика удара: проседание на замахе и довод корпуса на выносе.
    # Апперкот и крюки «садятся» на колени, а затем корпус идёт вперёд.
    var dip := 0.0
    var drive := 0.0
    if punch_kind != "":
        var pp: Dictionary = punch_info(punch_kind)
        var pth: Dictionary = PUNCH_PATH.get(str(pp.get("anim", punch_kind)), PUNCH_PATH["jab"])
        var ph := _punch_phases()
        dip = float(pth.get("dip", 0.0)) * float(ph["wind"]) * (1.0 - float(ph["hit"]))
        drive = float(pth.get("drive", 0.0)) * float(ph["ext"])

    var hip_h := 0.95 - 0.30 * _crouch - 0.16 * dip \
            - 0.02 * clampf(spd, 0.0, 2.0) + sin(t * 2.1) * 0.008
    _hip_h_dyn = hip_h
    var nz := Vector3(
        sin(t * 1.13) * 0.028 + sin(t * 2.71 + 1.3) * 0.011,
        0.0,
        sin(t * 0.93 + 0.7) * 0.024 + sin(t * 2.19 + 2.6) * 0.009) * idle_amp
    var bb := wob_body.step(_dt, 82.0, 6.5) * 0.32
    var pl := Vector3(_lean.x * hip_h * 0.34 + nz.x + bb.x,
            hip_h + bb.y,
            -_lean.y * hip_h * 0.34 + nz.z + bb.z)
    var cl := pl + Vector3(_lean.x * 0.24 + nz.x * 1.3, 0.50 - dip * 0.05,
            -_lean.y * 0.24 - 0.055 - spd * 0.018 + nz.z * 1.3 - drive * 0.10)
    # голова: цель — там, где она была бы жёстко, пружина даёт отставание
    var hu: Vector3 = torso.global_transform.basis.y.normalized()
    var hl: Vector3 = to_local(head.global_position + hu * 0.19)
    hl += Vector3(nz.x * 1.1 + sin(t * 1.9) * 0.012 * idle_amp, 0.0, nz.z * 1.1)
    rj_pelvis.tgt = to_global(pl)
    rj_chest.tgt = to_global(cl)
    rj_head.tgt = to_global(hl)


func _rig_tick(dt: float) -> void:
    if not _rig_live:
        _rig_reset()
    _dt = clampf(dt, 0.001, 0.05)
    _idle_t += dt
    _step_gate = maxf(0.0, _step_gate - _dt)
    if vel.length() > 0.5:
        _idle_t = 0.0
    _rig_targets(_dt)
    rj_pelvis.k = 520.0
    rj_pelvis.damp = 52.0
    rj_chest.k = 120.0
    rj_chest.damp = 13.0
    rj_head.k = 70.0
    rj_head.damp = 7.0
    rj_pelvis.spring(_dt)
    rj_chest.spring(_dt)
    rj_head.spring(_dt)
    _feet_tick(0, _dt)
    _feet_tick(1, _dt)

    var dl: Vector3 = to_local(rj_chest.p) - to_local(rj_pelvis.p)
    tilt = Vector2(atan2(dl.x, maxf(dl.y, 0.05)), atan2(-dl.z, maxf(dl.y, 0.05)))
    tilt_vel = Vector2.ZERO
    if stun > 0.0 and tilt.length() > FALL_TILT + 3.0 * fall_resist and not no_fall:
        _fall_down()


func _fall_down(boost: Vector3 = Vector3.ZERO) -> void:
    if fallen or ko:
        return
    fallen = true
    down_t = 1.9
    stun = maxf(stun, 1.9)
    punch_kind = ""
    blocking = false
    var imp := Vector3(
        clampf(vel.x * 1.1 + rj_chest.v.x * 0.8, -2.6, 2.6),
        1.45,
        clampf(vel.z * 1.1 + rj_chest.v.z * 0.8, -2.6, 2.6))
    enter_ragdoll((imp + boost).limit_length(5.2))
    knocked_down.emit()


func _get_up() -> void:
    fallen = false
    clear_ragdoll()
    _rig_reset()
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    vel = Vector3.ZERO
    stun = 0.45
    stamina = maxf(stamina, 45.0)
    wob_body.kick(Vector3(0.0, 1.5, 0.0))
    wob_torso.kick(Vector3(0.8, 0.0, 0.0))


# ------------------------------------------------------------------ анимация

func _lerp_angle(cur: float, target: float, k: float) -> float:
    return lerpf(cur, target, clampf(k, 0.0, 1.0))


## Фазы удара в долях длительности: замах (wind) → вынос до цели (hit) →
## удержание → возврат (back). "tw" — куда повёрнут корпус (−0.3 — замах в
## обратную сторону, 1.0 — полный доворот в удар), "sh" — смещение таза.
func _punch_phases() -> Dictionary:
    var dur: float = maxf(punch_dur, 0.001)
    var h := clampf(punch_hit_at / dur, 0.12, 0.90)
    var t01 := clampf(punch_t / dur, 0.0, 1.0)
    var w_end := h * 0.46
    var hold_end := minf(h + 0.10, 0.94)
    var d := {"wind": 0.0, "hit": 0.0, "back": 0.0, "ext": 0.0, "tw": 0.0, "sh": 0.0}
    if t01 < w_end:
        # замах: перчатка уходит наружу/вниз, корпус подкручивается обратно
        var u := ease(t01 / maxf(w_end, 0.001), 1.4)
        d["wind"] = u
        d["tw"] = -0.30 * u
        d["sh"] = -0.24 * u
    elif t01 < h:
        var u := ease((t01 - w_end) / maxf(h - w_end, 0.001), 0.55)
        d["wind"] = 1.0
        d["hit"] = u
        d["ext"] = u
        d["tw"] = lerpf(-0.30, 1.0, u)
        d["sh"] = lerpf(-0.24, 1.0, u)
    elif t01 < hold_end:
        d["wind"] = 1.0
        d["hit"] = 1.0
        d["ext"] = 1.0
        d["tw"] = 1.0
        d["sh"] = 1.0
    else:
        var u := clampf((t01 - hold_end) / maxf(1.0 - hold_end, 0.001), 0.0, 1.0)
        var r := 1.0 - ease(u, 0.75)
        # wind=0: на возврате рука уходит из IK-позы обратно в стойку плавно,
        # иначе в последнем кадре перчатка прыгает в стойку одним скачком
        d["wind"] = 0.0
        d["hit"] = r
        d["ext"] = r
        d["back"] = 1.0 - r
        d["tw"] = r
        d["sh"] = r
    return d


## Центр перчатки в мире — по нему считаем попадание и эффект.
func glove_point(arm: String) -> Vector3:
    var el: Node3D = el_l if arm == "l" else el_r
    return el.to_global(Vector3(0.0, -0.42, 0.0))


## Двухзвенная IK руки в точку aim: поворот плеча (локально к торсу)
## и угол локтя. pole_world — куда вынести локоть (для крюков — в сторону,
## для апперкота — вниз): от этого зависит, идёт перчатка по дуге или по нитке.
func _aim_arm(sh_node: Node3D, aim: Vector3, pole_world: Vector3 = Vector3.ZERO) -> Dictionary:
    const A := 0.34
    const B := 0.42
    var sp: Vector3 = sh_node.global_position
    var to: Vector3 = aim - sp
    var dist := clampf(to.length(), 0.20, A + B - 0.01)
    var dir := to.normalized()
    var cos_a := clampf((A * A + dist * dist - B * B) / (2.0 * A * dist), -1.0, 1.0)
    var alpha := acos(cos_a)
    var side: Vector3 = dir.cross(Vector3.UP)
    if side.length() < 0.01:
        side = dir.cross(Vector3.RIGHT)
    side = side.normalized()
    var perp: Vector3 = side.cross(dir).normalized()
    if perp.y > 0.0:
        perp = -perp
    if pole_world.length() > 0.01:
        var pw: Vector3 = pole_world - dir * pole_world.dot(dir)
        if pw.length() > 0.05:
            perp = perp.lerp(pw.normalized(), 0.85).normalized()
    var upper: Vector3 = (dir * cos(alpha) + perp * sin(alpha)).normalized()
    var elbow_pos: Vector3 = sp + upper * A
    var v: Vector3 = aim - elbow_pos
    if v.length() < 0.01:
        v = dir
    v = v.normalized()
    var y_axis: Vector3 = -upper
    # локальная X плеча — нормаль плоскости «плечо-локоть-цель»: тогда локоть
    # гнётся ровно в плоскости удара и перчатка приходит точно в точку прицела
    var x_axis: Vector3 = upper.cross(v)
    if x_axis.length() < 0.001:
        x_axis = side
    x_axis = x_axis.normalized()
    var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
    var world := Basis(x_axis, y_axis, z_axis)
    var v_local: Vector3 = world.transposed() * v
    var bend := atan2(-v_local.z, -v_local.y)
    var torso_b: Basis = torso.global_transform.basis.orthonormalized()
    var local_b: Basis = (torso_b.inverse() * world).orthonormalized()
    return {"qa": local_b.get_rotation_quaternion(), "el": bend}


func _apply_pose(l_sh: Vector3, l_el: float, r_sh: Vector3, r_el: float, k: float,
        q_l: Variant = null, q_r: Variant = null, arm_k: float = -1.0) -> void:
    var s := clampf(k, 0.0, 1.0)
    # рука на ударе догоняет IK-позу быстрее: иначе на контактном кадре перчатка
    # отстаёт от цели на 20-30 см и удар визуально «не достаёт»
    var sk := s if arm_k < 0.0 else clampf(arm_k, 0.0, 1.0)
    # удар закончился: сначала подхватываем текущий кватернион, потом сглаживаем
    # в стойку — иначе в последнем кадре рука рывком прыгает назад
    if q_l == null and _pq_l_on:
        _t_l_sh = (_pq_l * Quaternion.from_euler(wob_sh_l.a)).get_euler()
        wob_sh_l.clear()
        _pq_l_on = false
    if q_r == null and _pq_r_on:
        _t_r_sh = (_pq_r * Quaternion.from_euler(wob_sh_r.a)).get_euler()
        wob_sh_r.clear()
        _pq_r_on = false
    # сглаживаем цель, сверху накладываем пружину — кость отстаёт и перелетает
    var tl := _t_l_sh.lerp(l_sh, s)
    var tr := _t_r_sh.lerp(r_sh, s)
    var el := lerpf(_t_l_el, l_el, s)
    var er := lerpf(_t_r_el, r_el, s)
    if q_l != null:
        el = lerpf(_t_l_el, l_el, sk)
    if q_r != null:
        er = lerpf(_t_r_el, r_el, sk)

    wob_el_l.kick(Vector3(-(el - _t_l_el) * 1.2, 0.0, 0.0))
    wob_el_r.kick(Vector3(-(er - _t_r_el) * 1.2, 0.0, 0.0))
    var dl := tl - _t_l_sh
    var dr := tr - _t_r_sh

    _t_l_sh = tl
    _t_r_sh = tr
    _t_l_el = el
    _t_r_el = er

    if q_l != null:
        # удар с прицелом: ведём плечо кватернионом, без углов Эйлера
        _pq_l = _step_sh_q(sh_l, wob_sh_l, _pq_l, q_l, sk, _pq_l_on)
        _pq_l_on = true
    else:
        _pq_l_on = false
        wob_sh_l.kick(-dl * 1.45)
        sh_l.rotation = tl + wob_sh_l.step(_dt, 110.0, 8.0)
    if q_r != null:
        _pq_r = _step_sh_q(sh_r, wob_sh_r, _pq_r, q_r, sk, _pq_r_on)
        _pq_r_on = true
    else:
        _pq_r_on = false
        wob_sh_r.kick(-dr * 1.45)
        sh_r.rotation = tr + wob_sh_r.step(_dt, 110.0, 8.0)

    el_l.rotation.x = el + wob_el_l.step(_dt, 95.0, 7.5).x
    el_r.rotation.x = er + wob_el_r.step(_dt, 95.0, 7.5).x


## Шаг плеча по кватерниону: короткий slerp + ограниченная пружина.
## Раньше цель шла через углы Эйлера и на боковых ударах кость перескакивала
## на 80-90° за кадр — отсюда «сломанная» анимация.
func _step_sh_q(node: Node3D, w: Wob, prev: Quaternion, want: Quaternion,
        s: float, live: bool) -> Quaternion:
    var from: Quaternion = prev if live else node.quaternion
    var nq: Quaternion = from.slerp(want, clampf(s, 0.0, 1.0)).normalized()
    var d: Quaternion = (nq * from.inverse()).normalized()
    var ang := d.get_angle()
    if ang > 0.0001:
        w.kick(-d.get_axis() * ang * 1.2)
    var wo := w.step(_dt, 110.0, 8.0).limit_length(0.20)
    node.quaternion = (nq * Quaternion.from_euler(wo)).normalized()
    return nq


func _animate(dt: float) -> void:
    _dt = clampf(dt, 0.001, 0.05)
    var k := clampf(dt * 16.0, 0.0, 1.0)
    var arm_z_l := -0.04
    var arm_z_r := 0.04

    var l_sh := SH_GUARD_L
    var l_el := EL_GUARD_L
    var r_sh := SH_GUARD_R
    var r_el := EL_GUARD_R

    if blocking and stun <= 0.001:
        l_sh = SH_BLOCK_L
        l_el = EL_BLOCK_L
        r_sh = SH_BLOCK_R
        r_el = EL_BLOCK_R

    var ptwist := 0.0
    var pshift := Vector2.ZERO
    var arm_ext := 0.0
    var arm_side := ""
    var q_l: Variant = null
    var q_r: Variant = null
    # удар по цели: IK руки считается уже после доворота корпуса (см. ниже)
    var has_aim := false
    var pun_arm := ""
    var pun_path: Dictionary = {}
    var pun_d: Dictionary = {}

    if punch_kind != "":
        var p: Dictionary = punch_info(punch_kind)
        var anim := str(p.get("anim", punch_kind))
        var path: Dictionary = PUNCH_PATH.get(anim, PUNCH_PATH["jab"])
        var d := _punch_phases()
        var ext := float(d["ext"])
        var t01 := clampf(punch_t / maxf(punch_dur, 0.001), 0.0, 1.0)
        var target_sh: Vector3 = p["sh"]
        var target_el: float = float(p["el"])
        var punch_arm := str(p["arm"])
        arm_ext = clampf(ext, 0.0, 1.0)
        arm_side = punch_arm
        ptwist = float(p.get("twist", 0.0)) * float(d["tw"])
        pshift = p.get("hip", Vector2.ZERO) * float(d["sh"])
        # вторая рука остаётся в стойке у подбородка: поджимается и уходит
        # чуть назад, а не тянется вперёд — иначе кажется, что бьют двумя руками
        if punch_arm == "l":
            r_sh = SH_GUARD_R.lerp(SH_OFF_R, ext)
            r_el = lerpf(EL_GUARD_R, EL_OFF_R, ext)
        else:
            l_sh = SH_GUARD_L.lerp(SH_OFF_L, ext)
            l_el = lerpf(EL_GUARD_L, EL_OFF_L, ext)
        if punch_aim != Vector3.ZERO:
            has_aim = true
            pun_arm = punch_arm
            pun_path = path
            pun_d = d
        elif punch_arm == "l":
            l_sh = SH_GUARD_L.lerp(target_sh, ext)
            l_el = lerpf(EL_GUARD_L, target_el, ext)
        else:
            var wind := clampf(t01 * 3.0, 0.0, 1.0)
            if anim == "upper":
                r_sh = SH_UPPER_BACK.lerp(SH_GUARD_R, 1.0 - wind).lerp(target_sh, ext)
            else:
                r_sh = SH_GUARD_R.lerp(target_sh, ext)
            r_el = lerpf(EL_GUARD_R, target_el, ext)
    elif telegraph:
        r_sh = SH_UPPER_BACK

    if evading:
        arm_z_l = -0.25
        arm_z_r = 0.25
    if preview and punch_kind == "" and not blocking:
        # поза для примерки в гардеробе: руки по швам, чуть в стороны от тела,
        # чтобы перчатки не врезались в шорты и бёдра
        var dl := Vector3(-0.26, -1.0, 0.02).normalized()
        var dr := Vector3(0.26, -1.0, 0.02).normalized()
        l_sh = Quaternion(Vector3.DOWN, dl).get_euler()
        r_sh = Quaternion(Vector3.DOWN, dr).get_euler()
        l_el = 0.08
        r_el = 0.08
    if ko:
        var f_ko := ease(ko_fall, 2.0)
        arm_z_l = -0.7 * f_ko
        arm_z_r = 0.7 * f_ko

    l_sh = Vector3(l_sh.x, l_sh.y, l_sh.z + arm_z_l)
    r_sh = Vector3(r_sh.x, r_sh.y, r_sh.z + arm_z_r)

    # --- уклон: приседаем пружиной (с перелётом) и уводим корпус
    var crouch_target := 1.0 if evading else 0.0
    _crouch_vel += ((crouch_target - _crouch) * 145.0 - _crouch_vel * 9.0) * dt
    _crouch += _crouch_vel * dt
    _crouch = clampf(_crouch, -0.12, 1.25)

    # Корпус доворачивается ДО того, как решается IK руки: иначе рука считается
    # к старому положению торса и после доворота уезжает мимо цели.
    if ko or fallen:
        _fall_pose(dt)
    else:
        _apply_rig(ptwist, pshift)

    # плечо выносится вперёд на удар — перчатка достаёт до головы цели.
    # Сглаживаем, иначе плечо прыгает на 13 см за пару кадров и рука дёргается.
    var kn := clampf(dt * 18.0, 0.0, 1.0)
    _prot_l = lerpf(_prot_l, 0.13 * arm_ext if arm_side == "l" else 0.0, kn)
    _prot_r = lerpf(_prot_r, 0.13 * arm_ext if arm_side == "r" else 0.0, kn)
    sh_l.position = sh_l_base + Vector3(0.0, 0.0, -_prot_l)
    sh_r.position = sh_r_base + Vector3(0.0, 0.0, -_prot_r)

    if has_aim:
        # Траектория перчатки: замах из текущей стойки → дуга (крюк сбоку,
        # апперкот снизу, прямые почти по нитке) → точка попадания → возврат.
        var b := global_transform.basis
        var w_off: Vector3 = pun_path["wind"]
        var m_off: Vector3 = pun_path["mid"]
        var hit := float(pun_d["hit"])
        var back := float(pun_d["back"])
        var off := _punch_guard_off
        if back > 0.0:
            off = _punch_guard_off * ease(back, 0.7)
        elif hit > 0.0:
            var hu := hit
            off = w_off * (1.0 - hu) * (1.0 - hu) + m_off * 2.0 * (1.0 - hu) * hu
        else:
            off = _punch_guard_off.lerp(w_off, float(pun_d["wind"]))
        var sh_node: Node3D = sh_l if pun_arm == "l" else sh_r
        var sol: Dictionary = _aim_arm(sh_node, punch_aim + b * off, b * Vector3(pun_path["pole"]))
        var ext2 := clampf(float(pun_d["ext"]), 0.0, 1.0)
        var qb := clampf(maxf(ext2, float(pun_d["wind"]) * 0.9), 0.0, 1.0)
        var gq: Quaternion = Quaternion.from_euler(SH_GUARD_L if pun_arm == "l" else SH_GUARD_R)
        var want: Quaternion = gq.slerp(sol["qa"], qb).normalized()
        var g_el: float = EL_GUARD_L if pun_arm == "l" else EL_GUARD_R
        var el_t := lerpf(g_el, float(sol["el"]), qb)
        if pun_arm == "l":
            q_l = want
            l_el = el_t
        else:
            q_r = want
            r_el = el_t

    var arm_k := -1.0
    if has_aim:
        # на выносе рука догоняет цель быстро (контактный кадр точный), на замахе
        # и возврате — обычное сглаживание, чтобы не дёргалось
        arm_k = clampf(maxf(k, clampf(float(pun_d["ext"]), 0.0, 1.0) * 0.85), 0.0, 1.0)

    _apply_pose(l_sh, l_el, r_sh, r_el, k, q_l, q_r, arm_k)

    # --- вспышка / телеграф
    var e := clampf(flash * 3.0, 0.0, 1.0)
    for m in mats:
        if e > 0.01:
            m.emission_enabled = true
            m.emission = Color(1, 1, 1) * e
        else:
            m.emission_enabled = false

    if glove_mat:
        if telegraph:
            glove_mat.emission_enabled = true
            glove_mat.emission = Color(1.0, 0.72, 0.2) * (0.45 + 0.4 * sin(_clock * 24.0))
        else:
            glove_mat.emission_enabled = false


# ------------------------------------------------------------ кости от рига

## Двухзвенная IK: бедро доворачивается в сторону стопы, колено сгибается
## ровно настолько, чтобы достать до физической точки стопы.
func _leg_ik(th: Node3D, kn: Node3D, ft: Node3D, target: Vector3) -> void:
    var tp: Vector3 = hips.to_local(target)
    var hip_pt: Vector3 = th.position
    var d: Vector3 = tp - hip_pt
    var dist: float = clampf(d.length(), 0.22, LEG_UP + LEG_LO - 0.02)
    var to_foot: Vector3 = d.normalized() if d.length() > 0.001 else Vector3.DOWN
    var pole := Vector3(0.0, 0.0, -1.0)
    var perp: Vector3 = pole - to_foot * pole.dot(to_foot)
    if perp.length() < 0.02:
        perp = Vector3(1.0, 0.0, 0.0) if absf(to_foot.z) > 0.9 else Vector3(0.0, 0.0, -1.0)
    perp = perp.normalized()
    var cos_g: float = clampf((LEG_UP * LEG_UP + dist * dist - LEG_LO * LEG_LO)
            / (2.0 * LEG_UP * dist), -1.0, 1.0)
    var gam: float = acos(cos_g)
    var thigh_dir: Vector3 = (to_foot * cos(gam) + perp * sin(gam)).normalized()
    var y_axis: Vector3 = -thigh_dir
    var x_axis: Vector3 = Vector3(1.0, 0.0, 0.0) - thigh_dir * thigh_dir.x
    if x_axis.length() < 0.01:
        x_axis = Vector3(1.0, 0.0, 0.0)
    x_axis = x_axis.normalized()
    var z_axis: Vector3 = x_axis.cross(y_axis)
    th.basis = Basis(x_axis, y_axis, z_axis)
    var cos_b: float = clampf((LEG_UP * LEG_UP + LEG_LO * LEG_LO - dist * dist)
            / (2.0 * LEG_UP * LEG_LO), -1.0, 1.0)
    var bend: float = -(PI - acos(cos_b))
    kn.rotation = Vector3(bend, 0.0, 0.0)
    var chain: Basis = th.basis * Basis(Vector3(1.0, 0.0, 0.0), bend)
    ft.basis = chain.inverse()


func _apply_rig(twist: float, shift: Vector2) -> void:
    var pl := to_local(rj_pelvis.p) + Vector3(shift.x * 0.6, 0.0, shift.y * 0.6)
    hips.position = pl
    hips.rotation = Vector3(-_lean.y * 0.40, twist * 0.35, -_lean.x * 0.40)

    # корпус целится из таза в грудную точку — он отстаёт от таза и качается
    var up_t: Vector3 = hips.to_local(rj_chest.p) - torso.position
    if up_t.length() < 0.05:
        up_t = Vector3.UP
    var tb := wob_torso.step(_dt, 62.0, 6.5) * 0.4
    torso.basis = Basis(Quaternion(Vector3.UP, up_t.normalized())) \
            * Basis(Vector3.UP, twist) * Basis.from_euler(tb)

    # голова — отдельная масса: кивает, отстаёт, дёргается от удара
    var up_h: Vector3 = torso.to_local(rj_head.p) - head.position
    if up_h.length() < 0.05:
        up_h = Vector3.UP
    var hb := wob_head.step(_dt, 46.0, 5.5)
    head.basis = Basis(Quaternion(Vector3.UP, up_h.normalized())) \
            * Basis.from_euler(Vector3(-0.30 * _hit_t + hb.x, hb.y, hb.z))

    # руки отстают от корпуса: плечи болтаются
    var dv: Vector3 = global_transform.basis.inverse() * (rj_chest.p - _chest_prev)
    _chest_prev = rj_chest.p
    wob_sh_l.kick(Vector3(dv.z, -dv.y, -dv.x) * 1.8)
    wob_sh_r.kick(Vector3(dv.z, -dv.y, -dv.x) * 1.8)

    _leg_ik(th_l, kn_l, ft_l, rj_foot_l.p)
    _leg_ik(th_r, kn_r, ft_r, rj_foot_r.p)
    body.position = Vector3.ZERO
    body.rotation = Vector3.ZERO


func _fall_pose(dt: float) -> void:
    var f := ease(ko_fall, 2.0)
    if ko and not fallen:
        th_l.rotation.x = _lerp_angle(th_l.rotation.x, 0.5 * f, clampf(dt * 6.0, 0.0, 1.0))
        th_r.rotation.x = _lerp_angle(th_r.rotation.x, -0.3 * f, clampf(dt * 6.0, 0.0, 1.0))
        kn_l.rotation.x = _lerp_angle(kn_l.rotation.x, -1.2 * f, clampf(dt * 6.0, 0.0, 1.0))
        kn_r.rotation.x = _lerp_angle(kn_r.rotation.x, -0.8 * f, clampf(dt * 6.0, 0.0, 1.0))
        hips.position = Vector3(0.0, _hip_h_dyn - 0.35 * f, 0.0)
        body.rotation.z = deg_to_rad(86.0 * f) * (1.0 if is_player else -1.0)
        body.position.y = -0.28 * f
    else:
        hips.position = Vector3(0.0, _hip_h_dyn, 0.0)
        body.rotation = Vector3.ZERO
        body.position = Vector3.ZERO
    torso.rotation = wob_torso.step(dt, 62.0, 6.5) * 0.5
    var hb := wob_head.step(dt, 46.0, 5.5)
    head.rotation = Vector3(-0.30 * _hit_t + hb.x, hb.y, hb.z)


# ------------------------------------------------------------------ ragdoll

func _shape_for(kind: String, r: float, h: float) -> Shape3D:
    if kind == "sphere":
        var sp := SphereShape3D.new()
        sp.radius = r
        return sp
    if kind == "box":
        var bx := BoxShape3D.new()
        bx.size = Vector3(r * 2.0, h, 0.34)
        return bx
    var cp := CapsuleShape3D.new()
    cp.radius = r
    cp.height = maxf(h, r * 2.0 + 0.01)
    return cp


func _mesh_for(kind: String, r: float, h: float) -> Mesh:
    if kind == "sphere":
        return _ball(r)
    if kind == "box":
        return _cube(Vector3(r * 2.0, h, 0.34))
    return _caps(r, maxf(h, r * 2.0 + 0.01))


func enter_ragdoll(impulse: Vector3) -> void:
    if ragdoll != null or body == null:
        return
    var scene := get_tree().current_scene
    if scene == null:
        scene = get_parent()
    ragdoll = Node3D.new()
    ragdoll.name = "Ragdoll"
    scene.add_child(ragdoll)
    body.visible = false

    var defs := [
        {"n": "pelvis", "bone": hips, "off": Vector3(0, 0.02, 0), "kind": "caps", "r": 0.2, "h": 0.32, "m": 12.0, "c": c_trunks},
        {"n": "torso", "bone": torso, "off": Vector3(0, 0.48, 0), "kind": "caps", "r": 0.24, "h": 0.5, "m": 18.0, "c": c_skin},
        {"n": "head", "bone": head, "off": Vector3(0, 0.13, 0), "kind": "sphere", "r": 0.19, "h": 0.2, "m": 5.0, "c": c_skin},
        {"n": "up_l", "bone": sh_l, "off": Vector3(0, -0.18, 0), "kind": "caps", "r": 0.1, "h": 0.32, "m": 3.0, "c": c_skin},
        {"n": "up_r", "bone": sh_r, "off": Vector3(0, -0.18, 0), "kind": "caps", "r": 0.1, "h": 0.32, "m": 3.0, "c": c_skin},
        {"n": "fore_l", "bone": el_l, "off": Vector3(0, -0.18, 0), "kind": "caps", "r": 0.09, "h": 0.34, "m": 3.0, "c": c_glove},
        {"n": "fore_r", "bone": el_r, "off": Vector3(0, -0.18, 0), "kind": "caps", "r": 0.09, "h": 0.34, "m": 3.0, "c": c_glove},
        {"n": "thigh_l", "bone": th_l, "off": Vector3(0, -0.23, 0), "kind": "caps", "r": 0.13, "h": 0.44, "m": 8.0, "c": c_skin},
        {"n": "thigh_r", "bone": th_r, "off": Vector3(0, -0.23, 0), "kind": "caps", "r": 0.13, "h": 0.44, "m": 8.0, "c": c_skin},
        {"n": "shin_l", "bone": kn_l, "off": Vector3(0, -0.2, 0), "kind": "caps", "r": 0.1, "h": 0.4, "m": 5.0, "c": c_skin},
        {"n": "shin_r", "bone": kn_r, "off": Vector3(0, -0.2, 0), "kind": "caps", "r": 0.1, "h": 0.4, "m": 5.0, "c": c_skin},
        {"n": "foot_l", "bone": ft_l, "off": Vector3(0, -0.03, -0.06), "kind": "box", "r": 0.09, "h": 0.11, "m": 2.0, "c": Color(0.06, 0.07, 0.1)},
        {"n": "foot_r", "bone": ft_r, "off": Vector3(0, -0.03, -0.06), "kind": "box", "r": 0.09, "h": 0.11, "m": 2.0, "c": Color(0.06, 0.07, 0.1)},
    ]

    for d in defs:
        var bone: Node3D = d["bone"]
        var rb := RigidBody3D.new()
        rb.name = "part_" + str(d["n"])
        rb.mass = float(d["m"])
        rb.collision_layer = 0
        rb.collision_mask = 1
        rb.linear_damp = 0.5
        rb.angular_damp = 1.2
        var cs := CollisionShape3D.new()
        cs.shape = _shape_for(str(d["kind"]), float(d["r"]), float(d["h"]))
        rb.add_child(cs)
        var mi := MeshInstance3D.new()
        mi.mesh = _mesh_for(str(d["kind"]), float(d["r"]), float(d["h"]))
        mi.material_override = _mat(d["c"], 0.75)
        rb.add_child(mi)
        ragdoll.add_child(rb)
        var gt := bone.global_transform
        rb.global_transform = Transform3D(gt.basis, gt * d["off"])
        ragdoll_parts[str(d["n"])] = rb

    var joints := [
        ["pelvis", "torso", torso.global_position],
        ["torso", "head", head.global_position],
        ["torso", "up_l", sh_l.global_position],
        ["up_l", "fore_l", el_l.global_position],
        ["torso", "up_r", sh_r.global_position],
        ["up_r", "fore_r", el_r.global_position],
        ["pelvis", "thigh_l", th_l.global_position],
        ["thigh_l", "shin_l", kn_l.global_position],
        ["shin_l", "foot_l", ft_l.global_position],
        ["pelvis", "thigh_r", th_r.global_position],
        ["thigh_r", "shin_r", kn_r.global_position],
        ["shin_r", "foot_r", ft_r.global_position],
    ]
    for j in joints:
        var pin := PinJoint3D.new()
        ragdoll.add_child(pin)
        pin.global_position = j[2]
        pin.node_a = NodePath("../part_" + str(j[0]))
        pin.node_b = NodePath("../part_" + str(j[1]))

    # скорость получает всё тело, иначе шарниры гасят её в ноль
    for k in ragdoll_parts.keys():
        var rb: RigidBody3D = ragdoll_parts[k]
        var f := 1.0
        if str(k) == "head":
            f = 0.95
        elif str(k) == "pelvis":
            f = 0.9
        elif str(k).begins_with("thigh") or str(k).begins_with("shin"):
            f = 0.8
        elif str(k).begins_with("foot"):
            f = 0.7
        rb.linear_velocity = impulse * f
        rb.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0),
                randf_range(-3.0, 3.0)) * 0.5


func clear_ragdoll() -> void:
    if ragdoll != null:
        ragdoll.queue_free()
        ragdoll = null
    ragdoll_parts.clear()
    if body:
        body.visible = true
