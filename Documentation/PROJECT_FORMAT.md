# Cineleaf project format

A `.cineleaf` document is a directory package. Version 1 contains:

```text
Example.cineleaf/
  project.json
  Autosave/
    recovery.json        # present only while recovery is needed
  Derived/               # disposable bounded caches; never source media
```

`project.json` is UTF-8 JSON encoded with sorted keys. It records a format version, stable project identifier, metadata, canvas, rational frame rate, tracks, clips, asset references, trim points, transforms, effects supported by the current version, audio settings, text overlays, and export preferences.

External assets contain a security-scoped bookmark when macOS can create one, the last known path for display/relink, and cached non-authoritative metadata. Large source media is not copied into the package by default.

## Save and recovery

JSON is first encoded and validated in memory, written atomically to a sibling temporary file, and then replaces `project.json`. Autosave is debounced after committed edits. An unnamed project writes a recovery copy in Application Support; opening or deliberately discarding it clears that recovery item.

## Migration

The decoder reads the version before decoding the current model. Each migration transforms exactly one version to the next and revalidates the result. Unknown future versions are rejected without rewriting the package. A failed migration leaves the original bytes unchanged and returns a user-facing error with technical detail available locally.

