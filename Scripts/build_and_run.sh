#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./Scripts/prepare_native.sh
xcodebuild -resolvePackageDependencies -project VibeTalkAudioLab.xcodeproj -scheme VibeTalkAudioLab
xcodebuild -project VibeTalkAudioLab.xcodeproj -scheme VibeTalkAudioLab -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' build
