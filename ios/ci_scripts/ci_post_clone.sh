#!/bin/sh
set -e

# Navigate to project root (ci_scripts is inside ios/)
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install Flutter
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

# Disable analytics in CI
flutter config --no-analytics
dart --disable-analytics

# Get Flutter dependencies and generate files (including Generated.xcconfig)
flutter pub get

# Install CocoaPods dependencies
cd ios
pod install
