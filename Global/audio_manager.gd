extends Node


# SOUND EFFECTS
@onready var step = $SFX/Step
@onready var swallow = $SFX/Swallow
@onready var charge = $SFX/Charge
@onready var superjump = $SFX/Superjump
@onready var ouch = $SFX/Ouch
@onready var jump = $SFX/Jump
@onready var pop = $SFX/Pop
@onready var tongue = $SFX/Tongue

# BACKGROUND MUSIC
@onready var menu = $BGM/Menu
@onready var stage1 = $BGM/Lillius
@onready var boss1 = $BGM/Rhino

# Plays sound effect without overlapping each other
func play_unique(player: AudioStreamPlayer):
	for sfx in [$SFX/Step,$SFX/Swallow,$SFX/Charge,$SFX/Superjump,$SFX/Ouch, $SFX/Jump, $SFX/Pop, $SFX/Tongue]:
		sfx.stop()
	player.play()

# Plays music, very straightforward
func mus_play(player: AudioStreamPlayer):
	player.play()
