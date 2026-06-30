extends Node

@onready var step = $SFX/Step
@onready var swallow = $SFX/Swallow
@onready var charge = $SFX/Charge
@onready var superjump = $SFX/Superjump
@onready var ouch = $SFX/Ouch

func play_unique(player: AudioStreamPlayer):
	for sfx in [$SFX/Step,$SFX/Swallow,$SFX/Charge,$SFX/Superjump,$SFX/Ouch]:
		sfx.stop()
	player.play()
