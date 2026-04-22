#!/bin/bash

APP_ID=$(cat appid)

protontricks-launch \
	--no-runtime \
	--appid $APP_ID \
	~/.steam/steam/steamapps/compatdata/$APP_ID/pfx/drive_c/Program\ Files/Cheat\ Engine/Cheat\ Engine.exe
