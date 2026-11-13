class_name WaveDef
extends Resource
## Волна кооператива (часть 2): список пресетов EnemyDef с количеством и
## интервалом спавна. Сам EnemyDef не дублируется — в entries лежат ссылки.
##
## entries: Array[Dictionary], каждая запись:
##   {"def": EnemyDef, "count": int, "interval": float}
## count здесь базовый (до множителя от числа игроков), interval — базовый
## интервал между спавнами (до множителя spawn_interval_multiplier).

@export var id := ""
@export var title := ""
@export var entries: Array = []
## Волна-босс: HP босса дополнительно умножается на boss_hp_multiplier.
@export var boss := false
## Необязательная пауза перед волной, секунды.
@export var pre_delay := 0.0


func entry_defs() -> Array:
    var out: Array = []
    for e in entries:
        if e is Dictionary and e.get("def") is EnemyDef:
            out.append(e)
    return out


func base_count() -> int:
    var total := 0
    for e in entry_defs():
        total += maxi(0, int(e.get("count", 0)))
    return total
