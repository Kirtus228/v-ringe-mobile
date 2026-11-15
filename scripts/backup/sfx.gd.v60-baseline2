extends Node
## Процедурные звуки: несколько AudioStreamPlayer в пуле + боевая музыка лупом.

var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
# громкость из настроек игры: 0..1, применяется поверх базовой громкости состояния
var music_level := 1.0
var sfx_level := 1.0
var _music_base := -20.0
var _sfx_base := -8.0


func build() -> void:
    # отдельные шины громкости: так уровень из настроек действует на всё,
    # включая уже играющие звуки, и его не надо пересчитывать на каждый play()
    _make_bus("Music")
    _make_bus("SFX")
    for key in ["hit", "whoosh", "block", "bell", "ko", "step", "shove", "gasp", "cheer"]:
        var path := "res://sfx/%s.wav" % key
        if ResourceLoader.exists(path):
            streams[key] = load(path)
    for i in 7:
        var p := AudioStreamPlayer.new()
        p.volume_db = -8.0
        p.bus = "SFX"
        add_child(p)
        players.append(p)

    music = AudioStreamPlayer.new()
    music.volume_db = -20.0
    music.bus = "Music"
    add_child(music)
    var mpath := "res://music/fight_loop.wav"
    if ResourceLoader.exists(mpath):
        var stream := load(mpath)
        if stream is AudioStreamWAV:
            var w := stream as AudioStreamWAV
            w.loop_mode = AudioStreamWAV.LOOP_FORWARD
            w.loop_begin = 0
            w.loop_end = int(w.data.size() / 2)
        music.stream = stream


func play(key: String, pitch: float = 1.0, vol: float = -8.0) -> void:
    if not streams.has(key):
        return
    for p in players:
        if not p.playing:
            p.stream = streams[key]
            p.pitch_scale = pitch
            p.volume_db = vol
            p.play()
            return


## Человеческая громкость 0..1 → поправка в дБ (0 → тишина, 1 → без поправки).
## Степень 1.4 делает низ шкалы заметнее: 5/10 — это уже −9 дБ, а не −6.
func _user_db(level: float) -> float:
    if level <= 0.001:
        return -80.0
    return linear_to_db(pow(clampf(level, 0.0, 1.0), 1.4))


## Создаёт шину, если её ещё нет.
func _make_bus(bus_name: String) -> void:
    if AudioServer.get_bus_index(bus_name) >= 0:
        return
    AudioServer.add_bus()
    var idx := AudioServer.bus_count - 1
    AudioServer.set_bus_name(idx, bus_name)
    AudioServer.set_bus_send(idx, "Master")


func _set_bus(bus_name: String, level: float) -> void:
    var idx := AudioServer.get_bus_index(bus_name)
    if idx < 0:
        return
    AudioServer.set_bus_volume_db(idx, _user_db(level))
    AudioServer.set_bus_mute(idx, level <= 0.001)


func set_sfx_level(level: float) -> void:
    sfx_level = clampf(level, 0.0, 1.0)
    _set_bus("SFX", sfx_level)


func set_music_level(level: float) -> void:
    music_level = clampf(level, 0.0, 1.0)
    _set_bus("Music", music_level)
    _apply_music()


func _apply_music() -> void:
    if music == null:
        return
    music.volume_db = _music_base


# ------------------------------------------------------------------ музыка

func music_play(vol: float = -14.0) -> void:
    if music == null or music.stream == null:
        return
    _music_base = vol
    _apply_music()
    music.stream_paused = false
    if not music.playing:
        music.play()


func music_volume(vol: float) -> void:
    if music:
        _music_base = vol
        _apply_music()


func music_pause(paused: bool) -> void:
    if music:
        music.stream_paused = paused


func music_stop() -> void:
    if music:
        music.stop()
