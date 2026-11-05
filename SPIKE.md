# CloudKit spike (step 0 of studio-brain/specs/sync-web-build-brief.md)

Paused 2026-11-05 to work on Lampwerk. Nothing from this branch is on main.

## Done
- iCloud + CloudKit (container iCloud.com.outandscout.app), aps-environment and Background Modes > remote-notification on the app target (project.yml and the xcodeproj; the background mode comes from OutAndScout-Info.plist, merged with the generated Info.plist).
- `-allowProvisioningUpdates` registered the container and made the profile. No clicks in Signing & Capabilities were needed.
- Debug-only test: Projects > "cloudkit spike" row (OutAndScout/Debug/CloudKitSpike.swift). CKSyncEngine, private zone "Scouts", record spike-test; public record button.
- Local web test pages in spike-web/ (index.html private read/edit/save, public.html#<id> public read). Token goes in spike-web/token.js (gitignored; see token.example.js).

## Left
1. Install on the phone (last try: CoreDeviceError 4016, phone unavailable).
2. Elliot makes the web API token (postMessage; origins https://outandscout.com, http://localhost, http://localhost:8765).
3. Tests: b (phone writes and reads back), c (web signs in, edits, phone shows the edit), d (phone writes public record, public.html reads it with no sign-in). Serve with `python3 -m http.server 8765` in spike-web/.
