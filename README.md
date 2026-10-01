# out & scout

Location scouting for cinematographers. iPhone only, SwiftUI, landscape.

Point your phone at the location. See where the sun will be at any hour. Pin the spot. That's the whole app.

## Run it

1. Open `OutAndScout.xcodeproj` in Xcode 16 or later.
2. Pick the **OutAndScout** target, then **Signing & Capabilities**, and choose your team.
3. Plug in an iPhone and press run. The simulator has no camera or compass, so most of the app needs a real phone.

If the project file ever won't open, regenerate it: `brew install xcodegen && xcodegen`.

Fonts: drop `Geist-Regular.ttf`, `Geist-Medium.ttf` and `GeistMono-Regular.ttf` (from vercel.com/font) into a new `OutAndScout/Fonts/` folder. They load at launch. Until then it uses SF Pro and SF Mono.

## What's here

Screen names follow the v2 design canvas.

| Screen | File |
| --- | --- |
| Viewfinder | `Viewfinder/ViewfinderView.swift`, `ViewfinderFrame.swift`, `ViewfinderControls.swift` |
| Caption card, Location permission, Name-this-scene, Custom aspect | `Viewfinder/Cards.swift` |
| Projects panel, Kit panel | `Panels/Panels.swift` |
| Shot List | `ShotList/ShotListView.swift` |
| Export panel (PDF, CSV) | `ShotList/ExportPanel.swift`, `Export/Exporter.swift` |

Under the hood:

- `Camera/CameraController.swift`: AVFoundation on the virtual multi-camera device, so the phone picks the physical lens nearest the cine focal length and only crops the rest. Quality-prioritised stills, low-light boost, preview stabilisation, tap to focus/expose, long-press AE/AF lock, the sun slider for exposure. The readout under the lens wheel says which iPhone lens is live and how much it's cropping, and greys out when the crop gets soft.
- `Model/SunCalculator.swift`: NOAA solar position. Sunrise, sunset, golden and blue hour windows for wherever you're standing.
- `Model/KitCatalog.swift`: cameras, sensor modes and lens sets from the prototype. Sensor widths still need checking against manufacturer data.
- `Model/ScoutStore.swift`: projects, scenes and shots, saved as JSON in the app's Documents folder. Stills go in `Documents/shots/`.
- `Design/Theme.swift`: v2 tokens (paper, ink, graphite, sun, spacing, radius, type scale, buttons, chips).

## Not built yet

- Live link (needs outandscout.com/s/<project> first).
- Camera Control button, ProRAW and Apple Log.
- Sun path ignores roll; fine held roughly level.
- Caption suggestions use Vision's on-device labels only.
- Weather, moon, tides and the other later ideas in the brief.
