# LOCKED IN
Native iOS gym tracker built with SwiftUI + SwiftData.

## Current V0.1
- Full Body plan with main exercises + alternatives
- Set tracking: weight, reps, RIR
- Large rest timer
- History and stats
- Local SwiftData database
- Optional automatic JSON backup to a user-selected Files/iCloud Drive folder after each completed workout
- `LockedIn-Latest.json` is overwritten each workout
- Last 7 timestamped backups are retained

## Build
GitHub Actions generates an unsigned `LockedIn.ipa`. SideStore signs it with the user's Apple account during installation.

Bundle ID stays fixed: `app.lockedin.tracker`.