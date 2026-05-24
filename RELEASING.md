# Releasing CombatReticle

Single-source release process via the [BigWigs
packager](https://github.com/BigWigsMods/packager).

## One-time setup

- Create the project on [CurseForge](https://www.curseforge.com/wow/addons) and
  [Wago](https://addons.wago.io), then fill in `X-Curse-Project-ID` and
  `X-Wago-ID` in `CombatReticle.toc` with the real numeric IDs.
- Add `CF_API_KEY` and `WAGO_API_TOKEN` as repository secrets under
  *Settings → Secrets and variables → Actions*. The CI uploads to whichever
  destinations have a key set.

## Per-release flow

1. Pick the new version number (semver: bump major for breaking, minor for
   features, patch for fixes).
2. Update `## Version:` in `CombatReticle.toc`.
3. Prepend a new section to the top of `CHANGELOG.md` describing the changes
   (Markdown bullets; the packager renders it on the addon listings).
4. Commit, then tag and push:

   ```sh
   git commit -am "Release vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push --follow-tags
   ```

5. The release workflow (`.github/workflows/release.yml`) picks up the new tag
   and uploads the packaged zip to CurseForge and Wago. The release also
   shows up under *Releases* on GitHub.

## Building locally for testing

### Prerequisites

The packager shells out to several tools. Install them once:

- **git** — pulls the repo info embedded in the package.
- **subversion** (`svn`) — most WoW libraries listed in `.pkgmeta` live on
  SVN hosts. macOS removed it from the OS; install with
  `brew install subversion`.
- **zip** — final archive step. Pre-installed on macOS/Linux.
- **curl** — pre-installed on macOS/Linux. The CI runner has the same.
- **pandoc** *(optional)* — only needed if you ever switch the changelog
  to a non-Markdown format. `brew install pandoc`.

### Run the build

The packager script lives behind a GitHub redirect, so curl needs `-L`:

```sh
curl -sSfL https://github.com/BigWigsMods/packager/raw/master/release.sh | bash
```

The resulting zip lands in `.release/`. Drop it into
`World of Warcraft\_retail_\Interface\AddOns\` to test the exact build a
released player would receive.
