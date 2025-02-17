extends Node

## This node manages the interactions between the various AI, TTS, and STT functionalities.
## It is meant to serve as an example of merging a bunch of possibilities together.  
## But realisitcally, you will probably choose one Speech to text, AI brain and Text to Speech option in any given project.

# Signal when config options saved
signal options_saved

# Signal when config options loaded
signal options_loaded

# Variable to choose interaction button for speaking to NPC when using "proximity" mode
@export var activate_mic_button : String = "by_button"

# Variable for text to display while mic active and recording
@export var mic_recording_text: String = "Mic recording..."

# Variable for text to display while waiting for response
@export var waiting_text: String = "Waiting for response..."


# Enum for speech to text choice - note, if convai is chosen, convai will automatically be set as brain
enum speech_to_text_type {
	WIT,
	CONVAI,
	WHISPER,
	LOCALWHISPER
}

# Enum for text to speech choice
enum text_to_speech_type {
	GODOT,
	ELEVENLABS,
	CONVAI,
	WIT,
	XVASYNTH
}

# Enum for AI brain choice
enum ai_brain_type {
	CONVAI,
	GPTTURBO,
	GPT4ALL,
	TEXTGENWEBUI,
	TEXTGENWEBUISTREAMING
}

# Export for speech to text type
@export var speech_to_text_choice: speech_to_text_type

# Export for text to speech choice
@export var text_to_speech_choice: text_to_speech_type

# Export for AI Brain choice
@export var ai_brain_type_choice: ai_brain_type

# Export for whether to load api and ai options from config file; change to false if you want to use static api keys provided by your app
@export var use_config_file: bool = true

# Nodes used for wi, gpt, and text to speech
@onready var wit_ai_node = get_node("VRVoiceControl-WitAI")
@onready var gpt_node = get_node("GodotGPT35Turbo")
@onready var interact_label3D = get_node("InteractLabel3D")
@onready var mic_active_label3D = get_node("MicActiveLabel3D")
@onready var convai_node = get_node("GodotConvAI")
@onready var eleven_labs_tts_node = get_node("ElevenLabsTTS")
@onready var whisper_api_node = get_node("WhisperAPI")
@onready var gpt4all_node = get_node("GPT4All")
@onready var local_whisper_node = get_node("LocalWhisper")
@onready var placeholder_sound_player = get_node("PlaceholderSoundPlayer")
@onready var options_viewport = get_node("OptionsViewport2Din3D")
@onready var options_scene = options_viewport.get_scene_instance()
@onready var xvasynth_node = get_node("XVASynth")
@onready var convai_sse_node = get_node("ConvaiSSE")
@onready var textgenwebui_node = get_node("TextgenwebuiOpenAI")
# Variable used to determine if player can use proximity interaction
var close_enough_to_talk : bool = false

# Variable used to determine if already talking
var mic_active : bool = false

# Variables to save / load user preferences and API keys between sessions in config file
var wit_ai_token : String = "insert_your_wit_api_token_here"
var gpt_3_5_turbo_api_key : String = "insert your api key here"
var whisper_api_key : String = "insert your whisper api key"
var gpt_npc_background_directions : String = "You are a non-playable character in a video game.  You are a robot.  Your name is Bob.  Your job is taping boxes of supplies.  You love organization.  You hate mess. Your boss is Robbie the Robot. Robbie is a difficult boss who makes a lot of demands.  You respond to the user's questions as if you are in the video game world with the player."
var gpt_sample_npc_question : String = "Hi, what do you do here?"
var gpt_sample_npc_response : String = "Greetings fellow worker! My name is Bob and I am a robot.  My job is to tape up the boxes in this factory before they are shipped out to our customers!"
var gpt_temperature : float = 0.5
var convai_api_key : String = "insert your api key"
var convai_character_id : String = "9a86c86a-dc4e-11ed-8ecb-42010a7c4003"
var convai_session_id : String = "-1"
var last_convai_session_id : String = "-1"
var convai_standalone_tts_voice = "WUMale 1"
var eleven_labs_api_key : String = "insert your Eleven Labs API Key"
var eleven_labs_character_code : String = "nccuBdAiU0VZsr2UBFyD"
var wit_ai_tts_voice : String = "Prospector"
var wit_ai_tts_speed : int = 100
var wit_ai_tts_pitch : int = 100
var gpt4all_model_name : String = "ggml-gpt4all-j-v1.3-groovy.bin"
var config_text_to_speech_choice = text_to_speech_type.CONVAI
var config_ai_brain_type_choice = ai_brain_type.CONVAI
var config_speech_to_text_choice = speech_to_text_type.WIT
var xVASynth_model_path : String = ""
# Whether to use convai in stream or normal API mode
var use_convai_stream_mode : bool = true

# Variables for new Godot4 native text to speech (does not work on android)
var voices 
var voice_id

# Array to hold audio files for placeholder sounds (T0 DO: Implement example)
var placeholder_sound_array = []
# Used to select random placeholder sound options
var random : RandomNumberGenerator
# Used to determine whether voice playing is just a placeholder or is the final voice for the AI response
var placeholder_voice : bool = false


func _ready():
	# Load config file so it is ready if needed
	load_api_info()
	
	# Set voice for Godot text to speech
	if !OS.has_feature("android"):
		voices = DisplayServer.tts_get_voices_for_language("en")
		voice_id = voices[0]
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, Callable(self, "_on_voice_played"))
	
	# Set up xvasynth if user has entered a xVASynth model path in the config file
	if !OS.has_feature("android") and xVASynth_model_path != "":
		xvasynth_node.model_path = xVASynth_model_path
		var thread = Thread.new()
		thread.start(Callable(xvasynth_node, "initiate_XVASynth"))
		await get_tree().create_timer(7.0).timeout
		xvasynth_node.load_XVASynth_model()
		
	# Connect wit ai speech to text received signal to handler function
	wit_ai_node.connect("wit_ai_speech_to_text_received", Callable(self, "_on_wit_ai_processed"))
	
	# Connect AI response generated signal from GPT to handler function
	gpt_node.connect("AI_response_generated", Callable(self, "_on_gpt_3_5_turbo_processed"))
	
	# Connect AI response generated signal from ConvAI to handler function
	convai_node.connect("AI_response_generated", Callable(self, "_on_convai_processed"))
	convai_sse_node.connect("AI_response_generated", Callable(self, "_on_convai_processed"))
	
	# Connect whisper speech to text received signal to handler function
	whisper_api_node.connect("whisper_speech_to_text_received", Callable(self, "_on_whisper_processed"))
	
	# Connect AI response generated signal from GPT4All to handler function
	gpt4all_node.connect("AI_response_generated", Callable(self, "_on_gpt4all_processed"))
	
	# Connect AI response generated signal from Textgenwebui to handler function
	textgenwebui_node.connect("AI_response_generated", Callable(self, "_on_textgenwebui_processed"))
	
	# Connect local whisper speech to text received signal to handler function
	local_whisper_node.connect("whisper_speech_to_text_received", Callable(self, "_on_local_whisper_processed"))
	
	# Connect voice played signal from Wit ai
	wit_ai_node.connect("wit_voice_sample_played", Callable(self, "_on_voice_played"))
	
	# Connect voice played signal from Convai
	convai_node.connect("convAI_voice_sample_played", Callable(self, "_on_voice_played"))
	convai_sse_node.connect("convAI_voice_sample_played", Callable(self, "_on_voice_played"))
	
	# Connect voice played signal from ElevenLabs
	eleven_labs_tts_node.connect("ElevenLabs_generated_speech", Callable(self, "_on_voice_played"))
	
	# Connect voice played signal from XVASynth
	xvasynth_node.connect("xvasynth_voice_sample_played", Callable(self, "_on_voice_played"))
	
	# Connect options scene signals
	options_viewport.connect_scene_signal("ai_brain_option_chosen", Callable(self, "_on_ai_brain_option_chosen"))
	options_viewport.connect_scene_signal("tts_option_chosen", Callable(self, "_on_tts_option_chosen"))
#	options_viewport.connect_scene_signal("stt_option_chosen", Callable(self, "_on_stt_option_chosen"))
	
	#Connect 
	# If using config file to load keys and options, set those here
	if use_config_file == true:
		# Set wit.ai API key
		wit_ai_node.set_token(wit_ai_token)
		
		# Set wit.ai speech voice
		wit_ai_node.set_wit_tts_voice(wit_ai_tts_voice)
		
		# Set wit.ai speech speed
		wit_ai_node.set_wit_tts_speech_speed(wit_ai_tts_speed)
		
		# Set wit.ai speech pitch
		wit_ai_node.set_wit_tts_speech_pitch(wit_ai_tts_pitch)
		
		# Set GPT API key
		gpt_node.set_api_key(gpt_3_5_turbo_api_key)

		# Set GPT Temperature
		gpt_node.set_temperature(gpt_temperature)

		# Set GPT background info
		gpt_node.npc_background_directions = gpt_npc_background_directions
		gpt_node.sample_npc_question_prompt = gpt_sample_npc_question
		gpt_node.sample_npc_prompt_response = gpt_sample_npc_response

		# Set Textgenwebui background info
		textgenwebui_node.npc_background_directions = gpt_npc_background_directions
		textgenwebui_node.sample_npc_question_prompt = gpt_sample_npc_question
		textgenwebui_node.sample_npc_prompt_response = gpt_sample_npc_response
		# Set ConvAI API key
		convai_node.set_api_key(convai_api_key)
		convai_sse_node.set_api_key(convai_api_key)
		
		# Set ConvAI Character Code
		convai_node.set_character_id(convai_character_id)
		convai_sse_node.set_character_id(convai_character_id)
		
		# Set Convai Session ID to last one if not default
		if last_convai_session_id != "-1" and last_convai_session_id != "":
			convai_node.set_session_id(last_convai_session_id)
			convai_sse_node.set_session_id(last_convai_session_id)
		else:
			convai_node.set_session_id(convai_session_id)
			convai_sse_node.set_session_id(convai_session_id)
			
		# Set Convai Standalone Voice selection
		convai_node.set_convai_standalone_tts_voice(convai_standalone_tts_voice)
		
		# Set ElevenLabs API key
		eleven_labs_tts_node.set_api_key(eleven_labs_api_key)

		# Set ElevenLabs Character Code
		eleven_labs_tts_node.set_character_code(eleven_labs_character_code)

		#Set Whisper API key
		whisper_api_node.set_api_key(whisper_api_key)
		
		#Set GPT4All model
		gpt4all_node.set_model(gpt4all_model_name)
		
		# Set own options
		text_to_speech_choice = config_text_to_speech_choice
		ai_brain_type_choice = config_ai_brain_type_choice
		speech_to_text_choice = config_speech_to_text_choice
		
	# If using convai for speech to text, then make AI brain automatically use convai too for the most efficient pipeline
	if speech_to_text_choice == speech_to_text_type.CONVAI:
		ai_brain_type_choice = ai_brain_type.CONVAI
		# Activate convai voice commands
		convai_node.activate_voice_commands(true)
	
	elif speech_to_text_choice == speech_to_text_type.WIT:
		# Activate wit ai voice commands
		wit_ai_node.activate_voice_commands(true)
		
	elif speech_to_text_choice == speech_to_text_type.WHISPER:
		# Activate GPT Whisper speech to text
		whisper_api_node.activate_voice_commands(true)
		
	else:
		# Activate local whisper speech to text (only works on windows)
		local_whisper_node.activate_voice_commands(true)
		
	# If text to speech mode is convai, then if ConvAI is the AI brain, make sure its voice response mode is set to true, otherwise make sure to use standalone convAI TTS function
	if text_to_speech_choice == text_to_speech_type.CONVAI:
		if ai_brain_type_choice == ai_brain_type.CONVAI:
			convai_node.set_voice_response_mode(true)
			convai_sse_node.set_voice_response_mode(true)
			convai_node.set_use_standalone_tts(false)
		else:
			convai_node.set_voice_response_mode(false)
			convai_sse_node.set_voice_response_mode(false)
			convai_node.set_use_standalone_tts(true)	
	else:
		convai_node.set_voice_response_mode(false)
		convai_sse_node.set_voice_response_mode(false)
		convai_node.set_use_standalone_tts(false)
	# Set buttons on options menu to current choices
#	options_scene.get_node("ColorRect/STTOptionButton").selected = speech_to_text_choice
	options_scene.get_node("ColorRect/TTSOptionButton").selected = text_to_speech_choice
	options_scene.get_node("ColorRect/AIBrainOptionButton").selected = ai_brain_type_choice
	
	# Set up random for placeholder sounds
	random = RandomNumberGenerator.new()
	random.randomize()
	
	# Testing only right now
	# in standalone mode or character/getResponse mode
	#await get_tree().create_timer(10.0).timeout
	#convai_node.call_convai_speech_to_text_standalone("user://convaimicaudio.wav")
	
	# Testing for XVASynth
#	await get_tree().create_timer(10.0).timeout
#	xvasynth_node.XVASynth_synthesize("     First, I will win. Second, I will be victorious.  Third, I will triumph. Fourth, I will go to the movies.  Fifth, I will win an oscar.   ")
#	xvasynth_node.XVASynth_synthesize("     Sixth, I will laugh    ")
#	xvasynth_node.XVASynth_synthesize("     Ending here.   ")
#
	# Testing GPT4All server mode
	#await get_tree().create_timer(5.0).timeout
	#gpt4all_node.call_GPT4All("Hi, who are you?")
	
	# Testing Textgenwebui OpenAI mode
#	await get_tree().create_timer(10.0).timeout
#	gpt_node.url = "http://127.0.0.1:5001/v1/chat/completions"
#	gpt_node.call_GPT("Hi how are you doing today?")

	#Testing textgenwebui streaming openai mode
#	await get_tree().create_timer(10.0).timeout
#	textgenwebui_node.url = "http://0.0.0.1:5001/v1/chat/completions"
#	textgenwebui_node.streaming_url = "http://0.0.0.1"
#	$TextgenwebuiOpenAI.call_GPT_streaming("Hi what are you doing here?")

# Handler for player VR button presses to determine if player is trying to activate or stop mic while in proximity of NPC
func _on_player_controller_button_pressed(button):
	if button != activate_mic_button:
		return
		
	if button == activate_mic_button and close_enough_to_talk and !mic_active:
		if speech_to_text_choice == speech_to_text_type.WIT:
			wit_ai_node.start_voice_command()
		elif speech_to_text_choice == speech_to_text_type.CONVAI:
			convai_node.start_voice_command()
		elif speech_to_text_choice == speech_to_text_type.WHISPER:
			whisper_api_node.start_voice_command()
		else:
			local_whisper_node.start_voice_command()
		mic_active = true
		mic_active_label3D.text = mic_recording_text
		mic_active_label3D.visible = true
		return
		
	if button == activate_mic_button and close_enough_to_talk and mic_active:
		mic_active_label3D.text = waiting_text
		if speech_to_text_choice == speech_to_text_type.WIT:
			wit_ai_node.end_voice_command()
		elif speech_to_text_choice == speech_to_text_type.CONVAI:
			convai_node.end_voice_command()
		elif speech_to_text_choice == speech_to_text_type.WHISPER:
			whisper_api_node.end_voice_command()
		else:
			local_whisper_node.end_voice_command()
		mic_active = false
		return
	
	
# Called to activate ability to start talking to NPC when in NPC's area, and display message to user notifying proximity activation is available
func _on_npc_dialogue_enabled_area_entered(body):
	close_enough_to_talk = true
	interact_label3D.visible = true
	
	
# Called to disable ability to start talking to NPC when not in NPC's area unless pointing at NPC and hide message regarding promixity use
func _on_npc_dialogue_enabled_area_exited(body):
	close_enough_to_talk = false
	interact_label3D.visible = false


# Called when player points at NPC's body and presses the button assigned for interactions in the function pointer node (default: VR Trigger)	
# The VR Function Pointer node in XR Tools passes the location of the click which is why there is a parameter for "location" here although not used.
func _on_npc_area_interaction_area_clicked(location):
	# If mic is already active, then end voice command and display waiting notification to user while wit.ai and GPT process response
	if mic_active:
		if speech_to_text_choice == speech_to_text_type.WIT:
			wit_ai_node.end_voice_command()
		elif speech_to_text_choice == speech_to_text_type.CONVAI:
			convai_node.end_voice_command()
		elif speech_to_text_choice == speech_to_text_type.WHISPER:
			whisper_api_node.end_voice_command()
		else:
			local_whisper_node.end_voice_command()
		mic_active = false
		mic_active_label3D.text = waiting_text
	# Otherwise, start voice command and display mic recording notification to user	
	else:
		if speech_to_text_choice == speech_to_text_type.WIT:
			wit_ai_node.start_voice_command()
		elif speech_to_text_choice == speech_to_text_type.CONVAI:
			convai_node.start_voice_command()
		elif speech_to_text_choice == speech_to_text_type.WHISPER:
			whisper_api_node.start_voice_command()
		else:
			local_whisper_node.start_voice_command()
		mic_active = true
		mic_active_label3D.text = mic_recording_text
		mic_active_label3D.visible = true


# Function called when wit.ai finishes processing speech to text, use the text it produces to call GPT	
func _on_wit_ai_processed(prompt : String):
	mic_active_label3D.text = "Speech decoded as: " + prompt + "...Waiting for response."
	
	# Example of parsing speech to text for key command words like quitting the game; wit actually does this with its intent system but this could be a fallback if it misses it.
	if prompt.matchn("*quit*"):
		save_api_info()
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	
	# If using local GPT generation, play additional heard you prompt to fill space
	if ai_brain_type_choice == ai_brain_type.GPT4ALL: # or ai_brain_type_choice == ai_brain_type.TEXTGENWEBUI or ai_brain_type_choice == ai_brain_type.TEXTGENWEBUISTREAMING:
		# Play "I heard you" speech
		play_heard_you(prompt)
	
	if ai_brain_type_choice == ai_brain_type.CONVAI:
		if use_convai_stream_mode == false:
			convai_node.call_convAI(prompt)
		else:
			convai_sse_node.call_convai_SSE(prompt)
	elif ai_brain_type_choice == ai_brain_type.GPTTURBO:
		gpt_node.call_GPT(prompt)
	elif ai_brain_type_choice == ai_brain_type.TEXTGENWEBUI:
		textgenwebui_node.call_GPT(prompt)
	elif ai_brain_type_choice == ai_brain_type.TEXTGENWEBUISTREAMING:
		textgenwebui_node.call_GPT_streaming(prompt)
	else:
		# If using GPT4All, since you are calling an exe outside of the project you need to create a thread otherwise the program freezes while GPT4All is executing
		# To do: investigate mutex and semaphores
		var thread = Thread.new()
		var err = thread.start(Callable(gpt4all_node, "call_GPT4All").bind(prompt))
		#gpt4all_node.call_GPT4All_server(prompt)

# Function called when GPT 3.5 turbo finishes processes AI dialogue response, use text_to_speech addon node, Eleven AI or ConvAI to play the audio response	
# If you are using a different text to speech solution, the command to call it could be used here instead.
func _on_gpt_3_5_turbo_processed(dialogue : String):
	mic_active_label3D.text = "Response: " + dialogue
	if text_to_speech_choice == text_to_speech_type.GODOT:
		DisplayServer.tts_speak(dialogue, voice_id, 100, 1.0, 1.2, false)
	elif text_to_speech_choice == text_to_speech_type.ELEVENLABS:
		eleven_labs_tts_node.call_ElevenLabs(dialogue)
	elif text_to_speech_choice == text_to_speech_type.WIT:
		wit_ai_node.call_wit_TTS(dialogue)
	elif text_to_speech_choice == text_to_speech_type.XVASYNTH:
		xvasynth_node.XVASynth_synthesize(dialogue)
	else:
		convai_node.call_convAI_TTS(dialogue)


# Function called when convAI finishes processes AI dialogue response, use Convai node, text_to_speech addon node or Eleven Labs to play the audio response depending on user choice	
func _on_convai_processed(dialogue : String):
	mic_active_label3D.text = "Response: " + dialogue
	if text_to_speech_choice == text_to_speech_type.GODOT:
		# The false argument here is optional, if true you can interrupt dialogue, with false, allows streaming in advance of text for speech.  Waiting for Godot 4.1 to fully fix streaming responses.
		DisplayServer.tts_speak(dialogue, voice_id, 100, 1.0, 1.2, false)
	elif text_to_speech_choice == text_to_speech_type.ELEVENLABS:
		eleven_labs_tts_node.call_ElevenLabs(dialogue)
	elif text_to_speech_choice == text_to_speech_type.WIT:
		wit_ai_node.call_wit_TTS(dialogue)
	elif text_to_speech_choice == text_to_speech_type.XVASYNTH:
		xvasynth_node.XVASynth_synthesize(dialogue)
	# If using convai text to speech, don't need to do anything else since speech already generated by that node
	else:
		pass


# Function called when GPT4All finishes processing AI response, use the text it produces to call text to speech
func _on_gpt4all_processed(dialogue: String):
	mic_active_label3D.text = "Response: " + dialogue
	if text_to_speech_choice == text_to_speech_type.GODOT:
		DisplayServer.tts_speak(dialogue, voice_id, 100, 1.0, 1.2, false)
	elif text_to_speech_choice == text_to_speech_type.ELEVENLABS:
		eleven_labs_tts_node.call_ElevenLabs(dialogue)
	elif text_to_speech_choice == text_to_speech_type.WIT:
		wit_ai_node.call_wit_TTS(dialogue)
	elif text_to_speech_choice == text_to_speech_type.XVASYNTH:
		xvasynth_node.XVASynth_synthesize(dialogue)
	else:
		convai_node.call_convAI_TTS(dialogue)	


func _on_textgenwebui_processed(dialogue: String):
	mic_active_label3D.text = "Response: " + dialogue
	if text_to_speech_choice == text_to_speech_type.GODOT:
		DisplayServer.tts_speak(dialogue, voice_id, 100, 1.0, 1.2, false)
	elif text_to_speech_choice == text_to_speech_type.ELEVENLABS:
		eleven_labs_tts_node.call_ElevenLabs(dialogue)
	elif text_to_speech_choice == text_to_speech_type.WIT:
		wit_ai_node.call_wit_TTS(dialogue)
	elif text_to_speech_choice == text_to_speech_type.XVASYNTH:
		xvasynth_node.XVASynth_synthesize(dialogue)
	else:
		convai_node.call_convAI_TTS(dialogue)	

# Function called when whisper finishes processing speech to text, use the text it produces to call AI brain
func _on_whisper_processed(prompt: String):
	mic_active_label3D.text = "Speech decoded as: " + prompt + "...Waiting for response."
	# Example of parsing speech to text for key command words like quitting the game
	if prompt.matchn("*quit*"):
		save_api_info()
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	
	# If using local GPT generation, play additional heard you prompt to fill space
	if ai_brain_type_choice == ai_brain_type.GPT4ALL: # or ai_brain_type_choice == ai_brain_type.TEXTGENWEBUI or ai_brain_type_choice == ai_brain_type.TEXTGENWEBUISTREAMING:
		# Play "I heard you" speech
		play_heard_you(prompt)
	
	if ai_brain_type_choice == ai_brain_type.CONVAI:
		if use_convai_stream_mode == false:
			convai_node.call_convAI(prompt)
		else:
			convai_sse_node.call_convai_SSE(prompt)
	elif ai_brain_type_choice == ai_brain_type.GPTTURBO:
		gpt_node.call_GPT(prompt)
	elif ai_brain_type_choice == ai_brain_type.TEXTGENWEBUI:
		textgenwebui_node.call_GPT(prompt)
	elif ai_brain_type_choice == ai_brain_type.TEXTGENWEBUISTREAMING:
		textgenwebui_node.call_GPT_streaming(prompt)
	else:
		# If using GPT4All, since you are calling an exe outside of the project you need to create a thread otherwise the program freezes while GPT4All is executing
		# To do: investigate mutex and semaphores
		var thread = Thread.new()
		var err = thread.start(Callable(gpt4all_node, "call_GPT4All").bind(prompt))
		#gpt4all_node.call_GPT4All_server(prompt)


# Function called when local whisper finishes processing speech to text, use the text it produces to call AI brain
func _on_local_whisper_processed(prompt: String):
	mic_active_label3D.text = "Speech decoded as: " + prompt + "...Waiting for response."
	# Example of parsing speech to text for key command words like quitting the game
	if prompt.matchn("*quit*"):
		save_api_info()
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	
	# If using local GPT generation, play additional heard you prompt to fill space
	if ai_brain_type_choice == ai_brain_type.GPT4ALL: #or ai_brain_type_choice == ai_brain_type.TEXTGENWEBUI or ai_brain_type_choice == ai_brain_type.TEXTGENWEBUISTREAMING:
		# Play "I heard you" speech
		play_heard_you(prompt)
	
	if ai_brain_type_choice == ai_brain_type.CONVAI:
		if use_convai_stream_mode == false:
			convai_node.call_convAI(prompt)
		else:
			convai_sse_node.call_convai_SSE(prompt)
	elif ai_brain_type_choice == ai_brain_type.GPTTURBO:
		gpt_node.call_GPT(prompt)
	elif ai_brain_type_choice == ai_brain_type.TEXTGENWEBUI:
		textgenwebui_node.call_GPT(prompt)
	elif ai_brain_type_choice == ai_brain_type.TEXTGENWEBUISTREAMING:
		textgenwebui_node.call_GPT_streaming(prompt)
	else:
		# If using GPT4All, since you are calling an exe outside of the project you need to create a thread otherwise the program freezes while GPT4All is executing
		# To do: investigate mutex and semaphores
		var thread = Thread.new()
		var err = thread.start(Callable(gpt4all_node, "call_GPT4All").bind(prompt))
		#gpt4all_node.call_GPT4All_server(prompt)

# Receiver function for whenever AI voice is played
func _on_voice_played():
	if placeholder_voice == false:
		mic_active_label3D.visible = false
	# If a voice is played while placeholder is true, then set false for next voice
	else:
		placeholder_voice = false
	
func _on_ai_brain_option_chosen(choice):
	ai_brain_type_choice = choice
	
	
func _on_tts_option_chosen(choice):
	text_to_speech_choice = choice
	print("text to speech option is" + str(choice))
	if text_to_speech_choice == text_to_speech_type.CONVAI:
		if ai_brain_type_choice == ai_brain_type.CONVAI:
			convai_node.set_voice_response_mode(true)
			convai_sse_node.set_voice_response_mode(true)
			convai_node.set_use_standalone_tts(false)
		else:
			convai_node.set_voice_response_mode(false)
			convai_sse_node.set_voice_response_mode(false)
			convai_node.set_use_standalone_tts(true)	
	else:
		convai_node.set_voice_response_mode(false)
		convai_sse_node.set_voice_response_mode(false)
		convai_node.set_use_standalone_tts(false)

# This seemed to be too complicated to implement but leaving as example code commented out	
#func _on_stt_option_chosen(choice):
#	speech_to_text_choice = choice
#	print("speech to text option is" + str(choice))
#	if speech_to_text_choice == speech_to_text_type.CONVAI:
#		ai_brain_type_choice = ai_brain_type.CONVAI
#		# Activate convai voice commands
#		convai_node.activate_voice_commands(true)
#		wit_ai_node.activate_voice_commands(false)
#		whisper_api_node.activate_voice_commands(false)
#		local_whisper_node.activate_voice_commands(false)
#
#	elif speech_to_text_choice == speech_to_text_type.WIT:
#		# Activate wit ai voice commands
#		wit_ai_node.activate_voice_commands(true)
#		convai_node.activate_voice_commands(false)
#		whisper_api_node.activate_voice_commands(false)
#		local_whisper_node.activate_voice_commands(false)
#
#	elif speech_to_text_choice == speech_to_text_type.WHISPER:
#		# Activate GPT Whisper speech to text
#		whisper_api_node.activate_voice_commands(true)
#		wit_ai_node.activate_voice_commands(false)
#		convai_node.activate_voice_commands(false)
#		local_whisper_node.activate_voice_commands(false)
#	else:
#		# Activate local whisper speech to text (only works on windows)
#		local_whisper_node.activate_voice_commands(true)
#		wit_ai_node.activate_voice_commands(false)
#		convai_node.activate_voice_commands(false)
#		whisper_api_node.activate_voice_commands(false)


# Play placeholder "heard what you said" sound while waiting for AI response
func play_heard_you(prompt):
	placeholder_voice = true
	var possible_statement_array = ["I heard you say: ", "Hm, so you said: ", "If I heard right, you said: ", "I'm a great listener. You say: ", "Oh, you said: ", "What you're asking me is: "]
	var statement = random.randi_range(0, possible_statement_array.size()-1)
	if text_to_speech_choice == text_to_speech_type.GODOT:
		DisplayServer.tts_speak((possible_statement_array[statement] + prompt), voice_id, 100, 1.0, 1.2, false)
	elif text_to_speech_choice == text_to_speech_type.ELEVENLABS:
		eleven_labs_tts_node.call_ElevenLabs(possible_statement_array[statement] + prompt)
	elif text_to_speech_choice == text_to_speech_type.WIT:
		wit_ai_node.call_wit_TTS(possible_statement_array[statement] + prompt)
	elif text_to_speech_choice == text_to_speech_type.XVASYNTH:
		xvasynth_node.XVASynth_synthesize(possible_statement_array[statement] + prompt)
	else:
		convai_node.call_convAI_TTS(possible_statement_array[statement] + prompt)
	
	
# Saver function, saving options to config file
func save_api_info():
	# Save convai session id if using convai for possible persistence between sessions
	last_convai_session_id = convai_node.get_session_id()
	var err : int
	var prefs_cfg : ConfigFile = ConfigFile.new()
	var exe_cfg_path : String
	# Determine where to put file, then save it
	if OS.has_feature("editor"):
		exe_cfg_path = "user://ai_npc_api_keys.cfg"
		if not FileAccess.file_exists(exe_cfg_path):
			# To create a new file
			# warning-ignore:return_value_discarded
			FileAccess.open(exe_cfg_path, FileAccess.WRITE)
		err = prefs_cfg.load(exe_cfg_path)
	elif OS.has_feature("android"):
		exe_cfg_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false) + "/" + "ai_npc_api_keys.cfg"
		if not FileAccess.file_exists(exe_cfg_path):
			FileAccess.open(exe_cfg_path, FileAccess.WRITE)
		err = prefs_cfg.load(exe_cfg_path)
	else:
		exe_cfg_path = OS.get_executable_path().get_base_dir() + "/" + "ai_npc_api_keys.cfg"
		if not FileAccess.file_exists(exe_cfg_path):
			FileAccess.open(exe_cfg_path, FileAccess.WRITE)
		err = prefs_cfg.load(exe_cfg_path)
	
	if err == OK:
		prefs_cfg.set_value("api_keys", "wit_ai_token", wit_ai_token)
		prefs_cfg.set_value("api_keys", "gpt_3_5_turbo_api_key", gpt_3_5_turbo_api_key)
		prefs_cfg.set_value("api_keys", "whisper_api_key", whisper_api_key)
		prefs_cfg.set_value("gpt_options", "gpt_npc_background_directions", gpt_npc_background_directions)
		prefs_cfg.set_value("gpt_options", "gpt_sample_npc_question", gpt_sample_npc_question)
		prefs_cfg.set_value("gpt_options", "gpt_sample_npc_response", gpt_sample_npc_response)
		prefs_cfg.set_value("gpt_options", "gpt_temperature", gpt_temperature)
		prefs_cfg.set_value("api_keys", "convai_api_key", convai_api_key)
		prefs_cfg.set_value("api_keys", "convai_character_id", convai_character_id)
		prefs_cfg.set_value("api_keys", "convai_session_id", convai_session_id)
		prefs_cfg.set_value("convai_options", "convai_standalone_tts_voice", convai_standalone_tts_voice)
		prefs_cfg.set_value("convai_options", "last_convai_sesion_id", last_convai_session_id)
		prefs_cfg.set_value("api_keys", "eleven_labs_api_key", eleven_labs_api_key)
		prefs_cfg.set_value("api_keys", "eleven_labs_character_code", eleven_labs_character_code)
		prefs_cfg.set_value("wit_options", "wit_ai_tts_voice", wit_ai_tts_voice)
		prefs_cfg.set_value("wit_options", "wit_ai_tts_speed", wit_ai_tts_speed)
		prefs_cfg.set_value("wit_options", "wit_ai_tts_pitch", wit_ai_tts_pitch)
		prefs_cfg.set_value("gpt4all_options", "gpt4all_model_name", gpt4all_model_name)
		prefs_cfg.set_value("ai_npc_options", "ai_npc_controller_tts_choice", text_to_speech_choice)
		prefs_cfg.set_value("ai_npc_options", "ai_npc_controller_ai_brain_choice", ai_brain_type_choice)
		prefs_cfg.set_value("ai_npc_options", "ai_npc_controller_stt_choice", speech_to_text_choice)
		prefs_cfg.set_value("xVASynth_options", "xVASynth_model_path", xVASynth_model_path)
		err = prefs_cfg.save(exe_cfg_path)
	
	emit_signal("options_saved")
	
	
func load_api_info():
	var prefs_cfg: ConfigFile = ConfigFile.new()
	var err: int
	# Determine where file should be
	if OS.has_feature("editor"):
		err = prefs_cfg.load("user://ai_npc_api_keys.cfg")
		#print(err)
		#print("editor config loaded")
		print("Config directory is:")
		print(OS.get_config_dir())
		print("Data directory is:")
		print(OS.get_data_dir())
	elif OS.has_feature("android"):
#		print_debug("OS data directory is:" + str(OS.get_data_dir()))
#		print_debug("OS user data directory is" + str(OS.get_user_data_dir()))
#		print_debug("OS documents path is" + str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false)))
		var exe_cfg_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false) + "/" + "ai_npc_api_keys.cfg"
		err = prefs_cfg.load(exe_cfg_path)
		#print(err)
	else:
		var exe_cfg_path : String = OS.get_executable_path().get_base_dir() + "/" + "ai_npc_api_keys.cfg"
		err = prefs_cfg.load(exe_cfg_path)
		#print(err)
		
	if err == OK:
		wit_ai_token = prefs_cfg.get_value("api_keys", "wit_ai_token", "insert_your_wit_api_token_here")
		gpt_3_5_turbo_api_key = prefs_cfg.get_value("api_keys", "gpt_3_5_turbo_api_key", "insert your api key here")
		gpt_npc_background_directions = prefs_cfg.get_value("gpt_options", "gpt_npc_background_directions", "You are a non-playable character in a video game.  You are a robot.  Your name is Bob.  Your job is taping boxes of supplies.  You love organization.  You hate mess. Your boss is Robbie the Robot. Robbie is a difficult boss who makes a lot of demands.  You respond to the user's questions as if you are in the video game world with the player.")
		gpt_sample_npc_question = prefs_cfg.get_value("gpt_options", "gpt_sample_npc_question", "Hi, what do you do here?")
		gpt_sample_npc_response = prefs_cfg.get_value("gpt_options", "gpt_sample_npc_response", "Greetings fellow worker! My name is Bob and I am a robot.  My job is to tape up the boxes in this factory before they are shipped out to our customers!")
		gpt_temperature = prefs_cfg.get_value("gpt_options", "gpt_temperature", 0.5)
		convai_api_key = prefs_cfg.get_value("api_keys", "convai_api_key", "insert your api key")
		convai_character_id = prefs_cfg.get_value("api_keys", "convai_character_id", "insert your convai character code")
		convai_session_id = prefs_cfg.get_value("api_keys", "convai_session_id", "-1")
		last_convai_session_id = prefs_cfg.get_value("convai_options", "last_convai_sesion_id", "-1")
		convai_standalone_tts_voice = prefs_cfg.get_value("convai_options", "convai_standalone_tts_voice", "WUMale 1")
		eleven_labs_api_key = prefs_cfg.get_value("api_keys", "eleven_labs_api_key", "insert your Eleven Labs API Key")
		eleven_labs_character_code = prefs_cfg.get_value("api_keys", "eleven_labs_character_code", "nccuBdAiU0VZsr2UBFyD")
		wit_ai_tts_voice = prefs_cfg.get_value("wit_options", "wit_ai_tts_voice", "Prospector")
		wit_ai_tts_speed = prefs_cfg.get_value("wit_options", "wit_ai_tts_speed", 100)
		wit_ai_tts_pitch = prefs_cfg.get_value("wit_options", "wit_ai_tts_pitch", 100)
		whisper_api_key = prefs_cfg.get_value("api_keys", "whisper_api_key", "insert your whisper api key")
		gpt4all_model_name = prefs_cfg.get_value("gpt4all_options", "gpt4all_model_name", "ggml-gpt4all-j-v1.3-groovy.bin")
		config_text_to_speech_choice = prefs_cfg.get_value("ai_npc_options", "ai_npc_controller_tts_choice", text_to_speech_type.CONVAI)
		config_ai_brain_type_choice = prefs_cfg.get_value("ai_npc_options", "ai_npc_controller_ai_brain_choice", ai_brain_type.CONVAI)
		config_speech_to_text_choice = prefs_cfg.get_value("ai_npc_options", "ai_npc_controller_stt_choice", speech_to_text_type.WIT)
		xVASynth_model_path = prefs_cfg.get_value("xVASynth_options", "xVASynth_model_path", "")
	emit_signal("options_loaded")

