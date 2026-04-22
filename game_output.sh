#!/bin/bash

APP_ID=$(cat appid)

tail -F ~/steam-$APP_ID.log
