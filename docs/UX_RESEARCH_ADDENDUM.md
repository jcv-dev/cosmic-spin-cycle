# UX / game-feel research addendum — owner playtest #2

**Date:** 2026-11-25 · **Scope:** the six problems reported after the first playable M4–M6 build.
This is a working note, not a new bible: `docs/UX_BIBLE.md` remains the design source of truth and
this file records the evidence behind the changes made in response.

The owner's report, verbatim intent:

1. The tutorial tells you *what* but not *why*; copy should be "do X to Y" / "do X to avoid Y",
   clarity over sounding clever.
2. Thrown items sometimes bounce on the green duct.
3. Items ejected from one washer are sucked into the neighbouring "liso" washer.
4. The game is too slow, and there is almost no sound or music — especially when items arrive on
   the belts. "The lack of music is terrible since that is supposed to drive a core mechanic."
5. Pressing Shift near a washer did nothing and the game never explains what it does.
6. Raise the spawn rate again.

---

## 1. Tutorial copy: causal instructions beat evocative labels

**Evidence.** Text-heavy tutorials fail on three measured grounds: cognitive load (working memory
holds very little, so instructions must be short), passive-versus-active learning (players retain
what they *do*, not what they read), and motivation mismatch (players open a game to play, not to
read). Nielsen Norman Group's reading study — cited by GDevelop's onboarding guide — puts reading at
**20–28 % of on-screen words**, and lower in games. The same guide's prescriptions map almost
one-to-one onto the owner's complaint: *contextual teaching* (introduce a mechanic where it is
needed), *immediate application* (let the player use it in a safe situation right away), *feedback
loops* (immediate confirmation of success/failure), and *progressive disclosure* (one mechanic at a
time). Sources: [GDevelop, "Text-based game tutorials don't work"](https://gdevelop.io/blog/improve-game-tutorials);
[NN/g, "How little do users read?"](https://www.nngroup.com/articles/how-little-do-users-read/).

A separate thesis on discreet tutorials found that on-demand help buttons are usually ignored, while
**context-sensitive information delivered at the moment of uncertainty** is what players actually
use (the Half-Life: Alyx pattern). Source: [Designing a discreet tutorial (DiVA)](http://www.diva-portal.se/smash/get/diva2:1576946/FULLTEXT02.pdf).

**What we changed.** Every gate is now a *verb + object + purpose* sentence, in Spanish, on one line:

| Gate | Old copy (label) | New copy (cause) |
|---|---|---|
| 1 | `MUÉVETE` / `WASD` | `Muévete para alcanzar la ropa` |
| 2 | `AGARRA` / `ESPACIO` | `Agarra para poder lavarla` |
| 3 | `LANZA` / `APUNTA` | `Lanza para lavar la ropa` |
| 4 | `ESPERA EL PULSO` | `En el pulso entra seguro` |
| 5 | `TIRA A LA ROJA` | `Tira a la roja: pide ROJO` |
| 6 | `SHIFT AL PULSO` | `Golpea para lavar y calmar` |
| 7 | `TIRA A LA TAPA VERDE` | `Lleva la limpia a la tapa verde` |

Rules adopted: no riddle nouns ("ducto"), no bare control names without a purpose, one instruction
per gate, and the purpose always names the *object it affects* (ropa, lavadora, tapa).

**What we deliberately did not do.** We did not remove text entirely: the rhythm window cannot be
discovered from a laundromat, so it is staged *and* stated (UX_RESEARCH §12.2). We also kept the
gates short rather than explanatory paragraphs — the copy is causal, not a manual.

## 2. "Do X to avoid Y": the missing threat model

The first tutorial taught the positive loop but never named the failure. The build now has two
first-contact lines, each once per shift:

- `LA CINTA TRAE ROPA SUCIA` — where laundry comes from.
- `NO DEJES CAER LA ROPA AL VACÍO` — the shredder threat, shown the first time an item is lost.

The gate copy also names the *avoidance* case where it exists: "Golpea para lavar y calmar" implies
the machine can be in a bad state (turbulence) without using the word "turbulencia" before the
player has seen it.

## 3. Silent music: an engine contract, not a mix problem

**Root cause found in the code and confirmed by the engine docs.** `AudioStreamPlayer.stream` is
documented as: *"Setting this property stops all currently playing sounds."* Our phase setup called
`BeatConductor.start()` (which plays the stem) and then re-assigned the same stream in
`_apply_stem()`/`set_bpm()`, which stopped playback. The game was therefore running with a beat clock
derived from a **stopped** player, so the music was silent from the first frame — exactly the owner's
report in a game whose core mechanic is the music. Source:
[Godot 4 AudioStreamPlayer — `stream` property](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html).

**Fix and rule.** `BeatConductor.set_stream()` now restarts playback when the conductor is playing and
the player stopped. The invariant is covered by an audio check (`AUDIO playing=true`) and by the
existing beat-clock tests. Rule for the project: *never assign `stream` on a live player without an
explicit restart; a silent stem is a correctness bug, not a mix preference.*

**Conveyor audio.** Audio feedback is the cheapest confirmation channel we have, and the review of
auditory interventions in games reports measurable effects on performance and experience, while also
warning about **habituation**: repeated identical SFX get filtered out. Source:
[ACM, A Scoping Review of Auditory Interventions in Games and Gamification](https://dl.acm.org/doi/10.1145/3831300);
counter-example on repetition/limited benefit: [Here Comes No Boom! (CHI 2022)](https://dl.acm.org/doi/fullHtml/10.1145/3491102.3517581).
So the belt now has a quiet looping hum (`belt_hum`, −24 dB) plus a pitched-down short click on each
arrival (−13 dB, pitch 0.55) rather than an identical "ding" every time.

## 4. "Bounce on the green duct" and "sucked into the neighbouring washer": friendly volumes must not be physical

Both are collision/authority bugs, not physics tuning:

- The chute is a **destination**, so a dirty item should be refused with a label, never bounced. The
  rebound impulse (340 px/s) made the hatch read as a wall. The impulse is gone; the label
  `LAVA PRIMERO` remains. General rule: *friendly/refusal volumes never impart forces*.
- Washers accepted **clean** items. An item ejected from the upper machine landed inside the lower
  machine's catch volume and was re-inserted — the "sucked into the liso washer" report. The FSM now
  rejects `clean` items with its own reason (`REJECT_CLEAN`), and the catch volume is centred on the
  cabinet, so a clean item can rest next to a machine without being eaten.

The generous catch volume itself stays: aiming at a 48 px door with a ballistic throw is a Fitts's-law
problem (small target, fast motion) and the player's aim is not the skill we want to test — choosing
the *right machine* is. The assist covers the last centimetres, not the decision.

## 5. Shift/strike: every press must produce a response

**Evidence.** Game-feel literature is consistent: an action must fire a *layered* response (motion,
sound, particles, camera) on the same frame, and a "whiff" still needs feedback or the input feels
broken. The game-feel reference used for the project summarises it as trauma shake, hit-stop, tweens,
squash/stretch and layered audio-visual feedback fired together. Source:
[game-feel skill reference](https://raw.githubusercontent.com/gamedev-skills/awesome-gamedev-agent-skills/main/skills/disciplines/game-feel/SKILL.md).

**Changes.** The strike now draws a cyan arc in front of Pip for 160 ms, plays a whoosh (lower and
louder on a hit, higher and quieter on a whiff), keeps its graded action, and explains itself in the
tutorial as `Golpea para lavar y calmar`. The aim cone and 96 px range are unchanged so the action
stays directional; the difference is that pressing it is never silent or invisible.

## 6. Pacing: raise the rate, but keep it survivable

The first retune (10/8/6 s) was driven by the E2E bot proving the old 3.5/2.4/1.7 s cadence was 1.5×
faster than one player's loop. The owner then reported the opposite failure — too slow. The cadence is
now **7/6/5 s (83 spawns per shift, from 66)**, and the loop itself is faster because a single item
auto-starts its wash, washers catch the whole cabinet, and the chute pulls clean items in. The bot is
the guardrail: a 45 s gate run must still complete at least one delivery, and the 90 s run must keep
stability above zero. If the cadence rises again, the bot is the first thing to re-run.

**Rule of thumb extracted:** the spawn interval must stay above the measured loop time *minus* the
machine buffer. Our loop is ~10–13 s; 7 s works only because three slots wash in parallel and the
chute forgives aim. Below ~5 s the buffer is the only thing keeping the shift alive.

---

## Sources used in this addendum

| # | Source | Used for |
|---|---|---|
| 1 | [GDevelop — text-based tutorials don't work](https://gdevelop.io/blog/improve-game-tutorials) | cognitive load, contextual teaching, immediate application, 20–28 % reading |
| 2 | [NN/g — how little users read](https://www.nngroup.com/articles/how-little-do-users-read/) | reading-rate figure |
| 3 | [DiVA — designing a discreet tutorial](http://www.diva-portal.se/smash/get/diva2:1576946/FULLTEXT02.pdf) | context-sensitive help vs help buttons |
| 4 | [Godot 4 AudioStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html) | `stream` assignment stops playback |
| 5 | [ACM — auditory interventions scoping review](https://dl.acm.org/doi/10.1145/3831300) | audio affects performance; habituation risk |
| 6 | [CHI 2022 — Here Comes No Boom!](https://dl.acm.org/doi/fullHtml/10.1145/3491102.3517581) | counter-evidence on repeated SFX |
| 7 | [game-feel reference](https://raw.githubusercontent.com/gamedev-skills/awesome-gamedev-agent-skills/main/skills/disciplines/game-feel/SKILL.md) | layered feedback for every action |
