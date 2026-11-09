# Glow Studio

An **original** photo retouch and color-grading app for iPhone, built with Flutter.
It is not a copy of any existing product — all code, UI and image processing here
are written from scratch.

## What it does

Import a photo from the gallery or camera, edit across six tabs, press and hold
the preview to compare with the original, and save the full-resolution result to
your gallery.

- **Light**: brightness, contrast, saturation, warmth — live, on-GPU preview.
- **Skin**: edge-aware smoothing that softens skin while keeping eyes, brows and
  lips sharp.
- **Makeup** (face landmarks): lipstick with a color palette + intensity, blush,
  teeth whitening, eye brightening.
- **Shape** (face landmarks): subtle face slimming and eye enlarging via an
  inverse-mapped liquify warp.
- **Glow** (face landmarks): warm radiance on the cheekbones, under-eye
  brightening, and a lower-lip gloss.
- **Filters**: color-grade presets (Radiant, Warm Gold, Cool, Mono, Noir, Fade,
  Vivid), each previewed live.

Everything is **face-only** — nothing touches the background. Skin, makeup, glow
and reshape run through one isolate pipeline, so the preview matches the saved
photo; the preview uses a downscaled copy for smooth sliders while **Save**
re-renders at full resolution. On-device face detection (Google ML Kit) runs the
first time you open a landmark tab.

## Roadmap

Possible next face-only additions:

- Blemish / spot remover (tap to heal).
- More makeup: eyebrows, eyeshadow, eyeliner.
- Nose slimming and lip reshape.
- One-tap "looks" that combine several effects.

> Note on "AI transformations" (age, smile, gender swap): those rely on trained
> neural networks. Glow Studio would use its own / openly-licensed models, so the
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
