#!/usr/bin/env bash
# Port/eame: Port/eame Java (J2ME-Decade) as an unsigned iOS app, built with
# the Port/eame kit (port-eame-kit/tools/ios_env.sh). Runs on a Mac with
# Xcode (the kit's GitHub action runs it). No game is used or included: the
# player puts their own .jar files in the app's folder.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export PORTEAME_WORK="${PORTEAME_WORK:-$root/build/ios}"
source "$root/port-eame-kit/tools/ios_env.sh"

# The J2ME API jar, compiled from its source (as the project's own workflow
# does) against the prebuilt miniJVM runtime.
if command -v javac >/dev/null && command -v jar >/dev/null; then
    api="$PORTEAME_WORK/j2me_api"
    rm -rf "$api" && mkdir -p "$api/classes"
    find "$root/j2me_api/src" -name "*.java" > "$api/sources.txt"
    javac --release 8 -nowarn -cp "$root/J2MEEmulator/Resources/jars/minijvm_rt.jar" -d "$api/classes" @"$api/sources.txt"
    jar cf "$root/J2MEEmulator/Resources/jars/j2me_api.jar" -C "$api/classes" .
    ls -l "$root/J2MEEmulator/Resources/jars/j2me_api.jar"
else
    echo "No JDK: the prebuilt j2me_api.jar is used"
fi

porteame_xcodebuild "$root/J2MEEmulator.xcodeproj" J2MEEmulator \
    PRODUCT_BUNDLE_IDENTIFIER=org.porteame.java \
    GCC_OPTIMIZATION_LEVEL=3

app="$PORTEAME_WORK/xcode/Release-iphoneos/JarBox.app"
porteame_check_binary "$app/JarBox"
ls "$app"
porteame_package_app "$root/porteame.json" "$app"
