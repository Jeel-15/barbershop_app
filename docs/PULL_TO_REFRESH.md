# Pull to refresh: "Pole Pull"

The standard Material refresh circle is the same in every app, web or mobile. This one is Rosenthal's:
a barber pole that you turn with your finger, that spins while the data loads, and that stops with a
gold glint and "Updated 2:41 PM".

Status: built and checked on the owner's phone (see "Build notes").

---

## 1. Research (what was learned)

### Mobbin (how real apps do it)

| App | What it does | Lesson |
|---|---|---|
| [Snapchat](https://mobbin.com/flows/63199c15-1b59-4b81-b009-3d1cc2d2695e) | Pulls a yellow header open; the ghost (the brand character) peeks into the gap | The pulled space is a stage for **one brand object**, not a spinner |
| [Brilliant](https://mobbin.com/screens/44fbf42d-685c-4222-9d5d-326a9bc71bee) | A character on a soft trail that stretches with the finger | The object **follows the finger** and the trail shows tension |
| [Zomato](https://mobbin.com/flows/3757b875-ee32-49fc-899d-cb9b63682c3a) | After refresh: "Refreshed just now!" under the header | A **short confirmation line** closes the loop |
| [Brave](https://mobbin.com/flows/7893a48c-3499-48d7-b80d-b7684203ef34) | "New Content Available" pill | Say **what changed**, in words |
| [Mercury](https://mobbin.com/flows/5d378e9c-546a-43c0-8d8c-f57cc92c09ca) | Plain system spinner | The baseline everyone has; nothing to learn from it |

### Internet

- Keep the **mechanics familiar** (drag, threshold, release); put the creativity in the **visuals**. Apple treats refresh as a pattern to enhance, not reinvent ([vp0 summary](https://vp0.com/blogs/ios-pull-to-refresh-lottie-animation-free)).
- The indicator must **stay until the data is really loaded**, and appear only for a user-started refresh ([UI Patterns](https://ui-patterns.com/patterns/pull-to-refresh)).
- **Restraint**: an over-elaborate indicator annoys people ([Medium](https://medium.com/billeasy-artists/the-unrealised-importance-of-pull-to-refresh-bdf31d54a43)). Visible feedback is what makes people trust a refresh happened.
- A light **haptic when the pull becomes "armed"** is what Mail does ([MacStories](https://www.macstories.net/?p=45044)).
- State machine of a good indicator: idle, dragging, armed, loading, complete, finalizing, canceling ([custom_refresh_indicator](https://pub.dev/packages/custom_refresh_indicator) 4.0.2, MIT, verified publisher). It owns the gesture; we draw.
- Dribbble pull-to-refresh concepts are mostly character-led and **progress-linked** (the drawing is driven by how far you pulled, not by a timer).

### What the app already owns (the brand material)

- `assets/images/pole_strip.png`: one seamless period of the barber pole cut from the real logo (62 x 96 px). Reusing it means the pole looks exactly like the one in the crest.
- Gold gradient tokens (`goldLight`, `gold`, `goldDeep`), the glint star from the crest, `AnimatedCheck`, `AppHaptics`.
- `SnippingScissors` (empty states) stays for "nothing here"; refresh gets the pole.

---

## 2. Concepts considered

| # | Idea | Good | Bad | Verdict |
|---|---|---|---|---|
| A | **Barber pole** turns with the finger, spins while loading, stops with a glint | The most recognisable symbol of the shop (it is in the logo); spinning = "working" is its natural meaning; real texture exists | Needs ~84 px of pulled space | **Chosen** |
| B | Scissors open with the pull, snip at the threshold, snip while loading | Fun | A cut is the opposite of "bring something in"; busy; already used for empty states | Rejected |
| C | The crest assembles from a blur as you pull | Beautiful | Too detailed at 60 px; heavy | Rejected |
| D | Razor strop / comb | Charming | Not recognisable at a glance | Rejected |
| E | Pole + scissors together | Rich | Two ideas, busier, longer | Rejected (restraint) |

---

## 3. Specification

### Mechanics (unchanged from what people know)

Pull from the top, a point of resistance, release to refresh. Armed at **84 px** of pull; a rubber band up to ~126 px.
The content moves down with the finger, the indicator sits in the opened gap, glued to the content's top edge.

### Look

```
        ( dome )          <- gold brass cap, glass pole between caps
        | //// |
        | //// |          <- the real stripes, cylinder-shaded (dark edges, light centre)
        | //// |
        ( base )
   Release to refresh     <- state text (12.5 px, secondary colour)
```

Pole 18 x 52 px (caps included), label 12.5 px, both centred; whole thing is 75 px in an 84 px slot.

### States (what moves, when)

| State | Pole | Text | Extra |
|---|---|---|---|
| **dragging** (0 to 1) | fades and scales in (0.82 to 1.0) over the first 35%; **stripes turn with the finger** (1 period per 56 px pulled, both ways) | "Pull to refresh" fades in after 40% | shows "Updated ..." under it when there was a previous refresh |
| **armed** (>= 1) | one small pop (1.0 -> 1.1 -> 1.0, spring), a gold ring pulses out once; stretches a little as you pull on (up to +15% tall, -8% wide) | "Release to refresh" | light haptic, once |
| **canceling** | slides back with the content, stripes ease to a stop | fades out | |
| **settling / loading** | spins up with inertia to 1.4 periods per second (downward, like the real pole) | "Refreshing..." | at least 450 ms so the motion is read, even if the data is instant |
| **complete** | slows down with inertia, glint on the top cap, soft glow | check + "Updated 2:41 PM" (shop time) | held 900 ms, success haptic (light) |
| **failed** | slows to a stop, dims | error icon + "Couldn't refresh" (danger colour) | held 1200 ms, warning haptic |
| **finalizing** | slides up with the content (260 ms) | | |

Timings follow the app's motion rules (docs/MOTION.md): decelerate in, 200-300 ms for what the user waits on.

### Interaction details that make it feel "alive"

1. **Progress-linked**: nothing in the pull phase runs on a timer; every value is a function of how far the finger is. Pull back and it un-turns.
2. **Inertia**: the spin is integrated from a speed that chases a target speed (0 / follows finger / 1.4 per s), so it winds up and winds down like a real object instead of starting and stopping abruptly.
3. **Tension**: past the threshold the pole stretches slightly and the glow grows, so the "armed" point is felt, not only read.
4. **Closure**: the result is said in words with the time, like Zomato's "Refreshed just now".

### Accessibility and robustness

- "Remove animations": no spin, no pop, no ring; the pole is still, the words still change.
- The state text is a live region (TalkBack reads "Refreshing", "Updated 2:41 PM").
- Failure never throws into the zone: the indicator shows "Couldn't refresh" and the page keeps its old data.
- Works with any scroll view that can overscroll; same predicate as the Material indicator (depth 0).
- One widget, `AppRefresh`, replaces all 14 `RefreshIndicator`s.

---

## 4. Review (second pass, before building)

| Risk found when re-reading the plan | Decision |
|---|---|
| "Interactive" could turn into "busy" | One object, one gold accent, no particles. The ring and glint each play once. |
| A pole is tall; the pull may feel long on dense admin lists | The gap is 92 px (the first plan said 84, see below); the pole is 54 px. One constant (kPoleSlot) if it feels long. |
| Hand-coded animation can look cheap | Real logo texture for the stripes; cylinder shading and brass caps drawn from the crest's own gradients; every state is **rendered to a PNG and reviewed** (light and dark) before it ships. |
| Instant refresh (cached data) would flash | Minimum "Refreshing" time 450 ms. |
| Nothing says whether it worked | complete / failed lines with the time. |
| Another dependency | `custom_refresh_indicator` (MIT, 4.0.2): only the gesture state machine, ~600 lines we do not want to re-invent (and re-test across scroll edge cases). Drawing, motion and feel are ours. |
| Ticker running forever | Only while loading or settling; stopped in idle. Wrapped in a `RepaintBoundary`. |
| Tests | State machine with real drags; every visual state as a golden-style PNG preview; reduce-motion; failure path. |

## 5. Build notes

Code: `lib/design_system/brand/barber_pole.dart` (the object: real stripe texture, cylinder shading, brass caps, glint) and
`lib/design_system/motion/pole_refresh.dart` (`PoleRefreshFace` = the picture of one moment, `AppRefresh` = gesture, states and spin physics).
All 14 screens that had a `RefreshIndicator` now use `AppRefresh`. Preview of every state: `tool/preview/pole_preview_test.dart`.

What reviewing the pictures and running it changed:

- The stripe image has a dark ground cut from the logo: it looked washed out on the cream screen until a dark base was put under the glass.
- The first pole (46 px) overflowed once the second line ("Updated ...") was added: gap 84 -> 92 px, pole 19 x 54 px.
- The glint is white with a gold edge, so it reads on both themes.
- In the package, `IndicatorStateChange.currentState` is the state it *left*; the new one is `newState` (a test caught it).
- At rest the indicator builds nothing (its slot stays, so the page does not lose its scroll position).
- A test that tapped "the first Image" now taps a picture, because the pole is an Image too.

Checked on the phone (release build): pulling, "Release to refresh" with the stretched, glowing pole, "Refreshing", retract.
Frame times over 6 pulls: build max 9.3 ms, raster max 9.3 ms, **0 slow frames** (budget 16.7 ms).
