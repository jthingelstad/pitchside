# Kubb: Pitchside, agent guide

Framing written 2026-11-24, before any code. Every claim about a sibling repo below was
read from that repo at engine `v1.0.0` and Notation 2 edition `v2-2026.11`, and cites the
file. Where this guide infers rather than reads, it says so with **(inferred)**.

## 1. What Pitchside is

Kubb: Pitchside is an iPhone app for scoring **real** games of kubb, played on grass. A
scorer stands at the edge of the pitch and records the game throw by throw as it happens.
The record is a Planet Kubb Notation file. Kubb: Throwing Wood is the game; Pitchside
records the real thing. Both run on the same Kubb Engine.

The core idea: **the pitch is the input surface, not a form.** The engine already knows
what is standing, whose turn it is and how many batons are left, so most events should
take one tap on a drawn pitch. Tapping the kubb that fell records the result and, for
free, where that kubb stood.

Its place among the sibling repos (all beside this folder in `~/Projects/throwingwood/`):

- `kubb-engine`: the rules, physics, notation writer, session and pitch in pure Lua 5.4.
  Pitchside carries a tagged release of it and never edits it.
- `throwingwood-ios`: the Throwing Wood iPhone app. Pitchside copies how it carries the
  engine (Lua 5.4.5 with musl's maths, a pinned tag, a sha256 check) and its 1.0 design
  system.
- `kubb.thingelstad.xyz`: the web game at throwingwood.com, the reference for Throwing
  Wood's look, words and online play.
- `playdate-kubb`: the Playdate game the engine's core came from. Its `docs/PLAYERS.md` is
  the design behind saved players, teams of up to six and the throwing order.
- `pk-kubb-score`: Planet Kubb Notation (the spec, the grammar, the reader `kubb.js`, 150
  archived real games). It owns the notation. Anything Pitchside needs the file to say
  goes there first.

## 2. Users and context

**The scorer** is often a player sitting out a turn, a teammate, or a tournament
volunteer. They stand at the side of the pitch or behind a baseline, outdoors, in sun,
often with one hand free (the other holds batons, a drink or a clipboard). A pro turn is
fast: six batons, several kubbs falling to one baton, a drilled inkast of five or more
kubbs landing in a tight group. The scorer has to keep up without looking down for long,
and must never be stopped by the app in the middle of a turn.

**Beginners scoring a backyard game** are the second audience. They may not know the
notation, the advantage line, or what a punishment kubb is. The app has to teach by what
it shows (the engine says what can happen next) rather than by a help page. This follows
a rule already set for Throwing Wood: "Have the UI show it not a separate how to page"
(throwingwood-ios `AGENTS.md`, "The meter"). Being easy for a beginner matters as much as
keeping up with a pro.

## 3. Principles

- **Pitch as input.** The drawn pitch is where results are entered. A kubb is tapped where
  it is. Lists, forms and keyboards are for setup only.
- **Speed over completeness.** A turn can always be finished with the fewest taps the
  rules allow. Detail is something the scorer adds when there is time, never something the
  app waits for.
- **Detail is optional.** Each game has a set of things to record (section 7), each a row
  the scorer turns on or off, between turns too. A row adds taps and never changes the
  meaning of the others' data.
- **Never lose data.** The game is an append-only event log, saved after every event.
  State and notation are always rebuilt from the log. Undo and edits are new events, never
  changes to the state. (A 2013 Android scoring app for Planet Kubb broke this way: its
  undo changed the state directly. That history is from the brief; nothing about it is in
  these repos.)
- **Open format.** The export is a Planet Kubb Notation file anyone can read. The app's
  own files are plain and documented.
- **Same family as Throwing Wood.** It looks like the game and uses the same engine, but it
  is a tool, not a game (section 9).

## 4. Domain model

Terms come from the engine where it has them. Paths are kubb-engine's unless named.

**Match.** One game of kubb from the first toss to a winner. The engine's `core/match`
wraps a rules game, `tw.rules.new{ teams, surface, opening, first, rules, ... }`
(`core/rules.lua`; `docs/notes/rules-engine.md` "Rules engine"). The engine has no idea of
a set or series of games (best of three, a pool) **(inferred** from the absence of any
such structure in `core/` and `session/`). Pitchside adds a match's own fields: its
capture rows, its event log, its photos, its event name and place.

**Rules.** The engine plays U.S. National Kubb Championship Rules V4.0 (`core/rules.lua`
line 1), written into the file as `[Rules "U.S. Championship 4.0, 2-4-6"]` or `"..., six
from the start"` (`core/notation.lua`). The opening is `"2-4-6"` or `"six"`
(`rules.batonsFor`: 2 batons in turn 1, 4 in turn 2, then 6). It also has Kid rules
(`rules = "kid"`: three base kubbs a side, a throwing line 2 m in, no early-king loss;
`docs/notes/kid-mode.md`). What the brief calls "US Nationals" is this V4.0 rule set.

**Team and side.** Two sides, `A` and `B`. Team A's baseline is the engine's y = 0 and
Team B's y = 8. `First` says which side throws first. A team has 1 to 6 players in
throwing order (`docs/notes/rules-engine.md` "Throwing order"; Rules V4.0 sets no maximum,
six is the engine's cap, playdate-kubb `docs/PLAYERS.md` section 1).

**Player.** A person on a team. The Playdate's saved player is `{ key, name, id, made,
last, ... }`, where `key` is permanent and never reused and `id` is the game file id
(playdate-kubb `docs/PLAYERS.md` section 2). The file id is the name lowercased, spaces and
hyphens to `_`, other non-letters dropped, a taken id given `_b`, `_c` (`notation.assignIds`).
In the file, a team of one writes no prefix on its throws and a team of more writes the
shortest unique start of each id (`notation.fileIds`, engine 0.7.1). Pitchside's roster
is its own; a player's `key` is what history and stats point at.

**Turn.** One team's go: its inkast, then its batons. Turns are numbered from 1 and
alternate from `First`. Note two clashing words: the Rules V4.0 glossary's "round" is one
turn for each team (playdate-kubb `docs/PLAYERS.md` section 1), while the engine's "round"
is one pass of kubbs thrown in during an inkast (`docs/notes/rules-engine.md` "Judged at
the final position"). Pitchside should say "turn" and avoid "round" on screen.

**Inkast.** The attacker throws the kubbs it knocked down last turn into the defender's
half: first throws, then rethrows (II.C.6). The engine asks for each with
`need() -> { kind = "toss", side, kubb, rethrow, throwY, half, left }`. Whether a kubb is
in or out is judged once every kubb of the round has been thrown, not when it stops
(Jamie's ruling, 2026-11-13). A kubb out once is rethrown; out twice it becomes a
**punishment kubb**, placed by the defender (`need().kind = "punish"`). A kubb resting on
another is lowered beside it. A kubb thrown in that knocks the king over loses the game.
Then the defender **raises** each lying kubb on one end (`need().kind = "raise"`, with the
ends it may choose, `core/raising`). Notation tokens: `I` first throws, `R` rethrows, `P`
punishment kubbs, `Q` rescues, `N` kubbs that came to rest on another, `E` king toppled by
a thrown kubb (`docs/notes/rules-engine.md` "Notation conventions").

**Advantage line.** When the attacker has field kubbs still standing in its own half, it
throws its batons at kubbs from the one farthest from its own baseline
(`Game:_advantage`, `core/rules.lua`). The king shot is always from the baseline. The file
writes a bare `A`; the sheet keeps whole metres from the baseline, 0 to 4
(`pitch.advantageMeters`).

**Baton throw.** One baton. The engine asks with `need() -> { kind = "baton", side, n, of,
left, kingShot, throwY, advantageY, targets }`, where `targets` are the standing field
kubbs, else the base kubbs, else the king. The outcome it takes is `{ illegal, toppled,
kingToppled, moved, ownHalfHit }` (`docs/notes/rules-engine.md` "Baton outcome"). Tokens:
`-` miss, `F`/`3F` field kubbs, `B`/`2B` base kubbs, `2FB` both, `K` the king (win), `=`
a missed king shot, `E` king too early (loss), `3FE` a felled kubb took the king, `Z`
illegal, `G` resigned, `X` not thrown. A base kubb toppled while a field kubb still stands
is stood back up (II.B.4a).

**Kubb.** Ten kubbs with permanent ids: `a1`..`a5` Team A's base kubbs at x = -2..2 on
y = 0, `b1`..`b5` Team B's on y = 8, plus the `king` at (0, 4). Each kubb is
`{ id, kind = "base" | "field", half, where = "pitch" | "hand" | "out" | "punish", pose,
... }`. A **base kubb** stands on its baseline. A **field kubb** is one thrown in; its
`half` is the half it was thrown into, never recomputed from where it lies. Kubbs keep
their ids for the whole game: the kubb `a3` thrown back in is still `a3`.

**Event (Pitchside's own).** One entry in the match's append-only log: a baton recorded, a
kubb landed, a raise, a correction, a photo attached, an undo. Not the notation's `Event`
header, which names a tournament. The engine has no event log of this kind; its session
keeps a snapshot and a list of actions for a physics match (`docs/SESSION.md`). The log is
Pitchside's source of truth; engine state is derived from it by replaying it into a fresh
rules game, which is pure and has no randomness, so the rebuild is exact **(inferred** from
`core/rules.lua` taking no seed and no clock).

**Photo (Pitchside's own).** An image file with an id, attached to an event (an inkast, a
turn, a baton), optionally pinned to a point on the pitch. The notation has no photo
reference today (section 6).

**Position.** There are three frames in the engine. Pitchside must name which one every
stored point is in.

1. **The engine's world frame** (`core/pitch.lua`): metres, x across from -2.5 to 2.5,
   y down the pitch from 0 (Team A's baseline) to 8 (Team B's), the centre line at y = 4,
   the king at (0, 4), stakes at the four corners and both ends of the centre line. The
   pitch is 5 by 8 m. A kubb is 7 x 7 x 15 cm, the king 9 x 9 x 30 cm.
2. **The thrower's view frame** (`core/frame`, `docs/SESSION.md`): the thrower at y = 0
   on their own baseline looking toward +y. The session returns everything in it.
3. **The notation frame** (pk-kubb-score `docs/notation-2.md` "The pitch frame";
   converted only by `notation.toPitch` and `notation.fromPitch`): the origin is the
   centre-line stake on Team A's left as Team A stands on its baseline facing the king.
   **Across** is 0 to 5 along the centre line (the king at 2.50). **Depth** is metres from
   the centre line toward a baseline, 0 to 4, the same in both halves, so both baselines
   are at depth 4.00. The **half** (`a` or `b`) is the half the piece is in play for. A
   point has two decimals, rounded to the centimetre with halves to even. A cell is a
   whole metre square (`4,0`).

The brief described "a half-pitch frame with the king at (2.5, 0) and depth measured in
metres from each side's baseline". The code puts the king at (2.50, 0) but measures depth
from the **centre line**, with the baseline at 4.00. The code wins; see Open questions.

Pitchside stores every position in the notation frame, with its half, plus two fields of
its own: `approximate: true` for a tap and `source` (`tap`, later `photo`) **(inferred:
a recommendation, not an engine fact)**. Storing in the notation frame means the export
writes positions with no conversion and the app never needs the engine's world frame on
screen. Views are only drawings of this frame: a sideline view and a view from behind
either baseline. Behind Team B's baseline both axes are mirrored; the data never changes.

## 5. Engine integration

### Carrying the engine (as throwingwood-ios does)

throwingwood-ios `AGENTS.md`, "The engine must match the web's, bit for bit":

- The Lua is a tagged kubb-engine release, named once (`TAG` in `scripts/vendor-engine.sh`).
  `sync` copies that tag's tree, never the working tree, from the kubb-engine checkout
  beside it, byte for byte (`core/`, `pitch/`, `session/`, `tune/`, `version.lua`,
  `engine.json`, `LICENSE`). `check` verifies every file against the tag's `engine.json`,
  which has a sha256 per file and one for the bundle (`make bundle`:
  `build/kubb-engine-sources.json`). Never edit the copy; a fix goes into kubb-engine, is
  tagged, then synced.
- Lua 5.4.5 (wasmoon 1.16's) in a C target `CLua`, and musl 1.2.5's maths in `CMusl`
  with every symbol renamed `twm_*`, built with `-ffp-contract=off -fno-builtin
  -fno-modules`. This makes the phone's answers equal the web's WebAssembly ones bit for
  bit (kubb-engine `docs/DETERMINISM.md`). The Swift package is `ThrowingWoodKit` with
  targets `CMusl`, `CLua`, `KubbEngine`, `KubbRenderer`, `KubbPitch`; iOS 26.0, macOS 15.
- The host boots through `session/api` and calls `engineVersion`, `useTune`, then
  `setClient { label, location }` before any match.
- The version a person sees is `<app version> (<engine version>)`, from one place.

A rules-only scorer does not strictly need musl's maths: the rules engine does no physics
**(inferred)**. Pitchside should carry it anyway, so a scored game can later be shown or
replayed on the same engine with the same numbers, and because one way of carrying the
engine is easier to keep right than two. Pitchside carries its own copy of the C targets
and its own vendor scripts (`scripts/vendor-c.sh`, `scripts/vendor-engine.sh`,
`scripts/check-libm.sh`), copied from throwingwood-ios, never linked into it.

### What the engine offers today

- `tw.rules` is already a scorer's engine. It is a pure state machine that "knows nothing
  about physics: it asks for the next action and takes resolved throws (the outcome
  records) and the defender's choices" (`docs/notes/rules-engine.md`). It enforces Rules
  V4.0: the 2-4-6 opening, the advantage line, rethrows and punishment kubbs, judgment at
  the final position, II.B.4a, II.B.7, II.B.11, II.C.4b, rescues, the early king. It writes
  the score sheet and the Notation 2 file as it goes.
- `core/order` deals who throws each baton within II.B.5 and II.A.4 and refuses a change
  that breaks them (`order.change`).
- `core/namegen` and `kubbCall("names.<name>")` make player and team names from reviewed
  word lists (`docs/NAMES.md`).
- `kubbCall("pitch.<name>")` is the shared pitch: a lobby document and who acts
  (`docs/PITCH.md`), carried by a pitch server that runs no engine.
- Tools that already read real game files: `tools/realgames.mjs`, `tools/batonvalue.mjs`,
  `tools/realtiers.mjs`, and the Kubb Gym (`docs/notes/real-games.md`, `docs/notes/gym.md`).

### What is missing: record mode (the first piece of engine work)

The session, the only door a Swift host uses (`kubbCall`), runs physics matches: a throw
is a dial input in `frame(input)`, launched and simulated, and its outcome comes from the
physics. There is no call that takes an observed outcome. `tw.rules` takes outcomes but is
reachable only from inside Lua. So the gap is a **record mode**: a door through which a
host supplies what happened and gets back what the engine needs next, the state, and the
file. The gaps found so far, without designing the change:

- **Outcomes without positions.** A toss outcome needs a `rest` pose and a baton outcome
  needs `moved` poses. With "where kubbs stand" off the scorer gives neither. The engine uses poses
  to judge in or out and to place the advantage line. Record mode needs an in/out verdict
  per kubb and an advantage line given as observed (or approximate), not computed from
  poses.
- **Raising as observed.** The engine chooses or asks for the end a kubb is raised on. In
  a real game the defender raises it, and the scorer may only see where it ends up
  standing. Record mode should take the standing position (or none).
- **Record, don't enforce.** `core/order` refuses a thrower who breaks II.B.5 or II.A.4,
  and the rules raise an error on an action out of phase. A real game may break a rule;
  the scorer records what happened. Record mode needs to accept it and warn.
- **Unknown thrower.** The engine always names a thrower (it defaults to the team's first
  player and deals the order). With "who threw" off the thrower is not recorded, and the
  file must not claim one. The notation allows a token with no prefix.
- **Events the engine never writes.** `Y` (a failed rescue), `W` (a game called, as under a
  tournament clock) and substitutions (I.B lets registered players substitute) are in the
  notation or the rules but not in the engine's writer **(inferred** from
  `docs/notes/rules-engine.md`, which says `Y` is never written, and no `W` in its token
  list).
- **Typed names.** session `restore` refuses names that are not generated (`names.check`,
  kubb-engine `docs/SESSION.md`). Pitchside's team and player names are typed, so record
  mode must not run that check on them.
- **The file's labels.** `setClient` writes `[Scored by "Throwing Wood <label>"]`
  (`notation.scorer = "Throwing Wood"`) and `[Event "Throwing Wood"]` by default. A
  Pitchside file must say Pitchside and the real event. `location` takes only letters,
  digits, spaces, dots, hyphens and pluses, so "Minnehaha Park, Minneapolis" would be
  refused for its comma. There is no session call for the event name.
- **Rebuilding from a log.** Record mode should take a whole list of events and return the
  state after them, cheaply, so undo and edits are a rebuild (section 3).
- **Versioning.** New calls and fields that only add go with a minor version
  (`docs/VERSIONING.md`), and record mode should move no existing golden hash.

Shaping record mode is kubb-engine work, done there, released as a tag, then synced here.
It is the first thing to build, before any app screen depends on it.

## 6. Notation

### What Planet Kubb Notation captures today (Notation 2, edition 2026.11, tag `v2-2026.11`)

From pk-kubb-score `docs/notation-2.md`. The grammar (`grammar/planet-kubb-notation.peggy`)
and the conformance suite (`conformance/`) are the standard; the document explains them.

- Headers `[Key "value"]`: `Notation`, `Event`, `Location`, `Start`, `End`, `Duration`,
  `Surface`, `Rules`, `Base kubbs`, `Batons`, `Opening`, teams and their players with ids,
  `First`, `Win`, `Scored by` and others. A writer may add any key; a key containing a
  character other than letters and spaces (`Engine:seed`) is the writer's for good.
- One turn line a turn: `n. [player:]KUBBS [A] [player:]BATON ... # note`. A player prefix
  on any token says who threw it, so **who threw each baton is already expressible**.
- **Position lines already exist**, under their turn: `@` the pitch line (every field kubb
  standing in a half when the first baton is thrown), `~` the lay line (each kubb thrown
  in, as the two ends where it lay before it was raised), `^` the stance line (where each
  baton was thrown from), `*` the felled line (where each kubb a baton felled stood). Each
  is all cells (`4,0`, a metre square) or all points (`4.48,0.11`).
- Agreement rules: a pitch line is the whole half or is left out; a felled word gives
  every kubb of its token or is `-`; `p` entries number the turn's `P`.
- The king has no position.

The engine writes `@` and `*` lines only. It writes no `~` or `^` because its outcomes have
no such data (`docs/notes/rules-engine.md` "Positions").

### What Pitchside needs, and where it stands

| Need | Today | What is missing |
|---|---|---|
| Positions of inkast kubbs, felled kubbs | `@` and `*` lines | Nothing in the grammar. The pitch line's "whole half or nothing" rule means a turn with some kubbs untapped writes no pitch line. |
| Where an inkast kubb landed before it was raised | `~` lay line | It wants both ends of the lying kubb. One tap gives one point, so a tap cannot fill it. |
| Positions marked as approximate | Nothing | A point claims the centimetre. A cell is honest but coarse. The notation needs a way to say a line or an entry was tapped by eye. |
| Photo references | Nothing but free text in `# note` | A defined form: a photo id on a turn, an inkast or a baton, optionally with a point. |
| Who threw each baton | Player prefix | Nothing. A token without one says "not recorded". |
| The king shot | `K`, `=`, `E`; `^` gives where it was thrown from | The king's own position, if wanted. |
| Failed rescues, a called game | `Y`, `W` | Nothing in the grammar; the engine's writer lacks them (section 5). |

**The grammar must be extended before the app writes approximate positions or photo
references.** A change to the notation goes in pk-kubb-score in three places together:
the grammar, `docs/notation-2.md` and a conformance case (pk-kubb-score `AGENTS.md`), then
a new edition tag, then the engine's vendored copy (`make sync-notation`), then the
engine's writer. The engine's notation gate fails any file the released grammar does not
accept, so the order cannot be skipped. A writer's own header key (one with a colon) could
carry a stopgap, but the brief's point is that the data travels in the open format, so the
proper change is in the notation.

The app's own files (the event log, the photos) are a separate format from the export.
The notation file is derived; the log is kept **(inferred: a recommendation)**.

## 7. Feature scope

### v1

- **Roster and teams.** Players saved across games, kept on this phone only; teams of 1
  to 6 in throwing order; sides A and B. **Team names and player names are typed** by the
  scorer, with no generator and no Shuffle (design review, 2026-11-24; Jamie the same day:
  "we dont have a UGC sharing issue in Pitchside"). Throwing Wood's generated-names rule
  does not apply here.
- **Match options are Throwing Wood's switches** (design review): opening 2-4-6 or six
  batons, surface grass, sand or snow, wind today off, light or strong, and who throws
  first. The rules are U.S. National Kubb Championship Rules V4.0. There are no rules
  presets and no Kid game: a Kid rules file is refused with a plain message.
- **What to record: independent rows, each mapped to notation**, changeable between turns
  (design review; replaces the three capture levels):
  - the turn, always (kubbs thrown in and what each baton felled);
  - who threw (the `k:` player prefix);
  - where kubbs stand (the `@` pitch line and the `*` felled line);
  - how kubbs lay (the `~` lay line);
  - where batons are thrown from (the `^` stance line).
  The file states what was captured in a writer's header, `[Pitchside:capture "..."]`,
  whose value is the words `turn`, `who`, `stand`, `lay`, `stance` for the rows that were
  on at any point in the game (the grammar takes a key with a colon; it sorts after the
  defined headers and the file stays canonical).
- **Position by tap**, in the notation frame (section 4), stored as approximate. Sideline
  and behind-the-baseline views.
- **Catch-up.** Record outcomes live, add positions between turns. Positions owed are
  visible until filled or waived.
- **Undo and edit anything**, as events in the log, with the state and the file rebuilt.
- **Photos on events**, optionally pinned to a spot, kept as separate files referenced by
  id.
- **Export**: the Planet Kubb Notation file (plain text, shareable) and a readable score
  sheet.
- **Offline first, local files.** No account and no network for scoring.

### Ecosystem (design for these now, build later)

- **Replay a real game in Throwing Wood.** The engine's replay (`session/replay.lua`)
  plays a match again from its options, seed and action log, through the physics. A real
  game has none of those, so this needs a new viewer that stands pieces where the file
  says, turn by turn. pk-kubb-score lists "a pitch replay" as an idea not built. It is
  only as good as the positions captured, which argues for "where kubbs stand".
- **Real games for the computer players.** The engine already measures itself against
  the 150 archived real games, which it treats as pro play, and keeps a play reference by
  level (`docs/reference/PLAY.md`, `play-levels.json`). Pitchside files would feed the
  same tools. A game would need to say its level (beginner, club, pro), which no header
  does today. Recorded games are private data: the engine's rule is to pass their folder
  to a tool, never copy them into a repository.
- **Player stats across games.** Built (design review): Stats follow the Planet Kubb
  scoresheet, hit %, 1st baton efficiency and Zero B @ T#, then rethrows, batons to clear
  the field, from 8 metres and hit % by player. The numbers come from pk-kubb-score's
  vendored reader (`kubb.js`) run in JavaScriptCore; Pitchside adds only Zero B's turn and
  baton and "from 8 metres" over the reader's turns. Across games, a saved name is the
  identity, on this phone only (the game keeps a map from file ids to saved names). Files
  opened from elsewhere count in their own stats, not under a saved name.

### Later

- Two phones scoring one match. The engine's shared pitch (`docs/PITCH.md`) is a lobby
  and a log of actions for one physics match with seats; two scorers of one real game is
  a different problem (two people recording the same event) **(inferred)**.
- Tournament mode: pools, brackets, a game clock (and `W` for a called game).
  [Events in Pitchside](docs/events.md) explores joining teams and running scheduled matches on grass and in Throwing Wood.
- Apple Watch tap-to-score.
- Correcting tapped positions from the photos with vision.

## 8. Interface brief for Claude Design

This section stands alone. A designer can work from it without reading the rest.

### What the app does

A person at the side of a real kubb pitch records the game as it happens. The screen
shows the pitch. The app always knows what can happen next, so the scorer mostly taps
the thing that happened: the kubb that fell, the spot a kubb landed, the MISS button.

### The pitch, for drawing it

- A rectangle 5 m wide and 8 m long, with a centre line across the middle and six stakes
  (four corners, both ends of the centre line).
- Each team has five **base kubbs** standing on its baseline, 1 m apart, the outer ones
  0.5 m in from the sidelines. The **king** stands in the centre.
- Kubbs knocked down are thrown back into the other half and stood up there: **field
  kubbs**. A team must clear the field kubbs in its target half before its base kubbs.
- Batons per turn: 2 in turn 1, 4 in turn 2, then 6.
- When a team's own field kubbs are left standing in its half, it throws from an
  **advantage line** through the one nearest the centre, not from its baseline.
- When all of the other side's kubbs are down, the next baton is at the king, from the
  baseline: down is a win, a miss is just a miss. Knocking the king over any earlier loses
  the game.

The design that answered this brief is in `docs/design/` (canvas and shots). Its review
decisions are in section 7 and win over this brief where they differ (capture levels,
generated team names, the rules choice).

### Screens and states to frame

1. **Home / recent games.** Games in progress first, one tap to resume. Finished games
   with teams, winner, date.
2. **Roster and team setup.** Saved players, building two teams of 1 to 6, setting the
   throwing order, choosing sides A and B. Players are real people, typed once with their
   real names and picked from the roster after that. Team names come from a generator (a
   name and a SHUFFLE control, as Throwing Wood does).
3. **Match setup.** Rules (V4.0 with 2-4-6 to start), who throws first, capture level
   (Outcomes, Plus inkast, Full) said in plain words, event and place.
4. **Live scoring on the pitch.** The main screen. Design it first and most carefully.
   - **Inkast.** The attacking team has N kubbs to throw in. At level 1: one tap for "all
     in", or counts of in and out. At level 2 and up: tap N spots in the target half; the
     app counts down. Then rethrows for kubbs out. A kubb out twice becomes a punishment
     kubb, placed by the defenders: one tap where they put it. Also: a kubb resting on
     another, and a kubb thrown in that knocks the king over (the throwing team loses).
   - **Batons.** The kubbs that can be hit now are marked (field kubbs first). Tap each
     kubb that fell; one big MISS. A baton can fell several kubbs. At level 3 the thrower
     is shown and can be changed. Always visible: whose turn, baton n of N, kubbs left on
     each side, the advantage line if there is one.
   - **The king shot.** When only the king is left: KING DOWN (win) and MISS. Rare cases
     reachable but out of the way: king knocked over too early (loss), an illegal throw,
     a resignation.
   - **The turn change.** The other team's turn begins without a screen to dismiss: what
     they have to throw in and how many batons.
   - **Catch-up.** Outcomes recorded fast, positions owed. Show what is owed, let the
     scorer fill it between turns, or leave it.
   - **Undo.** One tap, always in reach, undoes the last event. It never asks "are you
     sure".
   - **A photo being attached.** Taken without leaving the turn; optionally pinned to a
     spot on the pitch. Scoring goes on while it saves.
5. **Pitch orientation flip.** A sideline view and a view from behind either baseline.
   The scorer moves; the picture should match what they see.
6. **Game timeline / event log, with edits.** Every event in order, grouped by turn. Tap
   one to change it. An edit can make a later event impossible (a kubb that "fell" later
   no longer stands); show which events that touches.
7. **Score sheet and notation export.** A readable score sheet, turn by turn, and the
   Planet Kubb Notation text, shared as a file.
8. **Player and game stats.** Lighter, later: hit rate from 8 m, inkast efficiency,
   turns to clear.

### Constraints

- One-handed: the thumb of either hand reaches every scoring control.
- Tap targets big enough to hit while standing and glancing: Throwing Wood's minimum is
  48 pt on a phone, never under 44; a kubb on the drawn pitch is much smaller than that,
  so its touch area must be larger than its picture.
- Readable in direct sunlight.
- Whose turn it is and how many batons are left, at a glance.
- Nothing modal in the middle of a turn.
- Works in light and dark.

### The family look (what Throwing Wood uses; read from its code)

- **Woodcut in color**: "the Playdate game's look (bold black outlines, hard shadows,
  Londrina display type, TOK! / KLAK! bursts) with flat color" (kubb.thingelstad.xyz
  `docs/DESIGN.md`).
- The 1.0 system (throwingwood-ios `AGENTS.md` "The 1.0 design", `ThrowingWood/Design.swift`,
  `KubbRenderer/SceneSkin.swift`): ink `#16130f`, paper `#f7f0de`, header wood `#ecd09a`,
  muted `#5b4a2c`, warn `#cc3a30`. **Marigold `#f2b705`** is both the one "go" colour (one
  per screen) and **Team A**; **violet `#8e44ad`** (white type) is **Team B**. A 3 pt ink
  line, radius 6 on controls and 8 on cards, a hard shadow of 3 on controls and 5 on
  cards. Londrina Solid Black for titles (sentence case) and buttons, prompts and flags
  (capitals); Inter for everything else; nothing under 14 pt. One segmented bar for two to
  four choices. The minimap draws Team A as circles and Team B as squares.
- The match header reads "Turn 4 · baton 2 of 6" over the thrower's name, with each
  team's base kubbs standing as two numbers on the team colours.
- Throwing Wood has seven **scenes** (Park, Beach, Camping at night, Techno, Minnesota,
  Tournament, Black & White) that reskin its controls. Its dark looks are scenes, not a
  system dark mode. Contrast: 4.5:1 in the day look, 7:1 in every other scene.

### Questions the designer should decide, not inherit

- Marigold is both "go" and Team A in Throwing Wood. In a scoring tool every button
  belongs to a team. Keep it, or separate them?
- How dark mode works for a tool, given Throwing Wood's dark looks are game scenes.
- Whether the sunlight case wants 7:1 everywhere, not only 4.5:1.
- Top-down pitch (like the minimap) or a perspective view, and whether the sideline and
  baseline views are both top-down.
- Portrait, landscape or both, and where the thumb zone is.
- How a baton that fells three kubbs is entered fast: tap each and the next baton
  confirms, or tap each then a confirm.
- How "approximate" shows on a tapped position.
- How much of the game's play (bursts, sounds, haptics) a tool keeps. A haptic on every
  recorded event may be the confirmation a scorer needs without looking.
- How the capture level is explained to a beginner in one line.

## 9. Open questions

1. **Separate app or a mode in throwingwood-ios?** Current lean: a separate app. Reasons
   for it: a tool and a game have different first screens and audiences, and
   throwingwood-ios has a rule that "no name is typed anywhere" because names others see
   are user-generated content for App Store review, while Pitchside types real players'
   names and shares nothing (Jamie, 2026-11-24). Reasons
   against: two apps to carry the same engine and C targets. Pitchside now has its own bundle id and App Store
   record. Its public repository uses the MIT License.
2. **Where does the notation live?** It lives in pk-kubb-score today, as its own repo and
   tagged editions, vendored by the engine's tests, the Playdate's and the thingelstad.xyz
   gadget. The engine owns only the writer. The brief asked whether it should be an engine
   module; the code says it is already its own repo, and moving it would change three
   clients. Leaning: keep it there.
3. **How is record mode shaped?** A new door (`kubbCall("record.<name>")`?), or outcome
   calls on the existing session? Does it take one event at a time, or the whole log for a
   rebuild? What are its outcome records without poses? kubb-engine's call, as the first
   engine work.
4. **Per-thrower tracking: settled.** It is the "who threw" row. With it off the file
   carries no prefix, so record mode must take a throw with no thrower (section 5).
5. **Photo storage and export.** The photos sit beside the log. How does a game export
   with them (a folder, a zip, the notation alone with ids that dangle)? What does the
   notation's photo reference look like (section 6)?
6. **The position frame (a conflict with the brief).** The brief says depth is measured
   from each side's baseline. Notation 2 and the engine measure it from the centre line
   (baselines at 4.00, the king at 2.50, 0). This guide follows the code. If depth from the
   baseline reads better on screen, that is a label, not a second frame.
7. **"US Nationals" (a naming difference).** The engine's rule set is "U.S. National Kubb
   Championship Rules V4.0" and the file says "U.S. Championship 4.0". Use the engine's
   words on screen.
8. **Names: settled.** Player and team names are typed (Jamie, 2026-11-24: "we dont have
   a UGC sharing issue in Pitchside"; the design review dropped Shuffle). Note for the builder: the engine strips quotes, brackets,
   commas and parentheses from names in the file and makes ids from them
   (`docs/notes/rules-engine.md`), so "Kim (Jr.)" reaches the file changed.
9. **The lay line.** It is the "how kubbs lay" row, entered by a drag along each kubb
   (the design's answer to "one tap gives one point"). The drag is not designed in detail
   or built.
10. **Real-game levels.** Who says whether a scored game is beginner, club or pro, and in
    which header?
11. **Sharing the C targets: settled.** Copied, with Pitchside's own vendor scripts.
12. **The 2013 Android app.** Known only from the brief. If its source or store page
    exists, it is worth reading for what scorers asked of it.

## 10. Conventions for agents

- **Status (2026-11-24).** A game can be set up, scored, reopened, corrected and
  exported on the iPhone simulator. Games resumes every unfinished game. A local score
  sheet opens the timeline for corrections and previews a printable US Letter PDF.
  Every readable score sheet opens a read-only play-by-play viewer for its recorded
  inkasts, advantage, batons and result. Imported games support PDF export too. The live pitch, in-game timeline, score sheet,
  roster, local stats and opening other Notation 2 files are connected. The repository
  is public at `jthingelstad/pitchside`, with `main` as the default branch and an
  MIT license. Photos and lay-line entry are future work. Internal
  TestFlight builds use `com.throwingwood.pitchside` and the Dev tester group.
- **Navigation and appearance.** The live pitch uses the full screen. Leaving it for Games,
  the timeline, play by play or a finished score sheet restores the section bar.
  Games, Roster and Stats are available during setup and browsing. Switching sections preserves drafts and
  reading positions. Each throw shows the turn, player and action in order. The active
  player can be changed next to the recording controls when tracking is enabled.
  Only live scoring uses landscape, automatically on entry and resume. The pitch stays
  on the left, with scoring controls and independently scrollable turn history on the
  right. All other screens, including the timeline and play by play, use portrait.
  The file picker, PDF preview and share sheet use the system presentation.
  Inter, sentence-case labels, flat surfaces and a field-green action colour carry the
  tool interface. The pitch, lettered team markers and Pitchside wordmark carry the
  family look. The original canvas remains the reference for scoring interactions.
- **Layout.** `Pitchside/` contains the SwiftUI app. `ScorerView.swift` and
  `PitchCanvas.swift` draw the live screen. `ScorerScreen.swift` interprets gestures
  using the engine's next action and allowed events. `TimelineView.swift` previews
  corrections. `Demo.swift` supplies invented games for DEBUG builds.
  `PitchsideKit/` contains the Lua interpreter and musl maths, `KubbEngine`
  (kubb-engine v1.1.0), `Notation` (the pk-kubb-score v2-2026.11 reader running in
  JavaScriptCore), `PitchsideModel` and `PitchsideDesign`. The Xcode UI tests live in
  `PitchsideUITests/`. The working reference and simulator screenshots are under
  `docs/design/`.
- **Scorer seam.** `PitchsideModel/Scorer.swift` declares `LiveScorer` and
  `ScorerFactory`. `AppModel` uses `RecordScorer.Factory`. The scorer calls
  `record.rebuild` on open, `record.add` for observations and `record.build` for an edit
  preview. The engine returns the state, warnings, sheet and notation. See kubb-engine
  `docs/RECORD.md` at v1.1.0 for the record contract that implements section 5's proposal.
- **Storage.** Under Application Support `Pitchside/`, the roster is `roster.json` and
  each game has a `games/<uuid>/` directory. In `events.jsonl` the start entry pins
  setup, including typed names and explicit player ids. Each observation has its record
  fields and id at the top level. The reserved `_log` object carries journal metadata.
  A correction replaces, inserts or removes an observation by id. Undo and redo append
  the sequence number of the observation or correction they reverse or restore. A new
  observation or correction starts a fresh branch. Earlier journals with id-based undo
  keep their original meaning. The score sheet opens a local turn directly for editing.
  Undoing a correction to a finished game keeps the sheet open when the result still stands.
  Each opening of a local sheet reads its history and engine warnings from the journal.
  A newline terminates each synced entry. The next append truncates a torn tail.
  `game.json` keeps the game summary and `game.txt` is the engine's current notation,
  a draft until `state.over`. Opening the app repairs stale exports from the journal.
- **Capture and coordinates.** New games record the turn and standing positions.
  The writer's released capture header names `players`, `pitch` and `stance` if used,
  or `turns` when only outcomes are recorded. A switch applies per turn. The lay row is
  reserved. New taps carry half, across, depth and their approximate tap provenance in the
  journal. `PitchFrame` maps the three viewing positions to a common centre-line origin.
  Record mode returns metre cells for kubbs and writes stance points to the centimetre.
  The live pitch uses journal taps at their original approximate positions. Coincident
  targets offer an inline choice. Pieces known only to a cell share its drawing area. Pinch around a group
  to zoom the pitch up to 4×, then drag to pan. The header button zooms into the
  defending half or fits the pitch. A change of turn or view fits the pitch again.
  A field hit in the journal can carry `at[i].placement`, the ID of the toss or
  punishment placement (or the pitch-event ID and slot). It identifies that standing
  placement until it falls. An earlier unreferenced hit in a shared cell leaves the
  surviving positions at cell precision. Native piece IDs and tapped points in
  record mode remain an engine request. The observed advantage distance stays in the journal.
  On a baton with both located and unlocated hits, `knownFelled` keeps the available
  positions locally until the timeline editor can supply a complete felled word.
- **Play by play.** `GameReplay` builds immutable pitch snapshots from the vendored
  reader’s turn rows. `ReplayView` uses the live pitch geometry, orientations and zoom.
  Pitch and fall lines retain point or cell precision. A recorded fall can establish a
  standing position on a turn with no pitch line. An unidentified fall leaves uncertain
  survivors unlocated. Local games show one step per accepted toss, rethrow and
  punishment placement in the folded journal. Each step uses the engine state at that
  instant. A ring marks the newly placed kubb when its spot was recorded. Imports keep
  the grouped inkast and any lay line from the file. An inkast cut short by a baton
  groups any outstanding throws counted in by record mode. More → Play by play on the live scorer opens at the latest play
  and returns to the pending throw. Shared text files use the released engine's cells.
  Lay and throwing-spot coordinates appear when the file contains them.
- **Build and test.**
  - `swift test --package-path PitchsideKit` runs model, frame, contrast, reader and
    engine tests. Node is needed to compare the reader with archived games read in
    place from `../pk-kubb-score/games`. The Swift scorer replays all eleven tagged
    record fixtures and compares their output bytes with the tagged desktop engine.
    `scripts/record-fixtures.sh` regenerates the test input and reference output.
  - `xcodebuild -project Pitchside.xcodeproj -scheme Pitchside -destination
    'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build` builds
    the simulator app. Replace `build` with `-parallel-testing-enabled NO test` for
    the UI journeys.
  - `scripts/screenshots.sh --scorer "iPhone 17"` runs the UI journeys and writes their
    attachments to `docs/design/build-shots/` and checks the simulator export with the
    vendored reader. Omit `--scorer` to refresh the other
    demo screens too. By name the script prefers an already booted device, then
    the newest installed iOS runtime. A simulator UUID selects a specific version.
    DEBUG demo launches use a temporary game store.
  - On the macOS 27.2.1 development host with Xcode 27.2, the local iOS 26.2
    simulator exits in JavaScriptCore during reader startup, including on a fresh
    simulator. The iOS 26.2 GitHub runner passes the scoring journeys, as does
    the local iOS 27.2 simulator. Physical iOS 26.2 remains unverified.
  - `scripts/vendor-engine.sh check` and `scripts/vendor-notation.sh check` check
    the tagged copies. Finish simulator work with `xcrun simctl shutdown all`.
- **The engine is never edited here.** Not the vendored copy, not the kubb-engine checkout
  from here. A change to the rules, record mode or the writer is a kubb-engine pull
  request and a tag, then a sync here. The same for the notation: a pk-kubb-score pull
  request and an edition tag.
- **Cite the sibling repos** by repo name and path, with the tag when it matters:
  `kubb-engine/core/rules.lua` (v1.0.0), pk-kubb-score `docs/notation-2.md` (v2-2026.11),
  throwingwood-ios `AGENTS.md` "The 1.0 design". Read a sibling repo's `AGENTS.md` before
  relying on it; they change often.
- **Say when you infer.** Mark a claim not read from code as inferred, as this file does.
- **Never verify with a write to live data.** Recorded games are personal data: none in
  the repository, no names or places of real people in fixtures, only invented ones.
- The workstream's own rules (pull requests only, Codex reviews, worktrees for side work,
  times in US Central, clean up simulators) are in `../AGENTS.md` and `~/Projects/AGENTS.md`.
