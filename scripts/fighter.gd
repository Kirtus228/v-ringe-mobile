extends Node3D
## Боксёр: артикулированный скелет (плечо-локоть, бедро-колено-стопа),
## процедурная анимация ударов/блока/уклона/шага, «пьяный» баланс
## и физический ragdoll на RigidBody3D при нокдауне.

signal impact(kind)
signal footstep(power)
signal knocked_down
## Нокдаун по здоровью: тело падает, лежит и ждёт решения (подъём / поражение).
## knocked_down — общий «упал» (в т.ч. от потери баланса), эти сигналы — только
## про настоящий нокдаун по HP.
signal knockdown_started
signal downed
signal get_up_started
signal get_up_finished

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
        "stam": 9.0, "dmg": 5.6, "reach": 1.45, "dur": 0.28, "hit_at": 0.13,
        "score": 8, "push": 0.30, "stun": 0.18, "arm": "l", "cancel": 0.62,
        "sh": Vector3(1.55, 0.05, -0.08), "el": 0.10,
        "twist": -0.14, "hip": Vector2(0.03, 0.05),
    },
    "lhook": {
        "stam": 14.0, "dmg": 8.8, "reach": 1.30, "dur": 0.38, "hit_at": 0.19,
        "score": 16, "push": 0.42, "stun": 0.26, "arm": "l", "cancel": 0.78,
        "sh": Vector3(1.15, -0.95, -0.30), "el": 1.40,
        "twist": -0.70, "hip": Vector2(0.17, 0.09),
    },
    "rhook": {
        "stam": 16.0, "dmg": 10.4, "reach": 1.28, "dur": 0.42, "hit_at": 0.21,
        "score": 21, "push": 0.56, "stun": 0.34, "arm": "r", "cancel": 0.80,
        "sh": Vector3(1.10, 0.95, 0.10), "el": 1.50,
        "twist": 0.80, "hip": Vector2(-0.20, 0.11),
    },
    "upper": {
        "stam": 22.0, "dmg": 12.0, "reach": 1.25, "dur": 0.50, "hit_at": 0.24,
        "score": 24, "push": 0.63, "stun": 0.40, "arm": "r", "cancel": 0.84,
        "sh": Vector3(1.28, 0.0, 0.12), "el": 1.15,
        "twist": 0.32, "hip": Vector2(-0.04, 0.18),
    },
    # v71k: левый апперкот — lead-рука, чуть быстрее и слабее правого.
    "upper_l": {
        "stam": 20.0, "dmg": 10.0, "reach": 1.22, "dur": 0.46, "hit_at": 0.22,
        "score": 20, "push": 0.56, "stun": 0.36, "arm": "l", "cancel": 0.80,
        "sh": Vector3(1.24, 0.0, -0.12), "el": 1.10,
        "twist": -0.30, "hip": Vector2(0.04, 0.17),
    },
    "cross": {
        "stam": 15.0, "dmg": 9.6, "reach": 1.52, "dur": 0.36, "hit_at": 0.17,
        "score": 18, "push": 0.40, "stun": 0.24, "arm": "r", "cancel": 0.72,
        "sh": Vector3(1.52, 0.02, 0.02), "el": 0.08,
        "twist": 0.55, "hip": Vector2(-0.12, 0.08),
    },
}
## Пояснение к "cancel": доля длительности удара, после которой восстановление
## можно отменить новым ударом (комбо). Открывается в последние ~0.08-0.10 с
## анимации и никогда не раньше hit_at: джеб восстанавливается быстрее всех,
## апперкот — самый вложенный удар, крюки между ними.

## Удары в корпус: то же движение, но цель ниже и урон/выносливость другие.
## "base" — какой удар анимируется, "stam_hit" — сколько выносливости снимает
## чистый корпусной удар (в дополнение к обычному урону).
const BODY_PUNCHES := {
    "body_jab": {"base": "jab", "dmg": 5.2, "reach": 1.42, "dur": 0.30, "hit_at": 0.14,
        "score": 6, "push": 0.22, "stun": 0.12, "stam": 8.0, "stam_hit": 12.0},
    "body_cross": {"base": "cross", "dmg": 8.0, "reach": 1.50, "dur": 0.38, "hit_at": 0.18,
        "score": 14, "push": 0.34, "stun": 0.18, "stam": 13.0, "stam_hit": 16.0},
    "body_lhook": {"base": "lhook", "dmg": 7.6, "reach": 1.28, "dur": 0.40, "hit_at": 0.20,
        "score": 15, "push": 0.38, "stun": 0.20, "stam": 13.0, "stam_hit": 15.0},
    "body_rhook": {"base": "rhook", "dmg": 8.8, "reach": 1.26, "dur": 0.44, "hit_at": 0.22,
        "score": 18, "push": 0.48, "stun": 0.25, "stam": 15.0, "stam_hit": 17.0},
    "body_upper": {"base": "upper", "dmg": 9.6, "reach": 1.24, "dur": 0.52, "hit_at": 0.25,
        "score": 21, "push": 0.55, "stun": 0.30, "stam": 20.0, "stam_hit": 20.0},
    # v71k: корпусной вариант левого апперкота.
    "body_upper_l": {"base": "upper_l", "dmg": 9.0, "reach": 1.20, "dur": 0.47, "hit_at": 0.23,
        "score": 18, "push": 0.50, "stun": 0.27, "stam": 18.0, "stam_hit": 18.0},
}

## Траектория перчатки для каждого удара. Координаты локальные, от точки
## попадания: x — вправо, y — вверх, z — назад (цель впереди бойца).
## wind — куда перчатка уходит на замахе, mid — контрольная точка дуги
## (прямые удары идут почти по нитке, крюки — по дуге сбоку, апперкот — снизу),
## pole — куда смотрит локоть, dip — насколько проседают колени на замахе,
## drive — насколько корпус идёт вперёд на выносе,
## turn — насколько всё тело доворачивается в сторону удара (радианы, знак:
## + вперёд идёт правая сторона, − левая), pivot — доворот стопы ударной
## ноги на носке (пятка наружу), heel — подъём пятки, foot — какая стопа
## работает: "front" (передняя) или "back" (задняя).
##
## Цифры взяты из техники бокса: джеб почти без доворота, только лёгкий
## пивот задней ноги; кросс — пятка задней ноги разворачивается наружу,
## таз и корпус идут за ней, рука вылетает последней; хук — вес на переднюю
## ногу, таз и плечи резко доворачиваются, передняя стопа разворачивается
## внутрь на носке, локоть ~90°; апперкот — присед, таз поворачивается,
## пятка задней ноги поднимается, рука идёт снизу вверх по дуге.
const PUNCH_PATH := {
    "jab": {"wind": Vector3(-0.11, 0.02, 0.30), "mid": Vector3(-0.04, 0.0, 0.03),
        "pole": Vector3(0.30, -0.90, 0.20), "dip": 0.05, "drive": 0.30,
        "turn": -0.12, "pivot": 0.16, "heel": 0.06, "foot": "back"},
    "cross": {"wind": Vector3(0.15, -0.01, 0.34), "mid": Vector3(0.06, 0.0, 0.04),
        "pole": Vector3(0.35, -0.90, 0.25), "dip": 0.08, "drive": 0.55,
        "turn": 0.38, "pivot": 0.50, "heel": 0.34, "foot": "back"},
    # v71g: крюки переделаны. Раньше локоть тянуло ВНИЗ (pole.y = -0.45), и удар
    # шёл низкой дугой «загребанием»: перчатка приходила на 20 см ниже головы и
    # проходила сквозь лицо на дальнюю сторону. Теперь локоть поднят на уровень
    # плеча, замах остаётся у подбородка (а не падает на 30 см), дуга идёт
    # горизонтально сбоку — так крюк читается как крюк.
    "lhook": {"wind": Vector3(-0.46, -0.06, 0.22), "mid": Vector3(-0.34, 0.00, 0.02),
        "pole": Vector3(-0.94, 0.44, 0.06), "dip": 0.12, "drive": 0.42,
        "turn": -0.30, "pivot": 0.44, "heel": 0.14, "foot": "front",
        "retract": Vector3(-0.16, 0.02, 0.12),
        "swing": 2.40, "swing_y": -0.01},
    "rhook": {"wind": Vector3(0.46, -0.06, 0.22), "mid": Vector3(0.34, 0.00, 0.02),
        "pole": Vector3(0.94, 0.44, 0.06), "dip": 0.12, "drive": 0.42,
        "turn": 0.32, "pivot": 0.42, "heel": 0.20, "foot": "back",
        "retract": Vector3(0.16, 0.02, 0.12),
        "swing": -2.40, "swing_y": -0.01},
    "upper": {"wind": Vector3(0.16, -0.55, 0.22), "mid": Vector3(0.07, -0.22, -0.04),
        "pole": Vector3(0.20, -1.0, 0.50), "dip": 0.34, "drive": 0.55,
        "turn": 0.30, "pivot": 0.40, "heel": 0.30, "foot": "back"},
    # v71k: зеркало правого апперкота по X, ударная нога — передняя.
    "upper_l": {"wind": Vector3(-0.16, -0.55, 0.22), "mid": Vector3(-0.07, -0.22, -0.04),
        "pole": Vector3(-0.20, -1.0, 0.50), "dip": 0.34, "drive": 0.55,
        "turn": -0.30, "pivot": 0.40, "heel": 0.30, "foot": "front"},
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
## Ветка A (Этап 2): true — включить «скин-модельки» вместо
## процедурных примитивов. По умолчанию false = байт-в-байт прежний риг.
## Единственная точка проверки флага — fighter.gd::_build().
var use_skin_models := false
## Render-layer для адресного fill/rim света (Этап 2): 0 — не менять (базовое
## поведение), иначе все меши бойца получают этот слой, а свет бойца — эту маску.
var light_mask := 0
var hp := 100.0
var max_hp := 100.0
var stamina := 100.0
var max_stamina := 100.0
## v57: удар «на последних силах» — множитель урона текущего удара (1.0 — обычный).
## Ставится в start_punch(): если выносливости не хватало на удар, он всё равно
## идёт, но слабее 0.55. Раньше такой удар просто не начинался.
var punch_power := 1.0
## v57: текущий удар начат без запаса выносливости (для звука/HUD/тестов).
var exhausted := false

# --- v68: «выдохся» — выносливость в ноль, боец валится на настил (ragdoll),
## лежит, переводит дух и встаёт. Это НЕ нокдаун: HP и счётчик нокдаунов целы.
## Раньше он только приседал на колено — заказчик справедливо сказал, что от
## нуля сил должен быть настоящий пол.
## EXHAUST_LIE — сколько секунд лежит (включая само падение), дальше подъём.
const EXHAUST_LIE := 1.2
const EXHAUST_RECOVER := 45.0
var exhaust_down := false      # упал от усталости: тело в ragdoll на полу
var exhaust_getup := false     # встаёт: анимация подъёма от усталости
var exhaust_t := 0.0           # сколько ещё лежать
## v68: сколько ждём, пока тело осядет, сверх EXHAUST_LIE. Нужен как страховка:
## если физика почему-то не двигает части (headless-прогон, зажало в канатах),
## состояние всё равно не залипает — через 0.6 с начинаем вставать.
var _exhaust_wait := 0.0
## Сколько секунд «выдохся» длилось в последний раз (для тестов/отчёта).
var exhaust_last := 0.0
var _stam_prev := 100.0

# --- Пакет 2 / T6: «живой» нокдаун — тонус ragdoll и плавный переход в позу лежа.
## Сколько секунд ragdoll-поза плавно переходит в позу лежа (0.2–0.4 с).
const SETTLE_BLEND := 0.32
var _settle_blend := 1.0
var _settle_from_pos := Vector3.ZERO
var _settle_from_quat := Quaternion.IDENTITY
## Тонус: повышенное демпфирование частей, чтобы тело не болталось как тряпка.
const RAGDOLL_DAMP := {
    "head": {"ad": 4.2, "ld": 1.4},
    "torso": {"ad": 2.6, "ld": 1.0},
    "pelvis": {"ad": 2.2, "ld": 0.9},
    "up_l": {"ad": 3.0, "ld": 1.3},
    "up_r": {"ad": 3.0, "ld": 1.3},
    "fore_l": {"ad": 3.6, "ld": 1.5},
    "fore_r": {"ad": 3.6, "ld": 1.5},
    "thigh_l": {"ad": 2.4, "ld": 1.1},
    "thigh_r": {"ad": 2.4, "ld": 1.1},
    "shin_l": {"ad": 2.6, "ld": 1.2},
    "shin_r": {"ad": 2.6, "ld": 1.2},
    "foot_l": {"ad": 3.0, "ld": 1.4},
    "foot_r": {"ad": 3.0, "ld": 1.4},
}

## v71: анатомические пределы для ragdoll: (мин, макс) поворота вокруг X
## относительно родительской кости, в радианах. Физика ragdoll шарниров не знает,
## и после падения локоть/колено выворачивались назад — модель выглядела
## «сломанной» (заказчик: «после падения ломаются руки»). Ограничиваем изгиб
## так, чтобы сустав не гиперразгибался, а плечо/бедро не выкручивались.
const RAGDOLL_LIMITS := {
    "torso": Vector2(-0.95, 1.10),
    "head": Vector2(-0.70, 0.70),
    "up_l": Vector2(-1.90, 2.40),
    "up_r": Vector2(-1.90, 2.40),
    "fore_l": Vector2(-2.35, 0.35),
    "fore_r": Vector2(-2.35, 0.35),
    "thigh_l": Vector2(-1.90, 2.20),
    "thigh_r": Vector2(-1.90, 2.20),
    "shin_l": Vector2(-2.40, 0.15),
    "shin_r": Vector2(-2.40, 0.15),
    "foot_l": Vector2(-0.80, 0.90),
    "foot_r": Vector2(-0.80, 0.90),
}

## v68: смещение центра физической части ragdoll от сустава (в системе кости).
## Один источник и для создания частей, и для синхронизации модели с физикой.
const RAGDOLL_OFF := {
    "pelvis": Vector3(0.0, 0.02, 0.0),
    "torso": Vector3(0.0, 0.48, 0.0),
    "head": Vector3(0.0, 0.13, 0.0),
    "up_l": Vector3(0.0, -0.18, 0.0),
    "up_r": Vector3(0.0, -0.18, 0.0),
    "fore_l": Vector3(0.0, -0.18, 0.0),
    "fore_r": Vector3(0.0, -0.18, 0.0),
    "thigh_l": Vector3(0.0, -0.23, 0.0),
    "thigh_r": Vector3(0.0, -0.23, 0.0),
    "shin_l": Vector3(0.0, -0.2, 0.0),
    "shin_r": Vector3(0.0, -0.2, 0.0),
    "foot_l": Vector3(0.0, -0.03, -0.06),
    "foot_r": Vector3(0.0, -0.03, -0.06),
}

# --- v66: многофазный подъём после нокдауна ---------------------------------
## Ключевые кадры подъёма. Поза считается не «разворотом корпуса», а позой
## таза: задаём высоту таза (hy), наклон корпуса (p) и поворот на бок (roll),
## изгиб торса и головы (torso/head), углы ног (legs) и направление плеч
## (al/ar, в системе торса), сгиб локтя (el_*). Порядок фаз: лежим → тянемся
## руками к полу и заваливаемся на бок → встаём на четвереньки → ставим ногу
## и поднимаемся с колена → стойка с поиском равновесия.
## Заполняется один раз в _getup_table().
var _getup_keys: Array = []
## Минимальная высота голеностопа над настилом во время подъёма: если по
## ключевым кадрам стопа уходит ниже, колено догибается (см. _getup_foot_clamp).
const GETUP_FOOT_MIN := 0.07

# прокачка: уровни 0..4, множители пересчитываются в set_upgrades()
var upg := {"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0}
var dmg_mult := 1.0
## урон только от прокачки, без статов тренировки (база для пересчёта)
var base_dmg_mult := 1.0
## множитель скорости движения от статов тренировки (Этап 3), 1.0 — без статов
var move_mult := 1.0
# --- Этап 4: модификаторы арены (ставятся ArenaManager на бой)
## трение поверхности: 1.0 — норма, >1 — вязко/скользко-медленно, <1 — лёд
var surface_friction := 1.0
## доп. расход выносливости в секунду (0 — нет)
var stamina_drain := 0.0
## постоянная сила ветра (м/с^2), действует каждый кадр
var wind := Vector3.ZERO
## множитель гравитации для ragdoll (1.0 — обычная)
var gravity_mult := 1.0
var dur_mult := 1.0
var stam_mult := 1.0
var taken_mult := 1.0
var hp_mult := 1.0
var blocking := false
var evading := false
var dodge_t := 0.0
## v71k: направленный уклон. dodge_kind = "slip" (A/D) или "duck" (Shift без
## направления), dodge_dir — мировая сторона скольжения, dodge_dur — полная
## длительность, counter_t — короткое окно контратаки после уклона.
var dodge_kind := ""
var dodge_dir := Vector3.ZERO
var dodge_dur := 0.40
var counter_t := 0.0
const DODGE_SAFE_AFTER := 0.06
const DODGE_SAFE_UNTIL := 0.30
var stun := 0.0
var flash := 0.0
var ko := false
var ko_fall := 0.0
## v71e: тело уже «осело» после КО и лежит в авторской позе (не ragdoll-кучей).
## Раньше при КО ragdoll жил до экрана результата, и физика складывала модель
## в клубок: заказчик видел «моделька ломается».
var ko_lying := false
var ko_settle_t := 0.0
## v71e: можно ли «осаживать» КО-тело в позу лежа. Выключается на вылете за
## канаты (ringout): там тело должно падать на пол зала, а не на настил ринга.
var ko_settle_allowed := true
var punch_kind := ""
var punch_t := 0.0
var punch_dur := 0.3
var punch_hit_at := 0.13
var hit_done := false
## Активное окно попадания: удар может зарегистрироваться не в одной точке
## hit_at, а в интервале [hit_at, hit_at + hit_window]. Промах на отдельном
## кадре (цель чуть разошлась) больше не «съедает» удар; попадание всё равно
## только одно — его подтверждает main (hit_done), после контакта окно закрыто.
@export var hit_window := 0.06
## сколько кадров окна уже опробовано — чтобы «свист» промаха не дублировался
var impact_attempts := 0
## отдача/взмах руки при попадании проигрывается один раз за удар
var _recoil_done := false
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
## Роли материалов для ветки A (Этап 2): кожа и шнуровка. Заполняются в _build().
var _skin_mat: StandardMaterial3D = null
var _lace_mat: StandardMaterial3D = null
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

# --- нокдаун по здоровью. Проект полностью процедурный: AnimationTree и
# AnimationPlayer здесь нет, поэтому состояния сделаны явным автоматом —
# он же играет роль, которую в обычном проекте выполняет travel():
#   knockdown (падение) → downed (лежит, ждёт решения) → get_up (подъём) → NONE
# Управляет переходами main.gd: падение — когда HP дошло до нуля, подъём — по
# Space (у игрока) или таймером, поражение — когда нокдауны кончились.
enum KnockState { NONE, FALLING, DOWNED, GETUP }
## во время падения/лежания/подъёма удары не проходят
@export var knockdown_invulnerable := true
## v71p: сколько секунд после подъёма боец неуязвим (ставит main.gd при подъёме
## игрока: иначе его сразу роняли повторным ударом).
@export var getup_invuln := 2.0
## Текущий остаток окна неуязвимости, сек (тикает в tick).
var invuln_t := 0.0
## сколько нажатий Space нужно, чтобы встать (одного нажатия мало — надо жать)
@export var get_up_presses: int = 8
## с какой скоростью «остывает» прогресс, если перестать жать (доля в секунду)
@export var get_up_decay: float = 0.35
## сколько секунд тело лежит, прежде чем начнётся «downed» (таймер подъёма
## стартует именно с этого момента, а не с падения)
@export var fall_hold := 0.9
## длительность процедурной анимации подъёма (v66: 1.35 с — успевает
## пройти четвереньки и подъём с колена, а не один «разворот корпуса»)
@export var get_up_duration := 1.35
## v71l: границы, в которых ragdoll считается «осевшим» (для перехода в downed).
## Оффлайн-ринг 9.4×9.4 — значения по умолчанию; кооп-арена 20×20 выставляет
## свои, иначе нокдаун у края арены не «оседал» и боец застревал в FALLING.
@export var settle_radius := 3.4
@export var settle_max_y := 0.5
@export var settle_max_speed := 1.6
var knock_state: int = KnockState.NONE
var knock_t := 0.0
## сколько раз боец уже поднялся после нокдауна в этом бою
var knockdown_count := 0
## накопленный прогресс подъёма (0..1): растёт от нажатий, остывает без них
var get_up_progress := 0.0
## поза лежа: поворот и смещение тела, снятые с ragdoll в момент «downed»
var _down_quat := Quaternion.IDENTITY
var _down_pos := Vector3.ZERO

# --- активный ragdoll: точки-массы + мышцы-пружины + физические шаги
## Тело больше не «рисует» позу: таз, корпус, голова и стопы — это точки с
## массой и скоростью. Мышцы тянут их к желаемому положению, инерция тянет
## назад, ноги переставляются от растяжения. Кости — уже IK от этих точек.
const FOOT_Y := 0.09
const LEG_UP := 0.46
const LEG_LO := 0.42
const LEG_MAX := 0.845

# --- выносливость: скорость восстановления в секунду (с множителем прокачки).
## v56: по просьбе заказчика восстановление замедлено в 3 раза (было 22 и 6).
const STAM_REGEN := 22.0 / 3.0        # обычное восстановление ≈ 7.33/с
const STAM_REGEN_EVADE := 6.0 / 3.0   # в уклоне ≈ 2.0/с
const STAM_REGEN_BLOCK := -4.0        # в блоке не восстанавливается, а падает


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

## T10: AI-параметры под уровень (0 — первый бой, 1 — последний пояс).
## dmg_mult НЕ повышаем (урон соперника по условию T10 не растёт), поэтому
## сложность читается через скорость реакции, темп и защиту в main._ai_tick.
var ai_react := 0.35
var ai_tempo := 0.45
var ai_guard := 0.35
var ai_dodge := 0.10
var ai_counter := 0.10


func set_difficulty(v: float) -> void:
    diff = clampf(v, 0.0, 1.0)
    # v71: сложность поднята по просьбе заказчика. Было 0.88 + 0.92*diff —
    # на первом поясе соперник почти не бил больно. Теперь урон и темп растут
    # заметнее, а ИИ (ниже) стал реактивнее, чаще защищается и контратакует.
    dmg_mult = 0.95 + 1.05 * diff
    dur_mult = 1.0 - 0.20 * diff
    # T10: быстрее реакция/замах, плотнее темп, больше блок/уклон/контратака
    ai_react = 0.42 + 0.56 * diff
    ai_tempo = 0.50 + 0.56 * diff
    ai_guard = 0.34 + 0.30 * diff
    ai_dodge = 0.08 + 0.22 * diff
    ai_counter = 0.08 + 0.26 * diff


## Прокачка: пересчитывает множители под уровень из профиля.
func set_upgrades(d: Dictionary) -> void:
    for k in upg.keys():
        upg[k] = clampi(int(d.get(k, 0)), 0, 4)
    dmg_mult = 1.0 + 0.10 * float(upg["power"])
    base_dmg_mult = dmg_mult
    dur_mult = 1.0 - 0.07 * float(upg["speed"])
    stam_mult = 1.0 + 0.15 * float(upg["stamina"])
    taken_mult = 1.0 - 0.08 * float(upg["guard"])
    hp_mult = 1.0 + 0.10 * float(upg["health"])
    max_stamina = 100.0 * stam_mult
    stamina = minf(stamina, max_stamina)


## Этап 3: применить множители статов тренировки одним вызовом на старте боя.
## Урон = прокачка × стат, скорость движения × стат (HP считает main через max_hp).
func apply_stat_multipliers(stat_damage: float, stat_move: float) -> void:
    dmg_mult = base_dmg_mult * maxf(0.01, stat_damage)
    move_mult = maxf(0.01, stat_move)


func setup(as_player: bool, look_data: Dictionary = {}) -> void:
    is_player = as_player
    if look_data.is_empty():
        look = LookScript.default_look() if is_player else LOOK_ENEMY.duplicate()
    else:
        look = look_data.duplicate()
    _build()


# ------------------------------------------------------------------ материалы

## Этап 7: кэш материалов по (цвет, шероховатость) — чтобы рэгдолл и вспомогательные
## детали не создавали новый StandardMaterial3D на каждый нокдаун (шов шейдерных
## вариантов и «Condition f.is_null()» в кэше пайплайнов на слабых местах).
var _mat_cache: Dictionary = {}


func _mat_cached(c: Color, rough: float = 0.8) -> StandardMaterial3D:
    var key := str(c.to_html(false)) + "_" + str(snappedf(rough, 0.01))
    if _mat_cache.has(key):
        return _mat_cache[key]
    var m := _mat(c, rough)
    _mat_cache[key] = m
    return m


func _mat(c: Color, rough: float = 0.8) -> StandardMaterial3D:
    if OS.get_environment("VRINGE_DIAG") != "":
        _diag_mats += 1
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


# --- Общие Mesh-ресурсы (Этап 2). Одинаковые по параметрам примитивы
# переиспользуются между узлами и бойцами: геометрия не меняется ни на вершину,
# поэтому OFF-кадр остаётся пиксельно равен baseline, а число уникальных пар
# (mesh, material) — то есть оценка draw calls — падает в разы.
# Ключ включает режим детализации: OFF — исходные сегменты (как было),
# ветка A (use_skin_models) — щадящая тесселяция SKIN_* (на 720p силуэт тот же,
# зато влезает в бюджет треугольников).
static var _mesh_cache: Dictionary = {}

## Тесселяция скин-режима: при 720p на силуэте неотличима от дефолтной 64/32,
## но в 6-7 раз дешевле (на бойца ~105k → ~18k треугольников).
const SKIN_BALL_RADIAL := 24
const SKIN_BALL_RINGS := 12
const SKIN_CAPS_RADIAL := 24
const SKIN_CAPS_RINGS := 4
const SKIN_CYL_RADIAL := 24
const SKIN_CYL_RINGS := 2

## Детализация мешей текущей сборки: false — как в baseline, true — ветка A.
var _low_detail := false


func _mesh_key(kind: String, a: String) -> String:
    return ("L|" if _low_detail else "H|") + kind + "|" + a


func _caps(radius: float, height: float) -> CapsuleMesh:
    var key := _mesh_key("cap", "%.4f:%.4f" % [radius, height])
    if _mesh_cache.has(key):
        return _mesh_cache[key] as CapsuleMesh
    var m := CapsuleMesh.new()
    m.radius = radius
    m.height = height
    if _low_detail:
        m.radial_segments = SKIN_CAPS_RADIAL
        m.rings = SKIN_CAPS_RINGS
    _mesh_cache[key] = m
    return m


func _ball(radius: float) -> SphereMesh:
    var key := _mesh_key("ball", "%.4f" % radius)
    if _mesh_cache.has(key):
        return _mesh_cache[key] as SphereMesh
    var m := SphereMesh.new()
    m.radius = radius
    m.height = radius * 2.0
    if _low_detail:
        m.radial_segments = SKIN_BALL_RADIAL
        m.rings = SKIN_BALL_RINGS
    _mesh_cache[key] = m
    return m


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
    var key := _mesh_key("cyl", "%.4f:%.4f:%.4f" % [top, bottom, height])
    if _mesh_cache.has(key):
        return _mesh_cache[key] as CylinderMesh
    var m := CylinderMesh.new()
    m.top_radius = top
    m.bottom_radius = bottom
    m.height = height
    if _low_detail:
        m.radial_segments = SKIN_CYL_RADIAL
        m.rings = SKIN_CYL_RINGS
    _mesh_cache[key] = m
    return m


## v71f: открытая с двух сторон труба (голенище ботинка). Обычный CylinderMesh
## закрыт крышками, и у высокого голенища сверху была видна «крышка-звезда»:
## нога уходила в ботинок, а сверху торчала заглушка с веером треугольников.
func _cyl_open(top: float, bottom: float, height: float) -> CylinderMesh:
    var key := _mesh_key("cylo", "%.4f:%.4f:%.4f" % [top, bottom, height])
    if _mesh_cache.has(key):
        return _mesh_cache[key] as CylinderMesh
    var m := CylinderMesh.new()
    m.top_radius = top
    m.bottom_radius = bottom
    m.height = height
    m.cap_top = false
    m.cap_bottom = false
    if _low_detail:
        m.radial_segments = SKIN_CYL_RADIAL
        m.rings = SKIN_CYL_RINGS
    _mesh_cache[key] = m
    return m


func _cube(size: Vector3) -> BoxMesh:
    var key := _mesh_key("cube", "%.4f:%.4f:%.4f" % [size.x, size.y, size.z])
    if _mesh_cache.has(key):
        return _mesh_cache[key] as BoxMesh
    var m := BoxMesh.new()
    m.size = size
    _mesh_cache[key] = m
    return m


# ------------------------------------------------------------------ ветка A: скин
## Ветка A (Этап 2): улучшения ПОВЕРХ уже собранного примитивного рига.
## Ничего не переименовывает и не переносит: имена/позиции узлов рига те же,
## исходные примитивы остаются на месте (fallback при OFF).
##
## Что делает (только при use_skin_models=true):
##  1) материалы: кожа — матовая с мягким rim-обводом (не «пластик»),
##     перчатки — с лаковым clearcoat, шорты матовые;
##  2) стыки: дельтовидные «шапки» на плечах, накладки на локтях и коленях,
##     трапеции у шеи, икры — капсулы больше не читаются как отдельные шары;
##  3) перчатка: капсула-«рукавица» + манжета (вместо одного шара с отростком).
## Тесселяция берётся из скин-кэша (SKIN_*), поэтому бюджет не растёт.
## Канонические меши накладок: одна геометрия на всю сцену, размер задаётся
## масштабом узла. Так накладки бойцов не добавляют уникальных пар (mesh, material).
const CANON_JOINT_R := 0.1
const CANON_MITT_R := 0.1
const CANON_MITT_H := 0.4
const CANON_CAPS_R := 0.1
const CANON_CAPS_H := 0.4
const CANON_CYL_R := 0.1
const CANON_CYL_H := 0.4
const CANON_BOX := 1.0


func _canon_joint() -> SphereMesh:
    return _ball(CANON_JOINT_R)


func _canon_mitt() -> CapsuleMesh:
    return _caps(CANON_MITT_R, CANON_MITT_H)


## Ветка A: переводим ВСЕ примитивы рига на канонические меши, а размеры переносим
## в масштаб узла. Геометрия визуально та же (форма примитива), но в сцене вместо
## десятков уникальных мешей остаются 4 общих — это и есть «scene_draws после
## батчинга». Имена/позиции узлов рига не меняются. Только для use_skin_models.
func _canonicalize_body_meshes() -> void:
    _canon_walk(body)


func _canon_walk(n: Node) -> void:
    for ch in n.get_children():
        if ch is MeshInstance3D:
            _canon_mesh_instance(ch as MeshInstance3D)
        if ch.get_child_count() > 0:
            _canon_walk(ch)


## Масштаб узла, чтобы канонический шар CANON_JOINT_R дал эллипсоид нужных размеров.
func _joint_scale(rx: float, ry: float, rz: float) -> Vector3:
    return Vector3(rx, ry, rz) / CANON_JOINT_R


func _canon_mesh_instance(mi: MeshInstance3D) -> void:
    var m := mi.mesh
    if m == null:
        return
    var s := mi.scale
    if m is SphereMesh:
        var r := (m as SphereMesh).radius
        mi.mesh = _canon_joint()
        mi.scale = Vector3(s.x * r / CANON_JOINT_R, s.y * r / CANON_JOINT_R,
                s.z * r / CANON_JOINT_R)
    elif m is CapsuleMesh:
        var cm := m as CapsuleMesh
        mi.mesh = _caps(CANON_CAPS_R, CANON_CAPS_H)
        mi.scale = Vector3(s.x * cm.radius / CANON_CAPS_R, s.y * cm.height / CANON_CAPS_H,
                s.z * cm.radius / CANON_CAPS_R)
    elif m is CylinderMesh:
        var cy := m as CylinderMesh
        if is_equal_approx(cy.top_radius, cy.bottom_radius):
            # v71f: голенища ботинок открыты сверху (без крышек). Канонизация
            # не должна снова навешивать крышку — иначе на голени снова появляется
            # «заглушка-звезда» (см. _cyl_open).
            var open_ends := not cy.cap_top and not cy.cap_bottom
            mi.mesh = _cyl_open(CANON_CYL_R, CANON_CYL_R, CANON_CYL_H) if open_ends \
                    else _cyl(CANON_CYL_R, CANON_CYL_R, CANON_CYL_H)
            mi.scale = Vector3(s.x * cy.top_radius / CANON_CYL_R,
                    s.y * cy.height / CANON_CYL_H, s.z * cy.top_radius / CANON_CYL_R)
    elif m is BoxMesh:
        var bm := m as BoxMesh
        mi.mesh = _cube(Vector3(CANON_BOX, CANON_BOX, CANON_BOX))
        mi.scale = Vector3(s.x * bm.size.x / CANON_BOX, s.y * bm.size.y / CANON_BOX,
                s.z * bm.size.z / CANON_BOX)


func _build_skin_visuals(v: Dictionary) -> void:
    var aw := float(v["arm"])
    var lw := float(v["leg"])
    var wide := float(v["chest"])
    _skin_upgrade_materials()
    _canonicalize_body_meshes()
    # 1) плечи: дельтовидная шапка, сглаживает стык шара и капсулы
    for sh in [sh_l, sh_r]:
        var delt := _mesh(sh, _canon_joint(), _skin_mat, Vector3(0, -0.055, 0))
        delt.scale = _joint_scale(0.138 * aw * 1.12, 0.138 * aw * 0.9, 0.138 * aw * 1.04)
    # 2) локти: накладка, чтобы шар-плечо и предплечье не разъезжались
    for el in [el_l, el_r]:
        var ecap := _mesh(el, _canon_joint(), _skin_mat, Vector3(0, 0.018, 0))
        ecap.scale = _joint_scale(0.092 * aw, 0.092 * aw * 1.08, 0.092 * aw)
    # 3) колени и икры
    for kn in [kn_l, kn_r]:
        var kcap := _mesh(kn, _canon_joint(), _skin_mat, Vector3(0, 0.012, 0))
        kcap.scale = _joint_scale(0.106 * lw, 0.106 * lw * 1.1, 0.106 * lw)
        var calf := _mesh(kn, _canon_joint(), _skin_mat, Vector3(0, -0.15, 0.02))
        calf.scale = _joint_scale(0.074 * lw * 0.92, 0.074 * lw * 1.55, 0.074 * lw * 0.95)
    # 4) трапеции у шеи: мягкий переход торса в шею
    for sx in [-1.0, 1.0]:
        var trap := _mesh(torso, _canon_joint(), _skin_mat,
                Vector3(0.13 * wide * sx, 0.715, 0.0))
        trap.scale = _joint_scale(0.118 * wide, 0.118 * wide * 0.72, 0.118 * wide * 0.94)
    # 5) v71: отдельной капсулы-«рукавицы» больше нет — перчатка целиком
    # собирается в _forearm (кулак, ударная площадка, костяшки, большой палец,
    # шнуровка). Раньше поверх неё висела вторая капсула, из-за неё на перчатке
    # появлялись лишние бугры «посреди» и раздувалась геометрия.


## Материалы ветки A: мягкий rim по коже, лаковые перчатки, матовые шорты.
## Трогаем только материалы-роли, остальные (глаза, брови, волосы) не меняются.
## Этап 7: постоянный слот эмиссии у всех материалов бойца (эмиссия чёрная, пока
## нет вспышки). Убирает покадровую смену shader-варианта emission_enabled.
var _glove_emission_base := Color(0, 0, 0)


func _enable_emission_slots() -> void:
    # сначала запоминаем базовую эмиссию перчаток (свечение из гардероба), потом глушим
    if glove_mat != null:
        _glove_emission_base = glove_mat.emission
    for m in mats:
        if m != null:
            m.emission_enabled = true
            m.emission = Color(0, 0, 0)
    if glove_mat != null:
        glove_mat.emission_enabled = true
        glove_mat.emission = _glove_emission_base
    if _skin_mat != null:
        _skin_mat.emission_enabled = true
        _skin_mat.emission = Color(0, 0, 0)


func _skin_upgrade_materials() -> void:
    if _skin_mat != null:
        _skin_mat.roughness = 0.62
        _skin_mat.metallic_specular = 0.42
        _skin_mat.rim_enabled = true
        _skin_mat.rim = 0.55
        _skin_mat.rim_tint = 0.55
    if glove_mat != null:
        glove_mat.roughness = 0.30
        glove_mat.clearcoat_enabled = true
        glove_mat.clearcoat = 0.65
        glove_mat.clearcoat_roughness = 0.28
        glove_mat.rim_enabled = true
        glove_mat.rim = 0.35
    if _lace_mat != null:
        _lace_mat.roughness = 0.45
    for m in mats:
        if m == _skin_mat or m == glove_mat or m == _lace_mat:
            continue
        if m.albedo_color.is_equal_approx(c_skin_dark):
            m.roughness = 0.64
            m.rim_enabled = true
            m.rim = 0.3
        elif m.albedo_color.is_equal_approx(c_trunks):
            m.roughness = 0.74
            m.metallic_specular = 0.3


# ------------------------------------------------------------------ сборка тела
    _enable_emission_slots()

func _build() -> void:
    var v := LookScript.outfit(look)

    # --- Ветка A (Этап 2): ЕДИНСТВЕННАЯ точка проверки use_skin_models.
    # false (по умолчанию) — дальше строятся ровно те же примитивы с той же
    # тесселяцией, что и раньше (OFF-кадр пиксельно равен baseline).
    # true — щадящая тесселяция + улучшенные материалы/стыки (см. ниже).
    _low_detail = use_skin_models

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
    _skin_mat = skin
    _lace_mat = lace
    glove_mat = _mat(c_glove, 0.4)
    if v.has("glove_glow"):
        glove_mat.emission_enabled = true
        glove_mat.emission = v["glove_glow"]
        glove_mat.emission_energy_multiplier = 1.7

    hips = _node(body, Vector3(0, _hip_y, 0), "Hips")
    var hip_mesh := _mesh(hips, _caps(0.215, 0.28), trunks, Vector3(0, 0.01, 0))
    hip_mesh.scale = Vector3(wide, 1.0, wide * 0.95)
    # task-26: belt-меш («диск/тарелка» на бёдрах) убран полностью по просьбе заказчика:
    # на этой высоте капсула шорт уже, поэтому любое кольцо читалось как пластина.
    # Строка _mesh(hips, _cyl(...belt...), ...) удалена; шорты/бёдра не менялись.
    # (материал belt остаётся в mats как неиспользуемый — он нужен другим деталям)

    torso = _node(hips, Vector3(0, 0.14, 0), "Torso")
    var waist := _mesh(torso, _caps(0.19, 0.34), skin, Vector3(0, 0.18, 0))
    waist.scale = Vector3(wide * 0.98, 1.0, wide * 0.98)
    var chest := _mesh(torso, _caps(0.255, 0.5), skin, Vector3(0, 0.5, 0))
    chest.scale = Vector3(wide, 1.0, wide * 0.95)
    # грудные «шары» убраны по просьбе заказчика: торс остаётся гладкой капсулой
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
    # T9: повязка на голове убрана по просьбе заказчика (оставлена при откате
    # модели к v31). Материал band нужен для полоски на босых стопах.
    _hair(head, String(v["hair"]), v["hair_col"])

    sh_l = _arm_node(torso, Vector3(-0.32 * shx, 0.6, 0), skin, aw)
    sh_r = _arm_node(torso, Vector3(0.32 * shx, 0.6, 0), skin, aw)
    sh_l_base = sh_l.position
    sh_r_base = sh_r.position
    el_l = _node(sh_l, Vector3(0, -0.34, 0), "ElbowL")
    el_r = _node(sh_r, Vector3(0, -0.34, 0), "ElbowR")
    _forearm(el_l, skin, lace, aw, glove_r, -1.0)
    _forearm(el_r, skin, lace, aw, glove_r, 1.0)

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
    for i in 2:
        var ft: Node3D = ft_l if i == 0 else ft_r
        var kn: Node3D = kn_l if i == 0 else kn_r
        _build_boot(ft, kn, boot_style, boot, lace, band, skin)

    _apply_pose(SH_GUARD_L, EL_GUARD_L, SH_GUARD_R, EL_GUARD_R, 10.0)

    # Ветка A: поверх готового процедурного рига — стыки, материалы, форма перчатки.
    # (сам флаг проверяется один раз в начале _build; здесь только применение)
    if _low_detail:
        _build_skin_visuals(v)
    # Переодевание/смена соперника пересобирает тело — слой адресного света
    # возвращаем на новые меши (при light_mask=0 ничего не делаем).
    if light_mask != 0:
        _apply_light_mask(self, light_mask)


## Слой адресного fill/rim света (ставит main при visual_level>OFF).
func set_light_mask(m: int) -> void:
    light_mask = m
    if body != null:
        _apply_light_mask(self, m)


func _apply_light_mask(node: Node, mask: int) -> void:
    if node is GeometryInstance3D:
        (node as GeometryInstance3D).layers = mask
    for ch in node.get_children():
        _apply_light_mask(ch, mask)


## v70: обувь. Общий каркас — подошва, колодка, носок, пятка, шнуровка и полоса
## сбоку; фасоны различаются высотой голенища, липучками, жёсткостью и цветом
## подошвы. Все размеры в системе стопы: -Y вниз, -Z вперёд.
## v71f: голенище высоких ботинок строится НЕ на стопе, а на кости голени:
## иначе оно встаёт вертикально, пока голень наклонена, и вокруг ноги видна
## отрывающаяся «труба». Плюс оно открытое сверху (без крышки): раньше сверху
## торчала заглушка цилиндра с веером треугольников — «консервная банка».
func _build_boot(ft: Node3D, kn: Node3D, style: String, boot: Material,
        lace: Material, band: Material, skin: Material) -> void:
    var sole_d := _mat(Color(0.06, 0.06, 0.08), 0.92)
    var sole_l := _mat(Color(0.60, 0.61, 0.65), 0.78)
    # лодыжка: стопа висит на голени на -0.42 (см. _build)
    var ay := -0.42
    if style == "bare":
        # босиком с тейпом: стопа, носок и тейп-кольцо на подъёме
        _mesh(ft, _cube(Vector3(0.175, 0.075, 0.32)), skin, Vector3(0, -0.05, -0.045))
        _mesh(ft, _cube(Vector3(0.163, 0.052, 0.09)), skin, Vector3(0, -0.055, -0.225))
        _mesh(ft, _cyl(0.102, 0.102, 0.07), band, Vector3(0, 0.02, 0.0))
        _mesh(ft, _cube(Vector3(0.15, 0.012, 0.10)), band, Vector3(0, -0.025, -0.10))
        _mesh(ft, _ball(0.035), skin, Vector3(0, -0.045, -0.30))
        return
    # общая колодка
    _mesh(ft, _cube(Vector3(0.196, 0.10, 0.33)), boot, Vector3(0, -0.03, -0.045))
    _mesh(ft, _cube(Vector3(0.176, 0.072, 0.11)), boot, Vector3(0, -0.042, -0.24))
    _mesh(ft, _cube(Vector3(0.186, 0.075, 0.10)), boot, Vector3(0, -0.045, 0.135))
    if style == "speed":
        # скоростные: тонкая светлая подошва, узкая колодка, яркая полоса
        _mesh(ft, _cube(Vector3(0.20, 0.028, 0.36)), sole_l, Vector3(0, -0.086, -0.03))
        _mesh(ft, _cube(Vector3(0.014, 0.045, 0.24)), band,
                Vector3(0.098, -0.02, -0.05))
        _mesh(ft, _cube(Vector3(0.014, 0.045, 0.24)), band,
                Vector3(-0.098, -0.02, -0.05))
        for z in [-0.14, -0.09]:
            _mesh(ft, _cube(Vector3(0.165, 0.012, 0.045)), lace,
                    Vector3(0, 0.008, float(z)))
    else:
        _mesh(ft, _cube(Vector3(0.202, 0.034, 0.365)), sole_d, Vector3(0, -0.082, -0.035))
        var stripe_mat: Material = band
        _mesh(ft, _cube(Vector3(0.014, 0.05, 0.22)), stripe_mat,
                Vector3(0.099, -0.028, -0.05))
        _mesh(ft, _cube(Vector3(0.014, 0.05, 0.22)), stripe_mat,
                Vector3(-0.099, -0.028, -0.05))
    if style == "low":
        for z in [-0.15, -0.10, -0.05]:
            _mesh(ft, _cube(Vector3(0.17, 0.012, 0.042)), lace,
                    Vector3(0, 0.012, float(z)))
    elif style == "mid":
        # голенище на голени, открытое сверху: голень входит в него
        _mesh(kn, _cyl_open(0.10, 0.10, 0.13), boot, Vector3(0, ay + 0.035, 0.005))
        for z in [-0.15, -0.10, -0.05]:
            _mesh(ft, _cube(Vector3(0.17, 0.012, 0.042)), lace,
                    Vector3(0, 0.022, float(z)))
    elif style == "hi":
        _mesh(kn, _cyl_open(0.104, 0.104, 0.19), boot, Vector3(0, ay + 0.075, 0.005))
        _mesh(kn, _cyl_open(0.106, 0.106, 0.03), band, Vector3(0, ay + 0.155, 0.005))
        # шнуровка: три полосы на подъёме стопы и две на голенище
        for z in [-0.15, -0.10, -0.05]:
            _mesh(ft, _cube(Vector3(0.17, 0.012, 0.042)), lace,
                    Vector3(0, 0.045, float(z)))
        for i in 2:
            _mesh(kn, _cube(Vector3(0.15, 0.012, 0.04)), lace,
                    Vector3(0, ay + 0.085 + float(i) * 0.045, -0.065))
    elif style == "pro":
        # профи: две липучки поперёк и белая подошва
        _mesh(ft, _cube(Vector3(0.20, 0.028, 0.365)), sole_l, Vector3(0, -0.086, -0.035))
        for z in [-0.09, -0.02]:
            _mesh(ft, _cube(Vector3(0.205, 0.026, 0.05)), band,
                    Vector3(0, 0.025, float(z)))
            _mesh(ft, _cube(Vector3(0.035, 0.03, 0.055)), lace,
                    Vector3(0.09, 0.025, float(z)))
    elif style == "classic":
        # классические: высокое голенище, длинная шнуровка, светлая подошва
        _mesh(kn, _cyl_open(0.102, 0.102, 0.21), boot, Vector3(0, ay + 0.085, 0.005))
        _mesh(ft, _cube(Vector3(0.20, 0.03, 0.365)), sole_l, Vector3(0, -0.088, -0.035))
        # нижние шнурки на подъёме, верхние — по голенищу
        for i in 4:
            _mesh(ft, _cube(Vector3(0.165, 0.010, 0.030)), lace,
                    Vector3(0, 0.02 + float(i) * 0.022, -0.14 + float(i) * 0.032))
        for i in 3:
            _mesh(kn, _cube(Vector3(0.14, 0.010, 0.028)), lace,
                    Vector3(0, ay + 0.10 + float(i) * 0.035, -0.075))
        _mesh(kn, _cyl_open(0.106, 0.106, 0.028), band, Vector3(0, ay + 0.185, 0.005))
    elif style == "wrestle":
        # борцовки: плоская подошва, широкий ремешок и манжета
        _mesh(ft, _cube(Vector3(0.20, 0.026, 0.36)), sole_l, Vector3(0, -0.086, -0.03))
        _mesh(kn, _cyl_open(0.102, 0.102, 0.16), boot, Vector3(0, ay + 0.06, 0.005))
        _mesh(ft, _cube(Vector3(0.208, 0.05, 0.07)), band, Vector3(0, 0.02, -0.06))
        _mesh(kn, _cyl_open(0.107, 0.107, 0.035), lace, Vector3(0, ay + 0.145, 0.005))


## v70: причёски. Все варианты собраны из примитивов и «сидят» на черепе:
## общий каркас — шапка-купол, виски и затылок; поверх него фасон (ирокез,
## помпадур, пучок, дреды, длинные волосы, кудри, площадка).
## Цвет берётся из look (hair_color): hm — основной, hm_d — тень, hm_l — блик.
func _hair(h: Node3D, style: String, col: Color) -> void:
    if style == "bald":
        return
    var hm := _mat(col, 0.58)
    var hm_d := _mat(col.darkened(0.30), 0.72)
    var hm_l := _mat(col.lightened(0.22), 0.52)
    # виски — почти у всех стрижек, иначе голова выглядит лысой спереди
    for sx in [-1.0, 1.0]:
        _mesh(h, _cube(Vector3(0.022, 0.07, 0.055)), hm_d,
                Vector3(0.172 * sx, 0.135, -0.01))
    match style:
        "mohawk":
            # выбритые виски — тонкая тёмная шапка, поверх гребень из 5 плавников
            var base := _mesh(h, _ball(0.187), hm_d, Vector3(0, 0.235, 0.01))
            base.scale = Vector3(1.0, 0.40, 1.0)
            for i in 5:
                var z := -0.11 + float(i) * 0.055
                var tall := 0.045 + 0.025 * float(2 - abs(i - 2))
                var fin := _mesh(h, _cube(Vector3(0.052, 0.15 + tall, 0.075)), hm,
                        Vector3(0, 0.315 + tall * 0.35, z))
                fin.rotation_degrees = Vector3(-8.0 + float(i) * 4.0, 0.0, 0.0)
        "buzz":
            # ёжик: тонкий купол + короткий затылок
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.252, 0.01))
            cap.scale = Vector3(1.03, 0.52, 1.03)
            _mesh(h, _cube(Vector3(0.20, 0.06, 0.07)), hm_d, Vector3(0, 0.17, 0.165))
        "tail":
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.235, 0.01))
            cap.scale = Vector3(1.05, 0.72, 1.05)
            # резинка и хвост из двух прядей
            _mesh(h, _cyl(0.055, 0.055, 0.045), _mat(col.darkened(0.08), 0.5),
                    Vector3(0, 0.20, 0.185))
            var t1 := _mesh(h, _caps(0.062, 0.12), hm, Vector3(0, 0.115, 0.225))
            t1.rotation_degrees = Vector3(20, 0, 0)
            var t2 := _mesh(h, _caps(0.046, 0.17), hm_l, Vector3(0, 0.01, 0.275))
            t2.rotation_degrees = Vector3(30, 0, 0)
        "afro":
            # пышный шар + «дольки» по силуэту
            var puff := _mesh(h, _ball(0.225), hm, Vector3(0, 0.33, 0.02))
            puff.scale = Vector3(1.06, 0.95, 1.06)
            for ang in 6:
                var a := TAU * float(ang) / 6.0
                _mesh(h, _ball(0.085), hm_d if ang % 2 == 0 else hm_l,
                        Vector3(cos(a) * 0.16, 0.29 + sin(a) * 0.02, 0.02 + sin(a) * 0.16))
            _mesh(h, _ball(0.09), hm, Vector3(0, 0.43, 0.02))
        "pompadour":
            # гладкая шапка + высокий волнистый кок спереди с подвёрнутым краем
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.225, 0.015))
            cap.scale = Vector3(1.02, 0.58, 1.02)
            var quiff := _mesh(h, _ball(0.145), hm, Vector3(0, 0.345, -0.085))
            quiff.scale = Vector3(1.15, 0.95, 0.85)
            quiff.rotation_degrees = Vector3(-22, 0, 0)
            var lip := _mesh(h, _ball(0.105), hm_l, Vector3(0, 0.315, -0.175))
            lip.scale = Vector3(1.05, 0.60, 0.55)
            _mesh(h, _cube(Vector3(0.23, 0.03, 0.05)), hm_d, Vector3(0, 0.265, -0.155))
        "undercut":
            # выбритые бока + гладкий верх с косой чёлкой
            var shaved := _mesh(h, _ball(0.185), hm_d, Vector3(0, 0.21, 0.01))
            shaved.scale = Vector3(1.02, 0.45, 1.02)
            var top := _mesh(h, _ball(0.19), hm, Vector3(0, 0.255, -0.005))
            top.scale = Vector3(1.0, 0.58, 1.0)
            var sweep := _mesh(h, _ball(0.10), hm_l, Vector3(0, 0.30, -0.12))
            sweep.scale = Vector3(1.1, 0.70, 0.85)
            sweep.rotation_degrees = Vector3(-14, 0, 0)
        "bun":
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.235, 0.01))
            cap.scale = Vector3(1.05, 0.70, 1.05)
            _mesh(h, _cyl(0.028, 0.028, 0.03), _mat(col.darkened(0.08), 0.5),
                    Vector3(0, 0.30, 0.13))
            _mesh(h, _ball(0.082), hm, Vector3(0, 0.355, 0.15))
            _mesh(h, _ball(0.05), hm_l, Vector3(0, 0.385, 0.125))
        "dreads":
            var cap := _mesh(h, _ball(0.187), hm_d, Vector3(0, 0.235, 0.01))
            cap.scale = Vector3(1.04, 0.66, 1.04)
            # 6 прядей по затылку и бокам
            for i in 6:
                var px := -0.15 + float(i % 3) * 0.15
                var pz := 0.10 + float(i / 3) * 0.07
                var d := _mesh(h, _caps(0.032, 0.20), hm if i % 2 == 0 else hm_l,
                        Vector3(px, 0.115, pz))
                d.rotation_degrees = Vector3(8.0, 0.0, -6.0 + float(i % 3) * 6.0)
        "long":
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.24, 0.01))
            cap.scale = Vector3(1.05, 0.70, 1.05)
            # полотно волос до плеч и две пряди у лица
            var back := _mesh(h, _caps(0.155, 0.46), hm, Vector3(0, -0.03, 0.14))
            back.scale = Vector3(0.95, 1.0, 0.55)
            var back2 := _mesh(h, _caps(0.12, 0.30), hm_l, Vector3(0, -0.22, 0.17))
            back2.scale = Vector3(0.85, 1.0, 0.5)
            for sx in [-1.0, 1.0]:
                var side := _mesh(h, _caps(0.045, 0.30), hm_d,
                        Vector3(0.165 * sx, 0.03, 0.02))
                side.rotation_degrees = Vector3(4.0, 0.0, -5.0 * sx)
        "curls":
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.24, 0.01))
            cap.scale = Vector3(1.04, 0.64, 1.04)
            # «кудри»: шарики по куполу и затылку
            for i in 10:
                var a := TAU * float(i) / 10.0
                var rr := 0.13 + 0.035 * float(i % 2)
                _mesh(h, _ball(0.062), hm if i % 2 == 0 else hm_l,
                        Vector3(cos(a) * rr, 0.30 + 0.02 * float(i % 3),
                                0.02 + sin(a) * rr))
            _mesh(h, _ball(0.075), hm, Vector3(0, 0.365, 0.02))
        "flat":
            # площадка: короткие бока + широкий ровный верх, сходящийся к макушке
            var cap := _mesh(h, _ball(0.188), hm_d, Vector3(0, 0.22, 0.005))
            cap.scale = Vector3(1.02, 0.40, 1.02)
            _mesh(h, _cyl(0.150, 0.186, 0.12), hm, Vector3(0, 0.285, 0.005))
            _mesh(h, _cyl(0.132, 0.132, 0.02), hm_l, Vector3(0, 0.348, 0.005))
        _:
            # общий купол (tail/afro и новые фасоны обрабатываются выше)
            var cap := _mesh(h, _ball(0.187), hm, Vector3(0, 0.235, 0.01))
            cap.scale = Vector3(1.05, 0.72, 1.05)


func _arm_node(parent: Node3D, pos: Vector3, skin: Material, aw: float = 1.0) -> Node3D:
    var sh := _node(parent, pos, "Shoulder")
    _mesh(sh, _ball(0.125 * aw), skin, Vector3(0, -0.02, 0))
    _mesh(sh, _caps(0.1 * aw, 0.34), skin, Vector3(0, -0.18, 0))
    return sh


func _forearm(elbow: Node3D, skin: Material, lace: Material, aw: float = 1.0,
        gr: float = 0.15, side: float = 1.0) -> void:
    _mesh(elbow, _caps(0.085 * aw, 0.3), skin, Vector3(0, -0.16, 0))
    # v71d: форма по референсу заказчика (классическая боксёрская перчатка):
    #  - широкий кулак-«рукавица»: большой округлый ударный купол + меньший
    #    тыльный кулак у запястья (двухдольный силуэт, а не идеальный шар);
    #  - ударный торец слегка приплюснут;
    #  - крупный большой палец с внутренней стороны у самого запястья;
    #  - манжета с акцентной полосой; никаких надписей и мелких бугорков.
    var fist_r := gr * 1.04
    var wrist_y := -0.30
    # манжета: расширяется от предплечья к перчатке (сращивает руку и кулак)
    _mesh(elbow, _cyl(0.10 * aw, 0.145 * aw, 0.14), glove_mat,
            Vector3(0, wrist_y, 0))
    # акцентная полоса на манжете (без текста) — заподлицо с манжетой
    _mesh(elbow, _cyl(0.118 * aw, 0.122 * aw, 0.022), lace,
            Vector3(0, wrist_y + 0.052, 0))
    # v71d: ОДНА гладкая масса кулака (как на референсе) — яйцо, вытянутое к
    # ударному торцу. Двухдольный вариант читался как «снеговик», поэтому
    # тыльную долю убрал.
    var fist := _mesh(elbow, _ball(fist_r), glove_mat,
            Vector3(0, wrist_y - 0.24, 0.0))
    fist.scale = Vector3(1.04, 1.18, 1.02)
    # приплюснутая ударная площадка спереди
    var pad := _mesh(elbow, _ball(fist_r * 0.70), glove_mat,
            Vector3(0, wrist_y - 0.24 - fist_r * 0.78, -0.006))
    pad.scale = Vector3(0.98, 0.52, 0.96)
    # большой палец: крупный, с внутренней стороны, у середины перчатки
    var thumb := _mesh(elbow, _caps(fist_r * 0.44, fist_r * 1.05), glove_mat,
            Vector3(-side * fist_r * 0.72, wrist_y - 0.13, -0.02))
    thumb.rotation_degrees = Vector3(8.0, 0.0, side * 54.0)


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


## Можно ли отменить текущий удар новым. Отмена — только в восстановлении:
## не раньше hit_at (иначе «фантомный» отменённый удар без контакта) и не
## раньше доли "cancel" от длительности (у каждого удара своя).
func can_cancel() -> bool:
    if punch_kind == "":
        return false
    var p: Dictionary = punch_info(punch_kind)
    var cancel_at: float = punch_dur * float(p.get("cancel", 1.0))
    return punch_t >= maxf(punch_hit_at, cancel_at)


func start_punch(kind: String, aim: Vector3 = Vector3.ZERO) -> bool:
    if ko or fallen or stun > 0.0 or blocking or evading:
        return false
    # новый удар в окне отмены заменяет остаток восстановления предыдущего
    if punch_kind != "" and not can_cancel():
        return false
    var p: Dictionary = punch_info(kind)
    # v57: удар НЕ отменяется из-за нехватки выносливости. Раньше здесь стоял
    # `if stamina < cost: return false` — после замедления восстановления в 3 раза
    # (v56) дорогие удары (апперкот 22, правый хук 16) просто «не нажимались».
    # Теперь на нуле сил удар всё равно идёт, но слабее (punch_power 0.55),
    # а шкала выносливости честно уходит в ноль.
    var cost := float(p["stam"])
    exhausted = stamina < cost
    punch_power = 0.55 if exhausted else 1.0
    stamina = maxf(0.0, stamina - cost)
    punch_kind = kind
    punch_t = 0.0
    punch_dur = float(p["dur"]) * dur_mult
    punch_hit_at = float(p["hit_at"]) * dur_mult
    hit_done = false
    impact_attempts = 0
    _recoil_done = false
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
    vel = vel.limit_length(MAX_SPEED * move_mult)
    return true


func try_dodge(dir: Vector3 = Vector3.ZERO) -> bool:
    if ko or stun > 0.0 or dodge_t > 0.0 or punch_kind != "":
        return false
    # v57: уклон тоже не отменяется из-за нехватки выносливости — кнопка не должна
    # молча «не работать». Шкала просто уходит в ноль.
    stamina = maxf(0.0, stamina - 12.0)
    var side := Vector3(dir.x, 0.0, dir.z)
    if side.length() > 0.12:
        dodge_kind = "slip"
        dodge_dir = side.normalized()
        dodge_dur = 0.40
        dodge_t = dodge_dur
        # скрутка в сторону: переносим вес и уводим голову с линии
        var local_side := signf(global_transform.basis.x.dot(dodge_dir))
        wob_body.kick(Vector3(0.0, 0.22, 0.0) + global_transform.basis.x * local_side * 0.55)
        wob_torso.kick(Vector3(0.25, -local_side * 0.55, local_side * 0.35))
    else:
        dodge_kind = "duck"
        dodge_dir = Vector3.ZERO
        dodge_dur = 0.34
        dodge_t = dodge_dur
        wob_body.kick(Vector3(0.0, 0.45, -0.35))
        wob_torso.kick(Vector3(0.55, 0.0, 0.0))
    evading = true
    counter_t = 0.0
    return true


## v71k: прогресс уклона (0 — старт, 1 — конец) и окно скольжения.
func dodge_age() -> float:
    return clampf(dodge_dur - dodge_t, 0.0, dodge_dur)


func in_slip_window() -> bool:
    if not evading:
        return false
    # тесты/старые вызовы ставят evading=true без dodge_t — сохраняем прежнее
    # поведение (полная неуязвимость), чтобы не ломать gate-тесты.
    if dodge_t <= 0.001:
        return true
    var age := dodge_age()
    return age >= DODGE_SAFE_AFTER and age <= DODGE_SAFE_UNTIL


func take_hit(dmg: float, push: Vector3) -> void:
    # i-frames: пока лежим или встаём, урон не проходит (даже если main.gd
    # забыл проверить состояние)
    if is_invulnerable():
        return
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
    if ko or fallen or knock_state != KnockState.NONE:
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
    invuln_t = 0.0
    ko = false
    ko_fall = 0.0
    ko_lying = false
    ko_settle_t = 0.0
    ko_settle_allowed = true
    punch_kind = ""
    punch_t = 0.0
    punch_aim = Vector3.ZERO
    _punch_guard_off = Vector3.ZERO
    hit_done = false
    impact_attempts = 0
    _recoil_done = false
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
    knock_state = KnockState.NONE
    knock_t = 0.0
    knockdown_count = 0
    get_up_progress = 0.0
    # v68: сбрасываем «выдохся» вместе с остальным состоянием
    exhaust_down = false
    exhaust_getup = false
    exhaust_t = 0.0
    exhaust_last = 0.0
    # T10: победная поза сбрасывается на новый бой
    victory = false
    victory_t = 0.0
    _stam_prev = max_stamina
    _settle_blend = 1.0
    _settle_from_quat = Quaternion.IDENTITY
    _settle_from_pos = Vector3.ZERO
    _down_quat = Quaternion.IDENTITY
    _down_pos = Vector3.ZERO
    surface_friction = 1.0
    stamina_drain = 0.0
    wind = Vector3.ZERO
    gravity_mult = 1.0
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
    hit_done = false
    impact_attempts = 0
    _recoil_done = false
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
    # Пакет 2 / T6: пока тело в ragdoll — «мышечный тонус» (не тряпка)
    if ragdoll != null:
        _ragdoll_muscle(dt)
        _ragdoll_rest(dt)
    stun = maxf(0.0, stun - dt)
    flash = maxf(0.0, flash - dt)
    _hit_t = maxf(0.0, _hit_t - dt)
    if dodge_t > 0.0:
        dodge_t = maxf(0.0, dodge_t - dt)
        if dodge_t <= 0.0:
            # после скольжения — короткое окно контратаки
            counter_t = 0.22
            evading = false
    evading = dodge_t > 0.0
    counter_t = maxf(0.0, counter_t - dt)
    var regen := STAM_REGEN_BLOCK if blocking else STAM_REGEN
    if evading:
        regen = STAM_REGEN_EVADE
    # v68: пока лежит или встаёт от усталости — силы не восстанавливаются
    if exhaust_down or exhaust_getup:
        regen = 0.0
    # v68: ноль выносливости → боец валится на настил по-настоящему (ragdoll),
    # а не просто приседает. Проверяем ДО восстановления: иначе кадровый +0.12
    # уже «не ноль».
    if not exhaust_down and not exhaust_getup and not ko and not fallen \
            and knock_state == KnockState.NONE \
            and stamina <= 0.01 and _stam_prev > 0.01:
        start_exhaust()
    stamina = clampf(stamina + regen * stam_mult * dt, 0.0, max_stamina)
    # Этап 4: доп. расход выносливости и постоянный ветер арены
    if stamina_drain > 0.0:
        stamina = maxf(0.0, stamina - stamina_drain * dt)
    _stam_prev = stamina
    # v71p: тикаем окно неуязвимости после подъёма
    if invuln_t > 0.0:
        invuln_t = maxf(0.0, invuln_t - dt)
    if wind != Vector3.ZERO and not ko and not fallen:
        # v71m: ветер арены — ПОРЫВАМИ с нулевым средним, а не постоянным сносом.
        # Раньше `vel += wind * dt` давал установившуюся скорость wind/трение
        # (~0.9 м/с на «Крыше»), и обоих бойцов сдувало за край ринга: бой
        # кончался поражением через 2 секунды после старта («моментальный
        # накаут»). Теперь снос ограничен: смещение не копится, а качается
        # вокруг нуля, порыв виден, но сам по себе за канаты не выносит.
        vel += wind * sin(_clock * 0.85 + _ph) * 0.75 * dt

    if fallen:
        # тело «приезжает» туда, где осел ragdoll, чтобы не телепортироваться
        if ragdoll_parts.has("pelvis"):
            var prb: RigidBody3D = ragdoll_parts["pelvis"]
            position.x = prb.global_position.x
            position.z = prb.global_position.z
        if exhaust_down or exhaust_getup:
            # v68: упал от усталости — лежим, пока тело не осядет на настил,
            # потом встаём сами (это не нокдаун: таймер и «ВСТАТЬ» не нужны)
            if exhaust_getup:
                knock_t += dt
                if knock_t >= maxf(get_up_duration, 0.01):
                    _finish_exhaust_up()
            else:
                exhaust_t = maxf(0.0, exhaust_t - dt)
                if exhaust_t <= 0.0:
                    _exhaust_wait += dt
                    if _ragdoll_settled() or _exhaust_wait >= 0.6:
                        _exhaust_begin_up()
        elif knock_state != KnockState.NONE:
            # настоящий нокдаун: сам не встаём — решение принимает main.gd
            if knock_state == KnockState.FALLING:
                knock_t += dt
                # «downed» — когда тело уже на полу, а не в полёте: иначе поза
                # лежа снимается с ещё летящего ragdoll и подъём выглядит криво.
                # v71b: не даём ragdoll «кувыркаться» слишком долго — иначе в
                # кадре видно запутанные руки/ноги («моделька ломается»).
                var settled: bool = knock_t >= fall_hold + 0.6 or \
                        (knock_t >= fall_hold and _ragdoll_settled())
                if settled:
                    _enter_downed()
            elif knock_state == KnockState.GETUP:
                knock_t += dt
                if knock_t >= maxf(get_up_duration, 0.01):
                    _finish_get_up()
        else:
            # потеря баланса (не нокдаун по HP): поднимаемся сами, как раньше
            down_t -= dt
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
        # Активное окно попадания [hit_at, hit_at + hit_window]: пробуем каждый
        # кадр, пока main не подтвердит контакт (hit_done). Одиночный кадр
        # больше не решает исход удара. Если кадр перескочил всё окно (сильный
        # лаг), всё равно даём одну попытку — как раньше в точке hit_at.
        if not hit_done and punch_t >= punch_hit_at \
                and (punch_t <= punch_hit_at + hit_window or impact_attempts == 0):
            impact_attempts += 1
            impact.emit(punch_kind)
            # отдача удара: рука отпружинивает назад — один раз, даже на промах
            if not _recoil_done:
                _recoil_done = true
                var arm: Wob = wob_sh_l if str(p["arm"]) == "l" else wob_sh_r
                arm.kick(Vector3(-7.5, 0.0, 0.0))
                wob_torso.kick(Vector3(-1.9, 0.0, 0.0))
        if punch_t >= punch_dur:
            punch_kind = ""
            punch_aim = Vector3.ZERO

    if ko:
        ko_fall = minf(1.0, ko_fall + dt * 2.0)
        # v71e: КО-падение живёт в ragdoll ~секунду, затем тело оседает в
        # авторскую позу лежа (та же, что при нокдауне). Иначе физика оставляет
        # клубок из рук/ног до конца боя — «сломанная моделька».
        if ragdoll != null and not ko_lying and ko_settle_allowed:
            ko_settle_t += dt
            if ko_settle_t >= 1.15 or (ko_settle_t >= 0.55 and _ragdoll_settled()):
                _enter_ko_lying()

    _animate(dt)


# ------------------------------------------------------------------ корневая физика

func drive(dir: Vector3, dt: float) -> void:
    if ko or fallen or stun > 0.0:
        return
    if dir.length() < 0.01:
        return
    dir = Vector3(dir.x, 0.0, dir.z).normalized()
    var accel := ACCEL * move_mult / maxf(0.35, surface_friction)
    if blocking:
        accel *= 0.5
    vel += dir * accel * dt
    var max_speed := MAX_SPEED * move_mult
    if vel.length() > max_speed:
        vel = vel.normalized() * max_speed


func _body_physics(dt: float) -> void:
    var friction := (4.0 if vel.length() > 0.3 else 7.5) \
            * clampf(surface_friction, 0.35, 2.5)
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
    # v71c: ragdoll писал bone.basis напрямую (там были и Y/Z-повороты). Поза и
    # ragdoll-лимиты задают только X, поэтому после подъёма у локтей/коленей
    # оставался «винт» из ragdoll — руки смотрели в стороны и выглядели
    # сломанными. Полный сброс поворотов костей перед возвратом в стойку.
    for n in [torso, head, th_l, th_r, kn_l, kn_r, sh_l, sh_r, el_l, el_r,
            ft_l, ft_r]:
        if n != null:
            n.rotation = Vector3.ZERO
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


## v68: выносливость ушла в ноль — боец не приседает, а валится на настил.
## Тело уходит в обычный ragdoll (как при нокдауне), но это НЕ нокдаун: HP не
## теряется, счётчик нокдаунов не растёт, лежачего не добивают. Лежит
## EXHAUST_LIE секунд, потом встаёт той же анимацией подъёма, что после нокдауна.
## Работает и для игрока, и для ИИ.
func start_exhaust() -> bool:
    if ko or fallen or knock_state != KnockState.NONE or exhaust_down or exhaust_getup:
        return false
    exhaust_down = true
    exhaust_getup = false
    exhaust_t = EXHAUST_LIE
    _exhaust_wait = 0.0
    stun = maxf(stun, EXHAUST_LIE + get_up_duration)
    punch_kind = ""
    punch_aim = Vector3.ZERO
    punch_t = 0.0
    blocking = false
    evading = false
    dodge_t = 0.0
    vel = Vector3.ZERO
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    stamina = 0.0
    exhausted = true
    punch_power = 0.55
    exhaust_last = EXHAUST_LIE + get_up_duration
    # падаем назад: ноги подламываются, корпус клюёт, тело валится на настил.
    fallen = true
    down_t = 0.0
    enter_ragdoll(Vector3.ZERO)
    # Общий крен назад вокруг точки опоры (стопы). Просто «раскрутить» все части
    # бесполезно: стопы стоят на настиле и трение гасит вращение — тело оседало
    # на корточки. Задаём скорости как у жёсткого поворота вокруг стоп: верх
    # уходит назад, ноги остаются на месте — фигура гарантированно заваливается.
    var omega: Vector3 = global_transform.basis.x.normalized() * 1.9
    for key in ragdoll_parts:
        var rb: RigidBody3D = ragdoll_parts[key]
        if rb == null:
            continue
        rb.linear_velocity = omega.cross(rb.global_position - global_position)
        rb.angular_velocity = omega
    return true


## Тело улеглось на настил: переводим ragdoll в обычную позу лежа и запускаем
## ту же анимацию подъёма, что после нокдауна (без счётчиков и таймера «ВСТАТЬ»).
func _exhaust_begin_up() -> void:
    exhaust_down = false
    exhaust_getup = true
    knock_t = 0.0
    get_up_progress = 0.0
    _down_quat = Quaternion(Vector3.RIGHT, 1.5)
    var rb: RigidBody3D = ragdoll_parts.get("pelvis")
    if rb != null:
        var pelvis := rb.global_position
        var hip_pt := to_local(pelvis)
        # стартовая поза для плавного перехода ragdoll → поза лежа
        _settle_from_quat = rb.global_transform.basis.orthonormalized().get_rotation_quaternion()
        _settle_from_pos = hip_pt - _settle_from_quat * Vector3(0.0, _hip_h_dyn, 0.0)
        hip_pt.y = 0.20
        _down_pos = hip_pt - _down_quat * Vector3(0.0, _hip_h_dyn, 0.0)
    else:
        _settle_from_quat = _down_quat
        _settle_from_pos = Vector3(0.0, -0.82, 0.0)
        _down_pos = _settle_from_pos
    _settle_blend = 0.0
    clear_ragdoll()


## Встал после усталости: возвращаем управление и часть сил.
func _finish_exhaust_up() -> void:
    exhaust_down = false
    exhaust_getup = false
    exhaust_t = 0.0
    fallen = false
    knock_t = 0.0
    down_t = 0.0
    body.basis = Basis.IDENTITY
    body.position = Vector3.ZERO
    vel = Vector3.ZERO
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    stun = 0.0
    _rig_reset()
    _settle_pose()
    stamina = clampf(EXHAUST_RECOVER, 0.0, max_stamina)
    exhausted = false
    punch_power = 1.0
    _stam_prev = stamina


func _cancel_exhaust() -> void:
    if exhaust_down or exhaust_getup:
        exhaust_down = false
        exhaust_getup = false
        exhaust_t = 0.0


func _fall_down(boost: Vector3 = Vector3.ZERO) -> void:
    if fallen or ko or knock_state != KnockState.NONE:
        return
    _cancel_exhaust()
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
    _cancel_exhaust()
    fallen = false
    clear_ragdoll()
    _rig_reset()
    _settle_pose()
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    vel = Vector3.ZERO
    stun = 0.45
    stamina = maxf(stamina, 45.0)
    wob_body.kick(Vector3(0.0, 1.5, 0.0))
    wob_torso.kick(Vector3(0.8, 0.0, 0.0))


# ------------------------------------------------------- нокдаун и подъём

## Удары, блок, уклон и шаг во время нокдауна недоступны.
func is_down() -> bool:
    return knock_state != KnockState.NONE


## Пока лежим, встаём или ещё 2 с после подъёма — урон не проходит
## (v71p: без окна неуязвимости после подъёма игрока роняли повторно сразу же).
func is_invulnerable() -> bool:
    return (knockdown_invulnerable and knock_state != KnockState.NONE) or invuln_t > 0.0


## v71p: окно неуязвимости после подъёма (секунды).
func start_invuln(seconds: float) -> void:
    invuln_t = maxf(invuln_t, seconds)


## Сколько ещё действует окно неуязвимости (для HUD/тестов).
func invuln_left() -> float:
    return invuln_t


## HP дошло до нуля: падаем в нокдаун. Это замена KO-ветке, пока у бойца
## остались попытки (их считает main.gd по max_knockdowns).
func start_knockdown(impulse: Vector3 = Vector3.ZERO) -> bool:
    if ko or knock_state != KnockState.NONE:
        return false
    hp = 0.0
    ko = false
    # v71: считаем нокдаун в момент падения (main.gd заранее знает, что это не
    # третье падение). От счётчика зависит доля восстановления HP.
    knockdown_count += 1
    knock_state = KnockState.FALLING
    knock_t = 0.0
    get_up_progress = 0.0
    fallen = true
    down_t = 0.0
    _cancel_exhaust()
    stun = maxf(stun, fall_hold + get_up_duration + 0.2)
    punch_kind = ""
    punch_aim = Vector3.ZERO
    _punch_guard_off = Vector3.ZERO
    blocking = false
    evading = false
    dodge_t = 0.0
    vel = Vector3.ZERO
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    var imp := impulse
    if imp.length() < 0.5:
        imp = -global_transform.basis.z * 2.0 + Vector3(0.0, 1.4, 0.0)
    enter_ragdoll(imp)
    knocked_down.emit()
    knockdown_started.emit()
    return true


## Тело уже лежит на полу и почти не двигается.
func _ragdoll_settled() -> bool:
    var rb: RigidBody3D = ragdoll_parts.get("pelvis")
    if rb == null:
        return true
    var p := rb.global_position
    # v71l: границы вынесены в экспорт — на 20×20 арене тело может осесть
    # далеко от центра, и жёсткие ±3.4 оставляли его в FALLING навсегда.
    return p.y < settle_max_y and rb.linear_velocity.length() < settle_max_speed \
            and absf(p.x) < settle_radius and absf(p.z) < settle_radius


## Тело осело: снимаем позу лежа и переходим в «downed» — только теперь main.gd
## запускает 10-секундный таймер и показывает подсказку.
func _enter_downed() -> void:
    knock_state = KnockState.DOWNED
    knock_t = 0.0
    get_up_progress = 0.0
    var rb: RigidBody3D = ragdoll_parts.get("pelvis")
    if rb != null:
        var pelvis := rb.global_position
        # Ориентацию лежачего тела задаём сами: таз ragdoll после падения часто
        # остаётся почти вертикальным, и «лежа» выглядело как присед. Ложим на
        # спину, головой от соперника — как после пропущенного удара.
        _down_quat = Quaternion(Vector3.RIGHT, 1.5)
        var hip_pt := to_local(pelvis)
        # T6: стартовая поза для плавного перехода ragdoll → поза лежа
        _settle_from_quat = rb.global_transform.basis.orthonormalized().get_rotation_quaternion()
        _settle_from_pos = hip_pt - _settle_from_quat * Vector3(0.0, _hip_h_dyn, 0.0)
        # лежачее тело кладём на пол: таз на высоте полуроста корпуса, а не там,
        # где оказался таз ragdoll (тот часто висит на куче других частей)
        hip_pt.y = 0.20
        _down_pos = hip_pt - _down_quat * Vector3(0.0, _hip_h_dyn, 0.0)
    else:
        _down_quat = Quaternion(Vector3.RIGHT, 1.5)
        _down_pos = Vector3(0.0, -0.82, 0.0)
        _settle_from_quat = _down_quat
        _settle_from_pos = _down_pos
    # T6: 0.2–0.4 с скелет плавно «въезжает» из позы ragdoll в позу лежа,
    # иначе в момент подмены модели тело прыгает одним кадром
    _settle_blend = 0.0
    # ragdoll на полу уже не нужен: дальше лежит и встаёт обычный скелет,
    # поэтому поза лежа → подъём идут без подмены модели
    clear_ragdoll()
    downed.emit()


## v71e: КО-тело осело. Переводим ragdoll в авторскую позу лежа — ту же, что
## при нокдауне (таблица подъёма, ключ t=0): тело на спине, руки раскинуты на
## настиле. Дальше позу держит _getup_pose с knock_t = 0, физика больше не крутит.
func _enter_ko_lying() -> void:
    if ko_lying:
        return
    ko_lying = true
    knock_t = 0.0
    get_up_progress = 0.0
    vel = Vector3.ZERO
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    _down_quat = Quaternion(Vector3.RIGHT, 1.5)
    var rb: RigidBody3D = ragdoll_parts.get("pelvis")
    if rb != null:
        var pelvis := rb.global_position
        var hip_pt := to_local(pelvis)
        _settle_from_quat = rb.global_transform.basis.orthonormalized() \
                .get_rotation_quaternion()
        _settle_from_pos = hip_pt - _settle_from_quat * Vector3(0.0, _hip_h_dyn, 0.0)
        # кладём ровно на настил, а не туда, где оказался таз физики
        hip_pt.y = 0.20
        _down_pos = hip_pt - _down_quat * Vector3(0.0, _hip_h_dyn, 0.0)
    else:
        _down_pos = Vector3(0.0, -0.82, 0.0)
        _settle_from_quat = _down_quat
        _settle_from_pos = _down_pos
    _settle_blend = 0.0
    clear_ragdoll()


## Подъём запускается только из «downed»: во время падения встать нельзя.
func begin_get_up() -> bool:
    if knock_state != KnockState.DOWNED:
        return false
    knock_state = KnockState.GETUP
    knock_t = 0.0
    get_up_progress = 0.0
    clear_ragdoll()
    _rig_reset()
    vel = Vector3.ZERO
    stun = maxf(stun, get_up_duration * 0.5)
    get_up_started.emit()
    return true


## Одно «нажатие на подъём»: добавляет 1/N прогресса. Возвращает накопленное
## значение; 1.0 — можно вставать. Вызывать только в состоянии DOWNED.
func get_up_press() -> float:
    if knock_state != KnockState.DOWNED:
        return 0.0
    get_up_progress = clampf(get_up_progress + 1.0 / maxf(float(get_up_presses), 1.0),
            0.0, 1.0)
    return get_up_progress


## Остывание прогресса, если игрок перестал жать.
func get_up_cool(dt: float) -> void:
    if knock_state != KnockState.DOWNED:
        return
    get_up_progress = maxf(0.0, get_up_progress - get_up_decay * dt)


func _finish_get_up() -> void:
    knock_state = KnockState.NONE
    knock_t = 0.0
    fallen = false
    down_t = 0.0
    body.basis = Basis.IDENTITY
    body.position = Vector3.ZERO
    vel = Vector3.ZERO
    tilt = Vector2.ZERO
    tilt_vel = Vector2.ZERO
    # управление возвращается сразу: после анимации подъёма боец в стойке
    stun = 0.0
    _rig_reset()
    # v71c: полный сброс позы/пружин в стойку (а не только _apply_pose): иначе
    # после ragdoll оставались «накопленные» кватернионы плеч и руки вставали
    # криво (локти в стороны) — заказчик видел это как сломанные руки.
    _settle_pose()
    # v71: счётчик нокдаунов растёт при ПАДЕНИИ (см. start_knockdown), а не при
    # подъёме — иначе третье падение переживалось и КО наступало только на
    # четвёртом, хотя заказчик просил «3 нокдауна — победа нокаутом».
    get_up_finished.emit()


## Таблица подъёма (v66). Поля: t — доля времени, p — наклон корпуса назад
## (рад, 1.5 — лежим, 0 — стоим), roll — поворот на бок, hy — высота таза,
## dz — сдвиг таза вперёд/назад, torso/head — изгиб корпуса и головы,
## legs — [бедро_л, колено_л, бедро_п, колено_п], al/ar — куда смотрят плечи,
## el_l/el_r — сгиб локтя (2.4 — рука у подбородка, 0.2 — почти прямая).
func _getup_table() -> Array:
    if not _getup_keys.is_empty():
        return _getup_keys
    _getup_keys = [
        # 0.00 — лежим на спине, руки раскинуты в стороны и лежат на настиле
        # (v71: раньше руки смотрели «вперёд» и из-за перспективы выглядели
        # поднятыми вверх — заказчик описал это как «после падения ломаются руки»)
        {"t": 0.00, "p": 1.50, "roll": 0.00, "hy": 0.20, "dz": 0.00,
            "torso": 0.00, "head": 0.00, "legs": [0.10, -0.32, -0.06, -0.28],
            "al": Vector3(-0.30, -0.92, 0.20), "el_l": 0.55,
            "ar": Vector3(0.30, -0.92, 0.20), "el_r": 0.55},
        # 0.08 — пришли в себя: голова отрывается от пола, колени подтягиваются,
        # руки поджимаются к груди (иначе на боку перчатка уходит в пол)
        {"t": 0.08, "p": 1.36, "roll": 0.12, "hy": 0.25, "dz": -0.02,
            "torso": 0.42, "head": 0.35, "legs": [0.62, -0.95, 0.46, -0.84],
            "al": Vector3(-0.45, -0.55, 0.70), "el_l": 1.15,
            "ar": Vector3(0.45, -0.55, 0.70), "el_r": 1.15},
        # 0.20 — завалились на бок, руки ставятся на пол, колени под корпусом
        {"t": 0.20, "p": 1.02, "roll": 0.38, "hy": 0.33, "dz": -0.04,
            "torso": 0.72, "head": 0.10, "legs": [1.05, -1.60, 0.95, -1.50],
            "al": Vector3(-0.50, -0.45, 0.74), "el_l": 1.05,
            "ar": Vector3(0.50, -0.45, 0.74), "el_r": 1.05},
        # 0.31 — руки отжимают корпус: голова уходит вниз, таз между колен
        {"t": 0.31, "p": 0.62, "roll": 0.20, "hy": 0.42, "dz": -0.03,
            "torso": 0.85, "head": 0.05, "legs": [0.50, -2.05, 0.55, -1.95],
            "al": Vector3(-0.44, -0.22, 0.87), "el_l": 0.55,
            "ar": Vector3(0.44, -0.22, 0.87), "el_r": 0.55},
        # 0.42 — четвереньки: колени на полу, руками упирается в пол
        {"t": 0.42, "p": 0.32, "roll": 0.06, "hy": 0.45, "dz": -0.02,
            "torso": 0.95, "head": 0.00, "legs": [0.22, -2.05, 0.26, -1.95],
            "al": Vector3(-0.40, -0.05, 0.92), "el_l": 0.20,
            "ar": Vector3(0.40, -0.05, 0.92), "el_r": 0.20},
        # 0.58 — ставим правую стопу вперёд, левое колено ещё на полу
        {"t": 0.58, "p": 0.20, "roll": 0.02, "hy": 0.54, "dz": 0.00,
            "torso": 0.74, "head": -0.10, "legs": [0.22, -2.05, 1.15, -1.50],
            "al": Vector3(-0.34, -0.75, 0.56), "el_l": 0.85,
            "ar": Vector3(0.34, -0.75, 0.56), "el_r": 0.85},
        # 0.72 — встаём с колена: ноги разгибаются, руки уходят от пола
        {"t": 0.72, "p": 0.14, "roll": 0.00, "hy": 0.72, "dz": 0.02,
            "torso": 0.50, "head": -0.08, "legs": [0.55, -1.20, 0.85, -1.05],
            "al": Vector3(-0.30, -0.90, 0.30), "el_l": 0.55,
            "ar": Vector3(0.30, -0.90, 0.30), "el_r": 0.55},
        # 0.85 — почти встал, корпус разгибается, руки идут к подбородку
        {"t": 0.85, "p": 0.05, "roll": 0.00, "hy": 0.93, "dz": 0.01,
            "torso": 0.14, "head": 0.00, "legs": [0.22, -0.42, 0.20, -0.38],
            "al": Vector3(-0.24, -1.00, 0.06), "el_l": 0.50,
            "ar": Vector3(0.24, -1.00, 0.06), "el_r": 0.50},
        # 0.94 — перелёт: чуть выше нормы и с лёгким наклоном назад
        {"t": 0.94, "p": -0.03, "roll": 0.00, "hy": 0.96, "dz": 0.00,
            "torso": -0.05, "head": 0.02, "legs": [0.12, -0.34, -0.04, -0.28],
            "al": Vector3(-0.22, -1.00, 0.02), "el_l": 0.55,
            "ar": Vector3(0.22, -1.00, 0.02), "el_r": 0.55},
        # 1.00 — стойка (дальше _finish_get_up ставит позу стража)
        {"t": 1.00, "p": 0.00, "roll": 0.00, "hy": 0.95, "dz": 0.00,
            "torso": 0.00, "head": 0.00, "legs": [0.10, -0.32, -0.06, -0.28],
            "al": Vector3(-0.22, -1.00, 0.00), "el_l": 0.55,
            "ar": Vector3(0.22, -1.00, 0.00), "el_r": 0.55},
    ]
    return _getup_keys


## Процедурная анимация подъёма (v66): поза таза + наклон корпуса + работа ног
## и рук по ключевым кадрам. Тело не «разворачивается колом» вокруг точки
## опоры, а сначала заваливается на бок и встаёт на четвереньки, потом
## подтягивает колено и только затем разгибается в стойку.
func _getup_pose(dt: float) -> void:
    var keys: Array = _getup_table()
    var f := clampf(knock_t / maxf(get_up_duration, 0.01), 0.0, 1.0)
    # T6: сначала 0.2–0.4 с плавного перехода из позы ragdoll в позу лежа
    _settle_blend = minf(1.0, _settle_blend + dt / SETTLE_BLEND)
    var sw := smoothstep(0.0, 1.0, _settle_blend)
    var lie_q: Quaternion = _settle_from_quat.slerp(_down_quat, sw).normalized()
    var lie_p: Vector3 = _settle_from_pos.lerp(_down_pos, sw)
    # таз той позы, в которой тело лежит (ось «таз → пол» у лежачего тела)
    var lie_hip: Vector3 = lie_p + lie_q * Vector3(0.0, _hip_h_dyn, 0.0)
    # кадр, внутри которого находимся, и плавная доля внутри него
    var ia := 0
    for i in range(keys.size() - 1):
        if f >= float(keys[i]["t"]):
            ia = i
    var a: Dictionary = keys[ia]
    var b: Dictionary = keys[mini(ia + 1, keys.size() - 1)]
    var span := maxf(float(b["t"]) - float(a["t"]), 0.001)
    var u := clampf((f - float(a["t"])) / span, 0.0, 1.0)
    var su := u * u * (3.0 - 2.0 * u)
    # ориентация корпуса: наклон (из лежачего в вертикаль) + поворот на бок
    var qa: Quaternion = Quaternion(Vector3.RIGHT, float(a["p"])) \
            * Quaternion(Vector3.BACK, float(a["roll"]))
    var qb: Quaternion = Quaternion(Vector3.RIGHT, float(b["p"])) \
            * Quaternion(Vector3.BACK, float(b["roll"]))
    var q: Quaternion = qa.slerp(qb, su).normalized()
    var qq: Quaternion = lie_q.slerp(q, sw).normalized()
    # пока не поймал равновесие — тело покачивается, к стойке качание сходит
    var sway := sin(f * 33.0) * 0.05 * (1.0 - f) * (1.0 - f)
    body.basis = Basis(qq) * Basis(Vector3.BACK, sway)
    # таз: поднимается по кадрам, а боковое смещение от падения сходит на нет,
    # к концу боец стоит ровно над своей точкой (корень — на месте)
    var k_hz := smoothstep(0.10, 0.80, f)
    var dz := lerpf(float(a["dz"]), float(b["dz"]), su)
    var hip_key := Vector3(lerpf(lie_hip.x, 0.0, k_hz),
            lerpf(float(a["hy"]), float(b["hy"]), su),
            lerpf(lie_hip.z, dz, k_hz))
    var hip: Vector3 = lie_hip.lerp(hip_key, sw)
    body.position = hip - qq * Vector3(0.0, _hip_h_dyn, 0.0)
    hips.position = Vector3(0.0, _hip_h_dyn, 0.0)
    hips.rotation = Vector3.ZERO
    # корпус: изгиб вперёд + пружина
    var tp := lerpf(float(a["torso"]), float(b["torso"]), su)
    torso.rotation = Vector3(tp, 0.0, 0.0) + wob_torso.step(dt, 62.0, 6.5) * 0.4
    # ноги: колени подтягиваются, потом разгибаются в стойку
    var la: Array = a["legs"]
    var lb: Array = b["legs"]
    var th_l_v := lerpf(float(la[0]), float(lb[0]), su)
    var kn_l_v := lerpf(float(la[1]), float(lb[1]), su)
    var th_r_v := lerpf(float(la[2]), float(lb[2]), su)
    var kn_r_v := lerpf(float(la[3]), float(lb[3]), su)
    # страховка: голеностоп не должен уходить под настил (в фазах переката на
    # бок и четверенек стопа иначе проваливается на 6–11 см)
    kn_l_v = _getup_foot_clamp(hip.y, qq, th_l_v, kn_l_v)
    kn_r_v = _getup_foot_clamp(hip.y, qq, th_r_v, kn_r_v)
    th_l.rotation = Vector3(th_l_v, 0.0, 0.0)
    kn_l.rotation = Vector3(kn_l_v, 0.0, 0.0)
    th_r.rotation = Vector3(th_r_v, 0.0, 0.0)
    kn_r.rotation = Vector3(kn_r_v, 0.0, 0.0)
    # стопа держится параллельно полу: гасим наклон корпуса и сгибы ноги
    var pitch_now := lerpf(float(a["p"]), float(b["p"]), su)
    ft_l.basis = Basis(Vector3.RIGHT, -(pitch_now + th_l_v + kn_l_v))
    ft_r.basis = Basis(Vector3.RIGHT, -(pitch_now + th_r_v + kn_r_v))
    # руки: упор в пол → подхват колена → стойка у подбородка
    var al: Vector3 = (a["al"] as Vector3).lerp(b["al"], su).normalized()
    var ar: Vector3 = (a["ar"] as Vector3).lerp(b["ar"], su).normalized()
    var sh_l_v: Vector3 = Quaternion(Vector3.DOWN, al).get_euler()
    var sh_r_v: Vector3 = Quaternion(Vector3.DOWN, ar).get_euler()
    var gk := smoothstep(0.45, 0.80, f)
    # v71c: к стойке идём кватернионом, а не линейной интерполяцией углов Эйлера.
    # Раньше на середине перехода (f≈0.8) плечо получало промежуточные Y/Z —
    # руки вставали «буквой П» (локти в стороны, перчатки у головы), и после
    # подъёма от усталости это выглядело как сломанные руки.
    var q_sh_l: Quaternion = Quaternion.from_euler(sh_l_v).slerp(
            Quaternion.from_euler(SH_GUARD_L), gk).normalized()
    var q_sh_r: Quaternion = Quaternion.from_euler(sh_r_v).slerp(
            Quaternion.from_euler(SH_GUARD_R), gk).normalized()
    _apply_pose(SH_GUARD_L,
            lerpf(lerpf(float(a["el_l"]), float(b["el_l"]), su), EL_GUARD_L, gk),
            SH_GUARD_R,
            lerpf(lerpf(float(a["el_r"]), float(b["el_r"]), su), EL_GUARD_R, gk),
            clampf(dt * 20.0, 0.0, 1.0), q_sh_l, q_sh_r)
    # голова: сначала поднимаем (смотрим, где ринг), к стойке — прямо
    var hd := lerpf(float(a["head"]), float(b["head"]), su)
    var hb := wob_head.step(dt, 46.0, 5.5)
    head.rotation = Vector3(hd + hb.x, hb.y, hb.z)


## Страховка подъёма: голеностоп не ниже GETUP_FOOT_MIN над настилом.
## Считаем реальную высоту голеностопа по углам ноги (таз + поворот корпуса) и,
## если стопа провалилась, догибаем колено — стопа уходит назад и вверх, как при
## настоящей постановке ноги. Возвращает скорректированный угол колена.
func _getup_foot_clamp(hip_y: float, q: Quaternion, th: float, kn: float) -> float:
    var fixed := kn
    for i in 10:
        var ankle: Vector3 = Vector3(0.0,
                -LEG_UP * cos(th) - LEG_LO * cos(th + fixed),
                -LEG_UP * sin(th) - LEG_LO * sin(th + fixed))
        var ankle_y: float = hip_y + (q * ankle).y
        if ankle_y >= GETUP_FOOT_MIN or fixed <= -2.60:
            break
        fixed -= 0.08
    return fixed


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
    # --- локти: углом (перехода через ±π там нет, сглаживаем как раньше)
    var sl := sk if q_l != null else s
    var sr := sk if q_r != null else s
    var el := lerpf(_t_l_el, l_el, sl)
    var er := lerpf(_t_r_el, r_el, sr)
    wob_el_l.kick(Vector3(-(el - _t_l_el) * 0.6, 0.0, 0.0))
    wob_el_r.kick(Vector3(-(er - _t_r_el) * 0.6, 0.0, 0.0))
    _t_l_el = el
    _t_r_el = er
    # --- плечи: ВСЕГДА кватернионами (v67). Раньше стойка/блок шли через углы
    # Эйлера: на боковых ударах представление перескакивало через ±π и кость
    # дёргалась до 50-57° за кадр. Кватернион такого разрыва не имеет.
    var want_l: Quaternion = Quaternion.from_euler(l_sh)
    var want_r: Quaternion = Quaternion.from_euler(r_sh)
    if q_l != null:
        want_l = q_l
    if q_r != null:
        want_r = q_r
    _pq_l = _step_sh_q(sh_l, wob_sh_l, _pq_l, want_l, sl, _pq_l_on)
    _pq_r = _step_sh_q(sh_r, wob_sh_r, _pq_r, want_r, sr, _pq_r_on)
    _pq_l_on = true
    _pq_r_on = true
    # углы Эйлера держим в актуальном виде: их читают отладочные замеры
    _t_l_sh = sh_l.rotation
    _t_r_sh = sh_r.rotation

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
        # v67: отскок пружины мягче (было 1.2 и ограничение 0.20 рад) — на хуках
        # кость «резинила» и давала лишние 10° дёрганья на контактном кадре
        w.kick(-d.get_axis() * ang * 0.55)
    var wo := w.step(_dt, 110.0, 8.0).limit_length(0.10)
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
    var body_turn := 0.0
    var foot_side := ""
    var foot_yaw := 0.0
    var foot_heel := 0.0
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
        # всё тело доворачивается в сторону удара, ударная стопа разворачивается
        # на носке и приподнимает пятку — как в технике бокса
        var path_turn := float(path.get("turn", 0.0))
        body_turn = path_turn * float(d["tw"])
        foot_side = "l" if str(path.get("foot", "back")) == "front" else "r"
        foot_yaw = signf(path_turn) * float(path.get("pivot", 0.0)) * float(d["tw"])
        foot_heel = float(path.get("heel", 0.0)) * float(d["hit"])
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
            if anim == "upper_l" or anim == "upper":
                var wind_l := clampf(t01 * 3.0, 0.0, 1.0)
                l_sh = SH_UPPER_BACK.lerp(SH_GUARD_L, 1.0 - wind_l).lerp(target_sh, ext)
            else:
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
        # v71k: направленный слip/duck: корпус уходит в сторону и вниз, руки
        # держатся в защите у головы, глаза на сопернике (голова анти-доворачивается
        # в _apply_rig). Не приседаем «пружиной», а переносим вес.
        var denv := clampf(sin(clampf(dodge_age() / maxf(dodge_dur, 0.01), 0.0, 1.0) * PI), 0.0, 1.0)
        var guard_l := SH_BLOCK_L.lerp(SH_GUARD_L, 0.35)
        var guard_r := SH_BLOCK_R.lerp(SH_GUARD_R, 0.35)
        l_sh = l_sh.lerp(guard_l, denv)
        r_sh = r_sh.lerp(guard_r, denv)
        l_el = lerpf(l_el, EL_BLOCK_L, denv)
        r_el = lerpf(r_el, EL_BLOCK_R, denv)
        arm_z_l = -0.04
        arm_z_r = 0.04
        if dodge_kind == "slip":
            var side := signf(global_transform.basis.x.dot(dodge_dir))
            ptwist += side * 0.55 * denv
            pshift += Vector2(side * 0.20, -0.01) * denv
            body_turn += side * 0.28 * denv
            foot_side = "l" if side < 0.0 else "r"
            foot_yaw = side * 0.35 * denv
        else:
            pshift += Vector2(0.0, -0.08) * denv
            ptwist += 0.10 * denv
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
        # v71k: руки не «празднуют» — вниз-вперёд, локти согнуты, перчатки у
        # корпуса/лица. Зеркально и плавно по ko_fall, без ухода вверх.
        var f_ko := ease(ko_fall, 2.0)
        arm_z_l = -0.06 * f_ko
        arm_z_r = 0.06 * f_ko
        var down_l := Quaternion(Vector3.DOWN,
                Vector3(-0.16, -1.0, 0.44).normalized())
        var down_r := Quaternion(Vector3.DOWN,
                Vector3(0.16, -1.0, 0.44).normalized())
        q_l = Quaternion.from_euler(SH_GUARD_L).slerp(down_l, f_ko).normalized()
        q_r = Quaternion.from_euler(SH_GUARD_R).slerp(down_r, f_ko).normalized()
        l_el = lerpf(EL_GUARD_L, 1.05, f_ko)
        r_el = lerpf(EL_GUARD_R, 1.05, f_ko)

    l_sh = Vector3(l_sh.x, l_sh.y, l_sh.z + arm_z_l)
    r_sh = Vector3(r_sh.x, r_sh.y, r_sh.z + arm_z_r)

    # --- уклон: приседаем пружиной (с перелётом) и уводим корпус
    var crouch_target := 0.0
    if evading:
        crouch_target = 0.85 if dodge_kind == "duck" else 0.35
    _crouch_vel += ((crouch_target - _crouch) * 145.0 - _crouch_vel * 9.0) * dt
    _crouch += _crouch_vel * dt
    _crouch = clampf(_crouch, -0.12, 1.25)

    # Корпус доворачивается ДО того, как решается IK руки: иначе рука считается
    # к старому положению торса и после доворота уезжает мимо цели.
    if ko or fallen:
        _fall_pose(dt)
    elif victory:
        # T10: победная поза — обе перчатки вверх, покачивание
        _victory_pose(dt)
    else:
        _apply_rig(ptwist, pshift, body_turn, foot_side, foot_yaw, foot_heel)

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
            # v71g: на возврате крюк уходит обратно по своей дуге (вбок), а не
            # тянется сквозь лицо соперника по прямой к стойке.
            var rb := ease(back, 0.7)
            off = _punch_guard_off * rb
            if pun_path.has("retract"):
                off += Vector3(pun_path["retract"]) * rb
        elif hit > 0.0:
            var hu := hit
            off = w_off * (1.0 - hu) * (1.0 - hu) + m_off * 2.0 * (1.0 - hu) * hu
        else:
            off = _punch_guard_off.lerp(w_off, float(pun_d["wind"]))
        var sh_node: Node3D = sh_l if pun_arm == "l" else sh_r
        var aim_pt: Vector3 = punch_aim + b * off
        # v71h: крюки идут не по прямой, а по ДУГЕ вокруг оси корпуса: перчатка
        # выносится в сторону на угол swing и оттуда сметает к цели. Раньше
        # смещение задавалось точками wind/mid, и рука всё равно шла почти по
        # нитке — заказчик так и сказал: «левый хук идёт по прямой».
        if pun_path.has("swing"):
            # v71i: дуга строится ВОКРУГ ПЛЕЧА, а не вокруг центра корпуса.
            # Раньше радиус брался до цели (0.9–1.1 м) и точка ведения уезжала
            # на метр в сторону: рука до неё не дотягивалась, IK выпрямляла её
            # по направлению к точке — и крюк визуально шёл по прямой.
            # Теперь точка держится на 0.42–0.68 м от плеча: локоть всё время
            # согнут, предплечье идёт по горизонтали, дуга читается.
            var sh_pos: Vector3 = sh_node.global_position
            var to_aim := punch_aim - sh_pos
            var d_target := Vector3(to_aim.x, 0.0, to_aim.z).length()
            var vy2 := punch_aim.y - sh_pos.y + float(pun_path.get("swing_y", 0.0))
            var m := 0.0
            if back > 0.0:
                m = ease(back, 0.7) * 0.9
            elif hit > 0.0:
                m = 1.0 - hit
            else:
                m = float(pun_d["wind"])
            var u := Vector3(to_aim.x, 0.0, to_aim.z)
            if u.length() < 0.001:
                u = -b.z
            u = u.normalized()
            var base_dir := u.rotated(Vector3.UP, float(pun_path["swing"]) * m)
            var r_wind2 := 0.42
            var r_hit := clampf(d_target - 0.12, 0.40, 0.62)
            var k1 := 1.0 - clampf(m, 0.0, 1.0)
            # лёгкий вынос наружу на середине дуги: рука не «складывается» в
            # точку, а ведёт перчатку по кругу
            var rr := lerpf(r_wind2, r_hit, k1) + 0.08 * sin(PI * k1)
            # v71i: к цели приходим по КАСАТЕЛЬНОЙ — точка контакта смещена на бок
            # головы со стороны удара, а не в центр. Иначе последний отрезок дуги
            # снова смотрит прямо в лицо, и крюк читается как прямой удар.
            var left_dir := Vector3(u.z, 0.0, -u.x)
            var side_sign := signf(float(pun_path["swing"]))
            aim_pt = sh_pos + base_dir * rr + Vector3(0.0, vy2, 0.0) \
                    + left_dir * side_sign * 0.11 * k1
        var sol: Dictionary = _aim_arm(sh_node, aim_pt, b * Vector3(pun_path["pole"]))
        var ext2 := clampf(float(pun_d["ext"]), 0.0, 1.0)
        var qb := clampf(maxf(ext2, float(pun_d["wind"])), 0.0, 1.0)
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
        arm_k = clampf(maxf(k, clampf(float(pun_d["ext"]), 0.0, 1.0) * 0.60), 0.0, 1.0)

    # во время подъёма, лежания и ragdoll руки и ноги ведёт не поза, а ragdoll /
    # анимация подъёма — не перебиваем
    if knock_state != KnockState.GETUP and knock_state != KnockState.DOWNED \
            and not exhaust_down and not exhaust_getup and not victory \
            and not (ko and ko_lying) and ragdoll == null:
        _apply_pose(l_sh, l_el, r_sh, r_el, k, q_l, q_r, arm_k)

    # --- вспышка / телеграф
    # Этап 7: emission_enabled НЕ переключаем покадрово (это смена шейдерного
    # варианта → компиляция пайплайна + спам "Condition f.is_null()" в кэше).
    # Слот эмиссии включён один раз в _enable_emission_slots(), тут только цвет.
    var e := clampf(flash * 3.0, 0.0, 1.0)
    for m in mats:
        if m.emission_enabled:
            m.emission = Color(1, 1, 1) * e

    if glove_mat:
        if telegraph:
            glove_mat.emission = Color(1.0, 0.72, 0.2) * (0.45 + 0.4 * sin(_clock * 24.0))
        else:
            glove_mat.emission = _glove_emission_base

    # v68: ragdoll больше не подменяет модель примитивами — он ВЕДЁТ её кости.
    # Кадр заканчивается синхронизацией: видимое тело целое (кости связаны
    # иерархией и длины звеньев фиксированы — «рассыпаться» физически не может),
    # а падает и катится по настилу настоящая физика.
    if ragdoll != null:
        _ragdoll_sync()


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


func _apply_rig(twist: float, shift: Vector2, body_turn := 0.0,
        foot_side := "", foot_yaw := 0.0, foot_heel := 0.0) -> void:
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

    # голова — отдельная масса: кивает, отстаёт, дёргается от удара.
    # При довороте тела в удар голова чуть отстаёт, но взгляд держит цель.
    var up_h: Vector3 = torso.to_local(rj_head.p) - head.position
    if up_h.length() < 0.05:
        up_h = Vector3.UP
    var hb := wob_head.step(_dt, 46.0, 5.5)
    head.basis = Basis(Quaternion(Vector3.UP, up_h.normalized())) \
            * Basis.from_euler(Vector3(-0.30 * _hit_t + hb.x, hb.y, hb.z)) \
            * Basis(Vector3.UP, -body_turn * 0.65)

    # руки отстают от корпуса: плечи болтаются
    var dv: Vector3 = global_transform.basis.inverse() * (rj_chest.p - _chest_prev)
    _chest_prev = rj_chest.p
    wob_sh_l.kick(Vector3(dv.z, -dv.y, -dv.x) * 1.8)
    wob_sh_r.kick(Vector3(dv.z, -dv.y, -dv.x) * 1.8)

    _leg_ik(th_l, kn_l, ft_l, rj_foot_l.p)
    _leg_ik(th_r, kn_r, ft_r, rj_foot_r.p)
    # стопа ударной ноги разворачивается на носке (пятка наружу) и поднимает
    # пятку — тело доворачивается вокруг врытой в пол стопы, а не «в воздухе»
    if foot_side == "l":
        ft_l.basis = ft_l.basis * Basis(Vector3.UP, foot_yaw) * Basis(Vector3.RIGHT, -foot_heel)
    elif foot_side == "r":
        ft_r.basis = ft_r.basis * Basis(Vector3.UP, foot_yaw) * Basis(Vector3.RIGHT, -foot_heel)
    body.position = Vector3.ZERO
    body.rotation = Vector3(0.0, body_turn, 0.0)


## Пакет 2 / T10: победная поза — обе перчатки вверх и покачивание.
var victory := false
var victory_t := 0.0


func start_victory() -> void:
    if ko or fallen or knock_state != KnockState.NONE:
        return
    victory = true
    victory_t = 0.0
    punch_kind = ""
    punch_aim = Vector3.ZERO
    blocking = false
    evading = false
    dodge_t = 0.0
    vel = Vector3.ZERO
    stun = maxf(stun, 0.10)
    exhausted = false
    punch_power = 1.0


func stop_victory() -> void:
    victory = false
    victory_t = 0.0


## Поза победы: руки вверх, корпус покачивается, голова поднята.
func _victory_pose(dt: float) -> void:
    var k := clampf(dt * 5.0, 0.0, 1.0)
    victory_t += dt
    var sway := sin(victory_t * 2.1) * 0.09
    var bob := sin(victory_t * 3.0) * 0.02
    body.rotation = body.rotation.lerp(Vector3.ZERO, k)
    body.position = body.position.lerp(Vector3(0.0, bob, 0.0), k)
    hips.position = hips.position.lerp(Vector3(sway * 0.35, _hip_h_dyn + 0.01, 0.0), k)
    hips.rotation = hips.rotation.lerp(Vector3(0.0, 0.0, sway * 0.5), k)
    torso.rotation = torso.rotation.lerp(Vector3(-0.18, 0.0, sway), k)
    th_l.rotation = th_l.rotation.lerp(Vector3(0.06, 0.0, 0.0), k)
    th_r.rotation = th_r.rotation.lerp(Vector3(0.04, 0.0, 0.0), k)
    kn_l.rotation = kn_l.rotation.lerp(Vector3(-0.10, 0.0, 0.0), k)
    kn_r.rotation = kn_r.rotation.lerp(Vector3(-0.08, 0.0, 0.0), k)
    ft_l.basis = Basis(Vector3.RIGHT, -(th_l.rotation.x + kn_l.rotation.x))
    ft_r.basis = Basis(Vector3.RIGHT, -(th_r.rotation.x + kn_r.rotation.x))
    # обе перчатки над головой, чуть покачиваются в такт
    var up_l := Quaternion(Vector3.DOWN,
            Vector3(-0.16, 1.0, -0.05 + sway * 0.5).normalized()).get_euler()
    var up_r := Quaternion(Vector3.DOWN,
            Vector3(0.16, 1.0, -0.05 - sway * 0.5).normalized()).get_euler()
    _apply_pose(up_l, -0.10, up_r, -0.10, clampf(dt * 12.0, 0.0, 1.0))
    head.rotation = head.rotation.lerp(Vector3(-0.24, sin(victory_t * 1.7) * 0.12, 0.0), k)


func _fall_pose(dt: float) -> void:
    # v68: встаём после усталости — та же анимация подъёма, что после нокдауна
    if exhaust_getup:
        _getup_pose(dt)
        return
    # v71e: КО-тело лежит в авторской позе (knock_t = 0 → поза лежа)
    if ko and ko_lying:
        _getup_pose(dt)
        return
    if knock_state == KnockState.GETUP or knock_state == KnockState.DOWNED:
        # в DOWNED knock_t = 0, поэтому _getup_pose держит позу лежа
        _getup_pose(dt)
        return
    var f := ease(ko_fall, 2.0)
    if ko and not fallen and ragdoll == null:
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


## Диагностика Этапа 7 (env VRINGE_DIAG): сколько рэгдоллов/материалов создаётся.
var _diag_ragdolls := 0
var _diag_mats := 0


## Пакет 2 / T6: «мышечный тонус» ragdoll. Полностью мягкое тело смотрится как
## тряпка: голова болтается, руки разлетаются. Здесь мы лёгкими поправками
## скоростей держим голову и предплечья — тело падает, но выглядит живым.
## Физику не ломаем: части всё равно сталкиваются и висят на шарнирах.
## v67: тело улеглось — усыпляем части ragdoll. Иначе после КО физика крутится
## до конца боя: тело медленно «ползёт» по настилу и ест процессор.
## Усыпляем только при настоящем КО (при нокдауне тело ещё встаёт, при вылете
## за канаты — летит дальше).
var _ragdoll_rest_t := 0.0


func _ragdoll_rest(dt: float) -> void:
    if ragdoll == null or not ko:
        _ragdoll_rest_t = 0.0
        return
    var moving := false
    for key in ragdoll_parts:
        var rb: RigidBody3D = ragdoll_parts[key]
        if rb == null:
            continue
        if rb.linear_velocity.length() > 0.35 or rb.angular_velocity.length() > 0.9:
            moving = true
            break
    if moving:
        _ragdoll_rest_t = 0.0
        return
    _ragdoll_rest_t += dt
    if _ragdoll_rest_t >= 0.45:
        for key in ragdoll_parts:
            var rb: RigidBody3D = ragdoll_parts[key]
            if rb == null:
                continue
            rb.linear_velocity = Vector3.ZERO
            rb.angular_velocity = Vector3.ZERO
            rb.can_sleep = true
            rb.sleeping = true


func _ragdoll_muscle(dt: float) -> void:
    var torso_rb: RigidBody3D = ragdoll_parts.get("torso")
    var head_rb: RigidBody3D = ragdoll_parts.get("head")
    if torso_rb == null:
        return
    var k := clampf(dt * 8.0, 0.0, 1.0)
    # голова: не даём ей раскручиваться и «отрываться» от корпуса
    if head_rb != null:
        head_rb.angular_velocity = head_rb.angular_velocity.limit_length(5.0) \
                .lerp(Vector3.ZERO, k * 0.45)
        var chest := torso_rb.global_position
        var want_head := chest + (head_rb.global_position - chest).normalized() * 0.30
        head_rb.linear_velocity = head_rb.linear_velocity.lerp(
                (want_head - head_rb.global_position) * 3.0, k * 0.22)
    # руки: не разлетаются в стороны и не складываются в клубок — держатся
    # на расстоянии корпуса, как у бойца в падении
    var chest_pos := torso_rb.global_position
    for part in ["up_l", "up_r", "fore_l", "fore_r"]:
        var rb: RigidBody3D = ragdoll_parts.get(part)
        if rb == null:
            continue
        rb.angular_velocity = rb.angular_velocity.limit_length(9.0).lerp(Vector3.ZERO, k * 0.25)
        var dir := (rb.global_position - chest_pos)
        var radius := 0.55 if part.begins_with("fore") else 0.42
        var target := chest_pos + (dir.normalized() if dir.length() > 0.01 else Vector3.UP) * radius
        # v71k: руки в падении — вниз/к корпусу, а не вверх (не даём физике
        # подбросить перчатки над головой).
        target.y = minf(target.y, chest_pos.y + (0.02 if part.begins_with("fore") else 0.16))
        rb.linear_velocity = rb.linear_velocity.lerp((target - rb.global_position) * 2.2,
                k * 0.16)


func enter_ragdoll(impulse: Vector3) -> void:
    if ragdoll != null or body == null:
        return
    if OS.get_environment("VRINGE_DIAG") != "":
        _diag_ragdolls += 1
        print("DIAG ragdolls=", _diag_ragdolls, " mats=", mats.size(),
                " кадр=", Engine.get_frames_drawn())
    var scene := get_tree().current_scene
    if scene == null:
        scene = get_parent()
    ragdoll = Node3D.new()
    ragdoll.name = "Ragdoll"
    scene.add_child(ragdoll)
    # v68: модель НЕ скрываем. Раньше здесь стояло body.visible = false и вместо
    # бойца рисовались 13 отдельных капсул/шаров — со стороны это выглядело как
    # «тело рассыпалось на кусочки». Теперь физика ведёт настоящую модель
    # (см. _ragdoll_sync), а у частей ragdoll нет своих мешей.
    body.visible = true

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
        # T6: тонус — у головы и рук демпфирование выше, тело не «тряпка»
        var damp: Dictionary = RAGDOLL_DAMP.get(str(d["n"]), {"ad": 1.2, "ld": 0.5})
        rb.linear_damp = float(damp["ld"])
        rb.angular_damp = float(damp["ad"])
        # T6: не засыпаем в полёте — иначе тело замирает в воздухе
        rb.can_sleep = false
        rb.gravity_scale = gravity_mult
        var cs := CollisionShape3D.new()
        cs.shape = _shape_for(str(d["kind"]), float(d["r"]), float(d["h"]))
        rb.add_child(cs)
        # v68: мешей у частей ragdoll больше нет — рисуется сама модель бойца.
        # Меш-примитивы оставляли «куски» на настиле после падения.
        ragdoll.add_child(rb)
        var off_v: Vector3 = RAGDOLL_OFF.get(str(d["n"]), d["off"])
        var gt := bone.global_transform
        rb.global_transform = Transform3D(gt.basis, gt * off_v)
        # v68: запоминаем исходную ориентацию кости — от неё считаем кратчайший
        # поворот при синхронизации модели с физикой
        _rd_rest_basis[str(d["n"])] = gt.basis.orthonormalized()
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
        # v71k: руки не разлетаются вверх — гасим вращение и тянем вниз-вперёд
        if str(k).begins_with("up_") or str(k).begins_with("fore_"):
            rb.angular_velocity *= 0.25
            rb.linear_velocity += Vector3(0.0, -0.55, -0.15)


func clear_ragdoll() -> void:
    if ragdoll != null:
        ragdoll.queue_free()
        ragdoll = null
    ragdoll_parts.clear()
    _rd_rest_basis.clear()
    if body:
        body.visible = true


## v68: ragdoll ведёт видимую модель.
## Кость не «приклеивается» к физической капсуле жёстко: капсулы симметричны,
## и поворот можно трактовать двояко — перевёрнутый таз физически ничем не
## отличается, а модель встала бы вверх ногами и ушла под настил. Поэтому берём
## из физики ГЕОМЕТРИЮ: направление «сустав → центр части» (позиция однозначна),
## а поворот вокруг него достраиваем кратчайшей дугой от исходной позы. Так тело
## падает по-настоящему, но всегда остаётся целым и нормально ориентированным.
## Позиции костей в иерархии жёсткие — «рассыпаться» физически не может.
var _rd_rest_basis: Dictionary = {}


func _ragdoll_sync() -> void:
    var pelvis: RigidBody3D = ragdoll_parts.get("pelvis")
    var torso_rb: RigidBody3D = ragdoll_parts.get("torso")
    if pelvis == null or torso_rb == null or hips == null:
        return
    if not _rd_rest_basis.has("torso") or not _rd_rest_basis.has("pelvis"):
        return
    # позвоночник: от таза к груди — это «верх» тела в мире
    var rest_spine: Vector3 = (_rd_rest_basis["torso"] * RAGDOLL_OFF["torso"]
            - _rd_rest_basis["pelvis"] * RAGDOLL_OFF["pelvis"]).normalized()
    var spine: Vector3 = torso_rb.global_position - pelvis.global_position
    var pb: Basis = _rd_rest_basis["pelvis"]
    if spine.length() > 0.001 and rest_spine.length() > 0.001:
        pb = (Basis(Quaternion(rest_spine, spine.normalized())) * pb) \
                .orthonormalized()
    hips.global_transform = Transform3D(pb,
            pelvis.global_position - pb * RAGDOLL_OFF["pelvis"])
    # плечи возвращаем на место: удар их сдвигает, в ragdoll этот сдвиг лишний
    sh_l.position = sh_l_base
    sh_r.position = sh_r_base
    _ragdoll_bone(torso, "torso")
    _ragdoll_bone(head, "head")
    _ragdoll_bone(sh_l, "up_l")
    _ragdoll_bone(el_l, "fore_l")
    _ragdoll_bone(sh_r, "up_r")
    _ragdoll_bone(el_r, "fore_r")
    _ragdoll_bone(th_l, "thigh_l")
    _ragdoll_bone(kn_l, "shin_l")
    _ragdoll_bone(ft_l, "foot_l")
    _ragdoll_bone(th_r, "thigh_r")
    _ragdoll_bone(kn_r, "shin_r")
    _ragdoll_bone(ft_r, "foot_r")


## Ориентировать кость по её физической части: направление «сустав → центр
## части» берём из физики, поворот вокруг этого направления достраиваем
## кратчайшей дугой от исходной позы (без произвольного «винта»).
func _ragdoll_bone(node: Node3D, part: String) -> void:
    var rb: RigidBody3D = ragdoll_parts.get(part)
    if node == null or rb == null or not _rd_rest_basis.has(part):
        return
    var rest: Basis = _rd_rest_basis[part]
    var off: Vector3 = RAGDOLL_OFF[part]
    var rest_axis: Vector3 = rest * off
    var dir: Vector3 = rb.global_position - node.global_position
    var b: Basis = rest
    if rest_axis.length() > 0.001 and dir.length() > 0.001:
        b = (Basis(Quaternion(rest_axis.normalized(), dir.normalized())) * rest) \
                .orthonormalized()
    var parent_basis: Basis = node.get_parent().global_transform.basis \
            .orthonormalized()
    # v71: анатомические пределы сустава — иначе ragdoll выворачивает локти,
    # колени и шею назад и модель выглядит сломанной. v71b: ограничиваем ТОЛЬКО
    # сгиб (X); жёсткие пределы по Y/Z выкручивали плечо/бедро и давали
    # «запутанную» позу при падении.
    var lim: Vector2 = RAGDOLL_LIMITS.get(part, Vector2.ZERO)
    if lim != Vector2.ZERO:
        var rel: Basis = parent_basis.inverse() * b
        var e: Vector3 = rel.get_euler()
        e.x = clampf(e.x, lim.x, lim.y)
        b = (parent_basis * Basis.from_euler(e)).orthonormalized()
    node.basis = parent_basis.inverse() * b

# ============== Этап 3, волна 5 (task-29): тренировочные ключи позы ==============
## Слой моторных ключей для анимаций тренировки: присед, наклон, упор, шаг ног.
## ВКЛЮЧАЕТСЯ ТОЛЬКО в тренировке при train_anim_level != OFF (ставит TrainingMode).
## В бою не участвует: при выключенном флаге ни один трансформ не меняется.
var train_pose_enabled := false

@export var train_hip_height_min := -0.45
@export var train_hip_height_max := 0.30
@export var train_pitch_max := 1.25
@export var train_knee_max := 1.9
@export var train_thigh_max := 1.2
@export var train_shoulder_max := 1.8
@export var train_elbow_max := 2.5
@export var train_foot_max := 0.7
@export var train_yaw_max := 0.9

var _train_pose_cur: Dictionary = {}
## v71q: был ли изменён общий корпус (body) для поз лёжа/виса/скамьи.
## Пока false, старые клипы не трогаются вообще (байт-в-байт как раньше).
var _train_body_used := false


func set_train_pose_enabled(on: bool) -> void:
    # Важно для OFF-байтности: если режим не менялся — НИЧЕГО не трогаем.
    if on == train_pose_enabled:
        return
    train_pose_enabled = on
    if not on:
        reset_train_pose()


## Вернуть риг в нейтраль (без сдвига таза/наклонов).
func reset_train_pose() -> void:
    _train_pose_cur = {}
    if hips == null or torso == null:
        return
    if _train_body_used and body != null:
        body.transform = Transform3D.IDENTITY
        _train_body_used = false
    hips.position.y = _hip_y
    hips.rotation = Vector3.ZERO
    torso.rotation = Vector3.ZERO
    if head != null:
        head.rotation = Vector3.ZERO
    for n in [th_l, th_r, kn_l, kn_r, sh_l, sh_r, el_l, el_r, ft_l, ft_r]:
        if n != null:
            n.rotation = Vector3.ZERO


## Применить тренировочную позу (словарь ключей) с весом 0..1.
## v69: знаки и опора исправлены.
##  - В ключах колено задаётся ПОЛОЖИТЕЛЬНЫМ числом = «согнуть»; в риге сгиб
##    колена — это отрицательный поворот (раньше ключи клампились в 0..+lim и
##    ноги выгибались в обратную сторону — модель «ломалась»).
##  - Высота таза считается ОТ НОГ: по самой выпрямленной ноге подбираем так,
##    чтобы стопа стояла на настиле. Отсюда присед/бег/прыжок выглядят живыми,
##    а не «висят в воздухе» или «проваливаются в пол».
##  - Стопа доворачивается плашмя: гасит наклон таза и сгибы ноги.
##  - hip_height остался для подскоков (положительный = тело отрывается выше
##    расчётной опоры); присед теперь задаётся углами ног, а не сдвигом таза.
func apply_train_pose(d: Dictionary, weight: float = 1.0) -> void:
    if not train_pose_enabled or hips == null or torso == null:
        return
    var w := clampf(weight, 0.0, 1.0)
    if d.is_empty():
        reset_train_pose()
        return
    # v71q: отладочный оверрайд для кадров новых режимов (в игре env пуст).
    # VRINGE_TRAIN_SUPPORT=plank|hang|bench; VRINGE_TRAIN_SUPPORT_H=<м>.
    var dbg_support := OS.get_environment("VRINGE_TRAIN_SUPPORT").strip_edges().to_lower()
    if dbg_support != "":
        d = d.duplicate(true)
        d["support"] = dbg_support
        var dbg_h := OS.get_environment("VRINGE_TRAIN_SUPPORT_H").strip_edges()
        if dbg_h != "":
            d["support_h"] = float(dbg_h)
        if not d.has("body_pitch"):
            d["body_pitch"] = -1.45 if dbg_support == "plank" else (
                    1.45 if dbg_support == "bench" else 0.0)
    _train_pose_cur = d
    var hip_p := clampf(float(d.get("hip_pitch", 0.0)), -train_pitch_max,
            train_pitch_max) * w
    var hip_yaw := clampf(float(d.get("hip_yaw", 0.0)), -train_yaw_max,
            train_yaw_max) * w
    var torso_p := clampf(float(d.get("torso_pitch", 0.0)), -0.8, train_pitch_max) * w
    var torso_yaw := clampf(float(d.get("torso_yaw", 0.0)), -train_yaw_max,
            train_yaw_max) * w
    # ноги: в ключах «+» = бедро вперёд, колено — согнуть
    var th_l_v := clampf(float(d.get("thigh_l", d.get("thigh", 0.0))),
            -train_thigh_max, train_thigh_max) * w
    var th_r_v := clampf(float(d.get("thigh_r", d.get("thigh", 0.0))),
            -train_thigh_max, train_thigh_max) * w
    var kn_l_v := clampf(float(d.get("knee_l", d.get("knee", 0.0))),
            0.0, train_knee_max) * w
    var kn_r_v := clampf(float(d.get("knee_r", d.get("knee", 0.0))),
            0.0, train_knee_max) * w
    # высота таза от ног: самая выпрямленная нога ставит стопу на настил
    var drop_l := LEG_UP * cos(hip_p + th_l_v) + LEG_LO * cos(hip_p + th_l_v - kn_l_v)
    var drop_r := LEG_UP * cos(hip_p + th_r_v) + LEG_LO * cos(hip_p + th_r_v - kn_r_v)
    var drop := maxf(drop_l, drop_r)
    # подскок: только положительная добавка (тело отрывается от пола)
    var lift := maxf(0.0, clampf(float(d.get("hip_height", 0.0)),
            train_hip_height_min, train_hip_height_max)) * w
    hips.position = Vector3(0.0, FOOT_Y + 0.05 + drop + lift, 0.0)
    hips.rotation = Vector3(hip_p, hip_yaw, 0.0)
    torso.rotation = Vector3(torso_p, torso_yaw, 0.0)
    if head != null:
        head.rotation = Vector3(clampf(float(d.get("head_pitch", 0.0)), -0.6, 0.8) * w,
                0.0, 0.0)
    th_l.rotation = Vector3(th_l_v, 0.0, 0.0)
    th_r.rotation = Vector3(th_r_v, 0.0, 0.0)
    kn_l.rotation = Vector3(-kn_l_v, 0.0, 0.0)
    kn_r.rotation = Vector3(-kn_r_v, 0.0, 0.0)
    # стопа плашмя (плюс явная добавка из ключей, если нужна)
    var ft_l_add := clampf(float(d.get("foot_l", d.get("foot", 0.0))),
            -train_foot_max, train_foot_max) * w
    var ft_r_add := clampf(float(d.get("foot_r", d.get("foot", 0.0))),
            -train_foot_max, train_foot_max) * w
    if ft_l != null:
        ft_l.rotation = Vector3(-(hip_p + th_l_v - kn_l_v) + ft_l_add, 0.0, 0.0)
    if ft_r != null:
        ft_r.rotation = Vector3(-(hip_p + th_r_v - kn_r_v) + ft_r_add, 0.0, 0.0)
    # руки: «+» = вперёд/вверх (как стойка), «−» = за спину/вверх над головой
    var sh_l_v := clampf(float(d.get("shoulder_l", d.get("shoulder", 0.0))),
            -train_shoulder_max, train_shoulder_max) * w
    var sh_r_v := clampf(float(d.get("shoulder_r", d.get("shoulder", 0.0))),
            -train_shoulder_max, train_shoulder_max) * w
    var el_l_v := clampf(float(d.get("elbow_l", d.get("elbow", 0.0))),
            0.0, train_elbow_max) * w
    var el_r_v := clampf(float(d.get("elbow_r", d.get("elbow", 0.0))),
            0.0, train_elbow_max) * w
    if sh_l != null:
        sh_l.rotation = Vector3(sh_l_v, 0.0, 0.0)
    if sh_r != null:
        sh_r.rotation = Vector3(sh_r_v, 0.0, 0.0)
    if el_l != null:
        el_l.rotation = Vector3(el_l_v, 0.0, 0.0)
    if el_r != null:
        el_r.rotation = Vector3(el_r_v, 0.0, 0.0)

    # --- v71q: положение всего корпуса (лёжа/вис/планка/скамья) ---
    # Новые ключи по умолчанию нулевые; при их отсутствии body не трогаем,
    # поэтому старые клипы остаются как были.
    var body_pitch := clampf(float(d.get("body_pitch", 0.0)), -1.9, 1.9) * w
    var body_roll := clampf(float(d.get("body_roll", 0.0)), -1.6, 1.6) * w
    var body_yaw := clampf(float(d.get("body_yaw", 0.0)), -1.6, 1.6) * w
    var body_y := clampf(float(d.get("body_y", 0.0)), -2.0, 3.0) * w
    var support := str(d.get("support", "floor")).to_lower()
    var want_body: bool = support != "floor" or absf(body_pitch) > 0.0001 \
            or absf(body_roll) > 0.0001 or absf(body_yaw) > 0.0001 \
            or absf(body_y) > 0.0001
    if want_body:
        _train_body_used = true
        var pivot := Vector3(0.0, hips.position.y, 0.0)
        var bb := Basis.from_euler(Vector3(body_pitch, body_yaw, body_roll))
        body.transform = Transform3D(bb, pivot - bb * pivot + Vector3(0.0, body_y, 0.0))
        body.force_update_transform()
        if support != "floor":
            var support_h := clampf(float(d.get("support_h", 0.0)), -1.0, 5.0)
            if support_h <= 0.001:
                support_h = 2.3 if support == "hang" else (
                        0.45 if support == "bench" else 0.04)
            var shift := 0.0
            match support:
                "hang":
                    # кисти на перекладине support_h: поднимаем/опускаем всё тело
                    var hy := (glove_point("l").y + glove_point("r").y) * 0.5
                    shift = support_h - hy
                "plank":
                    # вес на руках и носках: в планке/отжиманиях на полу должны
                    # стоять И ладони, И стопы. Раньше якорились только перчатки —
                    # тело висело в воздухе, а ноги уходили вверх (кадры v71s).
                    var lo := minf(glove_point("l").y, glove_point("r").y)
                    for ft in [ft_l, ft_r]:
                        if ft != null:
                            lo = minf(lo, ft.global_position.y)
                    shift = support_h - lo
                "bench":
                    # спина/таз на скамье support_h, стопы на полу
                    shift = support_h - hips.global_position.y
            body.position.y += shift * w
            body.force_update_transform()
    elif _train_body_used and body != null:
        # клип вернулся к обычной стойке — убираем прошлый body-трансформ
        body.transform = Transform3D.IDENTITY
        _train_body_used = false


func _set_side_rot(n: Node3D, v: float, lim: float, w: float, lo: float = -1.0) -> void:
    if n == null:
        return
    var a := clampf(v, lo * lim if lo < 0.0 else lo, lim)
    n.rotation = Vector3(a * w, 0.0, 0.0)


## Текущие ключи (для отладочного лога/гейта).
func train_pose_values() -> Dictionary:
    if hips == null or torso == null:
        return {}
    return {"hip_height": snappedf(hips.position.y - _hip_y, 0.001),
            "hip_pitch": snappedf(hips.rotation.x, 0.01),
            "torso_pitch": snappedf(torso.rotation.x, 0.01),
            "elbow_l": snappedf(el_l.rotation.x if el_l != null else 0.0, 0.01),
            "elbow_r": snappedf(el_r.rotation.x if el_r != null else 0.0, 0.01),
            "body_pitch": snappedf(body.rotation.x if body != null else 0.0, 0.01),
            "body_roll": snappedf(body.rotation.z if body != null else 0.0, 0.01),
            "body_yaw": snappedf(body.rotation.y if body != null else 0.0, 0.01),
            "body_y": snappedf(body.position.y if body != null else 0.0, 0.001),
            "support": str(_train_pose_cur.get("support", "floor")),
            "support_h": snappedf(float(_train_pose_cur.get("support_h", 0.0)), 0.01)}

