# Credits and third-party notices

Infyter is a modified version of GymMane, originally created by InlitX and
distributed under GNU GPL v3. Infyter preserves that license and records its
material changes in `MODIFICATIONS.md`.

## Exercise illustrations

The exercise art in `assets/art/` comes from
[Workout Guide](https://github.com/bryllim/workout-guide) by
[Bryl Lim](https://bryllim.com), which builds on pose artwork from
[Everkinetic](https://github.com/everkinetic/data).

Both are licensed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), and Infyter's
copy stays under that same license — the rest of the app is GPLv3.

**Changes made.** Each Workout Guide frame is a 512 × 512 SVG holding a single
`<path>`. That path data was lifted into one plain-text file per exercise —
three lines, one per frame — so the app draws it with `path_drawing` and tints
it with the current theme instead of shipping a fixed-colour image. The
geometry is untouched.

Every exercise in the catalogue names the illustration it uses in its `art:`
field, and the files under `assets/art/` are named after the Workout Guide
exercise they come from, so any frame can be traced back to its original.
Several exercises share one illustration when they are the same movement done
with different equipment.

**Exceptions.** A few illustrations have no Workout Guide counterpart, so they
come straight from [everkinetic/data](https://github.com/everkinetic/data) and
went through Workout Guide's own pipeline (sharp, potrace and svgo, same
settings), exactly as its Everkinetic-based frames did:

- `flat-bench-press.txt` — *Wide-Grip Bench Press* (`dist/svg/0082-*.svg`).
  Frame 1 is the pressed pose; frames 2 and 3 are the starting pose.
- `barbell-curl.txt` — *Biceps Curls With Barbell* (`dist/svg/0211-*.svg`).
  Frame 1 is the curled pose; frames 2 and 3 are the starting pose.
- `alternating-bicep-curl.txt` — *Alternating Biceps Curl With Dumbbell*
  (`dist/svg/0223-*.svg`). The frames swap between its two poses.
- `incline-chest-press.txt` — *Incline Chest Press*, which only exists as
  `src/images-ai/0084-F.ai.png` and `0084-S.ai.png`. The two poses were aligned
  on a shared canvas and their lines thickened slightly to match the other
  frames. Frame 1 is the pressed pose; frames 2 and 3 are the starting pose.

`plank-hold.txt` reuses frames 1 and 2 of Workout Guide's `plank` (frame 1
again as frame 3), so a held plank never drops to the knees.

## Fonts

Nunito, by the Nunito Project Authors, under the SIL Open Font License
(`assets/fonts/Nunito-OFL.txt`).
