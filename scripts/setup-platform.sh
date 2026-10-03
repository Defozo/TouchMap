#!/usr/bin/env bash
set -euo pipefail
tools_dir=${TOUCHMAP_TOOLS_DIR:-"$HOME/touchmap-toolchain"}
mkdir -p "$tools_dir"
npm install --prefix "$tools_dir" @oniroproject/oniro-app@0.11.0
oniro="$tools_dir/node_modules/.bin/oniro-app"
"$oniro" sdk install 6.0
"$oniro" cmdtools install
export ONIRO_EMULATOR_URL=https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/download/v6.1/oniro_emulator.zip
"$oniro" emulator install
