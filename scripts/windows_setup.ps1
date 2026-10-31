# Foldfleet — Windows setup (PowerShell)
# Run these in Windows PowerShell, in the unzipped Foldfleet folder.
# You do NOT need a Mac for steps 1–4. Steps 5+ need a cloud Mac.

# 1. Check Python (for the rule tests)
python --version
#    If missing: winget install Python.Python.3.12

# 2. Check the game rules — no Mac, no Swift needed
python scripts/verify_logic.py
#    Expected: 22 passed, 0 failed

# 3. Optional: Swift for Windows (syntax-checks pure Swift logic only;
#    it CANNOT build SwiftUI / UIKit / iOS apps)
winget install Swift.Toolchain
#    Then open the folder in VS Code and install the "Swift" extension.

# 4. Edit the game in VS Code
code .

# 5. When ready to build: push to GitHub, then on a cloud Mac
#    (MacinCloud / MacStadium / AWS EC2 Mac, or a macOS GitHub Actions runner):
#      xcodebuild -version
#        -> Xcode 27.1 Build version 27A9275
#      xcodebuild test -scheme Foldfleet -destination 'platform=iOS Simulator,name=iPhone Duo'
#
#    Do NOT run macOS in a VM on this PC for a release build.
