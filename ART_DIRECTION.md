# Skyfold art direction: airmail and travel paper

The whole game should feel made by a person with a point of view, not generated. One idea
drives every decision: **you are a sheet of paper travelling the world**, so everything you
see is paper, print and travel ephemera.

## References (concrete, not "vibes")

- Airmail envelopes: the red and blue diagonal border stripes, "PAR AVION" labels.
- Boarding passes and luggage tags: notched edges, perforated tear lines, monospaced codes.
- Passport stamps: ink outlines, slightly rotated, imperfect, overprinted.
- Split-flap departures boards: rows of codes, cities and status words.
- Pop-up books and paper theater: flat cut-card layers at different depths, visible card
  thickness, nothing perfectly regular.
- Screen-printed travel posters: few flat colors, stepped color bands instead of smooth
  gradients, hard-edged offset shadows.

## Color

Use `Palette` (Core/Theme.swift) only. Day is cream card stock, ochre ground, airmail red
(`accent`) and airmail blue (`secondary`). Night is ink blue with sodium-lamp amber accents,
bone-white moon and type. A screen uses two or three colors at once, not six.

## Type

- `Font.display` (system serif): titles, city names, the wordmark.
- `Font.ticket` (monospaced): scores, distances, flight codes, gate letters, times.
- `Font.skyfold` (plain system sans): body text and controls.
- Signage labels in small caps style: uppercase, tracking about +1.5, small size.

## Shape and depth

- Corner radius 0 to 8 pt. Tickets get notches and dashed perforations, not pill bubbles.
- Shadows are hard print offsets (about 3 pt down-right, no blur, ink at 15 to 20%).
- Small deliberate imperfection: a stamp rotated 2 to 6 degrees, a card a degree off,
  layers slightly misaligned. Seeded, so it is the same every time.
- Left-aligned, asymmetric layouts with a clear hierarchy. Avoid a centered stack of
  identical cards.

## The 3D world

A pop-up book diorama: cut-paper clouds in two or three flat layers, origami birds, card
buildings with punched-out windows, a sky in four to six flat bands, a flat sun or moon disc.
Matte materials, faceted folds, crisp shadows. The plane leaves a dashed line behind it, like
a route drawn on a map.

## Copy

Short, plain and specific, in airport and logbook language: "Now arriving", "Gate A",
"Boarding", "Final call", "Flight log", "End flight". Logbook entries read like real notes.

## Do not use

- Neon or purple-to-blue gradients, mint-on-black "cyber" accents, glows, bloom, lens flares.
- Frosted glass (`.ultraThinMaterial` and friends), gradient buttons, glossy materials.
- Sparkle icons, emoji, confetti bursts, "magic" particle effects.
- Big rounded bubbly cards (radius 18+), soft blurry drop shadows, everything centered.
- SF Symbols as decoration. Use them only where an icon carries meaning, at one weight.
- Em dashes, exclamation-heavy hype, and words like journey, embark, unleash, elevate, epic,
  seamless, magical. No "Welcome to X!".
- Smooth icosphere clouds and generic random-noise low-poly.
