# Development workspace

This checkout is the independent FilmCutter 1.1 working repository on branch
`codex/v1.1`. Its `origin` is the public WarsawYing/FilmCutter repository; the
read-only local `beta-source` remote records where this checkout was seeded.

Historical documentation belongs under `versions/`, and published source
states belong in Git tags. Generated applications, ZIP files, private TIFF
fixtures, build caches and the pinned offline `vendor/` cache are excluded from
commits. The older local development folders are intentionally not moved or
rewritten by this checkout, so their uncommitted work and histories remain
recoverable.

Use this directory for all 1.1 source changes and local release candidates.
Do not copy its `.git` directory into another FilmCutter repository.
