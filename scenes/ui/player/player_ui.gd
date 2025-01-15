extends Control

func setPlayerName(display_name: String):
	%NameLabel.text = display_name

func setHPBarRatio(ratio: float):
	%HPBar.value = ratio * 100 