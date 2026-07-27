# Rendering pipeline

1. Validate a project snapshot and resolve every enabled media reference.
2. Build a deterministic render plan ordered by track and timeline position.
3. Insert source time ranges into video/audio composition tracks; gaps remain transparent over the configured canvas color and silence in audio.
4. Apply preferred source transforms, fit/fill/crop, user transform, opacity, and video fade ramps.
5. Mix audio level and fade ramps with clipping-aware headroom.
6. Render text layers and their fade/slide animation with Core Animation.
7. Preview through `AVPlayerItem`; reuse a matching composition revision and cancel obsolete rebuilds.
8. Export through an available AVFoundation preset to H.264 or HEVC and AAC, exposing real progress and cancellation.
9. Inspect the finished asset before reporting success; remove partial output on failure or cancellation.

The preview may choose derived proxy media and display-sized output. The export render plan always resolves source media and requested delivery settings. Preview degradation must never alter project data or final quality.

