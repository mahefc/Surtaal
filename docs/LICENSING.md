# Sound licensing & provenance

## Synthesised sounds
Most instruments are generated at runtime by `scripts/audio/synth_baker.gd` (original code; parameters in
`data/instruments/*.json`). Nothing is derived from commercial libraries. Instrument names describe the *target character*
of an original synthesis patch.

## Recorded world / keys / winds (categories "World", "Keys", "Western", "Chinese")
Real recordings from the **Versilian Community Sample Library (VCSL)** by Versilian Studios, released under **CC0 1.0 Universal**:
https://github.com/sgossner/VCSL . Used: Ocarina, Harmonica, Pipe Organ, Recorder, Tenor Saxophone, Dan Tranh zither, Harpsichord,
Folk Harp, FM Electric Piano, Clavisynth, Kalimba, Balafon, Vibraphone, and one-shot Darbuka, Frame Drum, Cajon, Bongos, Agogo,
Woodblock, Tambourine, Finger Cymbals (see `data/instruments/world.json`). `tools/fetch_vcsl.ps1` re-downloads exactly this subset.

## Indian percussion (category "Indian")
Real tabla strokes (Na, Na open, Tun, Te, Ghe, Ke) recorded by **dio-333** on Freesound, released under **CC0 1.0**, as packaged in
https://github.com/tmhglnd/mercury (see `data/instruments/indian_real.json`). `tools/fetch_tabla.ps1` re-downloads them.

## Not used: Sonic Atlas (Pitch Innovations)
Commercial plug-in. Its licence allows use in your own music but forbids repacking its sounds into other apps or libraries, so none of
its samples may be bundled here.

## Recorded instruments (category "Orchestra")
Real recordings from **VSCO 2 Community Edition** by Sam Gossner, released under **CC0 1.0 Universal** (public-domain dedication):
https://github.com/sgossner/VSCO-2-CE  (licence: https://creativecommons.org/publicdomain/zero/1.0/).
CC0 requires no attribution; the credit is given here anyway.

Used: the full set of recorded pitches for each instrument, with every velocity layer (soft and loud; the upright piano's mf and f):
- Strings: Violin Section, Viola Section, Cello Section, Solo Violin, Solo Double Bass, Concert Harp
- Brass: French Horn, Trumpet, Tenor Trombone, Tuba
- Woodwinds: Flute, Oboe, Clarinet, Bassoon
- Keys and tuned percussion: Acoustic Piano (upright), Marimba, Glockenspiel, Xylophone
- Percussion: Bass Drum, Orchestral Snare, Gong, Crash Cymbal, Conga

`tools/fetch_samples.ps1` downloads this set into `assets/samples/<id>/` and writes `data/instruments/sampled.json`.

## Recorded grand piano (category "Keys", Salamander Grand Piano)
**Salamander Grand Piano** V3 by Alexander Holm, released under **CC-BY 3.0**. Attribution is required, and it is given in the
instrument description and in `data/instruments/sampled.json`. Source: https://github.com/sfzinstruments/SalamanderGrandPiano
Four of its sixteen velocity layers are used (v2, v6, v10, v14), trimmed to 6 s, and stored as 16-bit WAV in
`assets/samples/salamander_grand/`. `tools/fetch_salamander.py` downloads, converts and merges it into `sampled.json`.

## Sources checked and not used
- **LANDR Samples** (samples.landr.com): free packs are licensed for use inside your own recordings only, with no redistribution or
  bundling in an app. Not used.
- **Sonatina Symphonic Orchestra**: CC Sampling Plus 1.0 (no redistribution, retired licence). Not used.
- **Philharmonia Orchestra**, **Spitfire LABS**: their terms forbid making their samples into a sampler instrument or another library. Not used.
- Paid libraries: not used.

NOT covered by this pack: Indian instruments (sitar, bansuri, tabla, mridangam, shehnai, nadaswaram ...), Chinese instruments and choir.
Those remain synthesised until properly licensed or self-recorded material is added (record each in `docs/SAMPLE_LICENSES.csv`:
`file, source, author, license, date, proof-of-rights`).
