#!/usr/bin/env bash
set -eu
export GERBIL_HOME=$(dirname $(cd ${0%/*} && echo $PWD))
export PATH="$GERBIL_HOME/bin:$PATH"

echo "[*] Building gerbil languages"

cd lang && ./build.ss
