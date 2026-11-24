`record-games.json`: kubb-engine v1.1.0's record-mode games (`tests/fixtures/record/games.lua`),
each with its setup, its events, and the file and warnings the engine's own `record.build`
gives for them (desktop Lua 5.4 on the tag, read only). The names are made up.
RecordTests replays each through `RecordScorer` and expects the same file byte for byte.
Remake it when the engine moves (scripts/record-fixtures.sh).
