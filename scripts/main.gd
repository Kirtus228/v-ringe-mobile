extends Node3D
## Главный узел: арена, свет, камера, бой, HUD и состояния игры.

const ArenaScript = preload("res://scripts/arena.gd")
const FighterScript = preload("res://scripts/fighter.gd")
const HudScript = preload("res://scripts/hud.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const LookScript = preload("res://scripts/look.gd")
const SplashScript = preload("res://scripts/splash.gd")
const StoryScript = preload("res://scripts/story.gd")
const TouchScript = preload("res://scripts/touch.gd")
const Lang = preload("res://scripts/lang.gd")

enum St { MENU, FIGHT, KO, RESULT, PAUSE, CUSTOM, SETTINGS, UPGRADE, TRAINING, HOWTO,
        PREFIGHT, TOUR, STORY }

## Карьера: шесть поясов по десять соперников, каждый пояс — уровень сложности.
const BELTS := [
    {"name": "ДЕБЮТ", "en": "ROOKIE", "color": Color(0.62, 0.80, 1.00)},
    {"name": "ЛЮБИТЕЛЬ", "en": "AMATEUR", "color": Color(0.50, 0.90, 0.70)},
    {"name": "ПРОФИ", "en": "PRO", "color": Color(0.98, 0.86, 0.38)},
    {"name": "МАСТЕР", "en": "MASTER", "color": Color(0.99, 0.64, 0.30)},
    {"name": "ЭЛИТА", "en": "ELITE", "color": Color(0.96, 0.42, 0.38)},
    {"name": "ЭКСТРАПРОФИ", "en": "EXTRA PRO", "color": Color(0.90, 0.36, 0.72)},
]
const BELT_FIGHTS := 10

## Сюжетные турниры: три боя подряд на вылет, за победу — награда.
const TOURNAMENTS := [
    {"id": "debut", "name": "КУБОК ДЕБЮТА", "need": 0, "fights": 3,
        "coins": 350, "form": 70, "unlock": "",
        "intro": "Вечер новичков: три боя за один вечер. Побеждаешь — тебя замечают."},
    {"id": "city", "name": "КУБОК ГОРОДА", "need": 2, "fights": 3,
        "coins": 800, "form": 160, "unlock": "gloves_color:gold",
        "intro": "Городской турнир. В финале будет парень, который не падает с первого удара."},
    {"id": "champ", "name": "КУБОК ЧЕМПИОНОВ", "need": 4, "fights": 3,
        "coins": 1800, "form": 400, "unlock": "shorts_color:gold",
        "intro": "Турнир чемпионов. Здесь заканчиваются счастливые случайности."},
]

## Советы тренера перед боем: выдаются перемешанной колодой, без повторов.
const TIPS := [
    "Дыши. Первый раунд проигрывают те, кто держит дыхание.",
    "Джеб — твой дальномер. Бей им, пока не поймёшь дистанцию.",
    "Не бей в блок: после двух ударов в защиту соперник откроется.",
    "Ноги работают больше рук. Ушёл в сторону — уже наполовину защитился.",
    "Блок держи у подбородка, а не у груди.",
    "Он замахивается — не жди, шагни внутрь и бей коротко.",
    "Выносливость тоже оружие. Три удара в серию, не больше.",
    "Смотри ему в грудь: по плечам видно начало удара.",
    "Не стой на месте после обмена. Удар — шаг — удар.",
    "Он открывает подбородок, когда бьёт правой. Лови этот момент.",
    "Вылет за канаты — поражение. Держись центра ринга.",
    "Апперкот — снизу, коротко, с корпусом. Не бей издалека.",
    "В концовке раунда судьи смотрят последние десять секунд. Не сдавай их.",
    "Устал — уходи на дистанцию и восстанавливай дыхание, а не просто бей.",
    "Первые полминуты — разведка. Посмотри, что он делает после твоей атаки.",
]

## Соперники: восемь характеров боя. hp/dmg/spd/stam — множители к базовым
## параметрам боя, остальное — повадки: как часто лезет (aggr), держит блок
## (guard), уклоняется (dodge), сколько замахивается (wind), как быстро
## восстанавливается (rec), с какой дистанции работает (range), сколько
## бьёт в серии (combo) и как часто отвечает после защиты (counter).
## mix — доли джеба, левого хука, правого хука и апперкота.
## look — [цвет шорт, цвет перчаток, фигура, размер перчаток].
const STYLES := [
    {"id": "puncher", "ru": "ПАНЧЕР", "en": "PUNCHER",
        "desc_ru": "бьёт редко, но каждый удар — молот",
        "desc_en": "throws rarely, but every punch is a hammer",
        "tip_ru": "Не стой в обмене: пропустил тяжёлый — сразу уходи на дистанцию.",
        "tip_en": "Do not trade: after a heavy punch, get out of range.",
        "hp": 1.02, "dmg": 1.30, "spd": 1.14, "stam": 1.00, "heavy": 0.10,
        "aggr": 0.50, "guard": 0.30, "dodge": 0.04, "wind": 1.35,
        "rec": 1.12, "range": 1.42, "combo": 1, "counter": 0.10,
        "mix": [0.08, 0.22, 0.58, 0.12],
        "look": ["red", "black", "heavy", "twelve"],
        "nick_ru": ["МОЛОТ", "КУВАЛДА", "ПУШКА", "ГИРЯ", "БУЛЬДОЗЕР", "ТЯЖЁЛЫЙ"],
        "nick_en": ["HAMMER", "SLEDGE", "CANNON", "ANVIL", "BULLDOZER", "HEAVY"]},
    {"id": "speedster", "ru": "СКОРОСТНИК", "en": "SPEEDSTER",
        "desc_ru": "лёгкий и быстрый, сыплет джебами",
        "desc_en": "light and fast, peppers you with jabs",
        "tip_ru": "Держи блок у подбородка: он бьёт часто и ищет открытую голову.",
        "tip_en": "Keep your guard high: he throws often and hunts an open head.",
        "hp": 0.92, "dmg": 0.84, "spd": 0.78, "stam": 1.05,
        "aggr": 0.80, "guard": 0.32, "dodge": 0.20, "wind": 0.82,
        "rec": 0.72, "range": 1.42, "combo": 2, "counter": 0.15,
        "mix": [0.55, 0.20, 0.15, 0.10],
        "look": ["green", "white", "lean", "ten"],
        "nick_ru": ["ИСКРА", "ВЕТЕР", "СТРЕЛА", "МОЛНИЯ", "ЮЛА", "ШУСТРЫЙ"],
        "nick_en": ["SPARK", "WIND", "ARROW", "BOLT", "SPINNER", "QUICK"]},
    {"id": "defender", "ru": "ЗАЩИТНИК", "en": "DEFENDER",
        "desc_ru": "глухая защита и ответ после блока",
        "desc_en": "tight guard and a counter after blocking",
        "tip_ru": "Не бей в блок: два удара в защиту — он откроется, тогда и бей.",
        "tip_en": "Do not punch the guard: two blocked punches open him up.",
        "hp": 1.08, "dmg": 0.96, "spd": 1.04, "stam": 1.10, "heavy": 0.05,
        "aggr": 0.36, "guard": 0.74, "dodge": 0.12, "wind": 1.05,
        "rec": 1.00, "range": 1.40, "combo": 1, "counter": 0.45,
        "mix": [0.35, 0.30, 0.20, 0.15],
        "look": ["blue", "white", "normal", "fourteen"],
        "nick_ru": ["КАМЕНЬ", "СТЕНА", "БРОНЯ", "ЩИТ", "ЗАМОК", "НЕПРОБИВАЕМЫЙ"],
        "nick_en": ["STONE", "WALL", "ARMOR", "SHIELD", "CASTLE", "IRONCLAD"]},
    {"id": "aggressor", "ru": "АГРЕССОР", "en": "AGGRESSOR",
        "desc_ru": "лезет вперёд и не даёт дышать",
        "desc_en": "walks you down and gives no room to breathe",
        "tip_ru": "Он идёт вперёд — встречай джебом и уходи в сторону, не стой в углу.",
        "tip_en": "He keeps coming: meet him with the jab and step aside.",
        "hp": 1.00, "dmg": 1.02, "spd": 0.92, "stam": 1.18,
        "aggr": 0.95, "guard": 0.14, "dodge": 0.06, "wind": 0.95,
        "rec": 0.80, "range": 1.30, "combo": 3, "counter": 0.05,
        "mix": [0.30, 0.35, 0.30, 0.05],
        "look": ["black", "red", "normal", "twelve"],
        "nick_ru": ["БУРЯ", "ПРЕСС", "ТАРАН", "ОГОНЬ", "ДАВИЛА", "ШТОРМ"],
        "nick_en": ["STORM", "PRESS", "RAM", "FIRE", "CRUSHER", "GALE"]},
    {"id": "sniper", "ru": "СНАЙПЕР", "en": "SNIPER",
        "desc_ru": "держит дистанцию и бьёт с дальней",
        "desc_en": "keeps his distance and snipes from range",
        "tip_ru": "Он бегает по рингу — режь угол и не гонись за ним по прямой.",
        "tip_en": "He circles the ring: cut the angle instead of chasing.",
        "hp": 0.98, "dmg": 0.98, "spd": 0.90, "stam": 1.00,
        "aggr": 0.56, "guard": 0.36, "dodge": 0.16, "wind": 0.90,
        "rec": 0.85, "range": 1.55, "combo": 1, "counter": 0.18,
        "mix": [0.65, 0.10, 0.10, 0.15],
        "look": ["white", "blue", "lean", "twelve"],
        "nick_ru": ["ОХОТНИК", "СТРЕЛОК", "ПРИЦЕЛ", "КОМАР", "СНАЙП", "ДАЛЬНИЙ"],
        "nick_en": ["HUNTER", "SHARPSHOOTER", "SCOPE", "MOSQUITO", "SNIPE", "LONG"]},
    {"id": "counter", "ru": "КОНТРБОКСЁР", "en": "COUNTERPUNCHER",
        "desc_ru": "ждёт твою атаку и отвечает",
        "desc_en": "waits for your attack and answers it",
        "tip_ru": "Не бросай одиночный удар в пустоту — он ловит. Бей серией.",
        "tip_en": "Do not throw one lonely punch: he catches it. Work in bursts.",
        "hp": 1.00, "dmg": 1.06, "spd": 0.94, "stam": 1.06,
        "aggr": 0.44, "guard": 0.56, "dodge": 0.28, "wind": 0.95,
        "rec": 0.80, "range": 1.45, "combo": 2, "counter": 0.60,
        "mix": [0.22, 0.28, 0.28, 0.22],
        "look": ["gold", "black", "normal", "fourteen"],
        "nick_ru": ["ЭХО", "КАПКАН", "ПРУЖИНА", "ЗЕРКАЛО", "СТОРОЖ", "ОТВЕТ"],
        "nick_en": ["ECHO", "TRAP", "SPRING", "MIRROR", "SENTRY", "REPLY"]},
    {"id": "tank", "ru": "ТАНК", "en": "TANK",
        "desc_ru": "мало падает и много терпит",
        "desc_en": "hard to drop and hard to hurt",
        "tip_ru": "Его не сломать одним ударом — работай сериями и береги выносливость.",
        "tip_en": "One punch will not drop him: work in bursts, save stamina.",
        "hp": 1.28, "dmg": 1.08, "spd": 1.18, "stam": 1.38, "heavy": 0.35,
        "aggr": 0.56, "guard": 0.46, "dodge": 0.02, "wind": 1.18,
        "rec": 1.02, "range": 1.34, "combo": 1, "counter": 0.10,
        "mix": [0.16, 0.40, 0.34, 0.10],
        "look": ["black", "gold", "heavy", "fourteen"],
        "nick_ru": ["БЕТОН", "МЕДВЕДЬ", "СКАЛА", "УТЮГ", "ДУБ", "ТИТАН"],
        "nick_en": ["CONCRETE", "BEAR", "ROCK", "IRON", "OAK", "TITAN"]},
    {"id": "clincher", "ru": "КЛИНЧЕР", "en": "CLINCHER",
        "desc_ru": "липнет вплотную и молотит по корпусу",
        "desc_en": "sticks to your chest and hammers the body",
        "tip_ru": "Не давай ему войти вплотную: держи дистанцию джебом и уходи.",
        "tip_en": "Do not let him inside: keep the jab out and step away.",
        "hp": 1.16, "dmg": 1.00, "spd": 1.06, "stam": 1.26, "heavy": 0.20,
        "aggr": 0.88, "guard": 0.24, "dodge": 0.04, "wind": 1.00,
        "rec": 0.92, "range": 1.22, "combo": 2, "counter": 0.12,
        "mix": [0.12, 0.45, 0.36, 0.07],
        "look": ["red", "white", "heavy", "twelve"],
        "nick_ru": ["КЛЕЩ", "УДАВ", "ТИСКИ", "МЕЛЬНИЦА", "БУЛЬДОГ", "ЛИПКИЙ"],
        "nick_en": ["PINCHER", "BOA", "VICE", "MILL", "BULLDOG", "STICKY"]},
]

## Имена соперников: имя + прозвище стиля, без повторов на всю карьеру.
const OPP_FIRST_RU := ["АЛЕКСЕЙ", "МАКСИМ", "ИВАН", "ДМИТРИЙ", "СЕРГЕЙ", "АНДРЕЙ",
        "НИКИТА", "ПАВЕЛ", "РОМАН", "ЕГОР", "АРТЁМ", "КИРИЛЛ", "ГЛЕБ", "ТИМУР",
        "МАРК", "ДАНИИЛ"]
const OPP_FIRST_EN := ["ALEXEI", "MAXIM", "IVAN", "DMITRY", "SERGEI", "ANDREI",
        "NIKITA", "PAVEL", "ROMAN", "EGOR", "ARTEM", "KIRILL", "GLEB", "TIMUR",
        "MARK", "DANIIL"]

## Дистанция боя: 60 соперников карьеры + подсказка, что без прокачки дальше не пройти.
const FIGHT_COUNT := 60

const ASSESS_WIN_KO := [
    "Вот это работа. Он не понял, что его снесло — лучший комплимент.",
    "Чисто закрыл. Не зазнавайся: следующий будет злее.",
    "Хороший удар. Но я видел, как ты открывался — покажу на записи.",
]
const ASSESS_WIN_ROUGH := [
    "Победил, но пропустил больше, чем нужно. Работаем над защитой.",
    "Выиграл на характере. Это уважают, но так долго не протянешь.",
    "Было тяжело. Ты вытерпел — теперь учись не получать.",
]
const ASSESS_RINGOUT := [
    "Выкинул его за канаты — красиво. Но так может кончиться и для тебя.",
    "Публика такое любит. Судьи — не всегда. Аккуратнее с наклоном.",
    "Великолепный вылет. Только ногами не заигрывайся у края.",
]
const ASSESS_TIME := [
    "Держал темп — это хорошо. Но по очкам — не наш стиль. Нужен нокаут.",
    "Заработал очки и не дал себя поймать. Скучно, зато умно.",
    "Победа по очкам. Судьи любят активных — добавь давления в конце.",
]
const ASSESS_LOSE := [
    "Проиграл — не страшно. Ошибка была в ногах, я видел. Разберём.",
    "Он тебя переиграл в темпе. На следующем бою держи дистанцию.",
    "Голову выше. Такие бои учат больше, чем лёгкие победы.",
]
## Отдельная оценка, когда соперник уже объективно сильнее игрока.
const ASSESS_UPG := [
    "Он крепче и злее тебя. Без прокачки такой бой не вытянуть — иди в ПРОКАЧКУ.",
    "Вот что значит разница в подготовке. Вложи форму в силу и защиту.",
    "Такой темп на голых руках не держится. Прокачай здоровье и выносливость.",
]


const PROFILE_PATH := "user://profile.cfg"
const KEYS_PATH := "user://keys.cfg"
const SOUND_PATH := "user://sound.cfg"
const START_COINS := 300
const C_ACCENT := Color(0.22, 0.74, 0.97)
const C_AMBER := Color(0.98, 0.75, 0.14)
const C_RED := Color(0.97, 0.44, 0.44)

## Настраиваемые действия: id, подпись, клавиша по умолчанию, группа.
const ACTIONS := [
    {"id": "move_fwd", "label": "шаг вперёд", "label_en": "move forward", "def": KEY_W, "group": "движение"},
    {"id": "move_back", "label": "шаг назад", "label_en": "move back", "def": KEY_S, "group": "движение"},
    {"id": "move_left", "label": "шаг влево", "label_en": "move left", "def": KEY_A, "group": "движение"},
    {"id": "move_right", "label": "шаг вправо", "label_en": "move right", "def": KEY_D, "group": "движение"},
    {"id": "dodge", "label": "уклон", "label_en": "dodge", "def": KEY_SHIFT, "group": "движение"},
    {"id": "block", "label": "блок", "label_en": "block", "def": KEY_L, "group": "движение"},
    {"id": "punch_jab", "label": "джеб", "label_en": "jab", "def": KEY_J, "group": "удары"},
    {"id": "punch_hook_l", "label": "левый хук", "label_en": "left hook", "def": KEY_K, "group": "удары"},
    {"id": "punch_hook_r", "label": "правый хук", "label_en": "right hook", "def": KEY_I, "group": "удары"},
    {"id": "punch_upper", "label": "апперкот", "label_en": "uppercut", "def": KEY_U, "group": "удары"},
    {"id": "punch_cross", "label": "кросс", "label_en": "cross", "def": KEY_E, "group": "удары"},
]

## Корпусные удары: Ctrl + клавиша удара. В Input Map это отдельные действия,
## поэтому модификатор не путается с обычным ударом и не конфликтует с блоком
## (L) и уклоном (Shift). Сопоставление: действие -> удар, который анимируется.
const BODY_ACTIONS := {
    "punch_body_jab": "jab",
    "punch_body_cross": "cross",
    "punch_body_lhook": "lhook",
    "punch_body_rhook": "rhook",
    "punch_body_upper": "upper",
}
## Удар -> действие, чтобы взять настроенную игроком клавишу.
const PUNCH_ACTION := {
    "jab": "punch_jab",
    "cross": "punch_cross",
    "lhook": "punch_hook_l",
    "rhook": "punch_hook_r",
    "upper": "punch_upper",
}
## Модификатор корпусных ударов (одна константа, не разбросан по логике).
const BODY_MOD_KEY := KEY_CTRL
## Эти клавиши заняты меню и в настройку не попадают.
const RESERVED_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_C, KEY_T, KEY_R,
        KEY_P, KEY_F, KEY_V, KEY_H, KEY_F1, KEY_F11, KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

## Прокачка за отдельную валюту («форма»): 4 уровня, цена растёт.
## Чем выше пояс, тем важнее вложения: без них соперники быстро переигрывают.
const UPGRADES := [
    {"id": "power", "name": "СИЛА", "desc": "+10% урона за уровень"},
    {"id": "speed", "name": "СКОРОСТЬ", "desc": "удары быстрее на 7%"},
    {"id": "stamina", "name": "ВЫНОСЛИВОСТЬ", "desc": "+15% выносливости и её восстановления"},
    {"id": "guard", "name": "ЗАЩИТА", "desc": "−8% полученного урона"},
    {"id": "health", "name": "ЗДОРОВЬЕ", "desc": "+10% здоровья"},
]
const UPG_MAX := 4

const ROUND_TIME := 90.0
const RING_LIMIT := 3.0
const MIN_GAP := 1.12
const SPEED := 3.1
const ACCEL := 6.5
const DECEL := 4.2

var state: int = St.MENU
var player: Node3D
var enemy: Node3D
var hud: CanvasLayer
var sfx: Node
var cam: Camera3D
var arena: Node3D

var cam_shake := 0.0
var hitstop := 0.0
var flashes: Array = []

var timer := ROUND_TIME
var score := 0
var combo := 0
var comboTimer := 0.0
var ko_timer := 0.0
var ko_visual := false
var pending := ""
var result_bonus := 0
var high_score := 0
var clock := 0.0

# кошелёк, форма (валюта прокачки) и гардероб
var coins := START_COINS
var form := 0
var form_gain := 0
var upg := {"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0}
var belt := 0
var belt_wins := 0
var belt_won := false
var champion := false
var ai_skill := 0
## Текущий соперник: имя, стиль, параметры боя и внешность.
var opp: Dictionary = {}
var _enemy_look_key := ""
var lang_code := "ru"
var lang_override := ""
var belt_override := -1
var beltwins_override := -1
var fullscreen := false
var demo := false
var upgrade_sel := 0
var upgrade_msg := ""
var upgrade_msg_col := C_AMBER
var music_vol := 7
var sfx_vol := 9
var sound_sel := 0
var form_override := -1
var training := false
var training_hits := 0
var wins := 0
var matches := 0
var owned: Array = []
var look: Dictionary = {}
var coin_gain := 0
## Штраф за проигранный бой: списывается один раз, не больше, чем есть монет.
@export var points_loss_on_defeat: int = 40
var defeat_penalty := 0
var defeat_penalty_applied := false
## Буфер ввода удара: короткое окно, чтобы нажатие во время удара не терялось.
var punch_buf := ""
var punch_buf_body := false
var punch_buf_t := 0.0
var locker_sel := 0
var locker_opt := 0
var locker_msg := ""
var locker_msg_col := C_AMBER
var locker_msg_t := 0.0
var look_override: Dictionary = {}
var coins_override := -1
var locker_sel_override := -1
var locker_opt_override := -1
var keys: Dictionary = {}
var key_sel := 0
var key_wait := false
var keys_msg := ""
var keys_msg_col := C_AMBER
var settings_tab := 0
var game_sel := 0
var settings_back := St.MENU
var howto_back := St.MENU
var coach_tip := ""
var coach_line := ""
var tour_id := ""
var tour_wins := 0
var tour_done: Array = []
var tour_msg := ""
var tour_sel := 0
var tips_deck: Array = []
var last_tip := -1
var last_assess := -1
var story_sel := 0
var story_seen := false
var touch: CanvasLayer
var touch_ui := false
var touch_flag := false
var touch_body := false

var reset_armed := 0.0
var saved_flash := 0.0
var no_cash := false
var locker_test := false
var ui_test := false
var fight_test := false
var anim_test := false
var upg_test := false
var click_test := false
var career_test := false
var diff_test := false
var balance_test := false
var punch_test := false
var snd_test := false
var save_test := false
var coach_test := false
var story_test := false
var touch_test := false

var ai := {"state": "wait", "t": 0.8, "pending": "jab"}
var player_move := Vector3.ZERO
var player_vel := Vector3.ZERO
var chain := 0
var chain_t := 0.0
var knockdown_show := 0.0
var enemy_move := Vector3.ZERO
var _last_player_punch := ""

# клинч убран, остались только вылет за канаты
var ringout := false
var ringout_f: Node3D = null
var ringout_stage := 0
var ringout_t := 0.0
var ko_text := "КО!"
var steps_total := 0
var head_hits := 0

var autoplay := false
var shot_path := ""
var shot_delay := 1.4
var shot_taken := false
var splash_shot := ""
var splash_only := false
var sim_seconds := 0.0
var forced_state := ""
var pose_mode := ""
var pose_phase := 0.5
var pose_sheet := ""
var punch_kind_arg := ""
var cam_mode := ""
var solo := false
var passive := false
var no_ai := false
var selftest := false
var shots_dir := ""
var shots_count := 0
var shots_idx := 0
var shots_every := 0.05
var _shots_t := 0.0


## Крестик окна: успеть сохранить профиль до выхода.
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _save_profile()
        _save_sound()
        print("SAVE профиль сохранён при закрытии окна: пояс=", belt + 1,
                " взято=", belt_wins, "/", BELT_FIGHTS, " монет=", coins, " форма=", form)
        get_tree().quit()
    elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
        # «назад» на Android: из боя — пауза, из меню — выход, из экрана — назад
        if state == St.FIGHT or state == St.TRAINING:
            _set_state(St.PAUSE)
        elif state == St.MENU:
            _quit_game()
        elif state == St.PAUSE:
            _set_state(St.FIGHT)
        else:
            _set_state(St.MENU)


func _ready() -> void:
    _parse_args()
    _load_high_score()
    _load_sound()
    _load_profile()
    if belt_override >= 0:
        belt = clampi(belt_override, 0, BELTS.size() - 1)
    if beltwins_override >= 0:
        belt_wins = clampi(beltwins_override, 0, BELT_FIGHTS)
        champion = false
    if lang_override != "":
        lang_code = "en" if lang_override == "en" else "ru"
    Lang.set_code(lang_code)
    _setup_input()
    _build_world()

    player = FighterScript.new()
    player.name = "Player"
    add_child(player)
    player.setup(true, look)
    _apply_upgrades()
    player.impact.connect(_on_player_impact)
    player.footstep.connect(_on_step)
    player.knocked_down.connect(_on_knockdown.bind(player))

    enemy = FighterScript.new()
    enemy.name = "Enemy"
    add_child(enemy)
    enemy.setup(false)
    if solo:
        enemy.visible = false
    enemy.impact.connect(_on_enemy_impact)
    enemy.footstep.connect(_on_step)
    enemy.knocked_down.connect(_on_knockdown.bind(enemy))

    _reset_fight()
    # заставка для меню: один отрендеренный кадр, рисуем его один раз при запуске
    _apply_fullscreen()
    if DisplayServer.get_name() != "headless":
        await _make_splash()
    _apply_forced_state()

    if sim_seconds > 0.0:
        var steps := int(sim_seconds * 60.0)
        for i in steps:
            if state == St.FIGHT:
                _tick_fight(1.0 / 60.0)

    if selftest:
        _run_selftest()
    if locker_test:
        _run_lockertest()
    if ui_test:
        _run_uitest()
    if fight_test:
        _run_fighttest()
    if anim_test:
        _run_animtest()
    if upg_test:
        _run_upgtest()
    if click_test:
        _run_clicktest()
    if career_test:
        _run_careertest()
    if diff_test:
        _run_difftest()
    if balance_test:
        _run_balancetest()
    if punch_test:
        _run_punchtest()
    if snd_test:
        _run_sndtest()
    if save_test:
        _run_savetest()
    if coach_test:
        _run_coachtest()
    if story_test:
        _run_storytest()
    if touch_test:
        _run_touchtest()


func _run_selftest() -> void:
    _start_fight()
    var dt := 1.0 / 60.0
    var t := 0.0

    # разгон: давим вперёд, тело набирает скорость через силу
    player.reset(Vector3(0, 0, 0), 100.0)
    var p0 := player.position
    while player.vel.length() < player.MAX_SPEED * 0.9 and t < 4.0:
        player.drive(Vector3(0, 0, -1), dt)
        player.tick(dt)
        t += dt
    print("SELFTEST разгон_до_90%: ", snappedf(t, 0.001), " c, путь ",
            snappedf((player.position - p0).length(), 0.01), " м, скорость ",
            snappedf(player.vel.length(), 0.01))

    # тормозной путь
    p0 = player.position
    t = 0.0
    while player.vel.length() > 0.1 and t < 4.0:
        player.tick(dt)
        t += dt
    print("SELFTEST тормозной_путь: ", snappedf((player.position - p0).length(), 0.01),
            " м за ", snappedf(t, 0.001), " c")

    # шаги: сколько их и насколько они неравномерные (рэгдол-походка)
    player.reset(Vector3(0, 0, 0), 100.0)
    var step_marks: Array = []
    var last_steps: int = player.steps
    var lean_sum := 0.0
    var lean_max := 0.0
    t = 0.0
    while t < 2.6:
        player.drive(Vector3(0, 0, -1), dt)
        player.tick(dt)
        if player.steps != last_steps:
            last_steps = player.steps
            step_marks.append(t)
        lean_sum += player.tilt.length()
        lean_max = maxf(lean_max, player.tilt.length())
        t += dt
    var gaps: Array = []
    for i in range(1, step_marks.size()):
        gaps.append(float(step_marks[i]) - float(step_marks[i - 1]))
    var gap_min := 9.0
    var gap_max := 0.0
    for g in gaps:
        gap_min = minf(gap_min, float(g))
        gap_max = maxf(gap_max, float(g))
    print("SELFTEST шаги_за_2.6с: ", step_marks.size(), ", интервал ",
            snappedf(gap_min, 0.01), "..", snappedf(gap_max, 0.01), " c, пройдено ",
            snappedf((player.position - p0).length(), 0.01), " м")

    # пьяное качание в стойке: без ударов тело должно само ходить ходуном
    player.reset(Vector3(0, 0, 0), 100.0)
    var sway_max := 0.0
    var hx_min := 9.0
    var hx_max := -9.0
    var hz_min := 9.0
    var hz_max := -9.0
    for i in 300:
        player.tick(dt)
        sway_max = maxf(sway_max, player._lean.length())
        hx_min = minf(hx_min, player.head.global_position.x)
        hx_max = maxf(hx_max, player.head.global_position.x)
        hz_min = minf(hz_min, player.head.global_position.z)
        hz_max = maxf(hz_max, player.head.global_position.z)
    print("SELFTEST пьяное_качание: наклон до ", snappedf(sway_max, 0.001),
            " рад, голова гуляет на ", snappedf(hx_max - hx_min, 0.01), " м по X и ",
            snappedf(hz_max - hz_min, 0.01), " м по Z")

    # удар: отбрасывание, наклон и хит-стоп
    player.reset(Vector3(0, 0, -0.62), 100.0)
    enemy.reset(Vector3(0, 0, 0.62), 110.0)
    var ep := enemy.position
    var est: int = enemy.steps
    hitstop = 0.0
    _resolve(player, enemy, "upper")
    var tilt_max := 0.0
    t = 0.0
    while t < 0.8:
        enemy.tick(dt)
        tilt_max = maxf(tilt_max, enemy.tilt.length())
        t += dt
    print("SELFTEST апперкот: отброс ", snappedf((enemy.position - ep).length(), 0.01),
            " м, наклон ", snappedf(tilt_max, 0.01), " рад, шагов_для_баланса ",
            enemy.steps - est, ", хит-стоп ", snappedf(hitstop, 0.001), " c")

    # серия ударов валит соперника на настил
    var fell := false
    for i in 6:
        if enemy.fallen or enemy.ko:
            fell = true
            break
        player.position = enemy.position + Vector3(0, 0, -1.0)
        player.punch_kind = ""
        _resolve(player, enemy, "upper")
        enemy.tick(dt)
        if enemy.fallen:
            fell = true
    print("SELFTEST падение_от_серии: ", "да" if fell else "нет",
            ", ragdoll_деталей ", enemy.ragdoll_parts.size())


    # бросок из клинча: тело должно улетать физически
    state = St.FIGHT
    enemy.reset(Vector3(0, 0, 0.4), 110.0)
    var ep2 := enemy.position
    enemy.force_fall(Vector3(0, 0, -1), 3.4)
    var vm := 0.0
    for i in 45:
        await get_tree().physics_frame
        enemy.tick(dt)
        for k in enemy.ragdoll_parts:
            vm = maxf(vm, enemy.ragdoll_parts[k].linear_velocity.length())
    print("SELFTEST бросок: улетел на ", snappedf((enemy.position - ep2).length(), 0.01),
            " м, макс_скорость ", snappedf(vm, 0.01), " м/с")

    print("SELFTEST риг: стопа_", player.FOOT_Y, " нога_", player.LEG_UP + player.LEG_LO,
            " порог_шага_", player.LEG_MAX, " MAX_SPEED=", player.MAX_SPEED,
            " FALL_TILT=", player.FALL_TILT)
    get_tree().quit()

func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--shot="):
            shot_path = a.substr(7)
        elif a.begins_with("--delay="):
            shot_delay = float(a.substr(8))
        elif a.begins_with("--splashshot="):
            splash_shot = a.substr(13)
        elif a == "--splashonly":
            splash_only = true
        elif a.begins_with("--sim="):
            sim_seconds = float(a.substr(6))
        elif a.begins_with("--state="):
            forced_state = a.substr(8)
        elif a.begins_with("--pose="):
            pose_mode = a.substr(7)
        elif a.begins_with("--phase="):
            pose_phase = float(a.substr(8))
        elif a.begins_with("--poses="):
            pose_sheet = a.substr(8)
        elif a.begins_with("--punch="):
            punch_kind_arg = a.substr(8)
        elif a.begins_with("--cam="):
            cam_mode = a.substr(6)
        elif a == "--solo":
            solo = true
        elif a == "--auto" or a == "--autoplay":
            autoplay = true
        elif a == "--passive":
            autoplay = true
            passive = true
        elif a == "--noai":
            no_ai = true
        elif a == "--selftest":
            selftest = true
        elif a.begins_with("--frames="):
            var v := a.substr(9).split(",")
            shots_dir = v[0]
            shots_count = int(v[1]) if v.size() > 1 else 240
            if v.size() > 2:
                shots_every = float(v[2])
        elif a.begins_with("--coins="):
            coins_override = int(a.substr(8))
        elif a.begins_with("--form="):
            form_override = int(a.substr(7))
        elif a.begins_with("--lockersel="):
            locker_sel_override = int(a.substr(12))
        elif a.begins_with("--lockeropt="):
            locker_opt_override = int(a.substr(12))
        elif a.begins_with("--look="):
            for pair in a.substr(7).split(","):
                var kv := pair.split(":")
                if kv.size() == 2:
                    look_override[String(kv[0])] = String(kv[1])
        elif a == "--nocash":
            no_cash = true
        elif a == "--lockertest":
            locker_test = true
        elif a == "--uitest":
            ui_test = true
        elif a == "--fighttest":
            fight_test = true
        elif a == "--animtest":
            anim_test = true
        elif a == "--upgtest":
            upg_test = true
        elif a == "--clicktest":
            click_test = true
        elif a == "--careertest":
            career_test = true
        elif a == "--difftest":
            diff_test = true
        elif a == "--balancetest":
            balance_test = true
        elif a == "--sndtest":
            snd_test = true
        elif a == "--savetest":
            save_test = true
        elif a == "--coachtest":
            coach_test = true
        elif a == "--storytest":
            story_test = true
        elif a == "--touchtest":
            touch_test = true
            touch_flag = true
        elif a == "--touch":
            touch_flag = true
        elif a == "--touchbody":
            touch_flag = true
            touch_body = true
        elif a.begins_with("--lang="):
            lang_override = a.substr(7)
        elif a.begins_with("--belt="):
            belt_override = int(a.substr(7))
        elif a.begins_with("--beltwins="):
            beltwins_override = int(a.substr(11))
        elif a.begins_with("--penalty="):
            points_loss_on_defeat = maxi(0, int(a.substr(10)))
        elif a == "--punchtest":
            punch_test = true


# ---------------------------------------------------------------- сцена

func _build_world() -> void:
    var we := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.017, 0.021, 0.033)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.24, 0.3, 0.45)
    env.ambient_light_energy = 0.55
    env.glow_enabled = true
    env.glow_intensity = 0.45
    env.glow_bloom = 0.12
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color(0.05, 0.07, 0.11)
    env.fog_density = 0.006
    we.environment = env
    add_child(we)

    var dir := DirectionalLight3D.new()
    dir.light_energy = 0.35
    dir.rotation_degrees = Vector3(-58, 34, 0)
    add_child(dir)

    for sx in [-3.6, 3.6]:
        var spot := SpotLight3D.new()
        spot.position = Vector3(sx, 7.0, 2.2)
        spot.rotation_degrees = Vector3(-74, 0, 0)
        spot.light_energy = 14.0
        spot.spot_range = 20.0
        spot.spot_angle = 44.0
        spot.light_color = Color(0.86, 0.9, 1.0)
        add_child(spot)

    # световое пятно в центре ринга
    var top := SpotLight3D.new()
    top.position = Vector3(0, 8.5, 0.4)
    top.rotation_degrees = Vector3(-90, 0, 0)
    top.light_energy = 11.0
    top.spot_range = 16.0
    top.spot_angle = 34.0
    top.light_color = Color(1.0, 0.96, 0.9)
    add_child(top)

    arena = ArenaScript.new()
    arena.build()
    add_child(arena)

    cam = Camera3D.new()
    cam.fov = 46.0
    cam.far = 120.0
    add_child(cam)
    cam.position = Vector3(3.0, 3.1, 4.5)
    cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
    cam.current = true

    hud = HudScript.new()
    add_child(hud)
    hud.build()
    hud.on_button = func(id: String) -> void: _on_hud_button(id)

    sfx = SfxScript.new()
    add_child(sfx)
    sfx.build()
    _apply_sound()
    sfx.music_play(-20.0)
    print("MUSIC поток=", sfx.music.stream != null, " длительность=",
            sfx.music.stream.get_length() if sfx.music.stream != null else 0.0)

    # тач-управление: на телефоне всегда, на ПК — по флагу --touch (для кадров)
    touch_ui = touch_flag or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
    if touch_ui:
        touch = TouchScript.new()
        add_child(touch)
        touch.build()
        touch.punch.connect(func(kind: String) -> void: _player_punch(kind, touch.body_mode))
        touch.body_mode = touch_body
        touch.dodge.connect(_on_touch_dodge)
        touch.pause_pressed.connect(_on_touch_pause)
        print("TOUCH включено: тач=", DisplayServer.is_touchscreen_available(),
                " мобилка=", OS.has_feature("mobile"))


# ---------------------------------------------------------------- заставка

## Один раз собираем «фотографию» боя в отдельном вьюпорте и отдаём меню.
func _make_splash() -> void:
    var t0 := Time.get_ticks_msec()
    var sp := SplashScript.new()
    add_child(sp)
    var tex: Texture2D = await sp.render()
    sp.queue_free()
    if tex == null:
        return
    print("SPLASH готов за ", Time.get_ticks_msec() - t0, " мс")
    if splash_shot != "":
        var img := tex.get_image()
        var err := img.save_png(splash_shot)
        print("SPLASH снимок=", splash_shot, " err=", err, " размер=", img.get_size())
    if splash_only:
        print("SPLASH готов: ", tex.get_size())
        get_tree().quit()
        return
    hud.set_splash(tex)


# ---------------------------------------------------------------- тренер и турниры

## Следующий совет тренера: колода перемешивается, советы не повторяются.
func _next_tip() -> String:
    if tips_deck.is_empty():
        tips_deck = []
        for i in TIPS.size():
            if i != last_tip:
                tips_deck.append(i)
        tips_deck.shuffle()
    if tips_deck.is_empty():
        return String(TIPS[0])
    var idx: int = int(tips_deck.pop_back())
    last_tip = idx
    return String(TIPS[idx])


## Оценка боя тренером: зависит от исхода и того, как прошёл бой.
func _pick_assessment() -> String:
    var pool: Array = ASSESS_WIN_KO
    var won := pending == "win" or pending == "ringout" or pending == "timewin"
    if not won:
        # если соперник уже объективно сильнее — тренер прямо говорит про прокачку
        pool = ASSESS_UPG if (_fight_level() > 0.28 and _upg_total() < 5) else ASSESS_LOSE
    elif pending == "ringout":
        pool = ASSESS_RINGOUT
    elif pending == "timewin":
        pool = ASSESS_TIME
    elif player.taken > 55.0 or player.hp < 45.0:
        pool = ASSESS_WIN_ROUGH
    var idx := randi() % pool.size()
    if pool.size() > 1 and idx == last_assess:
        idx = (idx + 1) % pool.size()
    last_assess = idx
    return String(pool[idx])


## Номер боя карьеры (0..59): пояс и победы внутри пояса.
func _opp_index() -> int:
    var idx := belt * BELT_FIGHTS + belt_wins
    if tour_id != "":
        var t := _tournament_by_id(tour_id)
        var need := int(t.get("need", 0))
        idx = maxi(idx, need * BELT_FIGHTS + 4 + 4 * tour_wins)
    return clampi(idx, 0, FIGHT_COUNT - 1)


## Уровень боя 0..1: 0 — первый выход на ринг, 1 — последний пояс.
func _fight_level() -> float:
    return clampf(float(_opp_index()) / float(FIGHT_COUNT - 1), 0.0, 1.0)


func _opp_style() -> Dictionary:
    if opp.is_empty():
        return STYLES[0]
    return opp.get("style", STYLES[0])


func _opp_name(o: Dictionary) -> String:
    if o.is_empty():
        return Lang.t("opponent")
    var st: Dictionary = o.get("style", STYLES[0])
    var firsts: Array = OPP_FIRST_EN if Lang.is_en() else OPP_FIRST_RU
    var nicks: Array = st.get("nick_en", []) if Lang.is_en() else st.get("nick_ru", [])
    var fi := int(o.get("first", 0)) % firsts.size()
    var ni := int(o.get("nick", 0)) % nicks.size()
    return String(firsts[fi]) + " «" + String(nicks[ni]) + "»"


## Внешность соперника: цвета зависят от стиля, мелочи — от номера боя.
func _opp_look(o: Dictionary) -> Dictionary:
    var st: Dictionary = o.get("style", STYLES[0])
    var n := int(o.get("n", 0))
    var base: Array = st["look"]
    var skins := ["light", "pale", "tan", "olive", "dark", "deep"]
    var hairs := ["bald", "buzz", "mohawk", "tail", "afro"]
    var hair_cols := ["black", "brown", "blond", "red", "crimson", "gray", "blue"]
    var shorts := ["short", "long"]
    var boots := ["hi", "low", "bare"]
    var boots_cols := ["black", "red", "white", "blue", "gold"]
    return {
        "hair": String(hairs[(n * 3 + 1) % hairs.size()]),
        "hair_color": String(hair_cols[(n * 5 + 2) % hair_cols.size()]),
        "skin": String(skins[(n * 7 + 3) % skins.size()]),
        "build": String(base[2]),
        "gloves": String(base[3]),
        "gloves_color": String(base[1]),
        "shorts": String(shorts[n % shorts.size()]),
        "shorts_color": String(base[0]),
        "boots": String(boots[(n * 2) % boots.size()]),
        "boots_color": String(boots_cols[(n * 3) % boots_cols.size()]),
    }


## Собрать соперника под текущий бой: стиль, имя, цифры и внешность.
## Уровень растёт каждый бой, поэтому без прокачки дальше пояса не пройти.
func _make_opponent() -> Dictionary:
    var n := _opp_index()
    var level := clampf(float(n) / float(FIGHT_COUNT - 1), 0.0, 1.0)
    var si := (n * 5 + 3) % STYLES.size()
    var st: Dictionary = STYLES[si]
    var combo := (n * 61) % 96
    var o := {
        "n": n, "level": level, "style": st, "style_i": si,
        "first": combo / 6, "nick": combo % 6,
        "hp": 105.0 * (1.0 + 0.65 * level) * float(st["hp"]),
        "dmg": (0.88 + 0.92 * level) * float(st["dmg"]),
        "spd": (1.0 - 0.16 * level) * float(st["spd"]),
        "dmg_style": float(st["dmg"]),
        "spd_style": float(st["spd"]),
        "stam": 100.0 * float(st["stam"]),
    }
    o["name"] = _opp_name(o)
    o["look"] = _opp_look(o)
    return o


## Надеть соперника на бойца: здоровье, урон, скорость, выносливость и вид.
func _apply_opponent() -> void:
    opp = _make_opponent()
    ai_skill = int(round(float(opp["level"]) * 5.0))
    enemy.reset(Vector3(0, 0, -1.9), float(opp["hp"]))
    enemy.set_difficulty(float(opp["level"]))
    enemy.dmg_mult *= float(opp["dmg_style"])
    enemy.dur_mult *= float(opp["spd_style"])
    enemy.max_stamina = float(opp["stam"])
    enemy.stamina = enemy.max_stamina
    # на поздних поясах сбить с ног и выкинуть за канаты намного труднее
    enemy.fall_resist = clampf(0.55 * float(opp["level"])
            + float(_opp_style().get("heavy", 0.0)), 0.0, 1.0)
    player.fall_resist = 0.45 * float(opp["level"])
    # поздние соперники крепче держат удар: без прокачки силы их не пробить
    enemy.taken_mult = 1.0 - 0.35 * float(opp["level"])
    var lk: Dictionary = opp["look"]
    if _enemy_look_key != str(lk):
        _enemy_look_key = str(lk)
        enemy.set_look(lk)


func _upg_total() -> int:
    var s := 0
    for k in upg.keys():
        s += int(upg[k])
    return s


func _tournament(i: int) -> Dictionary:
    return TOURNAMENTS[clampi(i, 0, TOURNAMENTS.size() - 1)]


func _tournament_by_id(id: String) -> Dictionary:
    for t in TOURNAMENTS:
        if String(t["id"]) == id:
            return t
    return {}


func _tour_done(id: String) -> bool:
    return tour_done.has(id)


func _open_tournaments() -> void:
    tour_sel = clampi(tour_sel, 0, TOURNAMENTS.size() - 1)
    tour_msg = ""
    _set_state(St.TOUR)


func _close_tournaments() -> void:
    _save_profile()
    _set_state(St.MENU)


# ---------------------------------------------------------------- история

func _open_story() -> void:
    story_sel = clampi(story_sel, 0, StoryScript.PAGES.size() - 1)
    _set_state(St.STORY)


func _close_story() -> void:
    story_seen = true
    _save_profile()
    _set_state(St.MENU)


func _story_data() -> Dictionary:
    var pages: Array = []
    for i in StoryScript.PAGES.size():
        var p: Dictionary = StoryScript.PAGES[i]
        var num := ""
        if i == 0:
            num = Lang.t("story_prologue")
        else:
            num = Lang.t("story_chapter") + " " + str(i)
        pages.append({"title": String(p["title"]), "text": String(p["text"]),
                "num": num, "open": StoryScript.is_open(i, belt),
                "need": int(p["need"])})
    return {"pages": pages, "sel": story_sel}


func _story_key(code: int) -> void:
    match code:
        KEY_LEFT, KEY_A, KEY_UP, KEY_W:
            story_sel = wrapi(story_sel - 1, 0, StoryScript.PAGES.size())
            hud.show_story(_story_data())
        KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
            story_sel = wrapi(story_sel + 1, 0, StoryScript.PAGES.size())
            hud.show_story(_story_data())
        KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_Y, KEY_M:
            _close_story()


## Первый запуск: сразу показываем пролог, но только в живой игре (не в тестах).
func _maybe_story_intro() -> void:
    if demo or _testing() or story_seen or matches > 0:
        return
    story_sel = 0
    _set_state(St.STORY)


## Любой автотест или отладочный запуск: пролог сам не открываем.
func _testing() -> bool:
    return selftest or locker_test or ui_test or fight_test or anim_test or upg_test \
            or click_test or career_test or snd_test or save_test or coach_test \
            or story_test or touch_test \
            or shot_path != "" or forced_state != "" or pose_mode != ""


func _tour_key(code: int) -> void:
    match code:
        KEY_UP:
            tour_sel = wrapi(tour_sel - 1, 0, TOURNAMENTS.size())
            hud.show_tournaments(_tour_data())
        KEY_DOWN:
            tour_sel = wrapi(tour_sel + 1, 0, TOURNAMENTS.size())
            hud.show_tournaments(_tour_data())
        KEY_ENTER, KEY_SPACE:
            _tour_start(tour_sel)
        KEY_ESCAPE:
            _close_tournaments()


func _tour_data() -> Dictionary:
    var rows: Array = []
    for i in TOURNAMENTS.size():
        var t: Dictionary = TOURNAMENTS[i]
        var id := String(t["id"])
        var state_txt := ""
        var open := true
        if _tour_done(id):
            state_txt = "ВЗЯТ"
            open = false
        elif belt < int(t["need"]):
            state_txt = "НУЖЕН ПОЯС " + str(int(t["need"]) + 1)
            open = false
        elif tour_id == id:
            state_txt = "В ХОДЕ · " + str(tour_wins) + " / " + str(int(t["fights"]))
        rows.append({"name": String(t["name"]), "intro": String(t["intro"]),
                "reward": str(int(t["coins"])) + " монет · " + str(int(t["form"])) + " формы",
                "state": state_txt, "open": open, "need": int(t["need"]) + 1,
                "fights": int(t["fights"]), "done": _tour_done(id)})
    return {"rows": rows, "sel": tour_sel, "belt": belt, "msg": tour_msg, "touch": touch_ui}


## Старт турнирного боя: сначала карточка с советом тренера.
func _tour_start(i: int) -> void:
    var t := _tournament(i)
    var id := String(t["id"])
    if _tour_done(id) or belt < int(t["need"]):
        tour_msg = "этот турнир пока закрыт — нужен пояс " + str(int(t["need"]) + 1)
        hud.show_tournaments(_tour_data())
        return
    if tour_id != id:
        tour_id = id
        tour_wins = 0
    coach_tip = _next_tip()
    _save_profile()
    _start_prefight()


## Карточка «тренер перед боем».
func _start_career_fight() -> void:
    coach_tip = _next_tip()
    _start_prefight()


func _start_prefight() -> void:
    opp = _make_opponent()
    _set_state(St.PREFIGHT)


func _prefight_key(code: int) -> void:
    match code:
        KEY_ENTER, KEY_SPACE, KEY_J, KEY_U, KEY_K, KEY_I:
            _start_fight()
        KEY_ESCAPE:
            if tour_id != "" and tour_wins > 0:
                _open_tournaments()
            else:
                _set_state(St.MENU)


func _prefight_data() -> Dictionary:
    if opp.is_empty():
        opp = _make_opponent()
    var tour_txt := ""
    if tour_id != "":
        var t := _tournament_by_id(tour_id)
        tour_txt = String(t.get("name", "")) + " · бой " + str(tour_wins + 1) + " из " \
                + str(int(t.get("fights", 3)))
    var st: Dictionary = _opp_style()
    var level := float(opp.get("level", 0.0))
    var dots := ""
    var filled: int = clampi(1 + int(round(level * 4.0)), 1, 5)
    for i in 5:
        dots += "●" if i < filled else "○"
    var en := Lang.is_en()
    var hp_w := ["обычное", "крепкое", "очень крепкое"]
    var pw_w := ["обычная", "сильная", "очень сильная"]
    var sp_w := ["очень быстрая", "быстрая", "обычная", "медленная"]
    if en:
        hp_w = ["normal", "strong", "very strong"]
        pw_w = ["normal", "strong", "very strong"]
        sp_w = ["very fast", "fast", "normal", "slow"]
    var hp_rel := float(opp.get("hp", 105.0)) / 105.0
    var hp_word: String = hp_w[0] if hp_rel < 1.10 else (hp_w[1] if hp_rel < 1.30 else hp_w[2])
    var dmg_rel := float(opp.get("dmg", 1.0))
    var dmg_word: String = pw_w[0] if dmg_rel < 1.0 else (pw_w[1] if dmg_rel < 1.35 else pw_w[2])
    var spd_rel := float(opp.get("spd", 1.0))
    var spd_word: String = sp_w[0] if spd_rel < 0.88 else (sp_w[1] if spd_rel < 1.0
            else (sp_w[2] if spd_rel < 1.12 else sp_w[3]))
    var stats: String
    if en:
        stats = "HEALTH: " + hp_word + " · POWER: " + dmg_word + " · SPEED: " + spd_word
    else:
        stats = "ЗДОРОВЬЕ: " + hp_word + " · СИЛА: " + dmg_word + " · СКОРОСТЬ: " + spd_word
    return {"tip": coach_tip, "belt": belt, "belt_name": _belt_name(),
            "belt_color": _belt_color(), "belt_wins": belt_wins,
            "belt_fights": BELT_FIGHTS, "tour": tour_txt,
            "opp_name": String(opp.get("name", "")),
            "opp_style": String(st.get("en" if en else "ru", "")),
            "opp_desc": String(st.get("desc_en" if en else "desc_ru", "")),
            "opp_tip": String(st.get("tip_en" if en else "tip_ru", "")),
            "opp_stats": stats, "opp_dots": dots, "opp_level": level,
            "champion": champion, "touch": touch_ui}


## Двухшаговый сброс: первый Enter взводит, второй — стирает прогресс.
func _arm_reset() -> void:
    if reset_armed > 0.0:
        reset_armed = 0.0
        _reset_progress()
    else:
        reset_armed = clock
        hud.show_settings(_settings_data())


## Сброс прогресса: всё обратно к новичку, кроме ключей и громкости.
func _reset_progress() -> void:
    coins = START_COINS
    form = 0
    for u in UPGRADES:
        upg[String(u["id"])] = 0
    wins = 0
    matches = 0
    belt = 0
    belt_wins = 0
    champion = false
    tour_id = ""
    tour_wins = 0
    tour_done = []
    tips_deck = []
    last_tip = -1
    last_assess = -1
    story_sel = 0
    story_seen = false
    coach_tip = ""
    coach_line = ""
    tour_msg = ""
    owned = LookScript.default_owned()
    look = LookScript.default_look()
    if player != null:
        player.set_look(look)
        _apply_upgrades()
    high_score = 0
    _save_high_score()
    _save_profile()
    print("RESET прогресс сброшен: монет=", coins, " пояс=", belt + 1, " побед=", wins)
    _set_state(St.MENU)

# ---------------------------------------------------------------- экраны и данные

func _belt_name() -> String:
    var b: Dictionary = BELTS[clampi(belt, 0, BELTS.size() - 1)]
    return String(b["en"]) if Lang.is_en() else String(b["name"])


func _belt_color() -> Color:
    return BELTS[clampi(belt, 0, BELTS.size() - 1)]["color"]


func _menu_data() -> Dictionary:
    var lv := 0
    for u in upg:
        lv += int(upg[u])
    return {"high": high_score, "coins": coins, "form": form, "level": lv,
            "wins": wins, "matches": matches, "keys": _keys_text(),
            "belt": belt, "belt_wins": belt_wins, "belt_name": _belt_name(),
            "belt_color": _belt_color(), "belt_max": BELTS.size(),
            "belt_fights": BELT_FIGHTS, "champion": champion,
            "saved": saved_flash > 0.0,
            "tour_active": tour_id, "tour_wins": tour_wins,
            "tour_name": String(_tournament_by_id(tour_id).get("name", "")),
            "tour_done": tour_done.size(), "tour_total": TOURNAMENTS.size(),
            "touch": touch_ui}


func _result_data() -> Dictionary:
    return {"kind": pending, "score": score, "bonus": result_bonus,
            "hits": player.hits, "taken": int(player.taken), "hp": int(player.hp),
            "high": high_score, "coin_gain": coin_gain, "coins_total": coins,
            "wins": wins, "form_gain": form_gain, "form_total": form,
            "belt": belt, "belt_wins": belt_wins, "belt_name": _belt_name(),
            "belt_color": _belt_color(), "belt_fights": BELT_FIGHTS,
            "belt_won": belt_won, "champion": champion,
            "coach": coach_line, "tour": tour_msg,
            "tour_id": tour_id, "tour_wins": tour_wins,
            "tour_name": String(_tournament_by_id(tour_id).get("name", "")),
            "penalty": defeat_penalty}


func _howto_data() -> Dictionary:
    return {"keys": _keys_text(), "touch": touch_ui}


## Кнопки HUD (мышь и геймпад).
func _on_hud_button(id: String) -> void:
    match id:
        "play", "next":
            if state == St.RESULT or state == St.MENU:
                _start_career_fight()
        "tour":
            if state == St.MENU or state == St.RESULT:
                _open_tournaments()
        "tourstart":
            if state == St.TOUR:
                _tour_start(tour_sel)
        "story":
            if state == St.MENU or state == St.RESULT:
                _open_story()
        "storyback":
            if state == St.STORY:
                _close_story()
        "tourrow0", "tourrow1", "tourrow2":
            if state == St.TOUR:
                tour_sel = int(id.substr(7))
                hud.show_tournaments(_tour_data())
        "fight":
            if state == St.PREFIGHT:
                _start_fight()
        "reset":
            if state == St.SETTINGS:
                _reset_progress()
        "locker":
            if state == St.MENU or state == St.RESULT:
                _open_locker()
        "upgrade":
            if state == St.MENU or state == St.RESULT:
                _open_upgrades()
        "training":
            if state == St.MENU or state == St.RESULT:
                _open_training()
        "howto":
            if state != St.HOWTO:
                _open_howto()
        "settings":
            if state == St.MENU or state == St.RESULT or state == St.PAUSE:
                _open_settings(0)
        "back":
            if state == St.HOWTO:
                _close_howto()
        "exit":
            _quit_game()
        "resume":
            if state == St.PAUSE:
                _set_state(St.FIGHT)
        "tomenu":
            if state == St.PAUSE or state == St.RESULT or state == St.TRAINING:
                _leave_to_menu()
        "tab0":
            _settings_tab(0)
        "tab1":
            _settings_tab(1)
        "tab2":
            _settings_tab(2)
        # --- мобильные нажатия
        "back_all":
            _back_any()
        "storyprev":
            _story_step(-1)
        "storynext":
            _story_step(1)
        "gamerow0":
            game_sel = 0
            _game_activate()
        "gamerow1":
            game_sel = 1
            _game_activate()
        "gamerow2":
            game_sel = 2
            _game_activate()
        _:
            _touch_row_button(id)


## Тап по строке списка: прокачка, гардероб, ползунок громкости.
func _touch_row_button(id: String) -> void:
    if id.begins_with("upgrow"):
        upgrade_sel = clampi(int(id.substr(6)), 0, UPGRADES.size() - 1)
        _upgrade_buy()
    elif id.begins_with("lockercat"):
        locker_sel = clampi(int(id.substr(9)), 0, LookScript.CATALOG.size() - 1)
        locker_opt = 0
        hud.show_locker(_locker_data())
    elif id.begins_with("lockeritem"):
        var cat_now: Dictionary = LookScript.CATALOG[clampi(locker_sel, 0, LookScript.CATALOG.size() - 1)]
        locker_opt = clampi(int(id.substr(10)), 0, (cat_now["items"] as Array).size() - 1)
        _locker_apply()
    elif id.begins_with("snd:"):
        var parts: PackedStringArray = id.split(":")
        if parts.size() == 3:
            var row := int(parts[1])
            var val := clampi(int(parts[2]), 0, 10)
            sound_sel = clampi(row, 0, 1)
            if sound_sel == 0:
                music_vol = val
            else:
                sfx_vol = val
            _apply_sound()
            _save_sound()
            if sound_sel == 1:
                sfx.play("hit", 1.0, -6.0)
            _refresh_settings()


## «← НАЗАД» на экране: ведёт себя как Esc в этом состоянии.
func _back_any() -> void:
    match state:
        St.PAUSE:
            _set_state(St.FIGHT)
        St.SETTINGS:
            _close_settings()
        St.UPGRADE:
            _close_upgrades()
        St.CUSTOM:
            _close_locker()
        St.HOWTO:
            _close_howto()
        St.TOUR:
            _close_tournaments()
        St.STORY:
            _close_story()
        St.PREFIGHT:
            _prefight_key(KEY_ESCAPE)
        St.RESULT:
            _leave_to_menu()


func _story_step(dir: int) -> void:
    story_sel = wrapi(story_sel + dir, 0, StoryScript.PAGES.size())
    hud.show_story(_story_data())


func _open_howto() -> void:
    howto_back = St.MENU if state == St.MENU or state == St.RESULT else St.PAUSE
    _set_state(St.HOWTO)


func _close_howto() -> void:
    if howto_back == St.PAUSE:
        _set_state(St.PAUSE)
    else:
        _set_state(St.MENU)


func _howto_key(code: int) -> void:
    match code:
        KEY_ESCAPE, KEY_H, KEY_F1, KEY_ENTER, KEY_SPACE:
            _close_howto()


## Выход из игры: на вебе кнопки нет, там закрывают вкладку.
## Выход в главное меню из боя/итога: прогресс сохраняется на диск.
func _leave_to_menu() -> void:
    training = false
    no_ai = false
    if enemy != null:
        enemy.no_fall = false
    _save_profile()
    _save_sound()
    saved_flash = 1.0
    print("SAVE профиль сохранён: пояс=", belt + 1, " взято=", belt_wins, "/", BELT_FIGHTS,
            " монет=", coins, " форма=", form, " побед=", wins, " матчей=", matches)
    _reset_fight()
    _set_state(St.MENU)


func _quit_game() -> void:
    if OS.has_feature("web"):
        return
    _save_profile()
    get_tree().quit()


func _toggle_fullscreen() -> void:
    fullscreen = not fullscreen
    _apply_fullscreen()
    _save_profile()


func _apply_fullscreen() -> void:
    if OS.has_feature("web"):
        return
    var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
    DisplayServer.window_set_mode(mode)


func _set_lang(code: String) -> void:
    lang_code = "en" if code == "en" else "ru"
    Lang.set_code(lang_code)
    _save_profile()
    if state == St.SETTINGS:
        hud.show_settings(_settings_data())
    elif state == St.MENU:
        hud.show_menu(_menu_data())
    elif state == St.RESULT:
        hud.show_result(_result_data())
    elif state == St.HOWTO:
        hud.show_howto(_howto_data())

# ---------------------------------------------------------------- состояние

func _reset_fight() -> void:
    timer = ROUND_TIME
    score = 0
    combo = 0
    comboTimer = 0.0
    chain = 0
    chain_t = 0.0
    player_vel = Vector3.ZERO
    ko_timer = 0.0
    ko_visual = false
    pending = ""
    result_bonus = 0
    ringout = false
    ringout_f = null
    ringout_stage = 0
    ringout_t = 0.0
    Engine.time_scale = 1.0
    ko_text = "КО!"
    steps_total = 0
    head_hits = 0
    training_hits = 0
    defeat_penalty = 0
    defeat_penalty_applied = false
    punch_buf = ""
    punch_buf_body = false
    punch_buf_t = 0.0
    ai = {"state": "wait", "t": 0.9, "pending": "jab", "combo": 0, "counter_ok": false}
    player.preview = false
    player.reset(Vector3(0, 0, 1.9), 100.0)
    # соперник свой на каждый бой: уровень, стиль, имя и внешность
    _apply_opponent()
    _face_each_other()
    _refresh_hud()


func _apply_forced_state() -> void:
    if forced_state != "" or pose_mode != "" or shot_path != "":
        demo = true
    if pose_mode != "":
        _start_fight()
        if pose_sheet != "":
            _run_pose_sheet()
        else:
            _apply_pose()
    elif autoplay or forced_state == "fight":
        _start_fight()
    elif forced_state == "menu":
        _set_state(St.MENU)
    elif forced_state == "locker":
        _open_locker()
    elif forced_state == "hit":
        _start_fight()
        player.position = Vector3(0, 0, 0.55)
        enemy.position = Vector3(0, 0, -0.55)
        _face_each_other()
        _punch(player, enemy, "jab")
        # прокручиваем до момента попадания, чтобы кадр поймал контакт и искру
        for i in 9:
            _tick_fight(1.0 / 60.0)
    elif forced_state == "punch":
        # живой удар без прокрутки: покадровая съёмка всей анимации
        no_ai = true
        _start_fight()
        player.reset(Vector3(0.02, 0, 0.60), 100.0)
        enemy.reset(Vector3(0.0, 0, -0.22), 110.0)
        _face_each_other()
        var pk := "jab" if punch_kind_arg == "" else punch_kind_arg
        _punch(player, enemy, pk, pk.begins_with("body_"))
    elif forced_state == "keys" or forced_state == "settings":
        _open_settings(0)
    elif forced_state == "game" or forced_state == "lang":
        _open_settings(2)
    elif forced_state == "howto":
        _open_howto()
    elif forced_state == "pause":
        _start_fight()
        _set_state(St.PAUSE)
    elif forced_state == "prefight":
        coach_tip = _next_tip()
        _start_prefight()
    elif forced_state == "tour":
        _open_tournaments()
    elif forced_state == "story":
        story_sel = 0
        _set_state(St.STORY)
    elif forced_state == "upgrade":
        _open_upgrades()
    elif forced_state == "leave":
        _start_fight()
        _set_state(St.PAUSE)
        _leave_to_menu()
    elif forced_state == "sound":
        _open_settings(1)
    elif forced_state == "upgrade":
        form = maxi(form, form_override if form_override >= 0 else 800)
        _open_upgrades()
    elif forced_state == "training":
        _open_training()
    elif forced_state == "result":
        _reset_fight()
        pending = "win"
        result_bonus = 200 + int(player.hp * 3.0)
        score = 640
        player.hits = 12
        player.taken = 31.0
        player.hp = 69.0
        _finalize()
    elif forced_state == "resultlose":
        # кадр итога поражения: штраф видно, но профиль не пишется (demo)
        _reset_fight()
        pending = "lose"
        score = 480
        player.hits = 5
        player.taken = 100.0
        player.hp = 0.0
        defeat_penalty = maxi(points_loss_on_defeat, 0)
        _finalize()
    elif forced_state == "chain":
        _start_fight()
        chain = 3
        chain_t = 900.0
        score = 420
        player.hits = 9
        player.taken = 18.0
        player.hp = 72.0
        enemy.hp = 41.0
    elif forced_state == "ragdoll":
        _start_fight()
        enemy.hp = 0.0
        enemy.ko = true
        enemy.enter_ragdoll(Vector3(0.0, 2.0, 2.4))
        _end_fight("win", true)
    elif forced_state == "ringout":
        _start_fight()
        enemy.position = Vector3(0, 0, -2.7)
        enemy.force_fall(Vector3(0, 0, -1), 6.5)
    elif forced_state == "ko":
        _start_fight()
        enemy.ko = true
        enemy.hp = 0.0
        ko_visual = true
        pending = "win"
        ko_timer = 1.5
        _set_state(St.KO)
    else:
        _set_state(St.MENU)
    # отладочный кадр: показать мобильные кнопки с включённым корпусом
    if touch_ui and touch != null and touch_body:
        touch.body_mode = true
        touch.pad.queue_redraw()


func _start_fight() -> void:
    _reset_fight()
    state = St.FIGHT
    # на ринге видно, против кого бой: имя вместо общей подписи
    hud.set_opponent_name(String(opp.get("name", "")))
    # карточка тренера и меню прячут полоски — бой обязан включить их обратно
    hud.set_battle_visible(true)
    if touch_ui and touch != null:
        touch.set_active(true)
    hud.hide_overlay()
    sfx.play("bell", 1.0, -6.0)
    sfx.music_play(-13.0)


func _set_state(s: int) -> void:
    state = s
    if touch_ui and touch != null:
        touch.set_active(s == St.FIGHT or s == St.TRAINING)
    match s:
        St.MENU:
            hud.set_battle_visible(true)
            hud.set_training(false, form)
            hud.show_menu(_menu_data())
            sfx.music_volume(-20.0)
            sfx.music_pause(false)
            saved_flash = 0.0
            _maybe_story_intro()
        St.FIGHT:
            hud.set_battle_visible(true)
            hud.hide_overlay()
            hud.set_training(training, form)
            sfx.music_volume(-13.0)
            sfx.music_pause(false)
        St.PAUSE:
            hud.show_pause()
            sfx.music_pause(true)
            _save_profile()
        St.KO:
            if ko_visual:
                hud.show_ko(ko_text)
            else:
                hud.hide_overlay()
        St.CUSTOM:
            hud.set_battle_visible(false)
            hud.show_locker(_locker_data())
            sfx.music_volume(-20.0)
        St.SETTINGS:
            hud.set_battle_visible(false)
            hud.show_settings(_settings_data())
            sfx.music_volume(-20.0)
        St.UPGRADE:
            hud.set_battle_visible(false)
            hud.show_upgrades(_upgrades_data())
            sfx.music_volume(-20.0)
        St.TRAINING:
            hud.set_battle_visible(true)
            hud.hide_overlay()
            hud.set_training(true, form)
            sfx.music_volume(-16.0)
            sfx.music_pause(false)
        St.RESULT:
            hud.set_battle_visible(true)
            hud.set_training(false, form)
            hud.show_result(_result_data())
        St.HOWTO:
            hud.set_battle_visible(false)
            hud.show_howto({"keys": _keys_text()})
            sfx.music_volume(-20.0)
        St.PREFIGHT:
            hud.set_battle_visible(false)
            hud.show_prefight(_prefight_data())
            sfx.music_volume(-20.0)
            sfx.music_pause(false)
        St.TOUR:
            hud.set_battle_visible(false)
            hud.show_tournaments(_tour_data())
            sfx.music_volume(-20.0)
            sfx.music_pause(false)
        St.STORY:
            hud.set_battle_visible(false)
            hud.show_story(_story_data())
            sfx.music_volume(-20.0)
            sfx.music_pause(false)


func _start_or_restart() -> void:
    _start_fight()


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
    clock += delta
    cam_shake = maxf(0.0, cam_shake - delta * 26.0)
    _update_flashes(delta)

    if pose_mode != "":
        _apply_pose()
        _update_hud()
        _update_camera(delta)
        _check_shot()
        return

    # хит-стоп: на попадании мир замирает на пару кадров — удар чувствуется весомее
    if hitstop > 0.0 and (state == St.FIGHT or state == St.TRAINING):
        hitstop = maxf(0.0, hitstop - delta)
        _update_hud()
        _update_camera(delta)
        _check_shot()
        return

    match state:
        St.FIGHT, St.TRAINING:
            _tick_fight(delta)
        St.KO:
            _tick_ko(delta)
        St.CUSTOM:
            player.tick(delta)
            if locker_msg_t > 0.0:
                locker_msg_t = maxf(0.0, locker_msg_t - delta)
                if locker_msg_t <= 0.0 and locker_msg != "":
                    locker_msg = ""
                    hud.show_locker(_locker_data())
        St.MENU, St.RESULT, St.SETTINGS, St.UPGRADE, St.PREFIGHT, St.TOUR:
            player.tick(delta)
            enemy.tick(delta)

    if state != St.CUSTOM and state != St.SETTINGS and state != St.UPGRADE \
            and state != St.PREFIGHT and state != St.TOUR:
        _update_hud()
    _update_camera(delta)
    _check_shot()

    _maybe_frames(delta)



func _maybe_frames(_delta: float) -> void:
    if shots_dir == "":
        return
    _shots_t += _delta
    if _shots_t < shots_every:
        return
    _shots_t = 0.0
    var idx := shots_idx
    shots_idx += 1
    # ждём отрисовку кадра: без этого get_image() иногда отдаёт пустой буфер
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    var path := "%s/f_%04d.png" % [shots_dir, idx]
    img.save_png(path)
    if forced_state != "":
        print("FRAME ", idx, " state=", state, " p=", player.position,
                " e=", enemy.position, " упал=", player.fallen, "/", enemy.fallen,
                " ко=", player.ko, "/", enemy.ko, " cam=", cam.position.snapped(Vector3(0.01, 0.01, 0.01)),
                " cam_mode=", cam_mode, " cur_cam=", get_viewport().get_camera_3d(),
                " body=", player.body.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
                " pvis=", player.visible, "/", player.body.visible,
                " torsoY=", player.torso.global_transform.basis.y.snapped(Vector3(0.01, 0.01, 0.01)),
                " lean=", player._lean.snapped(Vector2(0.01, 0.01)),
                " hips=", player.hips.position.snapped(Vector3(0.01, 0.01, 0.01)),
                " trot=", player.hips.rotation.snapped(Vector3(0.01, 0.01, 0.01)),
                " chest=", player.rj_chest.p.snapped(Vector3(0.01, 0.01, 0.01)),
                " ctgt=", player.rj_chest.tgt.snapped(Vector3(0.01, 0.01, 0.01)),
                " pel=", player.rj_pelvis.p.snapped(Vector3(0.01, 0.01, 0.01)),
                " ptgt=", player.rj_pelvis.tgt.snapped(Vector3(0.01, 0.01, 0.01)))
    if shots_idx >= shots_count:
        print("FRAMES done ", shots_idx)
        get_tree().quit()
func _apply_pose() -> void:
    player.position = Vector3(0.04, 0, 0.78)
    enemy.position = Vector3(0, 0, -0.6)
    _face_each_other()
    # поза удара: бойцы на дистанции удара, игрок целится в голову
    var pk := pose_mode
    if pk == "hook":
        pk = "lhook"
    if pk in ["jab", "cross", "lhook", "rhook", "upper"]:
        _pose_once(pk, pose_phase)
        return
    match pose_mode:
        "dodge":
            player.dodge_t = 0.4
            player.evading = true
            player.freeze_pose("", 0.0)
            enemy.freeze_pose("", 0.0)
        "block":
            player.blocking = true
            player.freeze_pose("", 0.0)
            enemy.telegraph = true
            enemy.freeze_pose("", 0.0)
        "telegraph":
            enemy.telegraph = true
            enemy.freeze_pose("", 0.0)
            player.freeze_pose("", 0.0)
        "ko":
            enemy.position = Vector3(0.9, 0, -0.9)
            player.position = Vector3(-1.0, 0, 1.2)
            _face_each_other()
            enemy.ko = true
            enemy.ko_fall = 1.0
            enemy.freeze_pose("", 0.0)
            player.freeze_pose("", 0.0)
            cam_shake = 0.0
        "walk":
            # шаг от физики: передняя стопа уже впереди, задняя тянется
            player.freeze_pose("", 0.0)
            player.rj_foot_l.p = player.to_global(Vector3(-0.17, 0.09, -0.34))
            player.rj_foot_r.p = player.to_global(Vector3(0.17, 0.16, 0.26))
            player.vel = Vector3(0, 0, -1.6)
            player.turn_lean(Vector2(0.0, 0.25))
            for i in 6:
                player.tick(1.0 / 60.0)
            player.freeze_pose("", 0.0)
            enemy.freeze_pose("", 0.0)
        _:
            player.freeze_pose("", 0.0)
            enemy.freeze_pose("", 0.0)


## Отладочная раскадровка удара: ставит позу на заданных фазах и сохраняет
## кадры <prefix>_00.png… — по ним видно, похож ли удар на настоящий.
func _run_pose_sheet() -> void:
    var phases := [0.0, 0.16, 0.28, 0.38, 0.48, 0.58, 0.70, 0.84, 1.0]
    for i in phases.size():
        pose_phase = float(phases[i])
        _pose_once(pose_mode, pose_phase)
        for f in 3:
            await get_tree().process_frame
        await RenderingServer.frame_post_draw
        var img := get_viewport().get_texture().get_image()
        img.save_png("%s_%02d.png" % [pose_sheet, i])
        print("POSESHEET ", i, " phase=", pose_phase, " kind=", pose_mode,
                " torsoY=", player.torso.global_transform.basis.y.snapped(Vector3(0.01, 0.01, 0.01)),
                " head=", player.head.global_position.snapped(Vector3(0.01, 0.01, 0.01)),
                " glove=", player.glove_point(str(player.punch_info(pose_mode)["arm"])).snapped(Vector3(0.01, 0.01, 0.01)),
                " aim=", player.punch_aim.snapped(Vector3(0.01, 0.01, 0.01)))
    print("POSESHEET done")
    get_tree().quit()


## Одна поза удара с чистого листа: сбрасываем бойцов, чтобы на кадр не
## налезали остатки предыдущей позы и шагов.
func _pose_once(kind: String, phase: float) -> void:
    var pk := "lhook" if kind == "hook" else kind
    player.reset(Vector3(0.04, 0, 0.52), 100.0)
    enemy.reset(Vector3(0, 0, -0.2), 120.0)
    _face_each_other()
    player.punch_aim = _aim_at(enemy)
    enemy.blocking = pk == "jab"
    player.freeze_pose(pk, phase, false)
    enemy.freeze_pose("", 0.0, false)


func _check_shot() -> void:
    if shot_path != "" and not shot_taken and clock >= shot_delay:
        shot_taken = true
        _take_shot()


func _tick_fight(delta: float) -> void:
    if ringout_stage == 1:
        player.tick(delta)
        enemy.tick(delta)
        _ropes_tick(delta)
        _update_ringout(delta)
        return
    if not training:
        timer = maxf(0.0, timer - delta)
    comboTimer = maxf(0.0, comboTimer - delta)
    if comboTimer <= 0.0:
        combo = maxi(0, combo - 1)
    if chain_t > 0.0:
        chain_t = maxf(0.0, chain_t - delta)
        if chain_t <= 0.0:
            chain = 0

    # буфер удара: если игрок нажал во время предыдущего удара, дожимаем
    # нажатие в ближайший свободный кадр (окно 0.16 с), а не выбрасываем его
    if punch_buf_t > 0.0 and not autoplay:
        punch_buf_t = maxf(0.0, punch_buf_t - delta)
        if punch_buf != "" and player.punch_kind == "" and player.stun <= 0.001 \
                and not player.ko and not player.evading and not player.blocking:
            var bk := punch_buf
            var bb := punch_buf_body
            punch_buf = ""
            punch_buf_t = 0.0
            _try_player_punch(bk, bb)
        elif punch_buf_t <= 0.0:
            punch_buf = ""

    if autoplay:
        _autopilot(delta)
    elif not no_ai:
        _player_input(delta)
    if not no_ai:
        _ai_tick(delta)

    player.tick(delta)
    enemy.tick(delta)
    if training:
        # манекен не падает и не кончается: здоровье возвращается, его тянет назад
        enemy.hp = enemy.max_hp
        enemy.stamina = enemy.max_stamina
        enemy.ko = false
        enemy.position = enemy.position.lerp(Vector3(0.0, 0.0, -0.35),
                clampf(delta * 2.5, 0.0, 1.0))
    if not player.fallen and not player.ko:
        _clamp_ring(player)
    if not enemy.fallen and not enemy.ko:
        _clamp_ring(enemy)
    _separate(delta)
    _face_each_other()
    _ropes_tick(delta)
    steps_total = player.steps + enemy.steps
    if knockdown_show > 0.0:
        knockdown_show = maxf(0.0, knockdown_show - delta)
    hud.set_knockdown(knockdown_show > 0.0 and not player.ko and not enemy.ko)

    if state != St.FIGHT and state != St.TRAINING:
        return
    if training:
        hud.set_training(true, form)
    elif timer <= 0.0:
        _end_by_time()



# ---------------------------------------------------------------- канаты

func _ropes_tick(delta: float) -> void:
    for f in [player, enemy]:
        if f == null or f.ragdoll == null:
            continue
        var pel = f.ragdoll_parts.get("pelvis")
        if pel == null:
            continue
        var pp: Vector3 = pel.global_position
        var spd: float = pel.linear_velocity.length()
        # тело, летящее высоко или быстро, проходит сквозь канаты — они под ним прогибаются
        var flying: bool = spd > 2.8 or pp.y > 0.95
        var rim := 3.44
        for k in f.ragdoll_parts.keys():
            var rb: RigidBody3D = f.ragdoll_parts[k]
            var p: Vector3 = rb.global_position
            var ox := 0.0
            var oz := 0.0
            if absf(p.x) > rim:
                ox = signf(p.x)
            if absf(p.z) > rim:
                oz = signf(p.z)
            if ox == 0.0 and oz == 0.0:
                continue
            if flying:
                if arena:
                    arena.rope_hit(p, Vector3(ox, 0.0, oz), clampf(spd * 0.55, 0.5, 2.4))
                continue
            # вялое тело канаты пружинят обратно, не выпуская за ринг
            if ox != 0.0:
                rb.linear_velocity.x = -ox * absf(rb.linear_velocity.x) * 0.35
                rb.global_position.x = ox * (rim - 0.02)
            if oz != 0.0:
                rb.linear_velocity.z = -oz * absf(rb.linear_velocity.z) * 0.35
                rb.global_position.z = oz * (rim - 0.02)
            if arena:
                arena.rope_hit(p, Vector3(ox, 0.0, oz), 0.9)
                arena.pulse(0.07)
            if randf() < 0.3:
                sfx.play("shove", randf_range(1.15, 1.35), -21.0)
        if not ringout and ringout_stage == 0 and (absf(pp.x) > 3.75 or absf(pp.z) > 3.75) \
                and (spd > 2.9 or pp.y > 1.15):
            _begin_ringout(f)


## Вылет за канаты: замедляем время, ведём камеру за телом, даём ему упасть
## на пол зала и только потом показываем итог.
func _begin_ringout(f: Node3D) -> void:
    if ringout:
        return
    ringout = true
    ringout_f = f
    ringout_stage = 1
    ringout_t = 0.0
    knockdown_show = 0.0
    hud.set_knockdown(false)
    Engine.time_scale = 0.42
    print("RINGOUT ", "enemy" if f == enemy else "player")
    cam_shake = maxf(cam_shake, 9.0)
    sfx.play("gasp", 0.9, -3.0)
    sfx.play("cheer", 1.0, -6.0)
    if arena:
        arena.pulse(0.95)
    f.ko = true
    f.hp = minf(f.hp, 1.0)
    f.down_t = 900.0
    f.stun = 900.0
    if f == enemy:
        score += 150
    # подброс вверх и кувырок: тело переваливает через верхний канат, а не
    # пролетает сквозь него по прямой
    if f.ragdoll != null:
        var outward := Vector3(rpel_dir(f).x, 0.0, rpel_dir(f).z).normalized()
        for k in f.ragdoll_parts.keys():
            var rb: RigidBody3D = f.ragdoll_parts[k]
            var horiz := Vector3(rb.linear_velocity.x, 0.0, rb.linear_velocity.z)
            if horiz.length() < 0.1:
                horiz = outward
            horiz = horiz.normalized() * 1.45
            rb.linear_velocity = horiz + Vector3(0.0, 1.05, 0.0)
            rb.angular_velocity += Vector3(randf_range(-3.0, 3.0),
                    randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))


func rpel_dir(f: Node3D) -> Vector3:
    var pel = f.ragdoll_parts.get("pelvis")
    if pel == null:
        return -f.global_transform.basis.z
    var p: Vector3 = pel.global_position
    return Vector3(p.x, 0.0, p.z)


func _update_ringout(delta: float) -> void:
    if ringout_stage != 1:
        return
    ringout_t += delta / maxf(Engine.time_scale, 0.05)
    var pel = null
    if ringout_f != null:
        pel = ringout_f.ragdoll_parts.get("pelvis")
    var landed := false
    if pel != null:
        var pp: Vector3 = pel.global_position
        var spd: float = pel.linear_velocity.length()
        if ringout_t > 0.7 and pp.y < 0.55 and spd < 2.2:
            landed = true
    if landed or ringout_t > 2.6:
        _finish_ringout()


func _finish_ringout() -> void:
    ringout_stage = 2
    Engine.time_scale = 1.0
    if ringout_f == enemy:
        ko_text = "ЗА КАНАТЫ!"
        _end_fight("ringout", true)
    else:
        ko_text = "ТЫ ВЫЛЕТЕЛ"
        _end_fight("ringoutlose", true)

func _tick_ko(delta: float) -> void:
    ko_timer -= delta
    player.tick(delta * 0.5)
    enemy.tick(delta * 0.5)
    if ko_timer <= 0.0:
        _finalize()


# ---------------------------------------------------------------- ввод и ИИ

func _read_move() -> Vector3:
    var dir := Vector3.ZERO
    var fwd := -cam.global_transform.basis.z
    fwd.y = 0.0
    fwd = fwd.normalized()
    var right := cam.global_transform.basis.x
    right.y = 0.0
    right = right.normalized()
    if Input.is_action_pressed("move_fwd") or Input.is_key_pressed(KEY_UP):
        dir += fwd
    if Input.is_action_pressed("move_back") or Input.is_key_pressed(KEY_DOWN):
        dir -= fwd
    if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_LEFT):
        dir -= right
    if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_RIGHT):
        dir += right
    # стик: вверх — вперёд, вправо — вправо
    if touch_ui and touch != null and touch.move.length() > 0.01:
        dir += fwd * (-touch.move.y) + right * touch.move.x
    if dir.length() > 0.01:
        dir = dir.normalized()
    return dir


func _player_input(delta: float) -> void:
    if autoplay:
        return
    if player.ko:
        player_move = Vector3.ZERO
        return
    if Input.is_action_pressed("dodge") and not player.evading and player.stun <= 0.001:
        player.try_dodge()
    var touch_block: bool = touch_ui and touch != null and bool(touch.block)
    player.blocking = (Input.is_action_pressed("block") or touch_block) \
            and not player.evading and player.stun <= 0.001 and not player.ko
    if player.stun > 0.0:
        player_move = Vector3.ZERO
        return
    _move_player(_read_move(), delta)


func _move_player(dir: Vector3, delta: float) -> void:
    player_move = Vector3.ZERO
    if dir.length() > 0.01:
        dir = dir.normalized()
        player_move = dir
        # резкий разворот на скорости — заносит корпус
        if player.vel.length() > 1.5:
            var dot: float = player.vel.normalized().dot(dir)
            if dot < 0.0:
                player.turn_lean(Vector2(randf_range(-1.2, 1.2), 0.7) * player.vel.length() * 0.35)
    player.drive(dir, delta)


## Автопилот: демонстрационный бой и эталон для теста баланса.
## Держит дистанцию, закрывается от замаха и бьёт только в досягаемости.
func _autopilot(delta: float) -> void:
    var to := enemy.position - player.position
    to.y = 0.0
    var dist := to.length()
    if passive:
        player.blocking = false
        if dist < 2.2:
            player.drive(-to, delta)
        return
    var threat: bool = enemy.telegraph or enemy.punch_kind != ""
    if threat and dist < 1.75:
        player.blocking = true
        player_move = Vector3.ZERO
        if enemy.punch_kind == "" and player.punch_kind == "" and randf() < delta * 2.2:
            # соперник промахнулся или восстанавливается — короткий ответ
            player.blocking = false
            _punch(player, enemy, "jab")
        elif randf() < delta * 1.2 and player.stamina > 30.0:
            player.try_dodge()
        return
    player.blocking = false
    if dist > 1.42:
        player_move = to.normalized()
        player.drive(to, delta)
    elif dist < 1.02:
        player_move = -to.normalized()
        player.drive(-to * 0.5, delta)
    else:
        player_move = Vector3.ZERO
    if randf() < delta * 1.1:
        player.try_dodge()
    if dist < 1.5 and player.punch_kind == "" and randf() < delta * 2.6:
        var pick := randf()
        if pick < 0.42:
            _punch(player, enemy, "jab")
        elif pick < 0.66:
            _punch(player, enemy, "lhook")
        elif pick < 0.86:
            _punch(player, enemy, "rhook")
        else:
            _punch(player, enemy, "upper")


## Удар под дистанцию: с дальней хуком в пустоту не бьют.
func _pick_attack(st: Dictionary, dist: float) -> String:
    var mix: Array = st.get("mix", [0.3, 0.3, 0.3, 0.1])
    var kinds := ["jab", "lhook", "rhook", "upper"]
    var reach := [1.45, 1.30, 1.28, 1.25]
    var weights: Array = []
    var total := 0.0
    for i in kinds.size():
        var w := float(mix[i]) if i < mix.size() else 0.0
        if dist > float(reach[i]) - 0.04:
            w = 0.0
        weights.append(w)
        total += w
    if total <= 0.001:
        return "jab"
    var r := randf() * total
    for i in weights.size():
        r -= float(weights[i])
        if r <= 0.0:
            return String(kinds[i])
    return "jab"


## Замах соперника: время зависит от стиля (ветер) и уровня боя (навык).
func _ai_start_windup(st: Dictionary, skill: float) -> void:
    ai["state"] = "windup"
    ai["t"] = float(st.get("wind", 1.0)) * maxf(0.16, 0.34 - 0.09 * skill)
    ai["pending"] = _pick_attack(st, _distance())
    enemy.telegraph = true


func _ai_tick(delta: float) -> void:
    if enemy.ko or enemy.stun > 0.0:
        enemy_move = Vector3.ZERO
        return
    if player.fallen or player.ko:
        enemy_move = Vector3.ZERO
        ai["state"] = "wait"
        ai["t"] = 0.5
        return
    var st: Dictionary = _opp_style()
    var skill := clampf(float(opp.get("level", 0.0)), 0.0, 1.0)
    var guard_p := float(st.get("guard", 0.35))
    var dodge_p := float(st.get("dodge", 0.08)) + 0.10 * skill
    var aggr := clampf(float(st.get("aggr", 0.55)) + 0.12 * skill, 0.2, 1.0)
    var reach := float(st.get("range", 1.40))
    var counter_p := float(st.get("counter", 0.10))
    ai["t"] = float(ai["t"]) - delta
    var dist := _distance()
    enemy_move = Vector3.ZERO

    # реакция на удар игрока: уклон или блок, у контратакующего — сразу ответ
    if player.punch_kind != "" and _last_player_punch != player.punch_kind:
        _last_player_punch = player.punch_kind
        var busy: bool = str(ai["state"]) == "windup" or str(ai["state"]) == "recover"
        if not busy:
            var react := randf()
            if react < dodge_p and enemy.stamina > 20.0:
                enemy.try_dodge()
                if randf() < counter_p + 0.20 * skill:
                    ai["state"] = "counter"
                    ai["t"] = 0.10
            elif react < dodge_p + guard_p * (0.80 + 0.20 * skill) and enemy.stamina > 6.0:
                enemy.blocking = true
                ai["state"] = "guard"
                ai["t"] = randf_range(0.20, 0.40)
                ai["counter_ok"] = randf() < counter_p
    elif player.punch_kind == "":
        _last_player_punch = ""

    match str(ai["state"]):
        "wait":
            if float(ai["t"]) > 0.0:
                return
            if dist > reach + 0.16:
                ai["state"] = "approach"
                ai["t"] = 1.2
            elif enemy.stamina < 12.0:
                ai["state"] = "retreat"
                ai["t"] = randf_range(0.5, 1.0)
            elif dist < reach - 0.22 and randf() < 0.35:
                ai["state"] = "retreat"
                ai["t"] = randf_range(0.25, 0.55)
            else:
                var r := randf()
                if r < aggr and enemy.stamina > 16.0:
                    ai["combo"] = int(st.get("combo", 1)) - 1
                    _ai_start_windup(st, skill)
                elif r < aggr + guard_p * 0.45:
                    ai["state"] = "guard"
                    ai["t"] = randf_range(0.30, 0.70)
                    enemy.blocking = true
                elif r < aggr + guard_p * 0.45 + 0.14:
                    ai["state"] = "retreat"
                    ai["t"] = randf_range(0.22, 0.50)
                else:
                    ai["t"] = randf_range(0.12, 0.35)
        "approach":
            var to := player.position - enemy.position
            to.y = 0.0
            if to.length() > reach + 0.02:
                enemy_move = to.normalized()
                enemy.drive(to, delta)
                _clamp_ring(enemy)
            if _distance() <= reach + 0.12 or float(ai["t"]) <= 0.0:
                ai["state"] = "wait"
                ai["t"] = randf_range(0.05, 0.20)
        "retreat":
            var away := enemy.position - player.position
            away.y = 0.0
            enemy_move = -away.normalized()
            enemy.drive(-away, delta)
            _clamp_ring(enemy)
            if float(ai["t"]) <= 0.0 or _distance() > reach + 0.45:
                ai["state"] = "wait"
                ai["t"] = randf_range(0.10, 0.30)
        "guard":
            if float(ai["t"]) <= 0.0:
                enemy.blocking = false
                if bool(ai.get("counter_ok", false)) and enemy.stamina > 14.0 \
                        and dist < reach + 0.20:
                    ai["counter_ok"] = false
                    ai["combo"] = 0
                    _ai_start_windup(st, skill)
                else:
                    ai["state"] = "wait"
                    ai["t"] = randf_range(0.10, 0.30)
        "counter":
            if float(ai["t"]) <= 0.0:
                if enemy.stamina > 14.0:
                    ai["combo"] = 0
                    _ai_start_windup(st, skill)
                else:
                    ai["state"] = "wait"
                    ai["t"] = randf_range(0.12, 0.30)
        "windup":
            if float(ai["t"]) <= 0.0:
                enemy.telegraph = false
                if _distance() <= reach + 0.38:
                    _punch(enemy, player, str(ai["pending"]))
                ai["combo"] = int(ai.get("combo", 0)) - 1
                ai["state"] = "recover"
                ai["t"] = maxf(0.12, 0.42 - 0.14 * skill) * float(st.get("rec", 1.0))
        "recover":
            if float(ai["t"]) <= 0.0 and enemy.punch_kind == "":
                if int(ai.get("combo", 0)) > 0 and enemy.stamina > 14.0 \
                        and _distance() < reach + 0.28:
                    _ai_start_windup(st, skill)
                else:
                    ai["state"] = "wait"
                    ai["t"] = maxf(0.10, randf_range(0.20, 0.60) * float(st.get("rec", 1.0))
                            - 0.10 * skill)


func _unhandled_input(event: InputEvent) -> void:
    # геймпад: A/нижняя кнопка начинает бой и двигает меню вперёд
    if event is InputEventJoypadButton and event.pressed \
            and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
        if state == St.MENU or state == St.RESULT:
            _start_or_restart()
        elif state == St.HOWTO:
            _close_howto()
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if state == St.CUSTOM:
            _locker_key(event.keycode)
            return
        if state == St.SETTINGS:
            _settings_key(event.keycode)
            return
        if state == St.HOWTO:
            _howto_key(event.keycode)
            return
        if state == St.PREFIGHT:
            _prefight_key(event.keycode)
            return
        if state == St.STORY:
            _story_key(event.keycode)
            return
        if state == St.TOUR:
            _tour_key(event.keycode)
            return
        if state == St.UPGRADE:
            _upgrade_key(event.keycode)
            return
        match event.keycode:
            KEY_ENTER, KEY_SPACE, KEY_R:
                if state == St.MENU or state == St.RESULT:
                    _start_career_fight()
            KEY_C:
                if state == St.MENU or state == St.RESULT:
                    _open_locker()
            KEY_T:
                if state == St.MENU or state == St.RESULT or state == St.PAUSE:
                    _open_settings(0)
            KEY_V:
                if state == St.MENU or state == St.RESULT or state == St.PAUSE:
                    _open_settings(1)
            KEY_P:
                if state == St.MENU or state == St.RESULT:
                    _open_upgrades()
            KEY_F:
                if state == St.MENU or state == St.RESULT:
                    _open_training()
            KEY_H, KEY_F1:
                if state == St.MENU or state == St.RESULT or state == St.PAUSE:
                    _open_howto()
            KEY_G:
                if state == St.MENU or state == St.RESULT:
                    _open_tournaments()
            KEY_Y:
                if state == St.MENU or state == St.RESULT:
                    _open_story()
            KEY_F11:
                _toggle_fullscreen()
            KEY_M:
                if state == St.PAUSE or state == St.RESULT or state == St.TRAINING:
                    _leave_to_menu()
            KEY_ESCAPE:
                if state == St.FIGHT:
                    _set_state(St.PAUSE)
                elif state == St.TRAINING:
                    _close_training()
                elif state == St.PAUSE:
                    _set_state(St.FIGHT)
                elif state == St.RESULT:
                    _leave_to_menu()
            _:
                # сначала корпусные (Ctrl+удар) и только с точным модификатором:
                # иначе Ctrl+J сработал бы и как обычный джеб
                for bid in BODY_ACTIONS:
                    if event.is_action_pressed(String(bid), false, true):
                        _do_body_action(String(bid))
                        return
                for a in ACTIONS:
                    if event.is_action_pressed(String(a["id"])):
                        _do_action(String(a["id"]))
                        break


## Действие по настраиваемой клавише.
func _do_action(id: String) -> void:
    if (state != St.FIGHT and state != St.TRAINING) or autoplay:
        return
    match id:
        "punch_jab":
            _player_punch("jab")
        "punch_hook_l":
            _player_punch("lhook")
        "punch_hook_r":
            _player_punch("rhook")
        "punch_upper":
            _player_punch("upper")
        "punch_cross":
            _player_punch("cross")


## Корпусной удар: та же клавиша, но с модификатором, цель — корпус.
func _do_body_action(id: String) -> void:
    var kind := String(BODY_ACTIONS.get(id, ""))
    if kind == "":
        return
    _player_punch(kind, true)


# ---------------------------------------------------------------- тач

func _on_touch_dodge() -> void:
    if (state != St.FIGHT and state != St.TRAINING) or player == null:
        return
    if not player.evading and player.stun <= 0.001 and not player.ko:
        player.try_dodge()


func _on_touch_pause() -> void:
    if state == St.FIGHT:
        _set_state(St.PAUSE)
    elif state == St.PAUSE:
        _set_state(St.FIGHT)


# ---------------------------------------------------------------- управление

func _setup_input() -> void:
    for a in ACTIONS:
        keys[String(a["id"])] = int(a["def"])
    var cfg := ConfigFile.new()
    if cfg.load(KEYS_PATH) == OK:
        for a in ACTIONS:
            var id := String(a["id"])
            if cfg.has_section_key("keys", id):
                var v := int(cfg.get_value("keys", id, int(a["def"])))
                if v != 0:
                    keys[id] = v
    _apply_input_map()


func _apply_input_map() -> void:
    for a in ACTIONS:
        var id := String(a["id"])
        if not InputMap.has_action(id):
            InputMap.add_action(id)
        InputMap.action_erase_events(id)
        var ev := InputEventKey.new()
        ev.keycode = int(keys[id])
        InputMap.action_add_event(id, ev)
    # корпусные удары: Ctrl + та же клавиша, что и обычный удар (из настроек).
    # exact_match при проверке не даст обычному нажатию сработать как корпусное.
    for bid in BODY_ACTIONS:
        var base_id := String(PUNCH_ACTION[String(BODY_ACTIONS[bid])])
        if not InputMap.has_action(bid):
            InputMap.add_action(bid)
        InputMap.action_erase_events(bid)
        var cev := InputEventKey.new()
        cev.keycode = int(keys.get(base_id, 0))
        cev.ctrl_pressed = true
        InputMap.action_add_event(bid, cev)


func _save_keys() -> void:
    var cfg := ConfigFile.new()
    for a in ACTIONS:
        cfg.set_value("keys", String(a["id"]), int(keys[String(a["id"])]))
    cfg.save(KEYS_PATH)


func _key_name(id: String) -> String:
    return OS.get_keycode_string(int(keys.get(id, 0)))


func _action_index(id: String) -> int:
    for i in ACTIONS.size():
        if String(ACTIONS[i]["id"]) == id:
            return i
    return 0


func _keys_data() -> Dictionary:
    var rows: Array = []
    for a in ACTIONS:
        rows.append({"label": String(a["label"]),
                "key": _key_name(String(a["id"])),
                "group": String(a["group"])})
    return {"rows": rows, "sel": key_sel, "wait": key_wait,
            "msg": keys_msg, "msg_col": keys_msg_col}


## Подписи для меню: реальные клавиши игрока.
func _keys_text() -> Dictionary:
    return {
        "move": _key_name("move_fwd") + _key_name("move_left")
                + _key_name("move_back") + _key_name("move_right"),
        "dodge": _key_name("dodge"),
        "block": _key_name("block"),
        "jab": _key_name("punch_jab"),
        "hook_l": _key_name("punch_hook_l"),
        "hook_r": _key_name("punch_hook_r"),
        "upper": _key_name("punch_upper"),
        "cross": _key_name("punch_cross"),
        "body": OS.get_keycode_string(BODY_MOD_KEY),
    }


func _open_keys() -> void:
    _open_settings(0)


# ---------------------------------------------------------------- настройки

## Одно окно настроек: вкладка 0 — управление (клавиши), 1 — звук.
func _open_settings(tab: int = 0) -> void:
    settings_back = state if state == St.PAUSE or state == St.RESULT else St.MENU
    settings_tab = clampi(tab, 0, 2)
    key_wait = false
    keys_msg = ""
    sound_sel = 0
    game_sel = 0
    _set_state(St.SETTINGS)


func _close_settings() -> void:
    key_wait = false
    _save_sound()
    _set_state(settings_back)


func _settings_tab(idx: int) -> void:
    settings_tab = clampi(idx, 0, 2)
    key_wait = false
    _refresh_settings()


func _refresh_settings() -> void:
    if state == St.SETTINGS:
        hud.show_settings(_settings_data())


func _settings_data() -> Dictionary:
    if reset_armed > 0.0 and clock - reset_armed > 5.0:
        reset_armed = 0.0
    var d := {"tab": settings_tab, "music": music_vol, "sfx": sfx_vol,
            "sound_sel": sound_sel, "rows": [], "sel": key_sel, "wait": key_wait,
            "msg": keys_msg, "msg_col": keys_msg_col,
            "lang": lang_code, "fullscreen": fullscreen, "game_sel": game_sel,
            "reset_armed": reset_armed > 0.0, "touch": touch_ui}
    if settings_tab == 0:
        var rows: Array = []
        for a in ACTIONS:
            rows.append({"label": String(a["label"]) if not Lang.is_en() else String(a.get("label_en", a["label"])),
                    "key": _key_name(String(a["id"])), "group": String(a["group"])})
        d["rows"] = rows
    elif settings_tab == 1:
        d["sel"] = sound_sel
    else:
        d["sel"] = game_sel
    return d


func _settings_key(code: int) -> void:
    if code == KEY_TAB:
        settings_tab = (settings_tab + 1) % 3
        key_wait = false
        _refresh_settings()
        return
    if settings_tab == 0:
        _keys_key(code)
    elif settings_tab == 1:
        _sound_key(code)
    else:
        _game_key(code)


func _keys_say(text: String, col: Color) -> void:
    keys_msg = text
    keys_msg_col = col
    _refresh_settings()


func _keys_key(code: int) -> void:
    if key_wait:
        if code == KEY_ESCAPE:
            key_wait = false
            _refresh_settings()
            return
        if RESERVED_KEYS.has(code):
            key_wait = false
            _keys_say("эта клавиша занята меню — выбери другую", C_RED)
            return
        key_wait = false
        _keys_assign(code)
        return
    match code:
        KEY_UP:
            key_sel = wrapi(key_sel - 1, 0, ACTIONS.size())
            _refresh_settings()
        KEY_DOWN:
            key_sel = wrapi(key_sel + 1, 0, ACTIONS.size())
            _refresh_settings()
        KEY_ENTER, KEY_SPACE:
            key_wait = true
            keys_msg = ""
            _refresh_settings()
        KEY_R:
            for a in ACTIONS:
                keys[String(a["id"])] = int(a["def"])
            _apply_input_map()
            _save_keys()
            _keys_say("вернул клавиши по умолчанию", C_ACCENT)
        KEY_ESCAPE:
            _close_settings()


func _keys_assign(code: int) -> void:
    var id := String(ACTIONS[key_sel]["id"])
    var old := int(keys[id])
    for a in ACTIONS:
        var oid := String(a["id"])
        if oid != id and int(keys[oid]) == code:
            keys[oid] = old          # занятую клавишу меняем местами
    keys[id] = code
    _apply_input_map()
    _save_keys()
    _keys_say("назначено " + OS.get_keycode_string(code) + " — "
            + String(ACTIONS[key_sel]["label"]), C_ACCENT)


# ---------------------------------------------------------------- бой

func _on_step(power: float) -> void:
    if state != St.FIGHT and state != St.TRAINING:
        return
    sfx.play("step", randf_range(0.88, 1.12), -24.0 + clampf(power, 0.0, 3.0) * 3.0)


func _player_punch(kind: String, body: bool = false) -> void:
    if (state != St.FIGHT and state != St.TRAINING) or autoplay:
        return
    if _try_player_punch(kind, body):
        return
    # удар не стартовал: идёт предыдущий, не хватает выносливости или игрок
    # в блоке/уклоне — запоминаем нажатие на короткое окно
    punch_buf = kind
    punch_buf_body = body
    punch_buf_t = 0.16


## Запуск удара игрока; true — удар начался. Для корпусного удара kind
## превращается в body_<kind> и прицел уходит в корпус.
func _try_player_punch(kind: String, body: bool) -> bool:
    var full := ("body_" + kind) if body else kind
    if not _punch(player, enemy, full, body):
        return false
    if chain_t > 0.0:
        chain = mini(chain + 1, 6)
    else:
        chain = 1
    chain_t = 0.55
    return true


func _on_player_impact(kind: String) -> void:
    _resolve(player, enemy, kind)


func _on_enemy_impact(kind: String) -> void:
    _resolve(enemy, player, kind)


func _on_knockdown(who: Node3D) -> void:
    if state != St.FIGHT and state != St.TRAINING:
        return
    knockdown_show = 1.4
    cam_shake = maxf(cam_shake, 12.0)
    sfx.play("shove", 0.7, -3.0)
    sfx.play("gasp", 0.9, -8.0)
    if arena:
        arena.pulse(0.85)
    if who == enemy:
        score += 60


func _resolve(att: Node3D, def: Node3D, kind: String) -> void:
    if state != St.FIGHT and state != St.TRAINING:
        return
    if def.ko or def.fallen or att.fallen:
        return
    var p: Dictionary = att.punch_info(kind)
    var body_punch: bool = kind.begins_with("body_")
    var anim_kind := String(p.get("anim", kind))
    var dist := _distance()
    if dist > float(p["reach"]):
        sfx.play("whoosh", randf_range(0.9, 1.1), -14.0)
        return

    var blocked: bool = def.blocking and def.stun <= 0.001
    var hp_before: float = def.hp
    var push_dir := def.position - att.position
    push_dir.y = 0.0
    push_dir = push_dir.normalized()

    # уклон: прямые и боковые проходят мимо, апперкот достаёт присевшего
    if def.evading:
        if anim_kind != "upper":
            sfx.play("whoosh", randf_range(1.15, 1.3), -13.0)
            _spawn_flash(def.position + Vector3(0, 2.0, 0), Color(0.55, 0.75, 1.0), 1.0)
            return
        blocked = false

    if blocked:
        var dmg: float = float(p["dmg"]) * 0.18 * att.dmg_mult
        def.hp = maxf(0.0, def.hp - dmg)
        def.taken += dmg
        # блок гасит удар, но выматывает: чем сильнее соперник, тем дороже держать
        var stam_cost := 8.0
        if att == enemy:
            stam_cost += 10.0 * float(opp.get("level", 0.0))
        def.stamina = maxf(0.0, def.stamina - stam_cost)
        def.flash = 0.07
        def.position += push_dir * float(p["push"]) * 0.35
        def.push_impulse(push_dir, 1.6)
        hitstop = 0.045
        sfx.play("block", randf_range(0.95, 1.1), -10.0)
        cam_shake = maxf(cam_shake, 2.5)
        _spawn_flash(def.position + Vector3(0, 1.5, 0), Color(0.8, 0.85, 1.0), 1.4)
        if att == player:
            combo += 1
            comboTimer = 2.6
            score += int(round(float(p["score"]) * 0.3))
        _clamp_ring(def)
        return

    var dmg2: float = float(p["dmg"]) * att.dmg_mult
    if def.evading and anim_kind == "upper":
        dmg2 *= 0.8
    def.take_hit(dmg2, push_dir * float(p["push"]))
    if body_punch:
        # корпусной удар бьёт по выносливости: после серии в корпус
        # соперник дышит, бьёт реже и хуже держит блок
        def.stamina = maxf(0.0, def.stamina - float(p.get("stam_hit", 10.0)) * att.dmg_mult)
    _clamp_ring(def)
    att.hits += 1
    # хит-стоп и отбрасывание тем сильнее, чем тяжелее удар
    if anim_kind == "upper":
        hitstop = 0.12
        def.push_impulse(push_dir, 5.0)
    elif anim_kind == "rhook":
        hitstop = 0.10
        def.push_impulse(push_dir, 4.2)
    elif anim_kind == "lhook":
        hitstop = 0.085
        def.push_impulse(push_dir, 3.6)
    else:
        hitstop = 0.06
        def.push_impulse(push_dir, 2.6)
    sfx.play("hit", randf_range(0.92, 1.08), -5.0)
    cam_shake = maxf(cam_shake, 8.0 if kind == "upper" else 5.0)
    # точка попадания: перчатка в мире, зона по высоте головы
    var gp: Vector3 = att.glove_point(str(p["arm"]))
    var hd: Vector3 = def.head.global_position
    var head_hit: bool = (not body_punch) and gp.distance_to(hd) < 0.78 and gp.y > hd.y - 0.38
    var hit_pos: Vector3 = gp.lerp(hd, 0.45) if head_hit else gp
    if head_hit:
        head_hits += 1
        def.rj_head.v += push_dir * 1.6 + Vector3(0.0, 0.45, 0.0)
    var spark_col := Color(1.0, 0.96, 0.78) if head_hit else (
            Color(1.0, 0.62, 0.42) if body_punch else Color(1.0, 0.82, 0.6))
    _spawn_spark(hit_pos, spark_col)
    _spawn_flash(hit_pos, Color(1.0, 0.85, 0.6), 3.2 if head_hit else 2.4)
    if arena:
        arena.pulse(0.55 if (anim_kind == "upper" or anim_kind == "rhook") else 0.35)
    if anim_kind == "upper" or anim_kind == "rhook":
        if randf() < 0.45:
            sfx.play("gasp", randf_range(0.95, 1.05), -14.0)

    if att == player:
        combo += 1
        comboTimer = 2.6
        var mult := 1.0 + float(mini(combo - 1, 8)) * 0.25
        if chain >= 2:
            mult *= 1.0 + float(mini(chain - 1, 4)) * 0.15
        score += int(round(float(p["score"]) * mult))
        if training:
            # тренировка: попадания дают «форму» — отдельную валюту прокачки
            var fg := 2 + (2 if head_hit else 0)
            form += fg
            training_hits += 1
    else:
        combo = 0

    if def.hp <= 0.0 and hp_before > 0.0 and not training:
        def.hp = 0.0
        def.ko = true
        # физический ragdoll: тело падает по-настоящему
        var imp: Vector3 = push_dir * (2.6 if anim_kind == "upper" else 1.9)
        imp += Vector3(0.0, 1.9 if anim_kind == "upper" else 1.4, 0.0)
        if def.has_method("enter_ragdoll"):
            def.enter_ragdoll(imp)
        _end_fight("win" if att == player else "lose", true)


func _end_fight(kind: String, by_ko: bool) -> void:
    pending = kind
    ko_visual = by_ko
    ko_timer = 1.8 if by_ko else 1.1
    if kind == "ringout" or kind == "ringoutlose":
        ko_timer = 2.6
    if by_ko:
        if not ringout:
            ko_text = "КО!"
        sfx.play("ko", 1.0, -4.0)
        sfx.play("cheer", 1.0, -5.0)
        sfx.music_volume(-17.0)
        cam_shake = 13.0
        if arena:
            arena.pulse(1.0)
    _set_state(St.KO)


func _end_by_time() -> void:
    var kind := "draw"
    if player.hp > enemy.hp:
        kind = "timewin"
    elif player.hp < enemy.hp:
        kind = "timelose"
    _end_fight(kind, false)


## Списание очков за поражение. Вызывается из _finalize один раз за бой;
## флаг defeat_penalty_applied защищает от повторного списания.
func _apply_defeat_penalty() -> void:
    if defeat_penalty_applied:
        return
    defeat_penalty_applied = true
    defeat_penalty = clampi(points_loss_on_defeat, 0, coins)
    coins -= defeat_penalty
    if defeat_penalty > 0:
        print("PENALTY поражение: -", defeat_penalty, " монет, осталось ", coins)


func _finalize() -> void:
    result_bonus = 0
    if pending == "win":
        result_bonus = 200 + int(player.hp * 3.0)
    elif pending == "ringout":
        result_bonus = 260 + int(player.hp * 3.0)
    elif pending == "timewin":
        result_bonus = 60 + int(player.hp * 2.0)
    score += result_bonus
    if score > high_score and not no_cash and not demo:
        high_score = score
        _save_high_score()
    coin_gain = _match_coins()
    form_gain = 6 + head_hits * 3 + belt * 2
    if pending == "win" or pending == "ringout":
        form_gain += 30
    elif pending == "timewin":
        form_gain += 18
    elif pending == "lose" or pending == "timelose" or pending == "ringoutlose":
        form_gain += 6
    var won := pending == "win" or pending == "ringout" or pending == "timewin"
    var lost := pending == "lose" or pending == "timelose" or pending == "ringoutlose"
    belt_won = false
    if won and not training and not demo:
        belt_wins += 1
        if belt_wins >= BELT_FIGHTS:
            if belt < BELTS.size() - 1:
                belt += 1
                belt_wins = 0
                belt_won = true
                ko_text = "ПОЯС ВЗЯТ!"
            else:
                champion = true
                belt_wins = BELT_FIGHTS
                ko_text = "ЧЕМПИОН!"
    if not no_cash and not demo:
        coins += coin_gain
        form += form_gain
        # штраф за проигранный бой: один раз, не больше, чем есть монет
        if lost and not training:
            _apply_defeat_penalty()
        matches += 1
        if won:
            wins += 1
        _save_profile()
    print("RESULT kind=", pending, " score=", score, " hits=", player.hits,
            " taken=", int(player.taken), " hp=", int(player.hp), " time_left=", int(timer),
            " steps=", steps_total,
            " coins=", coins, " gain=", coin_gain, " form=", form, " form_gain=", form_gain,
            " wins=", wins, " matches=", matches, " head_hits=", head_hits)
    coach_line = _pick_assessment()
    tour_msg = ""
    if tour_id != "" and not training:
        var t := _tournament_by_id(tour_id)
        if won:
            tour_wins += 1
            if tour_wins >= int(t.get("fights", 3)):
                coins += int(t.get("coins", 0))
                form += int(t.get("form", 0))
                var un := String(t.get("unlock", ""))
                if un != "" and not owned.has(un):
                    owned.append(un)
                    _sanitize_owned()
                tour_done.append(tour_id)
                tour_msg = "КУБОК «" + String(t.get("name", "")) + "» ВЗЯТ · +"
                tour_msg += str(int(t.get("coins", 0))) + " монет, +"
                tour_msg += str(int(t.get("form", 0))) + " формы"
                tour_id = ""
                tour_wins = 0
                sfx.play("bell", 1.35, -6.0)
            else:
                tour_msg = String(t.get("name", "")) + ": бой " + str(tour_wins) + " из " \
                        + str(int(t.get("fights", 3))) + " взят"
        else:
            tour_msg = "ТУРНИР ПРОИГРАН — начни «" + String(t.get("name", "")) + "» заново"
            tour_id = ""
            tour_wins = 0
    _save_profile()
    print("COACH ", coach_line)
    if tour_msg != "":
        print("TOUR ", tour_msg)
    print("CAREER пояс=", belt + 1, "/", BELTS.size(), " взято=", belt_wins, "/", BELT_FIGHTS,
            " пояс_взят=", belt_won, " чемпион=", champion, " турнир=", tour_id,
            " тур_бои=", tour_wins, " взято_турниров=", tour_done.size())
    _set_state(St.RESULT)


## Точка удара: голова цели.
func _aim_at(f) -> Vector3:
    return f.head.global_position


## Прицел корпусного удара: солнечное сплетение, а не голова.
func _aim_body(f) -> Vector3:
    return f.torso.global_position + Vector3(0.0, 0.22, 0.0)


## Запуск удара. body = true — удар в корпус (цель ниже), kind уже body_*.
func _punch(att: Node3D, def: Node3D, kind: String, body: bool = false) -> bool:
    return att.start_punch(kind, _aim_body(def) if body else _aim_at(def))


func _match_coins() -> int:
    var c: int = int((25 + player.hits * 6 + int(player.hp * 0.3)) * (1.0 + 0.22 * belt))
    match pending:
        "win":
            c += 110
        "ringout":
            c += 140
        "timewin":
            c += 70
        "draw":
            c += 35
        "ringoutlose":
            c += 15
    return c


# ---------------------------------------------------------------- утилиты

func _distance() -> float:
    var a := player.position
    var b := enemy.position
    return Vector2(a.x - b.x, a.z - b.z).length()


func _face_each_other() -> void:
    if not player or not enemy:
        return
    player.look_at_target(enemy.position)
    enemy.look_at_target(player.position)


func _separate(delta: float) -> void:
    var d := _distance()
    if d > 0.001 and d < MIN_GAP:
        var dir := enemy.position - player.position
        dir.y = 0.0
        dir = dir.normalized()
        var push := (MIN_GAP - d) * 0.5
        player.position -= dir * push
        enemy.position += dir * push
        _clamp_ring(player)
        _clamp_ring(enemy)

    # толчки корпусом в клинче: кто давит вперёд, тот оттесняет
    if d < 1.42:
        var dir2 := enemy.position - player.position
        dir2.y = 0.0
        dir2 = dir2.normalized()
        var p_forward := player_move.dot(dir2)
        var e_forward := enemy_move.dot(-dir2)
        if p_forward > 0.45 and player.stamina > 8.0 and not player.ko and enemy.stun <= 0.001:
            player.stamina = maxf(0.0, player.stamina - 9.0 * delta)
            enemy.position += dir2 * 1.5 * delta
            enemy.push_impulse(dir2, 9.0 * delta)
            _clamp_ring(enemy)
            if randf() < delta * 3.5:
                sfx.play("shove", randf_range(0.85, 1.05), -13.0)
                if arena:
                    arena.pulse(0.08)
        if e_forward > 0.45 and enemy.stamina > 8.0 and not enemy.ko and player.stun <= 0.001:
            enemy.stamina = maxf(0.0, enemy.stamina - 9.0 * delta)
            player.position -= dir2 * 1.5 * delta
            player.push_impulse(-dir2, 9.0 * delta)
            _clamp_ring(player)
            if randf() < delta * 3.0:
                sfx.play("shove", randf_range(0.9, 1.1), -15.0)


func _clamp_ring(f: Node3D) -> void:
    f.position.x = clampf(f.position.x, -RING_LIMIT, RING_LIMIT)
    f.position.z = clampf(f.position.z, -RING_LIMIT, RING_LIMIT)


func _spawn_flash(pos: Vector3, col: Color, energy: float) -> void:
    var light := OmniLight3D.new()
    light.light_color = col
    light.light_energy = energy
    light.omni_range = 3.2
    light.position = pos
    add_child(light)
    flashes.append({"light": light, "t": 0.18, "dur": 0.18, "e": energy})


## Светящийся шарик в точке попадания: видно, куда именно пришёл удар.
func _spawn_spark(pos: Vector3, col: Color) -> void:
    var mi := MeshInstance3D.new()
    var sm := SphereMesh.new()
    sm.radius = 0.09
    sm.height = 0.18
    mi.mesh = sm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = col
    mat.emission_enabled = true
    mat.emission = col
    mat.emission_energy_multiplier = 5.0
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mi.material_override = mat
    mi.position = pos
    add_child(mi)
    flashes.append({"mesh": mi, "t": 0.24, "dur": 0.24, "e": 1.0})


func _update_flashes(delta: float) -> void:
    for i in range(flashes.size() - 1, -1, -1):
        var item: Dictionary = flashes[i]
        var dur: float = float(item["dur"]) if item.has("dur") else 0.18
        item["t"] = float(item["t"]) - delta
        var k: float = maxf(0.0, float(item["t"]) / dur)
        if item.has("mesh"):
            var mi: MeshInstance3D = item["mesh"]
            var grow: float = 1.0 + (1.0 - k) * 1.8
            mi.scale = Vector3.ONE * grow
            var mat: StandardMaterial3D = mi.material_override
            mat.albedo_color.a = k
            mat.emission_energy_multiplier = 5.0 * k
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        else:
            var light: OmniLight3D = item["light"]
            light.light_energy = float(item["e"]) * k
            if float(item["t"]) <= 0.0:
                light.queue_free()
        if float(item["t"]) <= 0.0:
            if item.has("mesh"):
                (item["mesh"] as MeshInstance3D).queue_free()
            flashes.remove_at(i)


func _update_camera(delta: float) -> void:
    if state == St.CUSTOM:
        cam.fov = 58.0
        var a := sin(clock * 0.28) * 0.30
        cam.position = Vector3(sin(a) * 3.3, 1.2, cos(a) * 3.3)
        cam.look_at(Vector3(0.0, 1.12, 0.0), Vector3.UP)
        return
    cam.fov = 46.0
    if cam_mode == "side":
        cam.position = Vector3(-0.4, 1.45, 6.2)
        cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
        return
    if cam_mode == "front":
        cam.position = Vector3(5.6, 1.55, 0.0)
        cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
        return
    if cam_mode == "duel" or cam_mode == "duel2":
        # отладочный ракурс для съёмки ударов: видно и корпус, и вынос руки
        cam.fov = 50.0
        var sx := 1.0 if cam_mode == "duel" else -1.0
        cam.position = Vector3(2.9 * sx, 1.62, 2.9)
        cam.look_at(Vector3(0.0, 1.16, 0.06), Vector3.UP)
        return
    if cam_mode == "top":
        # вид сверху: видно дугу бокового удара и замах
        cam.fov = 50.0
        cam.position = Vector3(0.25, 4.3, 1.15)
        cam.look_at(Vector3(0.06, 1.15, -0.02), Vector3.UP)
        return
    if cam_mode == "profile" or cam_mode == "profile2":
        # чистый профиль бойца вплотную: для съёмки траектории удара
        cam.fov = 42.0
        var px := 3.0 if cam_mode == "profile" else -3.0
        cam.position = Vector3(px, 1.35, 1.05)
        cam.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
        return
    var focus := (player.position + enemy.position) * 0.5
    var base := Vector3(3.0 + focus.x * 0.3, 3.1, 4.5 + focus.z * 0.4)
    if cam_shake > 0.05:
        var s := cam_shake * 0.012
        base += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
    cam.position = cam.position.lerp(base, clampf(delta * 5.0, 0.0, 1.0))
    cam.look_at(Vector3(focus.x * 0.35, 0.95, focus.z * 0.25), Vector3.UP)


func _update_hud() -> void:
    hud.set_stats(player.hp / player.max_hp, player.stamina / player.max_stamina,
            enemy.hp / enemy.max_hp, enemy.stamina / enemy.max_stamina)
    hud.set_timer(timer)
    hud.set_score(score, combo, high_score)
    hud.set_chain(chain, chain_t)


func _refresh_hud() -> void:
    _update_hud()


# ---------------------------------------------------------------- рекорд и скриншот

func _load_high_score() -> void:
    var cfg := ConfigFile.new()
    if cfg.load("user://record.cfg") == OK:
        high_score = int(cfg.get_value("game", "score", 0))


func _save_high_score() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("game", "score", high_score)
    cfg.save("user://record.cfg")


# ---------------------------------------------------------------- профиль и гардероб

func _load_profile() -> void:
    look = LookScript.default_look()
    owned = LookScript.default_owned()
    coins = START_COINS
    wins = 0
    matches = 0
    var cfg := ConfigFile.new()
    var had := cfg.load(PROFILE_PATH) == OK
    if had:
        coins = maxi(0, int(cfg.get_value("p", "coins", START_COINS)))
        form = maxi(0, int(cfg.get_value("p", "form", 0)))
        var up = cfg.get_value("p", "upg", {})
        if up is Dictionary:
            for u in UPGRADES:
                var uid := String(u["id"])
                upg[uid] = clampi(int(up.get(uid, 0)), 0, UPG_MAX)
        wins = maxi(0, int(cfg.get_value("p", "wins", 0)))
        matches = maxi(0, int(cfg.get_value("p", "matches", 0)))
        belt = clampi(int(cfg.get_value("p", "belt", 0)), 0, BELTS.size() - 1)
        belt_wins = clampi(int(cfg.get_value("p", "belt_wins", 0)), 0, BELT_FIGHTS)
        champion = bool(cfg.get_value("p", "champion", false))
        lang_code = "en" if String(cfg.get_value("p", "lang", "ru")) == "en" else "ru"
        fullscreen = bool(cfg.get_value("p", "fullscreen", false))
        tour_id = String(cfg.get_value("p", "tour_id", ""))
        tour_wins = clampi(int(cfg.get_value("p", "tour_wins", 0)), 0, 3)
        var td = cfg.get_value("p", "tour_done", [])
        if td is Array:
            tour_done = []
            for x in td:
                if x is String:
                    tour_done.append(x)
        var deck = cfg.get_value("p", "tips_deck", [])
        if deck is Array:
            tips_deck = []
            for x in deck:
                tips_deck.append(int(x))
        last_tip = int(cfg.get_value("p", "last_tip", -1))
        last_assess = int(cfg.get_value("p", "last_assess", -1))
        story_seen = bool(cfg.get_value("p", "story_seen", false))
        var ow = cfg.get_value("p", "owned", [])
        if ow is Array:
            owned = []
            for k in ow:
                if k is String:
                    owned.append(k)
        var lk = cfg.get_value("p", "look", {})
        if lk is Dictionary:
            for k in lk:
                if k is String and lk[k] is String:
                    look[k] = lk[k]
    for k in LookScript.default_owned():
        if not owned.has(k):
            owned.append(k)
    for k in look_override:
        var cid := str(k)
        var iid := str(look_override[k])
        if cid != "" and LookScript.item_count(cid) > 0:
            look[cid] = iid
            var okey := cid + ":" + iid
            if not owned.has(okey):
                owned.append(okey)
    if coins_override >= 0:
        coins = coins_override
    if form_override >= 0:
        form = form_override
    matches = maxi(matches, wins)
    _sanitize_owned()
    _sanitize_look()
    print("PROFILE монет=", coins, " форма=", form, " прокачка=", upg,
            " побед=", wins, " матчей=", matches, " вид=", look)
    _save_profile()


func _save_profile() -> void:
    if no_cash or demo or not look_override.is_empty() or coins_override >= 0 \
            or form_override >= 0 or belt_override >= 0 or beltwins_override >= 0 \
            or lang_override != "":
        return
    var cfg := ConfigFile.new()
    cfg.set_value("p", "coins", coins)
    cfg.set_value("p", "form", form)
    cfg.set_value("p", "upg", upg)
    cfg.set_value("p", "wins", wins)
    cfg.set_value("p", "matches", matches)
    cfg.set_value("p", "belt", belt)
    cfg.set_value("p", "belt_wins", belt_wins)
    cfg.set_value("p", "champion", champion)
    cfg.set_value("p", "lang", lang_code)
    cfg.set_value("p", "fullscreen", fullscreen)
    cfg.set_value("p", "tour_id", tour_id)
    cfg.set_value("p", "tour_wins", tour_wins)
    cfg.set_value("p", "tour_done", tour_done)
    cfg.set_value("p", "tips_deck", tips_deck)
    cfg.set_value("p", "last_tip", last_tip)
    cfg.set_value("p", "last_assess", last_assess)
    cfg.set_value("p", "story_seen", story_seen)
    cfg.set_value("p", "owned", owned)
    cfg.set_value("p", "look", look)
    cfg.save(PROFILE_PATH)


## В профиле могли остаться разделы/варианты из старых версий — выкидываем их.
func _sanitize_owned() -> void:
    var clean: Array = []
    for k in owned:
        if not (k is String):
            continue
        var s: String = k
        var parts: PackedStringArray = s.split(":")
        if parts.size() == 2 and LookScript.item_count(parts[0]) > 0:
            var it := LookScript.find_item(parts[0], parts[1])
            if str(it["id"]) == parts[1] and not clean.has(s):
                clean.append(s)
    for k in LookScript.default_owned():
        if not clean.has(k):
            clean.append(k)
    owned = clean


## Ничего из гардероба не должно ссылаться на некупленный вариант.
func _sanitize_look() -> void:
    var clean := {}
    for cat in LookScript.CATALOG:
        var cid := str(cat["id"])
        var arr: Array = cat["items"]
        var want := str(look.get(cid, ""))
        var pick := str(arr[0]["id"])
        for it in arr:
            if str(it["id"]) == want and owned.has(cid + ":" + want):
                pick = want
        clean[cid] = pick
    look = clean


func _owns(key: String) -> bool:
    return owned.has(key)


func _preview_look() -> Dictionary:
    var d := look.duplicate()
    var cat: Dictionary = LookScript.CATALOG[locker_sel]
    d[String(cat["id"])] = String(cat["items"][locker_opt]["id"])
    return d


func _locker_data() -> Dictionary:
    return {"cat": locker_sel, "idx": locker_opt, "owned": owned, "look": look,
            "coins": coins, "wins": wins, "matches": matches,
            "msg": locker_msg, "msg_col": locker_msg_col, "touch": touch_ui}


func _open_locker() -> void:
    locker_sel = 0
    locker_opt = 0
    locker_msg = ""
    locker_msg_t = 0.0
    if locker_sel_override >= 0:
        locker_sel = wrapi(locker_sel_override, 0, LookScript.CATALOG.size())
        var cid := String(LookScript.CATALOG[locker_sel]["id"])
        locker_opt = LookScript.item_index(cid, String(look.get(cid, "")))
    if locker_opt_override >= 0:
        var cat: Dictionary = LookScript.CATALOG[locker_sel]
        locker_opt = wrapi(locker_opt_override, 0, (cat["items"] as Array).size())
    player.set_look(look)
    player.reset(Vector3.ZERO, 100.0)
    player.preview = true
    player.look_at_target(Vector3(0.0, 1.0, 6.0))
    player.rotate_y(0.2)
    enemy.visible = false
    _set_state(St.CUSTOM)


func _close_locker() -> void:
    locker_msg = ""
    player.set_look(look)
    enemy.visible = not solo
    _reset_fight()
    _set_state(St.MENU)


func _locker_say(text: String, col: Color) -> void:
    locker_msg = text
    locker_msg_col = col
    locker_msg_t = 2.0
    hud.show_locker(_locker_data())


func _locker_move(d: int) -> void:
    locker_sel = wrapi(locker_sel + d, 0, LookScript.CATALOG.size())
    var cid := String(LookScript.CATALOG[locker_sel]["id"])
    locker_opt = LookScript.item_index(cid, String(look.get(cid, "")))
    player.set_look(_preview_look())
    hud.show_locker(_locker_data())


func _locker_pick(d: int) -> void:
    var cat: Dictionary = LookScript.CATALOG[locker_sel]
    var arr: Array = cat["items"]
    locker_opt = wrapi(locker_opt + d, 0, arr.size())
    player.set_look(_preview_look())
    hud.show_locker(_locker_data())


func _locker_apply() -> void:
    var cat: Dictionary = LookScript.CATALOG[locker_sel]
    var cid := String(cat["id"])
    var it: Dictionary = cat["items"][locker_opt]
    var iid := String(it["id"])
    var key := cid + ":" + iid
    var price := int(it["price"])
    if _owns(key):
        look[cid] = iid
        player.set_look(look)
        _save_profile()
        _locker_say("надето: " + String(it["name"]), C_ACCENT)
        return
    if coins < price:
        sfx.play("block", 0.85, -10.0)
        _locker_say("не хватает " + str(price - coins) + " очков — выигрывай матчи", C_RED)
        return
    coins -= price
    owned.append(key)
    look[cid] = iid
    player.set_look(look)
    _save_profile()
    sfx.play("bell", 1.25, -12.0)
    _locker_say("куплено: " + String(it["name"]) + "   −" + str(price), C_AMBER)


func _locker_key(code: int) -> void:
    match code:
        KEY_UP, KEY_W:
            _locker_move(-1)
        KEY_DOWN, KEY_S:
            _locker_move(1)
        KEY_LEFT, KEY_A:
            _locker_pick(-1)
        KEY_RIGHT, KEY_D:
            _locker_pick(1)
        KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
            _locker_apply()
        KEY_ESCAPE, KEY_C:
            _close_locker()


# ---------------------------------------------------------------- звук

func _load_sound() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SOUND_PATH) == OK:
        music_vol = clampi(int(cfg.get_value("s", "music", 7)), 0, 10)
        sfx_vol = clampi(int(cfg.get_value("s", "sfx", 9)), 0, 10)


func _save_sound() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("s", "music", music_vol)
    cfg.set_value("s", "sfx", sfx_vol)
    cfg.save(SOUND_PATH)


func _apply_sound() -> void:
    if sfx == null:
        return
    sfx.set_music_level(float(music_vol) / 10.0)
    sfx.set_sfx_level(float(sfx_vol) / 10.0)


func _sound_change(d: int) -> void:
    if sound_sel == 0:
        music_vol = clampi(music_vol + d, 0, 10)
    else:
        sfx_vol = clampi(sfx_vol + d, 0, 10)
    _apply_sound()
    _save_sound()
    if sound_sel == 1:
        sfx.play("hit", 1.0, -6.0)   # сразу слышно, насколько громко стало
    _refresh_settings()


## Вкладка «игра»: язык и полный экран.
func _game_key(code: int) -> void:
    match code:
        KEY_UP:
            game_sel = wrapi(game_sel - 1, 0, 3)
            _refresh_settings()
        KEY_DOWN:
            game_sel = wrapi(game_sel + 1, 0, 3)
            _refresh_settings()
        KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_SPACE:
            _game_activate()
        KEY_ESCAPE:
            _close_settings()


## Действие выбранной строки вкладки «игра» — и клавишей, и тапом.
func _game_activate() -> void:
    if game_sel == 0:
        _set_lang("en" if lang_code == "ru" else "ru")
    elif game_sel == 1:
        _toggle_fullscreen()
        _refresh_settings()
    else:
        _arm_reset()


func _sound_key(code: int) -> void:
    match code:
        KEY_UP:
            sound_sel = wrapi(sound_sel - 1, 0, 2)
            _refresh_settings()
        KEY_DOWN:
            sound_sel = wrapi(sound_sel + 1, 0, 2)
            _refresh_settings()
        KEY_LEFT:
            _sound_change(-1)
        KEY_RIGHT:
            _sound_change(1)
        KEY_R:
            music_vol = 7
            sfx_vol = 9
            _apply_sound()
            _save_sound()
            _refresh_settings()
        KEY_ESCAPE:
            _close_settings()


# ---------------------------------------------------------------- прокачка

func _upg_cost(id: String) -> int:
    return 60 + 40 * int(upg.get(id, 0))


func _upg_levels() -> Dictionary:
    return upg.duplicate()


func _upgrades_data() -> Dictionary:
    var rows: Array = []
    for u in UPGRADES:
        var uid := String(u["id"])
        rows.append({"name": String(u["name"]), "desc": String(u["desc"]),
                "lvl": int(upg.get(uid, 0)), "max": UPG_MAX, "cost": _upg_cost(uid)})
    return {"rows": rows, "sel": upgrade_sel, "form": form,
            "msg": upgrade_msg, "msg_col": upgrade_msg_col, "touch": touch_ui}


func _open_upgrades() -> void:
    upgrade_sel = 0
    upgrade_msg = ""
    _set_state(St.UPGRADE)


func _close_upgrades() -> void:
    upgrade_msg = ""
    _save_profile()
    _set_state(St.MENU)


func _apply_upgrades() -> void:
    if player == null:
        return
    player.set_upgrades(upg)


func _upgrade_buy() -> void:
    var u: Dictionary = UPGRADES[upgrade_sel]
    var uid := String(u["id"])
    var lvl := int(upg.get(uid, 0))
    if lvl >= UPG_MAX:
        upgrade_msg = "уже максимум — дальше некуда"
        upgrade_msg_col = C_AMBER
    else:
        var cost := _upg_cost(uid)
        if form < cost:
            upgrade_msg = "не хватает " + str(cost - form) + " формы — тренируйся (F) или дерись"
            upgrade_msg_col = C_RED
            sfx.play("block", 0.85, -10.0)
        else:
            form -= cost
            upg[uid] = lvl + 1
            _apply_upgrades()
            _save_profile()
            upgrade_msg = String(u["name"]) + " → уровень " + str(lvl + 1)
            upgrade_msg_col = C_ACCENT
            sfx.play("bell", 1.25, -12.0)
    hud.show_upgrades(_upgrades_data())


func _upgrade_key(code: int) -> void:
    match code:
        KEY_UP:
            upgrade_sel = wrapi(upgrade_sel - 1, 0, UPGRADES.size())
            hud.show_upgrades(_upgrades_data())
        KEY_DOWN:
            upgrade_sel = wrapi(upgrade_sel + 1, 0, UPGRADES.size())
            hud.show_upgrades(_upgrades_data())
        KEY_ENTER, KEY_SPACE:
            _upgrade_buy()
        KEY_ESCAPE:
            _close_upgrades()


# ---------------------------------------------------------------- тренировка

func _open_training() -> void:
    training = true
    no_ai = true
    player.preview = false
    enemy.no_fall = true
    _start_fight()
    timer = ROUND_TIME
    hud.set_opponent_name(Lang.t("dummy"))
    # манекен рядом и не бьёт: бей в своё удовольствие, копи «форму»
    player.reset(Vector3(0, 0, 0.75), 100.0)
    enemy.reset(Vector3(0, 0, -0.35), 110.0)
    _face_each_other()
    head_hits = 0
    _set_state(St.TRAINING)
    sfx.play("bell", 1.0, -6.0)


func _close_training() -> void:
    training = false
    no_ai = false
    enemy.no_fall = false
    _save_profile()
    print("TRAINING конец: попаданий=", training_hits, " форма=", form)
    _reset_fight()
    _set_state(St.MENU)


## Проверка прицела удара, второй руки и музыки числами.
func _run_fighttest() -> void:
    no_cash = true
    _start_fight()
    player.reset(Vector3(0, 0, 0.57), 100.0)
    enemy.reset(Vector3(0, 0, -0.55), 110.0)
    _face_each_other()
    head_hits = 0
    var best := 9.0
    var off_min := 9.0
    _punch(player, enemy, "jab")
    for i in 45:
        player.tick(1.0 / 60.0)
        enemy.tick(1.0 / 60.0)
        if player.punch_kind != "":
            best = minf(best, player.glove_point("l").distance_to(enemy.head.global_position))
            off_min = minf(off_min, player.glove_point("r").distance_to(enemy.head.global_position))
    print("FIGHTTEST удар: перчатка_до_головы=", snappedf(best, 0.01),
            " м, вторая_рука_до_головы>=", snappedf(off_min, 0.01),
            " м, попаданий_в_голову=", head_hits)
    print("FIGHTTEST музыка: длина=", snappedf(sfx.music.stream.get_length(), 0.1),
            " играет=", sfx.music.playing)
    get_tree().quit()


## Проверка прокачки и тренировки: множители, покупка, отказ, начисление формы.
func _run_upgtest() -> void:
    no_cash = true
    form = 200
    var hp0: float = player.max_hp
    upg = {"power": 4, "speed": 4, "stamina": 4, "guard": 4, "health": 4}
    _apply_upgrades()
    player.reset(Vector3.ZERO, 100.0)
    print("UPGTEST уровни4: hp=", snappedf(player.max_hp, 0.1),
            " (было ", snappedf(hp0, 0.1), ") урон×", snappedf(player.dmg_mult, 0.001),
            " длительность×", snappedf(player.dur_mult, 0.001),
            " выносливость=", snappedf(player.max_stamina, 0.1),
            " полученный_урон×", snappedf(player.taken_mult, 0.001))

    upg = {"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0}
    form = 100
    _open_upgrades()
    upgrade_sel = 0
    _upgrade_buy()
    var bought: bool = int(upg["power"]) == 1 and form == 40
    upgrade_sel = 1
    _upgrade_buy()
    var refused: bool = int(upg["speed"]) == 0 and upgrade_msg.begins_with("не хватает")
    print("UPGTEST покупка: сила=", upg["power"], " форма=", form, " ок=", bought,
            " · отказ=", refused, " (", upgrade_msg, ")")
    _close_upgrades()

    _open_training()
    var f0: int = form
    for k in 3:
        _punch(player, enemy, "jab")
        for i in 40:
            _tick_fight(1.0 / 60.0)
    var gained: int = form - f0
    print("UPGTEST тренировка: попаданий=", training_hits, " форма+=", gained,
            " всего=", form, " экран=", state == St.TRAINING)
    _close_training()
    print("UPGTEST выход: состояние меню=", state == St.MENU, " профиль форма=", form)
    get_tree().quit()


## Покадровая проверка анимации удара: ищем разрывы позы.
## Считаем шаг поворота плеча (градусы за кадр), шаг перчатки (м),
## прыжки углов Эйлера (признак «переворота» кости) и попадание в цель.
func _arm_quat(f, arm: String) -> Quaternion:
    var n: Node3D = f.sh_l if arm == "l" else f.sh_r
    return n.global_transform.basis.orthonormalized().get_rotation_quaternion()


func _run_animtest() -> void:
    no_cash = true
    _start_fight()
    for kind in ["jab", "lhook", "rhook", "upper"]:
        _anim_one(kind, 0.62, -0.50, "дальняя")
        _anim_one(kind, 0.30, -0.28, "вплотную")
    get_tree().quit()


## Прогон одного удара: 34 кадра, покадровые метрики плавности.
func _anim_one(kind: String, pz: float, ez: float, tag: String) -> void:
    var dt := 1.0 / 60.0
    player.reset(Vector3(0.04, 0, pz), 100.0)
    enemy.reset(Vector3(0.0, 0, ez), 110.0)
    _face_each_other()
    var arm := "l" if kind in ["jab", "lhook"] else "r"
    # сначала даём телу устояться, иначе метрика поймает стартовую тряску рига
    for i in 24:
        player.tick(dt)
        enemy.tick(dt)
    var aim := _aim_at(enemy)
    var reach: float = (player.sh_l if arm == "l" else player.sh_r).global_position.distance_to(aim)
    _punch(player, enemy, kind)
    var prev_q: Quaternion = _arm_quat(player, arm)
    var prev_g: Vector3 = player.glove_point(arm)
    var prev_e: Vector3 = (player.sh_l if arm == "l" else player.sh_r).rotation
    var q_steps: Array = []
    var g_steps: Array = []
    var e_jumps: Array = []
    var best := 9.0
    for i in 34:
        player.tick(dt)
        enemy.tick(dt)
        var q: Quaternion = _arm_quat(player, arm)
        var g: Vector3 = player.glove_point(arm)
        var e: Vector3 = (player.sh_l if arm == "l" else player.sh_r).rotation
        q_steps.append(rad_to_deg(prev_q.angle_to(q)))
        g_steps.append(prev_g.distance_to(g))
        e_jumps.append(maxf(absf(e.x - prev_e.x), maxf(absf(e.y - prev_e.y), absf(e.z - prev_e.z))))
        if player.punch_kind != "":
            best = minf(best, g.distance_to(aim))
        prev_q = q
        prev_g = g
        prev_e = e
    var sq: Array = q_steps.duplicate()
    sq.sort()
    var med: float = sq[sq.size() / 2]
    var imax := 0
    var vmax := 0.0
    for i in q_steps.size():
        if float(q_steps[i]) > vmax:
            vmax = float(q_steps[i])
            imax = i
    var gmax := 0.0
    for v in g_steps:
        gmax = maxf(gmax, float(v))
    var jumps := 0
    for v in e_jumps:
        if float(v) > 2.0:
            jumps += 1
    var steps_txt := ""
    for i in q_steps.size():
        steps_txt += str(int(round(float(q_steps[i])))) + " "
    print("ANIMTEST ", kind, " ", tag, ": плечо_макс=", snappedf(vmax, 0.1), "° кадр ", imax,
            " медиана=", snappedf(med, 0.1), "° пик/медиана=", snappedf(vmax / maxf(med, 0.01), 0.1),
            " перчатка_макс=", snappedf(gmax, 0.01), " м",
            " эйлеров_прыжков=", jumps,
            " цель_от_плеча=", snappedf(reach, 0.01), " м",
            " перчатка_до_цели=", snappedf(best, 0.01), " м")
    print("ANIMTEST ", kind, " ", tag, " шаги: ", steps_txt)


func _run_uitest() -> void:
    no_cash = true
    coins = 5000
    var ok := true
    var steps: Array = []

    _open_locker()
    ok = ok and state == St.CUSTOM and player.preview and not hud.battle.visible
    steps.append("меню→гардероб:" + ("ок" if state == St.CUSTOM and player.preview else "нет"))

    _locker_pick(1)
    _locker_apply()
    var hair2 := String(look["hair"])
    ok = ok and _owns("hair:" + hair2)
    steps.append("примерка+покупка:" + hair2)

    _close_locker()
    ok = ok and state == St.MENU and not player.preview and hud.battle.visible
    steps.append("гардероб→меню:" + ("ок" if state == St.MENU else "нет"))

    # настройки: шестерёнка в углу, вкладки мышью, звук и клавиши
    _set_state(St.MENU)
    await get_tree().process_frame
    await get_tree().process_frame
    var gear_ok: bool = hud.gear != null and is_instance_valid(hud.gear) \
            and hud.gear.mouse_filter == Control.MOUSE_FILTER_STOP
    if hud.gear != null:
        var gear_click := InputEventMouseButton.new()
        gear_click.button_index = MOUSE_BUTTON_LEFT
        gear_click.pressed = true
        hud.gear._gui_input(gear_click)
    await get_tree().process_frame
    var gear_open: bool = state == St.SETTINGS and settings_tab == 0
    var tab_btn: Button = null
    for ch in hud.overlay.get_children():
        if ch is Button and (ch as Button).text == "ЗВУК":
            tab_btn = ch
    if tab_btn != null:
        tab_btn.pressed.emit()
    await get_tree().process_frame
    var tab_ok: bool = state == St.SETTINGS and settings_tab == 1
    var music_before := music_vol
    _settings_key(KEY_LEFT)
    var vol_ok: bool = music_vol == clampi(music_before - 1, 0, 10)
    _settings_key(KEY_RIGHT)
    _settings_key(KEY_TAB)
    _settings_key(KEY_TAB)
    var tab_back: bool = settings_tab == 0
    # язык: переключаем на английский и обратно
    _set_lang("en")
    var en_ok: bool = Lang.is_en() and String(Lang.t("play")) == "PLAY"
    _set_lang("ru")
    var ru_ok: bool = not Lang.is_en() and String(Lang.t("play")) == "ИГРАТЬ"
    ok = ok and en_ok and ru_ok
    steps.append("язык: en " + ("ок" if en_ok else "нет") + ", ru " + ("ок" if ru_ok else "нет"))
    _close_settings()
    # «как играть»: открывается из меню и закрывается
    _open_howto()
    var how_ok: bool = state == St.HOWTO
    _howto_key(KEY_ESCAPE)
    ok = ok and how_ok and state == St.MENU
    steps.append("как играть: " + ("ок" if how_ok and state == St.MENU else "нет"))
    ok = ok and gear_ok and gear_open and tab_ok and vol_ok and tab_back
    ok = ok and state == St.MENU
    steps.append("настройки: шестерёнка " + ("ок" if gear_ok and gear_open else "нет")
            + ", вкладка мышью " + ("ок" if tab_ok else "нет")
            + ", громкость " + ("ок" if vol_ok else "нет")
            + ", TAB назад " + ("ок" if tab_back else "нет"))

    _start_fight()
    ok = ok and state == St.FIGHT
    for i in 120:
        _tick_fight(1.0 / 60.0)
    steps.append("бой:" + str(steps_total) + " шагов, hp=" + str(int(player.hp)))

    _set_state(St.PAUSE)
    ok = ok and state == St.PAUSE
    _set_state(St.FIGHT)
    ok = ok and state == St.FIGHT
    steps.append("пауза: ок")
    # выход в главное меню прямо из боя
    _set_state(St.PAUSE)
    _leave_to_menu()
    var leave_ok: bool = state == St.MENU and not training and not no_ai
    ok = ok and leave_ok
    steps.append("выход в меню из боя: " + ("ок" if leave_ok else "нет"))
    _start_fight()

    _end_fight("win", true)
    ok = ok and state == St.KO
    for i in 240:
        _process(1.0 / 60.0)
    ok = ok and state == St.RESULT
    steps.append("нокдаун→результат:" + ("ок" if state == St.RESULT else "нет"))

    _open_locker()
    ok = ok and state == St.CUSTOM
    _locker_move(2)
    _locker_pick(2)
    _locker_apply()
    _close_locker()
    ok = ok and state == St.MENU and not player.preview
    steps.append("результат→гардероб→меню:" + ("ок" if state == St.MENU else "нет"))

    # переназначение клавиш: своя клавиша и обмен занятой
    var old_hook := int(keys["punch_hook_l"])
    key_sel = _action_index("punch_jab")
    _keys_assign(KEY_Z)
    var ev_ok := false
    for ev in InputMap.action_get_events("punch_jab"):
        if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_Z:
            ev_ok = true
    key_sel = _action_index("punch_hook_l")
    _keys_assign(KEY_Z)
    var swap_ok: bool = int(keys["punch_hook_l"]) == KEY_Z and int(keys["punch_jab"]) == old_hook
    ok = ok and ev_ok and swap_ok
    steps.append("клавиши: своя " + ("ок" if ev_ok else "нет") + ", обмен "
            + ("ок" if swap_ok else "нет"))
    for a in ACTIONS:
        keys[String(a["id"])] = int(a["def"])
    _apply_input_map()
    _save_keys()

    # стресс: частое переодевание не должно копить узлы и ронять сцену
    _open_locker()
    var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
    for i in 60:
        if i % 2 == 0:
            _locker_move(1)
        else:
            _locker_pick(1)
    await get_tree().process_frame
    await get_tree().process_frame
    var nodes_after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
    var on_screen: int = hud.overlay.get_child_count()
    ok = ok and on_screen < 200
    steps.append("стресс 60 шагов: узлов %d→%d, на экране %d" % [nodes_before, nodes_after, on_screen])
    _close_locker()
    ok = ok and state == St.MENU

    print("UITEST ", "ок" if ok else "ОШИБКА", " · ", ", ".join(steps))
    get_tree().quit()


## Синтетический клик мышью по экранной точке: проверяем кнопки HUD.
func _click_at(p: Vector2) -> void:
    for down in [true, false]:
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = down
        ev.position = p
        ev.global_position = p
        Input.parse_input_event(ev)

## Карьера: десять побед поднимают пояс, шестой пояс делает чемпионом.
func _run_careertest() -> void:
    no_cash = true
    demo = false
    belt = 0
    belt_wins = 0
    champion = false
    _start_fight()
    var ok := true
    for i in 9:
        pending = "win"
        player.hp = 80.0
        player.hits = 5
        _finalize()
        await get_tree().process_frame
    var mid_belt := belt
    var mid_wins := belt_wins
    pending = "win"
    _finalize()
    await get_tree().process_frame
    ok = ok and belt == 1 and belt_wins == 0 and belt_won
    print("CAREERTEST пояс: было ", mid_belt + 1, "/", mid_wins, " после 10 побед пояс=",
            belt + 1, " взято=", belt_wins, " пояс_взят=", belt_won)

    belt = BELTS.size() - 1
    belt_wins = 0
    champion = false
    for i in 9:
        pending = "win"
        player.hp = 80.0
        player.hits = 5
        _finalize()
        await get_tree().process_frame
    var before_champ := champion
    pending = "win"
    _finalize()
    await get_tree().process_frame
    ok = ok and not before_champ and champion and belt == BELTS.size() - 1
    print("CAREERTEST чемпион: до последнего боя=", before_champ, " после=", champion,
            " пояс=", belt + 1, " взято=", belt_wins, "/", BELT_FIGHTS)

    belt = 2
    belt_wins = 3
    pending = "lose"
    _finalize()
    await get_tree().process_frame
    ok = ok and belt == 2 and belt_wins == 3
    print("CAREERTEST поражение: пояс=", belt + 1, " взято=", belt_wins, " (должно 3/10)")
    # сложность: каждый бой внутри пояса и между поясами сильнее
    var diff_lines: Array = []
    for b in BELTS.size():
        belt = b
        for w in [0, 4, 9]:
            belt_wins = w
            _reset_fight()
            diff_lines.append("пояс %d бой %d: %s · %s · hp %.0f · урон x%.2f · скорость x%.2f" % [
                    b + 1, w + 1, String(opp.get("name", "")),
                    String(_opp_style().get("ru", "")), enemy.max_hp,
                    enemy.dmg_mult, enemy.dur_mult])
    for line in diff_lines:
        print("CAREERTEST ", line)
    print("CAREERTEST ", "ок" if ok else "ОШИБКА")
    get_tree().quit()


## Сложность и разнообразие: 60 боёв, рост уровня, имена, стили, цифры.
func _run_difftest() -> void:
    no_cash = true
    demo = true
    var ok := true
    var names := {}
    var styles_seen := {}
    var prev_level := -1.0
    var prev_base_hp := 0.0
    var prev_base_dmg := 0.0
    var min_hp := 9999.0
    var max_hp := 0.0
    var min_dmg := 99.0
    var max_dmg := 0.0
    var min_spd := 99.0
    var max_spd := 0.0
    var adjacent_same := 0
    var last_style := -1
    var belt_avg: Array = []
    for b in BELTS.size():
        var sum_hp := 0.0
        var sum_dmg := 0.0
        for w in BELT_FIGHTS:
            belt = b
            belt_wins = w
            _reset_fight()
            var lvl := float(opp.get("level", 0.0))
            if lvl <= prev_level:
                ok = false
            prev_level = lvl
            var nm := String(opp.get("name", ""))
            if names.has(nm):
                ok = false
                print("DIFFTEST повтор имени: ", nm)
            names[nm] = true
            var si := int(opp.get("style_i", 0))
            styles_seen[si] = true
            if si == last_style:
                adjacent_same += 1
            last_style = si
            min_hp = minf(min_hp, enemy.max_hp)
            max_hp = maxf(max_hp, enemy.max_hp)
            min_dmg = minf(min_dmg, enemy.dmg_mult)
            max_dmg = maxf(max_dmg, enemy.dmg_mult)
            min_spd = minf(min_spd, enemy.dur_mult)
            max_spd = maxf(max_spd, enemy.dur_mult)
            sum_hp += enemy.max_hp
            sum_dmg += enemy.dmg_mult
            var base_hp := 105.0 * (1.0 + 0.65 * lvl)
            var base_dmg := 0.88 + 0.92 * lvl
            if base_hp <= prev_base_hp or base_dmg <= prev_base_dmg:
                ok = false
            prev_base_hp = base_hp
            prev_base_dmg = base_dmg
        belt_avg.append(Vector2(sum_hp / float(BELT_FIGHTS), sum_dmg / float(BELT_FIGHTS)))
    if names.size() != FIGHT_COUNT:
        ok = false
    if styles_seen.size() != STYLES.size():
        ok = false
    if adjacent_same != 0:
        ok = false
    for i in range(1, belt_avg.size()):
        if belt_avg[i].x <= belt_avg[i - 1].x or belt_avg[i].y <= belt_avg[i - 1].y:
            ok = false
    print("DIFFTEST боёв=", FIGHT_COUNT, " имён=", names.size(), " стилей=", styles_seen.size(),
            " подряд_одинаковых=", adjacent_same)
    print("DIFFTEST рост: hp %.0f→%.0f, урон x%.2f→x%.2f, скорость x%.2f→x%.2f" % [
            min_hp, max_hp, min_dmg, max_dmg, min_spd, max_spd])
    var belt_lines: Array = []
    for i in belt_avg.size():
        belt_lines.append("пояс %d: средний hp %.0f, средний урон x%.2f" % [
                i + 1, belt_avg[i].x, belt_avg[i].y])
    for line in belt_lines:
        print("DIFFTEST ", line)
    # таблица «сколько чистых ударов до нокаута» в конце пояса
    for b in [0, 2, 4, 5]:
        belt = b
        belt_wins = BELT_FIGHTS - 1
        var row := "пояс %d: " % (b + 1)
        for prof in [{"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0},
                {"power": 4, "speed": 4, "stamina": 4, "guard": 4, "health": 4}]:
            upg = prof
            _apply_upgrades()
            _reset_fight()
            var p_hits: int = ceili(enemy.max_hp
                    / (11.0 * player.dmg_mult * enemy.taken_mult))
            var e_hits: int = ceili(player.max_hp
                    / (11.0 * enemy.dmg_mult * player.taken_mult))
            row += "ты %d / он %d   " % [p_hits, e_hits]
        print("DIFFTEST ", row)
    upg = {"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0}
    _apply_upgrades()
    print("DIFFTEST ", "ок" if ok else "ОШИБКА")
    get_tree().quit()


## Реальный бой автопилота против ИИ: видно, что без прокачки карьера не тянется.
func _run_balancetest() -> void:
    no_cash = true
    demo = true
    autoplay = true
    no_ai = false
    var profiles := [
        {"name": "без прокачки", "upg": {"power": 0, "speed": 0, "stamina": 0, "guard": 0, "health": 0}},
        {"name": "середина", "upg": {"power": 2, "speed": 2, "stamina": 2, "guard": 2, "health": 2}},
        {"name": "максимум", "upg": {"power": 4, "speed": 4, "stamina": 4, "guard": 4, "health": 4}},
    ]
    for p in profiles:
        upg = p["upg"]
        _apply_upgrades()
        var wins := 0
        var total := 0
        var line := String(p["name"]) + ": "
        for b in [0, 2, 4, 5]:
            var bw := 0
            for fi in [0, 4, 8]:
                belt = b
                belt_wins = fi
                _start_fight()
                timer = ROUND_TIME
                var guard := 0
                while state == St.FIGHT and guard < 12000:
                    _tick_fight(1.0 / 30.0)
                    guard += 1
                var won: bool = pending == "win" or pending == "ringout" or pending == "timewin"
                print("BALANCE бой: пояс=", b + 1, " стиль=", String(_opp_style().get("ru", "")),
                        " итог=", pending, " hp=", int(player.hp), "/", int(enemy.hp),
                        " t=", int(ROUND_TIME - timer))
                if won:
                    wins += 1
                    bw += 1
                total += 1
                state = St.MENU
                Engine.time_scale = 1.0
            line += "пояс %d %d/3 · " % [b + 1, bw]
        print("BALANCETEST ", line, "всего ", wins, "/", total)
    autoplay = false
    get_tree().quit()


## Звук: уровень из настроек меняет громкость шин SFX и Music.
func _run_sndtest() -> void:
    var sfx_idx := AudioServer.get_bus_index("SFX")
    var mus_idx := AudioServer.get_bus_index("Music")
    var lines: Array = []
    for lvl in [10, 7, 4, 0]:
        sfx_vol = lvl
        music_vol = lvl
        _apply_sound()
        sfx.play("hit", 1.0, -6.0)
        lines.append("%d→SFX %.1f дБ, Music %.1f дБ, mute=%s" % [lvl,
            AudioServer.get_bus_volume_db(sfx_idx),
            AudioServer.get_bus_volume_db(mus_idx),
            str(AudioServer.is_bus_mute(sfx_idx))])
    print("SNDTEST шины: SFX idx=", sfx_idx, " Music idx=", mus_idx)
    for line in lines:
        print("SNDTEST ", line)
    sfx_vol = 9
    music_vol = 7
    _apply_sound()
    get_tree().quit()

## Тренер, турниры и сброс: советы без повторов, награды, чистый профиль.
func _run_coachtest() -> void:
    no_cash = true
    demo = false
    last_tip = -1
    tips_deck = []
    var seen := {}
    var repeat := false
    for i in TIPS.size():
        var t := _next_tip()
        if seen.has(t):
            repeat = true
        seen[t] = true
    print("COACHTEST советы: выдано=", seen.size(), " из ", TIPS.size(), " повторов=", repeat)

    pending = "win"
    player.taken = 10.0
    player.hp = 90.0
    var a1 := _pick_assessment()
    pending = "lose"
    player.taken = 40.0
    player.hp = 20.0
    var a2 := _pick_assessment()
    print("COACHTEST оценка: победа=«", a1.left(32), "…», поражение=«", a2.left(32), "…»")

    belt = 0
    tour_id = "debut"
    tour_wins = 0
    tour_done = []
    coins = 0
    form = 0
    for i in 3:
        pending = "win"
        player.hp = 80.0
        player.hits = 5
        player.taken = 20.0
        _finalize()
        await get_tree().process_frame
    var reward_ok := coins == 350 and form >= 70 and tour_done.has("debut") and tour_id == ""
    print("COACHTEST турнир: монет=", coins, " формы=", form, " взято=", tour_done,
            " турнир_активен=", tour_id)

    coins = 5000
    form = 999
    belt = 3
    belt_wins = 7
    champion = true
    _reset_progress()
    var reset_ok: bool = coins == START_COINS and belt == 0 and belt_wins == 0 \
            and form == 0 and not champion and tour_done.is_empty()
    print("COACHTEST сброс: монет=", coins, " пояс=", belt + 1, " взято=", belt_wins,
            " форма=", form, " чемпион=", champion)
    print("COACHTEST ", "ок" if (not repeat and reward_ok and reset_ok) else "ОШИБКА")
    get_tree().quit()


## История: главы открываются по поясам, экран листается и закрывается.
func _run_storytest() -> void:
    no_cash = true
    var ok := StoryScript.PAGES.size() == 7
    belt = 0
    ok = ok and StoryScript.is_open(0, belt) and StoryScript.is_open(1, belt)
    ok = ok and not StoryScript.is_open(2, belt)
    belt = 3
    ok = ok and StoryScript.is_open(4, belt) and not StoryScript.is_open(5, belt)
    belt = 5
    ok = ok and StoryScript.is_open(6, belt)
    var shortest := 9999
    for p in StoryScript.PAGES:
        shortest = mini(shortest, String(p["text"]).length())
    ok = ok and shortest > 120
    belt = 0
    story_seen = false
    story_sel = 0
    _set_state(St.STORY)
    ok = ok and state == St.STORY and hud.overlay.visible
    _story_key(KEY_RIGHT)
    ok = ok and story_sel == 1
    _story_key(KEY_LEFT)
    ok = ok and story_sel == 0
    _close_story()
    ok = ok and state == St.MENU and story_seen
    print("STORYTEST глав=", StoryScript.PAGES.size(), " минимальный_текст=", shortest,
            " пролог_после_закрытия=", story_seen)
    print("STORYTEST ", "ок" if ok else "ОШИБКА")
    get_tree().quit()


## Тач-управление: кнопки ударов, блок, уклон, стик и пауза.
func _run_touchtest() -> void:
    no_cash = true
    var ok := touch_ui and touch != null
    _start_fight()
    await get_tree().process_frame
    ok = ok and touch.active and touch.pad.visible

    # джеб: касание кнопки в левом нижнем углу
    var jab := {}
    for b in touch.BTN:
        if String(b["id"]) == "jab":
            jab = b
    var tap := InputEventScreenTouch.new()
    tap.index = 0
    tap.pressed = true
    tap.position = Vector2(jab["pos"])
    touch._on_gui_input(tap)
    await get_tree().process_frame
    var jab_ok: bool = player.punch_kind == "jab"
    print("TOUCHTEST джеб: вид=", player.punch_kind, " ожидали=jab")

    var up := InputEventScreenTouch.new()
    up.index = 0
    up.pressed = false
    up.position = Vector2(jab["pos"])
    touch._on_gui_input(up)

    # пятая кнопка — кросс
    var cbtn := {}
    for b in touch.BTN:
        if String(b["id"]) == "cross":
            cbtn = b
    player.punch_kind = ""
    var ct := InputEventScreenTouch.new()
    ct.index = 5
    ct.pressed = true
    ct.position = Vector2(cbtn["pos"])
    touch._on_gui_input(ct)
    await get_tree().process_frame
    var cross_ok: bool = player.punch_kind == "cross"
    print("TOUCHTEST кросс: вид=", player.punch_kind, " ожидали=cross")
    var ct_up := InputEventScreenTouch.new()
    ct_up.index = 5
    ct_up.pressed = false
    ct_up.position = ct.position
    touch._on_gui_input(ct_up)

    # переключатель корпуса: включаем и бьём джеб — должен уйти body_jab
    var bbtn := {}
    for b in touch.BTN:
        if String(b["id"]) == "body":
            bbtn = b
    player.punch_kind = ""
    var bt2 := InputEventScreenTouch.new()
    bt2.index = 6
    bt2.pressed = true
    bt2.position = Vector2(bbtn["pos"])
    touch._on_gui_input(bt2)
    var body_on: bool = touch.body_mode
    var bt2_up := InputEventScreenTouch.new()
    bt2_up.index = 6
    bt2_up.pressed = false
    bt2_up.position = bt2.position
    touch._on_gui_input(bt2_up)
    var jt := InputEventScreenTouch.new()
    jt.index = 7
    jt.pressed = true
    jt.position = Vector2(jab["pos"])
    touch._on_gui_input(jt)
    await get_tree().process_frame
    var body_ok: bool = player.punch_kind == "body_jab"
    print("TOUCHTEST корпус: включён=", body_on, " вид=", player.punch_kind, " ожидали=body_jab")
    var jt_up := InputEventScreenTouch.new()
    jt_up.index = 7
    jt_up.pressed = false
    jt_up.position = jt.position
    touch._on_gui_input(jt_up)
    ok = ok and cross_ok and body_on and body_ok

    # стик: тянем вверх-вправо
    var st := InputEventScreenTouch.new()
    st.index = 1
    st.pressed = true
    st.position = Vector2(touch.STICK_POS) + Vector2(60, -70)
    touch._on_gui_input(st)
    var stick_ok: bool = touch.move.length() > 0.6 and touch.move.y < -0.4 and touch.move.x > 0.3
    print("TOUCHTEST стик: move=", touch.move.snapped(Vector2(0.01, 0.01)))
    var st_up := InputEventScreenTouch.new()
    st_up.index = 1
    st_up.pressed = false
    st_up.position = st.position
    touch._on_gui_input(st_up)
    ok = ok and touch.move.length() == 0.0

    # блок держится пальцем
    var blk := {}
    for b in touch.BTN:
        if String(b["id"]) == "block":
            blk = b
    var bt := InputEventScreenTouch.new()
    bt.index = 2
    bt.pressed = true
    bt.position = Vector2(blk["pos"])
    touch._on_gui_input(bt)
    var block_ok: bool = touch.block
    var bt_up := InputEventScreenTouch.new()
    bt_up.index = 2
    bt_up.pressed = false
    bt_up.position = bt.position
    touch._on_gui_input(bt_up)
    block_ok = block_ok and not touch.block
    print("TOUCHTEST блок: держится/отпускается=", block_ok)

    # уклон (перед этим гасим начатый джеб, иначе уклон запрещён)
    player.punch_kind = ""
    var dod := {}
    for b in touch.BTN:
        if String(b["id"]) == "dodge":
            dod = b
    var dt := InputEventScreenTouch.new()
    dt.index = 3
    dt.pressed = true
    dt.position = Vector2(dod["pos"])
    touch._on_gui_input(dt)
    var dodge_ok: bool = player.dodge_t > 0.0
    print("TOUCHTEST уклон: dodge_t=", player.dodge_t, " evading=", player.evading)

    # пауза с экранной кнопки
    var pz := {}
    for b in touch.BTN:
        if String(b["id"]) == "pause":
            pz = b
    var pt := InputEventScreenTouch.new()
    pt.index = 4
    pt.pressed = true
    pt.position = Vector2(pz["pos"])
    touch._on_gui_input(pt)
    var pause_ok: bool = state == St.PAUSE and not touch.active
    print("TOUCHTEST пауза: state=", state, " touch_active=", touch.active)
    ok = ok and jab_ok and stick_ok and block_ok and dodge_ok and pause_ok

    # --- экраны меню пальцем: прокачка, гардероб, настройки, турниры, история
    _leave_to_menu()
    form = 500
    _on_hud_button("upgrade")
    var up_open: bool = state == St.UPGRADE
    var lvl_before := int(upg["power"])
    _on_hud_button("upgrow0")
    var up_buy: bool = int(upg["power"]) == lvl_before + 1
    print("TOUCHTEST прокачка: экран=", up_open, " уровень=", lvl_before, "→", int(upg["power"]))
    _on_hud_button("back_all")
    var up_back: bool = state == St.MENU

    _on_hud_button("locker")
    var lock_open: bool = state == St.CUSTOM
    _on_hud_button("lockercat2")
    _on_hud_button("lockeritem1")
    var lock_tap: bool = state == St.CUSTOM
    print("TOUCHTEST гардероб: экран=", lock_open, " тап по вещи=", lock_tap)
    _on_hud_button("back_all")
    var lock_back: bool = state == St.MENU

    _on_hud_button("settings")
    var set_open: bool = state == St.SETTINGS
    _on_hud_button("gamerow0")
    var lang_flip: bool = lang_code == "en"
    _on_hud_button("gamerow0")
    var lang_back: bool = lang_code == "ru"
    print("TOUCHTEST настройки: экран=", set_open, " язык en=", lang_flip, " назад ru=", lang_back)
    _on_hud_button("back_all")
    var set_back: bool = state == St.MENU

    _on_hud_button("tour")
    var tour_open: bool = state == St.TOUR
    _on_hud_button("tourrow2")
    var tour_sel_ok: bool = tour_sel == 2
    _on_hud_button("back_all")
    var tour_back: bool = state == St.MENU

    _on_hud_button("story")
    var story_open: bool = state == St.STORY
    _on_hud_button("storynext")
    var story_step: bool = story_sel == 1
    _on_hud_button("storyprev")
    _on_hud_button("back_all")
    var story_back: bool = state == St.MENU

    var menu_ok: bool = up_open and up_buy and up_back and lock_open and lock_tap and lock_back \
            and set_open and lang_flip and lang_back and set_back and tour_open and tour_sel_ok \
            and tour_back and story_open and story_step and story_back
    print("TOUCHTEST меню: прокачка=", up_open and up_buy and up_back,
            " гардероб=", lock_open and lock_tap and lock_back,
            " настройки=", set_open and lang_flip and set_back,
            " турниры=", tour_open and tour_sel_ok and tour_back,
            " история=", story_open and story_step and story_back)
    ok = ok and menu_ok
    print("TOUCHTEST ", "ок" if ok else "ОШИБКА")
    get_tree().quit()


## Сохранение прогресса: пишем профиль, читаем обратно, возвращаем как было.
func _run_savetest() -> void:
    var backup := PackedByteArray()
    if FileAccess.file_exists(PROFILE_PATH):
        backup = FileAccess.get_file_as_bytes(PROFILE_PATH)
    no_cash = false
    demo = false
    belt = 2
    belt_wins = 4
    champion = false
    coins = 777
    form = 123
    wins = 5
    matches = 6
    lang_code = "en"
    fullscreen = false
    _save_profile()
    var cfg := ConfigFile.new()
    var ok := cfg.load(PROFILE_PATH) == OK
    var b := int(cfg.get_value("p", "belt", -1))
    var bw := int(cfg.get_value("p", "belt_wins", -1))
    var cn := int(cfg.get_value("p", "coins", -1))
    var fm := int(cfg.get_value("p", "form", -1))
    var lg := String(cfg.get_value("p", "lang", ""))
    print("SAVETEST прочитано обратно: пояс=", b + 1, " взято=", bw, " монет=", cn,
            " форма=", fm, " язык=", lg)
    var good := ok and b == 2 and bw == 4 and cn == 777 and fm == 123 and lg == "en"
    print("SAVETEST ", "ок" if good else "ОШИБКА")
    # возвращаем профиль игрока как был
    if backup.size() > 0:
        var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
        f.store_buffer(backup)
        f.close()
    else:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
    print("SAVETEST профиль игрока восстановлен")
    get_tree().quit()


## Проверка живого окна: настоящий ввод мыши через вьюпорт, а не прямой вызов.
func _run_clicktest() -> void:
    _set_state(St.MENU)
    await get_tree().process_frame
    await get_tree().process_frame
    var gr: Rect2 = hud.gear.get_global_rect() if hud.gear != null else Rect2()
    _push_click(gr.get_center())
    await get_tree().process_frame
    await get_tree().process_frame
    print("CLICKTEST шестерёнка: клик=", gr.get_center(), " настройки=",
            state == St.SETTINGS, " вкладка=", settings_tab)
    var tab_btn: Button = null
    for c in hud.overlay.get_children():
        if c is Button and (c as Button).text == "ЗВУК":
            tab_btn = c
    var tr: Rect2 = tab_btn.get_global_rect() if tab_btn != null else Rect2()
    _push_click(tr.get_center())
    await get_tree().process_frame
    await get_tree().process_frame
    print("CLICKTEST вкладка: клик=", tr.get_center(), " вкладка=", settings_tab)
    var music0 := music_vol
    _push_click(Vector2(600, 250))
    await get_tree().process_frame
    print("CLICKTEST экран настроек: состояние=", state, " мышь_дошла=",
            state == St.SETTINGS, " музыка=", music0, " звуки=", sfx_vol)
    # кнопка ИГРАТЬ в меню запускает бой
    _set_state(St.MENU)
    await get_tree().process_frame
    await get_tree().process_frame
    var play_btn: Button = null
    for c in hud.overlay.get_children():
        if c is Button and (c as Button).text == Lang.t("play"):
            play_btn = c
    var pr: Rect2 = play_btn.get_global_rect() if play_btn != null else Rect2()
    _push_click(pr.get_center())
    await get_tree().process_frame
    await get_tree().process_frame
    print("CLICKTEST ИГРАТЬ: клик=", pr.get_center(), " бой=", state == St.FIGHT,
            " пояс=", belt + 1, " сложность=", ai_skill)
    get_tree().quit()


## Клик мышью через вьюпорт: тот же путь, что у настоящего ввода.
func _push_click(p: Vector2) -> void:
    for down in [true, false]:
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = down
        ev.position = p
        ev.global_position = p
        get_viewport().push_input(ev)

func _count_meshes(n: Node) -> int:
    var c := 1 if n is MeshInstance3D else 0
    for ch in n.get_children():
        c += _count_meshes(ch)
    return c


func _run_lockertest() -> void:
    no_cash = true
    coins = 99999
    _open_locker()
    print("LOCKERTEST базовое_тело ", _count_meshes(player.body), " деталей, вид ", look)
    for i in 60:
        player.tick(1.0 / 60.0)
    var hip: Vector3 = player.to_global(Vector3(0.0, player._hip_h_dyn, 0.0))
    var glv: Vector3 = player.el_l.to_global(Vector3(0.0, -0.42, 0.0))
    var grv: Vector3 = player.el_r.to_global(Vector3(0.0, -0.42, 0.0))
    print("LOCKERTEST поза: перчатки от таза ", (glv - hip).snapped(Vector3(0.01, 0.01, 0.01)),
            " / ", (grv - hip).snapped(Vector3(0.01, 0.01, 0.01)))
    for cat in LookScript.CATALOG:
        var cid := String(cat["id"])
        var line := "LOCKERTEST " + cid + ":"
        for i in cat["items"].size():
            locker_sel = LookScript.cat_index(cid)
            locker_opt = i
            _locker_apply()
            line += " %s=%d" % [String(cat["items"][i]["id"]), _count_meshes(player.body)]
        print(line, " → надето ", look[cid])
    print("LOCKERTEST кошелёк: потрачено ", 99999 - coins, " очков, куплено ",
            owned.size() - LookScript.default_owned().size(), " предметов")
    coins = 0
    owned = LookScript.default_owned()
    look = LookScript.default_look()
    player.set_look(look)
    locker_sel = LookScript.cat_index("gloves_color")
    locker_opt = LookScript.item_index("gloves_color", "neon")
    _locker_apply()
    print("LOCKERTEST отказ_без_денег: ", "да" if locker_msg.begins_with("не хватает") else "нет",
            " · ", locker_msg, " · цвет перчаток ", look["gloves_color"],
            " · владеет ", "да" if _owns("gloves_color:neon") else "нет")
    get_tree().quit()


## Проверка новых ударов: кросс, корпус, буфер ввода и штраф за поражение.
func _run_punchtest() -> void:
    no_cash = true
    demo = false
    var ok := true
    var lines: Array = []

    # 1. Input Map: кросс и корпусные действия, у корпусных — Ctrl
    var cross_action: bool = InputMap.has_action("punch_cross")
    var body_actions := 0
    for bid in BODY_ACTIONS:
        if InputMap.has_action(String(bid)):
            body_actions += 1
    var ctrl_ev := false
    if InputMap.has_action("punch_body_jab"):
        for ev in InputMap.action_get_events("punch_body_jab"):
            if ev is InputEventKey and (ev as InputEventKey).ctrl_pressed:
                ctrl_ev = true
    ok = ok and cross_action and body_actions == BODY_ACTIONS.size() and ctrl_ev
    lines.append("действия: кросс=%s, корпусных=%d/%d, Ctrl=%s" % [
            cross_action, body_actions, BODY_ACTIONS.size(), ctrl_ev])

    _start_fight()
    no_ai = true

    # 2. Кросс: начинается, доигрывает анимацию и наносит урон
    _place_for_punch()
    var p0: float = enemy.hp
    var cross_start: bool = _try_player_punch("cross", false)
    var cross_kind: bool = player.punch_kind == "cross"
    _tick_until_idle()
    var cross_hit: bool = enemy.hp < p0 - 0.01
    ok = ok and cross_start and cross_kind and cross_hit
    lines.append("кросс: старт=%s, вид=%s, урон=%s (hp %.0f→%.0f)" % [
            cross_start, cross_kind, cross_hit, p0, enemy.hp])

    # 2b. Ввод через _unhandled_input: кросс, Ctrl+джеб (корпус), обычный джеб
    _place_for_punch()
    var ev_cross := InputEventKey.new()
    ev_cross.keycode = int(keys["punch_cross"])
    ev_cross.pressed = true
    _unhandled_input(ev_cross)
    var cross_input: bool = player.punch_kind == "cross"
    _place_for_punch()
    var ev_body := InputEventKey.new()
    ev_body.keycode = int(keys["punch_jab"])
    ev_body.pressed = true
    ev_body.ctrl_pressed = true
    _unhandled_input(ev_body)
    var body_input: bool = player.punch_kind == "body_jab"
    _place_for_punch()
    var ev_plain := InputEventKey.new()
    ev_plain.keycode = int(keys["punch_jab"])
    ev_plain.pressed = true
    _unhandled_input(ev_plain)
    var plain_input: bool = player.punch_kind == "jab"
    ok = ok and cross_input and body_input and plain_input
    lines.append("ввод: E→кросс=%s, Ctrl+J→корпус=%s, J→джеб=%s" % [
            cross_input, body_input, plain_input])

    # 3. Корпус: другой удар (body_jab), урон есть, в голову не считается
    _place_for_punch()
    var bhp: float = enemy.hp
    var bhead: int = head_hits
    var body_start: bool = _try_player_punch("jab", true)
    var body_kind: bool = player.punch_kind == "body_jab"
    _tick_until_idle()
    var body_hit: bool = enemy.hp < bhp - 0.01
    var body_no_head: bool = head_hits == bhead
    ok = ok and body_start and body_kind and body_hit and body_no_head
    lines.append("корпус: старт=%s, вид=%s, урон=%s, не_в_голову=%s" % [
            body_start, body_kind, body_hit, body_no_head])

    # 4. Буфер: нажатие под конец удара не теряется, а доигрывается
    _place_for_punch()
    var rhook: bool = _try_player_punch("rhook", false)
    for i in 18:
        _tick_fight(1.0 / 60.0)
    _player_punch("cross")
    var buffered: bool = punch_buf == "cross"
    var buffered_fired := false
    for i in 60:
        _tick_fight(1.0 / 60.0)
        if player.punch_kind == "cross":
            buffered_fired = true
            break
    ok = ok and rhook and buffered and buffered_fired
    lines.append("буфер: удар=%s, запомнил=%s, доиграл кросс=%s" % [
            rhook, buffered, buffered_fired])

    # 5. Штраф: ровно один раз и без ухода в минус
    coins = 100
    points_loss_on_defeat = 40
    defeat_penalty_applied = false
    defeat_penalty = 0
    _apply_defeat_penalty()
    var after1: int = coins
    var pen1: int = defeat_penalty
    _apply_defeat_penalty()
    var repeat_coins: int = coins
    var once_ok: bool = pen1 == 40 and after1 == 60 and coins == 60 and defeat_penalty == 40
    coins = 10
    defeat_penalty_applied = false
    defeat_penalty = 0
    _apply_defeat_penalty()
    var floor_ok: bool = coins == 0 and defeat_penalty == 10
    ok = ok and once_ok and floor_ok
    lines.append("штраф: 100−40=%d, повторно=%d, с 10 монет списано %d" % [
            after1, repeat_coins, 10])

    # 6. Настройка штрафа доступна и через аргумент --penalty
    lines.append("настройка: points_loss_on_defeat=%d" % points_loss_on_defeat)

    _reset_fight()
    _set_state(St.MENU)
    print("PUNCHTEST ", "ок" if ok else "ОШИБКА")
    for l in lines:
        print("PUNCHTEST ", l)
    get_tree().quit()


## Поставить бойцов на дистанцию удара и обнулить состояние боя.
func _place_for_punch() -> void:
    player.reset(Vector3(0.0, 0.0, 0.75), 100.0)
    enemy.reset(Vector3(0.0, 0.0, -0.35), 120.0)
    _face_each_other()
    player.blocking = false
    player.stun = 0.0
    player.punch_kind = ""
    enemy.stun = 0.0
    enemy.hp = enemy.max_hp
    head_hits = 0


## Прокрутить бой, пока игрок не закончит текущий удар.
func _tick_until_idle() -> void:
    for i in 120:
        _tick_fight(1.0 / 60.0)
        if player.punch_kind == "" and player.stun <= 0.001:
            break


func _take_shot() -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    var err := img.save_png(shot_path)
    print("SHOT ", shot_path, " err=", err)
    get_tree().quit()
