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

```sh
curl -sSf https://github.com/BigWigsMods/packager/raw/master/release.sh | bash
```

The resulting zip lands in `.release/`. Drop it into
`World of Warcraft\_retail_\Interface\AddOns\` to test the exact build a
released player would receive.
