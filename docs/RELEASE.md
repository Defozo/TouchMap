# Local release packaging

Prepared for DEFOZO SOFTWARE HOUSE. Sole team member: Michał Kiełtyka.

`scripts/package-release.py` builds a local review bundle from a frozen commit. It never publishes a repository, uploads files or submits a competition entry. Python, Git and FFmpeg's `ffprobe` must be available. The committed dependency locks and `toolchain.lock.json` remain the build reference.

After final source changes, commit the reviewed tree, build and verify its signed HAP, complete the English demo, and run `scripts/verify-release.py` for that same commit. The expected inputs are `dist/touchmap-signed.hap`, `dist/touchmap-demo.mp4` and `dist/release-verification.json`. The verification must contain the committed team, matching HAP and sample hashes, explicit gates and the exact source commit.

```sh
# A preflight creates no release archive and returns JSON failures with exit code 1.
python3 scripts/package-release.py --commit HEAD --check-only

# Creates a local review bundle, retaining any explicitly outstanding gates.
python3 scripts/package-release.py --commit HEAD

# Final gate enforcement is explicit and fails unless every gate has passed.
python3 scripts/package-release.py --commit HEAD --require-all-gates
```

Use `--hap`, `--demo`, `--verification` and `--output` for other explicit paths. `HEAD` must resolve to the selected commit, tracked files must be clean, and all required source files must exist in that commit. Untracked working files are excluded. Tracked private environment/signing files cause rejection. Secret-content scanning and public repository review remain part of the separately recorded release gates.

The ZIP contains:

- `source.zip`, built only from `git archive` of the selected commit;
- the verified signed HAP and readable demonstration video;
- committed documentation, team data and portable sample packages;
- the complete release verification, including outstanding gates;
- `environment-manifest.json` with commit/tree identity, committed toolchain and packaging versions;
- `release-manifest.json` with per-artifact hashes and publication fields from the verification;
- `SHA256SUMS` for every other file, plus an external checksum for the complete ZIP.

Sorted paths, a fixed ZIP timestamp and a fixed compression setting make identical inputs deterministic under the recorded Python/zlib versions. An existing different archive is never silently replaced. The script validates video structure, not the truth of the recorded demonstration or its spoken language; those require the actual reviewed demo evidence. A bundle with outstanding gates remains a review candidate and its manifest says `competitionSubmitted: false`.
