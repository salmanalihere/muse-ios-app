#!/bin/bash
# Foldfleet — compile + run the pure Swift logic on Linux / macOS, without Xcode.
# Needs a Swift toolchain on PATH (Linux: swift.org 6.2+; macOS: Xcode CLI tools).
# This checks GameModel.swift, AIPlayer.swift, Persistence.swift and
# TrialManager.swift only. StoreManager.swift needs StoreKit and SwiftUI /
# UIKit / AVFoundation files still need Xcode 27.1 on a Mac.
set -e
cd "$(dirname "$0")/../.."
SWIFTC="${SWIFTC:-swiftc}"
if ! command -v "$SWIFTC" >/dev/null 2>&1; then
  echo "swiftc not found on PATH."
  echo "Linux: download Swift 6.2+ from swift.org, extract it, then run:"
  echo "  export PATH=\"\$HOME/swift-6.2.1-RELEASE-ubuntu24.04/usr/bin:\$PATH\""
  echo "  bash scripts/swift_check/run.sh"
  echo "macOS: install Xcode 27.1, then run the xcodebuild command in README.md instead."
  exit 1
fi
echo "Using: $($SWIFTC --version | head -1)"
"$SWIFTC" -typecheck Foldfleet/Models/GameModel.swift Foldfleet/Models/AIPlayer.swift Foldfleet/Models/Persistence.swift Foldfleet/Models/TrialManager.swift
echo "typecheck: OK"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp Foldfleet/Models/GameModel.swift Foldfleet/Models/AIPlayer.swift Foldfleet/Models/Persistence.swift Foldfleet/Models/TrialManager.swift "$TMP/"
cp scripts/swift_check/main.swift "$TMP/main.swift"
cd "$TMP"
"$SWIFTC" -swift-version 6 GameModel.swift AIPlayer.swift Persistence.swift TrialManager.swift main.swift -o foldfleet-check
./foldfleet-check
