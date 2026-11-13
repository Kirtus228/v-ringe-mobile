class_name TrainingConfig
extends Resource
## Конфиг режима «Тренировка»: список локаций, флаги прогрессии и износа.
## Экземпляр — resources/training_config.tres. Логика читает флаги отсюда.

## Локации в порядке показа в хабе.
@export var locations: Array[TrainingLocationDef] = []
## Включены ли разблокировки по условиям из TrainingLocationDef.unlock.
@export var use_location_unlocks := false
## Включён ли износ самодельного оборудования (подвал).
@export var use_equipment_wear := false
## Сколько прочности у оборудования на старте.
@export var durability_max := 100.0
## Восстановление прочности при починке.
@export var repair_restore := 100.0
## Закрывать локацию в меню, если она заблокирована (иначе видна с замком).
@export var hide_locked := false


func find_location(id: String) -> TrainingLocationDef:
	for l in locations:
		if l != null and l.id == id:
			return l
	return null


func find_station(location_id: String, station_id: String) -> StationDef:
	var loc := find_location(location_id)
	if loc == null:
		return null
	for s in loc.stations:
		if s != null and s.id == station_id:
			return s
	return null
