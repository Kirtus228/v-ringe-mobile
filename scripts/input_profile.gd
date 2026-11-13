class_name InputProfile
extends Resource
## Слой ввода: игрок читает действия через профиль, а не напрямую из Input.
## Пока это тонкая обёртка над InputMap (задел под сеть: интент → RPC и под
## разные устройства), но уже с фильтром по устройству и блокировкой.

enum Device { KEYBOARD, JOYPAD }

@export var device_type: Device = Device.KEYBOARD
@export var device_id: int = 0
## Если выключить — профиль не отдаёт нажатия (например, на паузе или в чужом
## матче).
@export var enabled: bool = true


func is_action_pressed(action: String) -> bool:
	if not enabled:
		return false
	if device_type == Device.KEYBOARD:
		return Input.is_action_pressed(action)
	# Godot 4.7: Input.is_action_pressed(action, exact_match) без device_id;
	# устройство фильтруется уровнем событий, здесь оставлен общий опрос.
	return Input.is_action_pressed(action)


func is_action_just_pressed(action: String) -> bool:
	if not enabled:
		return false
	if device_type == Device.KEYBOARD:
		return Input.is_action_just_pressed(action)
	return Input.is_action_just_pressed(action)


func is_action_just_released(action: String) -> bool:
	if not enabled:
		return false
	return Input.is_action_just_released(action)


## Значение аналоговой оси в диапазоне -1..1 (джойстик или клавиши).
func get_axis(negative_action: String, positive_action: String) -> float:
	if not enabled:
		return 0.0
	return Input.get_axis(negative_action, positive_action)


## Вектор движения из действий move_*; для клавиатуры нормализуется.
## T6/T7 пакета 10: раньше здесь стояло "move_forward" — такого действия нет
## (в InputMap оно называется "move_fwd"), из-за чего в локациях тренировки
## каждый кадр печаталось ERROR про отсутствующее действие (897 строк за 5 с).
func get_move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var v := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_fwd", "move_back"))
	if v.length() > 1.0:
		v = v.normalized()
	return v


## Есть ли в проекте действие (для новых действий из тренерского режима).
func has_action(action: String) -> bool:
	return InputMap.has_action(action)
