extends Node


# SOUND EFFECTS
@onready var step = $SFX/Step
@onready var swallow = $SFX/Swallow
@onready var charge = $SFX/Charge
@onready var superjump = $SFX/Superjump
@onready var ouch = $SFX/Ouch

# BACKGROUND MUSIC
@onready var menu = $BGM/Menu
@onready var stage1 = $BGM/Lillius
@onready var boss1 = $BGM/Rhino

func play_unique(player: AudioStreamPlayer):
	for sfx in [$SFX/Step,$SFX/Swallow,$SFX/Charge,$SFX/Superjump,$SFX/Ouch]:
		sfx.stop()
	player.play()
	
func mus_play(player: AudioStreamPlayer):
	player.play()
