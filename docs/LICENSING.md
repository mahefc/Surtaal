# Sound licensing & provenance

## Orchestra / keys (VSCO 2 CE)
Bundled melodic and orchestral percussion recordings from **VSCO 2 Community Edition** by Sam Gossner, **CC0 1.0**:
https://github.com/sgossner/VSCO-2-CE

- Strings: Violin Section, Viola Section, Cello Section, Solo Violin, Solo Double Bass, Concert Harp
- Brass: French Horn, Trumpet, Tenor Trombone, Tuba
- Woodwinds: Flute, Oboe, Clarinet, Bassoon
- Keys / tuned perc: Acoustic Piano (upright), Marimba, Glockenspiel, Xylophone
- Orchestral perc: Bass Drum, Orchestral Snare, Gong, Crash Cymbal, Conga

Catalogue: `data/instruments/sampled.json`. Fetch: `tools/fetch_samples.ps1`.

## Drum loop kit (Virtuosity Drums)
Studio drum kit for the loop builder from **Virtuosity Drums** by Versilian Studios / Karoryfer Samples, **CC0 1.0**:
https://github.com/sfzinstruments/virtuosity_drums

Used (mid mic; kick uses kickmic), velocity-layered one-shots: Kick, Snare, Hi-hat, Open Hi-hat, High Tom, Floor Tom, Rimshot, Ride, Crash.

Catalogue: `data/instruments/drums.json`. Samples: `assets/samples/{kick,snare,hat,...}/`. Rebuild: `python tools/fetch_drums.py`.

## Not used (cannot bundle)
- **LANDR Samples**: licence allows use only inside your own recordings — not redistribution or bundling in an app / sample library.
- **YouTube / copyrighted song rips**: not cleared for redistribution.
- **Sonatina**, **Philharmonia**, **Spitfire LABS**, **Sonic Atlas**, paid libraries: terms forbid bundling or are unsuitable.
