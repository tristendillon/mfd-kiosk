# Releasing (maintainers)

How CI validates the flake and how the GitHub Actions pipeline publishes the
flasher (ISO + raw GPT USB image) as a GitHub Release.

## CI on every push and PR

`.github/workflows/ci.yml` runs `nix flake check ./os` on every push to `master`
and on pull requests. This is a fast evaluation of all appliance outputs — it
does **not** build an image — so it catches Nix-level mistakes in seconds. See
[building.md](building.md#fast-checks-without-a-full-build) for the same check
locally.

## Cutting a release

Releases are **fleet-generic**: per-device and per-site config (hostname,
dashboard URL, credentials) is collected by the install wizard, not baked into
the image. The only baked-in knobs are the wizard's defaults
(`mfd.kiosk.baseUrl`, `mfd.kiosk.rebootTime`) plus optional recovery keys
(`mfd.kiosk.adminKeys`) in `os/hosts/kiosk/configuration.nix`.

Commit, push, and tag with a semver-ish `v*` tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which on
`ubuntu-latest`:

1. **Frees runner disk** to make room for the ~3 GB images.
2. **Installs Nix** and runs `nix build ./os#iso` plus `nix build
   ./os#usbImage` (the raw GPT USB image; built zstd-compressed and
   stream-decompressed during asset prep — Etcher/Rufus can't flash `.zst`
   directly).
3. **Splits both artifacts** into parts under 2 GiB
   (`mfd-kiosk-flasher.iso.part0`, `mfd-kiosk-flasher-usb.img.part0`, …).
   GitHub caps each release asset at **2 GiB** and both are larger, so neither
   can be uploaded whole.
4. **Writes `SHA256SUMS`** covering the parts and the reassembled whole
   ISO/`.img`.
5. **Creates the GitHub Release** with generated notes plus artifact-picking,
   reassembly and verification instructions (the same steps users follow in
   [Getting the flasher](../README.md#getting-the-flasher)) in the body, and
   uploads the parts and `SHA256SUMS` as assets.

## Testing the pipeline without a release

The Release workflow also supports a manual run: **Actions → Release →
Run workflow** (`workflow_dispatch`). It does the same build and split but
uploads the files as a **7-day workflow artifact** instead of creating a
release — use it to exercise the pipeline without publishing a tag.
