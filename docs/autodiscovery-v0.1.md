# AutoDiscovery v0.1

Goal: generate a reusable save profile from observed sandbox changes without requiring a hand-written JSON file for every game.

## Flow

1. Capture a metadata baseline of `Documents/**` and `Library/**`.
2. Exclude obvious volatile data (`Caches`, `UnityCache`, logs, temp data, yunooos/zonoe working directories).
3. After a real game save occurs, rescan and identify new/changed files.
4. Score candidates using location, extension, path semantics, bundle-id affinity, volatility penalties and co-change correlation.
5. Treat SQLite as a family: main DB + `-wal` + `-shm` + `-journal`.
6. Hash plausible candidates with SHA-256.
7. Generate `CSSaveProfile` internally. JSON is an output format, not a hand-written configuration requirement.

## Confidence policy

v0.1 intentionally caps one-session confidence below 0.90. A later learning-state layer will aggregate repeated sessions before auto-promoting a profile to trusted status.

## Integration

`CloudSaveDiscoveryAPI.h` exposes a small C ABI so the module can be moved into an existing dylib without coupling it to a test UI.

## Safety

AutoDiscovery only observes sandbox files. Destructive restore is intentionally not part of v0.1; restore will require Snapshot/Manifest validation and rollback in a separate transaction layer.
