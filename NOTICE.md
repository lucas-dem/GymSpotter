# Infyter — legal notices

Infyter is a modified version of GymMane.

- Original project: GymMane, copyright © 2026 InlitX.
- Infyter modifications began on 22 September 2026.
- The application source code is distributed under the GNU General Public
  License, version 3. A complete copy is in `LICENSE`.
- Recipients of a binary must receive access, at no additional charge, to the
  complete corresponding source used to build that exact binary.

The exercise illustrations in `assets/art/` are adapted from Workout Guide by
Bryl Lim and pose artwork from Everkinetic. They remain licensed under
Creative Commons Attribution-ShareAlike 4.0. See `CREDITS.md` for attribution
and modification details.

The Nunito fonts are copyright the Nunito Project Authors and are distributed
under the SIL Open Font License 1.1. The license is included at
`assets/fonts/Nunito-OFL.txt`.

The progress Excel export uses the `excel_community` 1.0.10 package (MIT License,
copyright (C) 2021 Kawaljeet Singh (justkawal) and copyright (C) 2026
DecksPlayer, excel_community fork), which is pure Dart.

The progress PDF export uses the `pdf` 3.12.0 package (Apache License 2.0,
copyright (C) 2017 David PHAM-VAN) and its `barcode` 2.2.9 dependency (Apache
License 2.0, copyright (C) 2020 David PHAM-VAN) and `bidi` 2.0.13 dependency
(MIT License, copyright (C) 2020 Mahdi K. Fard). All three are pure Dart. The
PDF is drawn with the bundled Nunito fonts; only the progress PDF, and only in
the languages that need them, also embeds these fonts, whose licenses are in
`assets/fonts/`:

- Infyter PDF Arabic (Arabic): Nunito and Noto Sans Arabic (copyright 2015-2021
  Google LLC) merged into one file, under the SIL Open Font License 1.1
  (`InfyterPdfArabic-OFL.txt`).
- Droid Sans Fallback (Japanese, Simplified and Traditional Chinese), digitized
  data copyright Google Corporation 2006, under the Apache License 2.0
  (`DroidSansFallbackFull-LICENSE.txt`).
- Nanum Gothic (Korean), copyright 2011 NHN Corporation, under the SIL Open
  Font License 1.1 (`NanumGothic-OFL.txt`).

Flutter and third-party packages retain their respective licenses. Their
notices are available inside the application under “Información legal y
licencias” → “Licencias de dependencias”.

The Android build also includes Google's Play In-App Updates library
(`com.google.android.play:app-update` 2.1.0, with `core-common` and the Play
services `basement` and `tasks` libraries). It is used only to ask the Google
Play Store app whether an update is available. Google distributes these
libraries under its own terms (Play Core Software Development Kit Terms of
Service and Android Software Development Kit License); they are not free
software.

Infyter is provided without warranty, to the extent permitted by law.
