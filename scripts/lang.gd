extends RefCounted
## Двуязычный интерфейс: ключ → [русский, английский].
## Неизвестный ключ возвращается как есть, поэтому строки, которые ещё не
## переведены, просто остаются на русском и ничего не ломают.

static var code := "ru"

const DICT := {
    # --- меню
    "title": ["В РИНГЕ", "IN THE RING"],
    "version": ["РАННИЙ ДОСТУП · v27", "EARLY ACCESS · v27"],
    "hook": ["Один раунд. 90 секунд. Вылетишь за канаты — проиграл.",
            "One round. 90 seconds. Fly through the ropes — you lose."],
    "play": ["ИГРАТЬ", "PLAY"],
    "locker": ["ГАРДЕРОБ", "WARDROBE"],
    "upgrade": ["ПРОКАЧКА", "UPGRADES"],
    "training": ["ТРЕНИРОВКА", "TRAINING"],
    "howto": ["КАК ИГРАТЬ", "HOW TO PLAY"],
    "exit": ["ВЫХОД", "QUIT"],
    "resume": ["ПРОДОЛЖИТЬ", "RESUME"],
    "belt": ["ПОЯС", "BELT"],
    "of": ["ИЗ", "OF"],
    "champion": ["ЧЕМПИОН · ВСЕ ПОЯСА ВЗЯТЫ", "CHAMPION · ALL BELTS WON"],
    "belt_won": ["ПОЯС ВЗЯТ", "BELT WON"],
    "next_fight": ["СЛЕДУЮЩИЙ БОЙ", "NEXT FIGHT"],
    "fight_of": ["бой", "fight"],
    "coins": ["монет", "coins"],
    "form": ["форма", "form"],
    "level": ["уровень", "level"],
    "wins": ["побед", "wins"],
    "record": ["рекорд", "best"],
    "controls_hint": ["WASD — шаг · E — кросс · J K I U — удары · Ctrl+удар — корпус · Shift — уклон · L — блок · Space — встать после нокдауна · Esc — пауза",
            "WASD — move · E — cross · J K I U — punches · Ctrl+punch — body · Shift — dodge · L — block · Space — get up after knockdown · Esc — pause"],
    # --- боевой HUD
    "you": ["ТЫ", "YOU"],
    "opponent": ["СОПЕРНИК", "OPPONENT"],
    "round": ["РАУНД", "ROUND"],
    "score": ["ОЧКИ", "SCORE"],
    "knockdown": ["НОКДАУН", "KNOCKDOWN"],
    "get_up_hint": ["SPACE — ВСТАТЬ", "PRESS SPACE TO GET UP"],
    "get_up_hint_touch": ["ТАП «ВСТАТЬ»", "TAP «GET UP»"],
    "get_up_countdown": ["Встать", "Get up"],
    "training_hud": ["ТРЕНИРОВКА", "TRAINING"],
    "dummy": ["МАНЕКЕН", "DUMMY"],
    "exit_hint": ["ESC — ВЫЙТИ", "ESC — EXIT"],
    # --- пауза
    "paused": ["ПАУЗА", "PAUSED"],
    "to_menu": ["ГЛАВНОЕ МЕНЮ", "MAIN MENU"],
    "pause_hint": ["ESC — продолжить      M — в главное меню, прогресс сохранится",
            "ESC — resume      M — main menu, progress is saved"],
    "saved": ["ПРОГРЕСС СОХРАНЁН", "PROGRESS SAVED"],
    "defeat_penalty": ["МОНЕТ ЗА ПОРАЖЕНИЕ", "COINS FOR THE LOSS"],
    "tour": ["ТУРНИРЫ", "TOURNAMENTS"],
    "story": ["ИСТОРИЯ", "STORY"],
    "story_hint": ["← → — главы      ESC — назад", "← → — chapters      ESC — back"],
    "story_locked": ["ОТКРОЕТСЯ НА ПОЯСЕ", "UNLOCKS AT BELT"],
    "story_prologue": ["ПРОЛОГ", "PROLOGUE"],
    "story_chapter": ["ГЛАВА", "CHAPTER"],
    "coach": ["ТРЕНЕР МИХАЛЫЧ", "COACH"],
    "opp_style": ["СТИЛЬ:", "STYLE:"],
    "difficulty": ["СЛОЖНОСТЬ", "DIFFICULTY"],
    "fight": ["В БОЙ", "FIGHT"],
    "tournaments": ["СЮЖЕТНЫЕ ТУРНИРЫ", "STORY TOURNAMENTS"],
    "tour_start": ["НАЧАТЬ ТУРНИР", "START TOURNAMENT"],
    "tour_hint": ["↑↓ — выбрать турнир      ENTER — начать      ESC — назад",
            "↑↓ — choose tournament      ENTER — start      ESC — back"],
    "prefight_hint": ["ENTER — в бой      ESC — назад", "ENTER — fight      ESC — back"],
    # --- мобильное управление
    "touch_move": ["Справа внизу — стик движения: веди пальцем.", "Bottom right — move stick: drag your finger."],
    "touch_punch": ["Слева внизу — четыре удара: ЛЕВЫЙ, ПРАВЫЙ, АППЕР, ДЖЕБ.",
            "Bottom left — four punches: LEFT, RIGHT, UPPER, JAB."],
    "touch_guard": ["БЛОК держи пальцем, УКЛОН — короткий тап. II сверху — пауза.",
            "Hold BLOCK, tap DODGE. II at the top — pause."],
    "prefight_hint_touch": ["ТАП по «В БОЙ» — начать", "TAP «FIGHT» to start"],
    "controls_hint_touch": ["Удары — слева внизу · стик — справа · БЛОК — держать · УКЛОН — тап",
            "Punches bottom left · stick bottom right · hold BLOCK · tap DODGE"],
    "tour_locked": ["нужен пояс", "needs belt"],
    "tour_done": ["ВЗЯТ", "WON"],
    "tour_progress": ["бой", "fight"],
    "reset_progress": ["СБРОСИТЬ ПРОГРЕСС", "RESET PROGRESS"],
    "reset_armed": ["нажми ещё раз — прогресс обнулится", "press again to wipe progress"],
    "reset_hint": ["↑↓ — выбрать      ← → или ENTER — переключить      ESC — назад",
            "↑↓ — select      ← → or ENTER — toggle      ESC — back"],
    # --- настройки
    "settings": ["НАСТРОЙКИ", "SETTINGS"],
    "settings_sub": ["меняется сразу и сохраняется между запусками",
            "applies instantly and is saved between runs"],
    "tab_keys": ["УПРАВЛЕНИЕ", "CONTROLS"],
    "tab_sound": ["ЗВУК", "AUDIO"],
    "tab_game": ["ИГРА", "GAME"],
    "language": ["ЯЗЫК", "LANGUAGE"],
    "fullscreen": ["ПОЛНЫЙ ЭКРАН", "FULLSCREEN"],
    "on": ["ВКЛ", "ON"],
    "off": ["ВЫКЛ", "OFF"],
    "back": ["ESC — назад", "ESC — back"],
    "back_btn": ["← НАЗАД", "← BACK"],
    "touch_upg_hint": ["ТАП по строке — купить уровень      ← НАЗАД сверху",
            "Tap a row to buy a level      BACK at the top"],
    "touch_locker_hint": ["ТАП по разделу и вещи — купить или надеть      ← НАЗАД сверху",
            "Tap a section and an item to buy or wear      BACK at the top"],
    "touch_tour_hint": ["ТАП по турниру — выбрать      ← НАЗАД сверху",
            "Tap a tournament to select      BACK at the top"],
    "touch_game_hint": ["ТАП по строке — переключить      ← НАЗАД сверху",
            "Tap a row to switch      BACK at the top"],
    "touch_sound_hint": ["ТАП по делению шкалы — выставить громкость      ← НАЗАД сверху",
            "Tap a level on the scale to set volume      BACK at the top"],
    "music": ["МУЗЫКА", "MUSIC"],
    "sfx": ["ЗВУКИ БОЯ", "FIGHT SOUNDS"],
    "movement": ["ДВИЖЕНИЕ", "MOVEMENT"],
    "punches": ["УДАРЫ", "PUNCHES"],
    "keys_hint": ["↑↓ — выбрать      ENTER — назначить другую      R — сброс      ESC — назад",
            "↑↓ — select      ENTER — rebind      R — reset      ESC — back"],
    "keys_tab_hint": ["TAB или клик по вкладке — звук", "TAB or click a tab — audio"],
    "sound_hint": ["← → — тише / громче      ↑ ↓ — выбрать строку      R — умолчания",
            "← → — quieter / louder      ↑ ↓ — select row      R — defaults"],
    "sound_alive": ["музыка играет и здесь: слышно, насколько сделал громче",
            "music plays here too: you hear the change right away"],
    "game_hint": ["↑↓ — выбрать      ← → или ENTER — переключить      ESC — назад",
            "↑↓ — select      ← → or ENTER — toggle      ESC — back"],
    "lang_hint": ["язык интерфейса", "interface language"],
    "full_hint": ["F11 — переключить в любом месте игры", "F11 toggles anytime"],
    # --- «как играть»
    "howto_sub": ["бой на ринге: один раунд, 90 секунд, без захватов",
            "a fight in the ring: one round, 90 seconds, no grappling"],
    "howto_move": ["Двигайся по рингу, уклоняйся и держи блок.",
            "Move around the ring, dodge and keep your guard."],
    "howto_punch": ["Пять ударов: джеб, кросс, два хука и апперкот. В голову — больше формы.",
            "Five punches: jab, cross, two hooks and an uppercut. Head shots give more form."],
    "howto_body": ["С Ctrl те же удары идут в корпус: снимают выносливость.",
            "With Ctrl the same punches go to the body: they drain stamina."],
    "howto_knockdown": ["Нокдаун: HP на нуле — падаешь, а не умираешь. Space — встать, у тебя 10 секунд, HP вернётся не полностью (всего 3 нокдауна).",
            "Knockdown: at zero HP you fall instead of dying. Space to get up within 10 seconds; HP comes back partially (3 knockdowns total)."],
    "howto_rope": ["Вылетел за канаты — сразу поражение. Соперника тоже можно вытолкнуть.",
            "Fly through the ropes and you lose. You can push your opponent out too."],
    "howto_career": ["Карьера: 6 поясов по 10 соперников. Побей десятерых — откроешь следующий пояс.",
            "Career: 6 belts, 10 opponents each. Beat all ten to unlock the next belt."],
    "howto_form": ["Форма копится за бои и тренировку, тратится на прокачку. Монеты — на гардероб.",
            "Form comes from fights and training, spent on upgrades. Coins buy wardrobe items."],
    "howto_back": ["ESC / H — назад", "ESC / H — back"],
    # --- итог боя
    "win": ["ПОБЕДА", "WIN"],
    "lose": ["ПОРАЖЕНИЕ", "LOSS"],
    "draw": ["НИЧЬЯ", "DRAW"],
    "by_ko": ["нокдаун", "knockout"],
    "by_time": ["по очкам", "on points"],
    "by_rope": ["соперник за канатами", "opponent through the ropes"],
    "you_rope": ["ты вылетел за канаты", "you flew through the ropes"],
    "time_over": ["время вышло", "time is up"],
    "even": ["равный бой", "even fight"],
    "win_bonus": ["за победу", "for the win"],
    "coin_gain": ["ОЧКОВ В КОПИЛКУ", "POINTS EARNED"],
    "form_gain": ["ФОРМЫ НА ПРОКАЧКУ", "FORM EARNED"],
    "again": ["ЕНТЕР / R — ЕЩЁ РАЗ", "ENTER / R — AGAIN"],
    # --- прокачка/гардероб (кратко, что видно в меню)
    "upgrade_level": ["ур.", "lvl"],
}


static func t(key: String) -> String:
    var pair: Array = DICT.get(key, [])
    if pair.is_empty():
        return key
    return String(pair[0]) if code == "ru" else String(pair[1])


static func set_code(c: String) -> void:
    code = "en" if c == "en" else "ru"


static func toggle() -> void:
    code = "en" if code == "ru" else "ru"


static func is_en() -> bool:
    return code == "en"
