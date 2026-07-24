class_name BootErrorOverlay
extends Control

@onready var _message: Label = (
	$SafeArea/Center/Panel/Margin/Rows/Message
)


func present(message: String) -> void:
	_message.text = message
	visible = true
	move_to_front()


func message_text() -> String:
	return _message.text
