# Glow Studio

An **original** photo retouch and color-grading app for iPhone, built with Flutter.
It is not a copy of any existing product — all code, UI and image processing here
are written from scratch.

## What it does (v1)

- Import a photo from the gallery or take one with the camera.
- **Light**: brightness, contrast, saturation, warmth — live, on-GPU preview.
- **Skin**: edge-aware skin smoothing that softens skin while keeping eyes,
  brows and lips sharp. Full quality is baked into the exported photo.
- **Filters**: a set of color-grade presets (Radiant, Warm Gold, Cool, Mono,
  Noir, Fade, Vivid), each previewed live.
- Press and hold the preview to compare against the original.
- Save the full-resolution result to your gallery.

The editing preview runs on a downscaled copy for smooth sliders; the **Save**
step re-renders the pipeline at full resolution on a background isolate.

## Roadmap (v2)

These need on-device face landmarks (Google ML Kit / Apple Vision) and are the
next milestone:

- Face reshape (subtle slim / eye enlarge / jaw) via a landmark mesh warp.
- Makeup overlays (lips, blush, brows) positioned from landmarks.
- Teeth whitening and eye brightening (localized).
- Background blur / replace via selfie segmentation.

> Note on "AI transformations" (age, smile, gender swap): those rely on trained
> neural networks. Glow Studio will use its own / openly-licensed models, so the
> *categories* of features can match a commercial editor, but the exact output
> quality of any specific proprietary app cannot be reproduced.

---

## Build the iOS app (no Mac needed) — GitHub Actions

A `.ipa` for iPhone can only be compiled on macOS. This repo ships a workflow
that builds an **unsigned** `.ipa` on a free GitHub-hosted macOS runner; AltStore
then re-signs it with your own Apple ID when you sideload.

1. Create a new repository on GitHub (e.g. `glow-studio`).
2. Push this project to it (see commands below).
3. On GitHub, open the **Actions** tab. The **Build iOS (unsigned IPA)** workflow
   runs on every push to `main`; you can also run it manually with **Run workflow**.
4. When it finishes (green check), open the run and download the
   **GlowStudio-unsigned-ipa** artifact. Unzip it to get `GlowStudio.ipa`.

### Push this project to GitHub

From this project folder:

```bash
git init
git add .
git commit -m "Glow Studio v1"
git branch -M main
git remote add origin https://github.com/<your-username>/glow-studio.git
git push -u origin main
```

(Replace `<your-username>` and the repo name. `git init`/`add`/`commit` are
already done locally if you received this project with history.)

---

## Put it on your iPhone with AltServer / AltStore

1. Install **AltServer** on this PC from the official site (`altstore.io`).
   On Windows you also need Apple's **iTunes** and **iCloud** (the versions from
   Apple's website, not the Microsoft Store) for the USB drivers.
2. Connect your iPhone by USB and trust the computer.
3. From the AltServer tray icon: **Install AltStore** → pick your device → sign in
   with your Apple ID. AltStore appears on the phone.
4. On the iPhone: **Settings → General → VPN & Device Management** → trust your
   Apple ID developer profile.
5. Get `GlowStudio.ipa` onto the phone (AirDrop, iCloud Drive, or the Files app).
6. Open **AltStore → My Apps → “+”** → choose `GlowStudio.ipa`. It installs.

**Free Apple ID limits:** sideloaded apps expire after **7 days** and must be
refreshed in AltStore (AltServer running, same Wi-Fi), and you can have at most
**3** sideloaded apps at once. A paid Apple Developer account removes these limits.

---

## Run locally (optional, for development)

With the Flutter SDK installed:

```bash
flutter pub get
flutter run            # on a connected Android device/emulator or desktop
flutter analyze
flutter test
```

iOS `flutter run` still requires a Mac with Xcode.

## Project layout

```
lib/
  main.dart                 app entry + theme
  screens/
    home_screen.dart        import / camera
    editor_screen.dart      preview + Light / Skin / Filters tabs + Save
  edit/
    adjustments.dart        color-matrix math + filter presets
    image_ops.dart          isolate image processing (smoothing + export bake)
  widgets/
    adjust_slider.dart
    filter_strip.dart
.github/workflows/ios.yml    builds the unsigned .ipa on macOS
```
