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
- `raised-leg-crunch.txt` — *Crunches* (`dist/svg/0291-*.svg`) with the bench
  masked out, so the legs stay raised at 90 degrees without support. The figure
  itself is untouched. Frame 1 is the crunched pose; frames 2 and 3 are the
  starting pose.

`plank-hold.txt` reuses frames 1 and 2 of Workout Guide's `plank` (frame 1
again as frame 3), so a held plank never drops to the knees.

`dead-bug.txt` keeps its Workout Guide name, but its frames are new, because
the original three frames showed three different figures. The two poses were
drawn with ChatGPT's image generation (OpenAI) on 2026-10-22. The style
reference was three of the app's Everkinetic-based frames (`raised-leg-crunch`
frame 2, `glute-bridge` frame 1 and `lateral-raise` frame 1), plus a
stick-figure pose guide. The poses were aligned on a shared canvas (scale and
shift only), their lines adjusted to the weight of the other frames, and traced
through the same sharp, potrace and svgo pipeline. Frame 1 is the extended
pose; frames 2 and 3 are the starting pose. Because its style reference is
Everkinetic artwork, it is shared under the same CC BY-SA 4.0 license.

`reverse-pec-deck.txt` keeps its Workout Guide name, but its frames are new,
because the original frames showed a chest fly seen from the front, with a
different machine in each frame. The two poses were drawn with ChatGPT's image
generation (OpenAI) on 2026-10-22. The style reference was frame 1 of three of
the app's illustrations — `wide-grip-lat-pulldown` (a Workout Guide original),
`machine-chest-press` and `lateral-raise` (both Everkinetic-based) — plus a
pose guide made from a simple 3D model of the man and the machine. The poses
were aligned on a shared canvas (scale and shift only), their lines adjusted
to the weight of the other frames, and traced through the same sharp, potrace
and svgo pipeline. Frame 1 is the pose with the arms out to the sides; frames 2
and 3 are the starting pose, with the arms forward. Because its style
reference is CC BY-SA 4.0 artwork, it is shared under the same license.

`floor-crunch.txt` is new: *Crunch Floor* keeps the feet on the floor, so it no
longer shares `crunch.txt` (calves on a bench) with the sit-ups that still use
it. The two poses were drawn with ChatGPT's image generation (OpenAI) on
2026-10-23. The poses were aligned on a shared canvas (scale and shift only),
their lines adjusted to the weight of the other frames, and traced through the
same sharp, potrace and svgo pipeline. Frame 1 is the crunched pose; frames 2
and 3 are the starting pose. It is shared under the same CC BY-SA 4.0 license
as the other illustrations.

`banded-dead-bug.txt` keeps its Workout Guide name, but its frames are new,
because the original frames mixed two figures in two styles, ran the band to
the feet instead of to an anchor behind the head, and bent one knee the wrong
way. The figure's two poses were drawn with ChatGPT's image generation (OpenAI)
on 2026-10-23. The sheet was also edited programmatically, with a tool that is
not recorded: its background was whitened, and the anchor post and the band
were drawn as plain shapes, identical in both poses. The poses were aligned on
a shared canvas (scale and shift only), their lines adjusted to the weight of
the other frames, and traced through the same sharp, potrace and svgo pipeline.
Frame 1 is the pose with one leg lowered; frames 2 and 3 are the starting pose.
It is shared under the same CC BY-SA 4.0 license as the other illustrations.

`flat-converging-chest-press.txt` is new, so `machine-chest-press.txt` stays
with the other chest presses that share it. The two poses were drawn with
ChatGPT's image generation (OpenAI) on 2026-10-23. The poses were aligned on a
shared canvas (scale and shift only), their lines adjusted to the weight of the
other frames, and traced through the same sharp, potrace and svgo pipeline.
Frame 1 is the pressed pose; frames 2 and 3 are the starting pose. It is shared
under the same CC BY-SA 4.0 license as the other illustrations.

`incline-chest-press.txt` keeps its name, but its frames are new; the old ones
came from Everkinetic's *Incline Chest Press* (`src/images-ai/0084-*.ai.png`).
The two poses were drawn with ChatGPT's image generation (OpenAI) on
2026-10-23. The poses were aligned on a shared canvas (scale and shift only),
their lines adjusted to the weight of the other frames, and traced through the
same sharp, potrace and svgo pipeline. Frame 1 is the pressed pose; frames 2
and 3 are the starting pose. It is shared under the same CC BY-SA 4.0 license
as the other illustrations.

`pendulum-hack-squat.txt` is new: the gym's hack squat is a pendulum machine,
with the shoulder pads on an arm that swings around a fixed pivot, so it no
longer shares `hack-squat.txt` (a 45-degree sled) with the hack squats that
still use it. The two poses were drawn with Google's generative AI in Google
Flow on 2026-10-24, from earlier versions, the first of them drawn with
ChatGPT's image generation (OpenAI) on 2026-10-23. The poses were aligned on a
shared canvas (scale and shift only), their lines adjusted to the weight of the
other frames, and traced through the same sharp, potrace and svgo pipeline.
Frame 1 is the bottom of the squat; frames 2 and 3 are the standing start. It
is shared under the same CC BY-SA 4.0 license as the other illustrations.

`high-pulley-overhead-tricep-extension.txt` is new: it shows the exercise as its
steps describe it, facing away from a high pulley with a rope, so *Cable
Overhead Triceps Extension (Rope Attachment)* no longer shares
`overhead-tricep-extension.txt` with the overhead extensions that still use it.
The two poses were drawn with Google's generative AI in Google Flow on
2026-10-30, from earlier versions, the first of them drawn with ChatGPT's image
generation (OpenAI) on 2026-10-29. The sheet was then edited programmatically:
in the bent-elbow pose, the two guide rods under the raised weight stack, which
the generator had erased, were redrawn in plain black from the rods of the
other pose. The poses were aligned on a shared canvas with the machine fixed
(same scale, shift only), their lines adjusted to the weight of the other
frames, and traced through the same sharp, potrace and svgo pipeline. Frame 1
is the pose with the elbows bent; frames 2 and 3 are the pose with the arms
extended. It is shared under the same CC BY-SA 4.0 license as the other
illustrations.

## Fonts

Nunito, by the Nunito Project Authors, under the SIL Open Font License
(`assets/fonts/Nunito-OFL.txt`).
