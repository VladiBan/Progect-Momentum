extends Control

@onready var property_container := get_node_or_null(
    "UserInt/DebugPanel/MarginContainer/VBoxContainer"
)

func _ready():
	visible = true
	size = Vector2(400, 120)
	position = Vector2(20,20)
func add_property(title: String, value, order: int = -1):
	if property_container == null:
		return
	visible = true
	var label := property_container.find_child(title, false, false)
	if label == null:
		label = Label.new()
		label.name = title
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		property_container.add_child(label)

		if order >= 0:
			property_container.move_child(label, order)

	label.text = title + ": " + str(value)
