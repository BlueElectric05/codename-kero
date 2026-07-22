extends StaticBody2D
class_name SwingAnchor

# Attach this to any Node2D you want the player to be able to grab and swing
# from (a vine tip, a hook, a branch, etc). It just needs to exist in the
# "swing_anchor" group — PlayerController.find_swing_anchor() scans that
# group for candidates in range and in front of the player.

func _ready() -> void:
	add_to_group("swing_anchor")