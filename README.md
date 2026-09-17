# yunooos

Generic iOS in-process cloud-save core designed to be embedded into an existing dylib.

## Current branch: AutoDiscovery v0.1

The first milestone focuses on **automatic save discovery** so each game does not require a manually-authored JSON profile.

```text
Host game sandbox
  -> metadata baseline
  -> player performs a real save
  -> change detection
  -> candidate scoring
  -> SQLite family grouping
  -> SHA-256 identity
  -> generated SaveProfile
```

The implementation borrows the safe architectural ideas we verified from prior cloud-save projects, while using the existing `a7987083/zonoe-` project as an iOS sandbox/import-export reference.

Run an iOS arm64 compile check on macOS/Xcode with:

```sh
make check
```

See `docs/autodiscovery-v0.1.md` for the current discovery model.
