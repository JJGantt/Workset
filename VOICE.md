# Spoken rep numbers

The watch speaks the rep number on each counted rep. This is what ships, what was tried,
and what would improve it.

## What ships

Numbers 1 to 50 rendered ahead of time with **Kokoro** (voice `af_sarah`, 24 kHz mono) at
`Workset Watch App/Numbers/n<N>.wav`.

Cadence: rep 4 is the lock-on chime (`Sounds/locked.wav`), reps 5 and up are spoken, and a
`.click` haptic fires on every rep including the spoken ones. Past 50 it falls back to the
tick: a tap meaning "one more" rather than a wrong number.

Three processing details any regeneration must keep:

- **Trimmed to the speech.** Leading silence inside a file reads as latency on every rep,
  a fixed delay that cannot be diagnosed from outside the audio.
- **Normalised** to 0.85 peak, so no number is louder than another.
- **6 ms fades** at both ends, or the onset clicks.

Words last 0.5 to 0.9 s, comfortably inside a rep period (2.5 to 3.5 s), so numbers never
overlap even at 47.

Pre-rendered rather than `AVSpeechSynthesizer` on purpose: live synthesis has unpredictable
first-utterance latency, and this sound has to land on a beat the lifter can feel. Files
decode in microseconds. They are loaded on demand and cached, since a set revisits the same
few numbers and loading fifty at launch would cost startup for words most sets never reach.

## Tried and rejected

**macOS `say`.** The legacy voices are not good enough for something heard dozens of times
per workout.

**Wikimedia Commons recordings.** Real native speakers, but recorded per word by different
contributors, so the voice would change between numbers mid-set. There is no single-speaker
1 to 50 set.

**Other Kokoro voices.** `af_heart`, `af_bella`, `af_nicole`, `af_sky`, `am_adam`,
`am_michael`, `bf_emma` and `bm_george` were auditioned; `af_sarah` was chosen, with some
words still weak.

**Carrier-phrase extraction, unfinished.** Isolated single words are the hardest case for
TTS: with no sentence around them the model guesses the intonation. Rendering "That makes
it six." and keeping only the final word should sound better, but Kokoro emits connected
speech with no gaps between words, so silence-based splitting cannot find the boundary and
returns roughly double the correct duration (1.0 to 1.24 s against 0.46 to 0.77 s for the
bare word).

## What would improve it

1. **A larger TTS model.** A hosted model such as `gpt-4o-mini-tts` is far larger than
   Kokoro's 82M parameters and would very likely beat everything above. Fifty short words
   cost cents.
2. **Forced alignment for carrier extraction.** Whisper with word-level timestamps can say
   where the final word starts and ends, so the carrier sentence can be cut there. Only worth
   doing if in-sentence rendering actually sounds better than the bare word, which has not
   been settled.
3. **Several takes per word within `af_sarah`** (speed 0.9, 1.0, 1.1; with and without
   punctuation; bare and in a carrier), keeping the best take per word. Takes of the same
   speaker only: mixing voices per word reintroduces the Commons problem.
