# Building the MFD kiosk image

How to build the appliance, why the build is heavy, and how to keep it from taking
down your machine. Read this before your first `nix run ./os#iso`.

---

## TL;DR

```sh
# 0. One-time host/env setup (see §2). Then, from the repo root:

# 1. Build the heavy part (WebKit) in isolation first — proves the OOM fix:
nix build ./os#nixosConfigurations.kiosk.config.system.build.toplevel --cores 4 --max-jobs 1 -L

# 2. Then the flasher ISO (cheap once WebKit is in the store):
nix run ./os#iso        # -> ./dist/mfd-kiosk-flasher.iso
```

If a build ever nukes Docker/WSL or dies with "No space left" / "out of memory" while
compiling `webkitgtk`, you skipped §2. Go do §2.

---

## 1. Why this build is heavy: the cog → WebKit problem

The kiosk browser is **`cog` 0.8.1** (WPE/WebKit single-window launcher). On our pinned
`nixos-25.05`, building it **compiles WebKitGTK from source** — a multi-hour, ~13 GB-peak-RAM
C++ build (`webkitgtk-2.50.4+abi=4.0`, ~8000 compile objects). That is the single most
expensive thing in the whole image, and on a memory-limited dev box it OOMs and can take the
Docker/WSL2 VM down with it (the OOM-killer reaps `dockerd`).

### Root cause (verified, not a guess)

`cog` 0.8.1 hardwires its WebKit dependency in its `CMakeLists.txt`:

```cmake
pkg_check_modules(SOUP       REQUIRED libsoup-2.4)     # legacy libsoup2
pkg_check_modules(WEB_ENGINE REQUIRED webkit2gtk-4.0)  # the 4.0 ABI specifically
```

That is the **legacy libsoup2 / webkit2gtk-4.0 ABI** = the nixpkgs attribute
`webkitgtk_4_0`. The problem: **Hydra no longer caches that ABI.** Checked against
`cache.nixos.org` for our locked rev (`ac62194c…`, `nixos-25.05`):

| nixpkgs attr | ABI | cache.nixos.org |
|---|---|---|
| `webkitgtk` / `webkitgtk_4_0` (what cog uses) | 4.0, libsoup2 | **404 — not cached** |
| `webkitgtk_4_1` | 4.1, libsoup3 | 200 — cached |
| `webkitgtk_6_0` | 6.0, GTK4 | 200 — cached |
| default `cog` (for this rev) | — | **404 — not cached** |

To re-verify yourself any time:

```sh
p=$(nix eval --raw "github:NixOS/nixpkgs/<rev>#webkitgtk_4_0")
curl -s -o /dev/null -w '%{http_code}\n' "https://cache.nixos.org/$(basename "$p" | cut -d- -f1).narinfo"
# 200 = cached (fetched), 404 = must build from source
```

So **every** build of this cog recompiles WebKit. This is also exactly why cog was removed
in nixpkgs **25.11** ("depends on unmaintained libraries" — libsoup2 is EOL), and why we
pin the appliance to 25.05.

### Why we don't just use a cached WebKit

Swapping cog onto the cached `webkitgtk_4_1` was tested and **rejected**: a `nix build
--dry-run` of `cog.override { webkitgtk_4_0 = webkitgtk_4_1; }` shows WebKit would be
*fetched* from cache and only cog would build — but cog 0.8.1's CMake `pkg_check_modules`
**requires** `webkit2gtk-4.0` and `libsoup-2.4` by name, so it fails to configure against
4.1. Making it work would mean patching cog's pkg-config names *and* its libsoup2 API usage
(high risk of source-level breakage). Not worth it.

**Decision:** keep cog + 25.05; build WebKit from source **once**, make that build
survivable, and reuse it from the local store on every later rebuild.

---

## 2. One-time setup so the build survives

Two independent knobs. Do both.

### 2a. Cap Nix build parallelism (already applied in this repo's dev container)

WebKit's peak RAM during the parallel compile phase ≈ `cores × ~1.5 GB`. With the default
`cores = 0` (= all cores, e.g. 16) that's ~24 GB → OOM on a 16 GB box. We cap it in
`/etc/nix/nix.custom.conf` (root-owned; already `!include`d by `/etc/nix/nix.conf`):

```ini
cores = 4
max-jobs = 2
```

- `cores = 4` bounds WebKit's internal `ninja -j` → peak ≈ 6 GB.
- `max-jobs = 2` limits how many derivations build at once.

Verify it's live (single-user Nix reads this at invocation — no daemon restart needed):

```sh
nix show-config | grep -E '^(cores|max-jobs) '   # -> cores = 4 / max-jobs = 2
```

You can also pass these per-invocation instead: `--cores 4 --max-jobs 1`. The CLI flag wins
over the file, so use `--max-jobs 1` for the one heavy WebKit run if you want to be extra safe.

### 2b. Give the WSL2 VM headroom (Windows host, do once)

This is the hard guarantee that `dockerd` is never OOM-killed. `memory` can't exceed the
host; a large **swap** lets the compile spill instead of triggering the VM OOM-killer.
Edit `C:\Users\<you>\.wslconfig` on the **Windows** side:

```ini
[wsl2]
memory=14GB        # leave headroom for Windows; raise if you have 32GB+ host RAM
swap=32GB
swapfile=C:\\wsl-swap.vhdx
```

Then, **with VS Code closed**, from a Windows terminal:

```powershell
wsl --shutdown
```

and reopen the dev container. **The VM only picks up `.wslconfig` after a full
`wsl --shutdown`** — editing the file is not enough. Confirm inside the container:

```sh
free -g   # MemTotal and Swap should reflect the new limits
```

> Gotcha we hit: edited `.wslconfig`, started building, still OOM'd — because WSL hadn't
> been restarted and the VM was still on the old 16 GB / 4 GB limits. Always `free -g` first.

---

## 3. The isolated WebKit build (recommended first run)

WebKit is the only risky/slow part. Build it alone first so you find out the OOM fix works
*before* committing to the full image pipeline. From the **repo root**:

```sh
nix build ./os#nixosConfigurations.kiosk.config.system.build.toplevel --cores 4 --max-jobs 1 -L
```

- `-L` streams full build logs so you can watch WebKit's object count climb (~x/8000).
- This builds the whole system closure, but WebKit dominates the wall-clock.
- Expect **roughly 1–2 hours** on 4 cores; it is CPU-bound, not I/O-bound.

**Watch it stay bounded** in a second terminal:

```sh
watch -n5 free -g
```

RAM-used should plateau well under your limit; any overflow lands in swap; `dockerd` stays
up. If used RAM climbs toward the ceiling with little swap in use, your `--cores`/`.wslconfig`
didn't take — stop and recheck §2.

When it finishes, WebKit is in `/nix/store`. Confirm:

```sh
nix path-info ./os#nixosConfigurations.kiosk.config.system.build.toplevel   # resolves = built
```

---

## 4. Full build workflow

Once WebKit is in the store, everything downstream is cheap (no recompile).

```sh
# Flasher USB image (carries the prebuilt kiosk image) -> ./dist/
nix run ./os#iso            # -> ./dist/mfd-kiosk-flasher.iso

# Or just the bare kiosk disk image (for direct dd in the lab):
nix build ./os#image        # -> result/mfd-kiosk_*.raw.zst
```

`nix run ./os#iso` dereferences the store symlink into a real, transferable file under
`./dist/` (a plain `nix build` only leaves a `/nix/store` symlink you can't copy to Windows).
See the top-level `README.md` for what to do with the ISO (flash a USB → boot the board →
`mfd-flash` → `mfd-set-token`).

### Rebuild behavior

WebKit is **only** recompiled when its derivation hash changes — i.e. when you bump the
nixpkgs pin in `os/flake.nix`. Day-to-day config edits (URL, keys, modules) reuse the
WebKit already in your store. So you pay the ~13 GB build once per nixpkgs bump, not per
config change.

---

## 5. Optional: share WebKit so nobody rebuilds it

A one-time-per-machine WebKit build is still painful across teammates / CI. After it builds,
push the closure to a shared binary cache (Cachix or self-hosted attic):

```sh
cachix push <cache> $(nix path-info ./os#nixosConfigurations.kiosk.config.system.build.toplevel)
```

Then add the cache + its public key to `/etc/nix/nix.custom.conf`:

```ini
extra-substituters = https://<cache>.cachix.org
extra-trusted-public-keys = <cache>.cachix.org-1:<key>
```

Now other machines/CI **fetch** WebKit instead of compiling it. Skip this if it's just you
on one box.

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Build dies compiling `webkitgtk` around object ~4000/8000; Docker/WSL "socket" dies | VM OOM-killer reaps dockerd | §2: cap `cores`, set big WSL `swap`, **`wsl --shutdown`** |
| `free -g` still shows old small RAM/swap after editing `.wslconfig` | WSL not restarted | Close VS Code, `wsl --shutdown`, reopen |
| WebKit rebuilds even though you built it before | nixpkgs pin changed, or store GC'd it | Rebuild once; pin a GC root or use a shared cache (§5) |
| `cores`/`max-jobs` not taking effect | edited wrong file / not reloaded | Confirm `nix show-config \| grep -E 'cores\|max-jobs'`; single-user Nix needs no daemon restart |
| Want to confirm whether a package is cached before building | — | `nix eval --raw <flake>#<attr>` then curl its `.narinfo` (see §1) |
| `nix build` errors: path "…image.nix not tracked by Git" | flake ignores untracked files | `git add -N os/modules/<file>.nix` |

---

## Reference: key facts

- **Browser:** `cog` 0.8.1 → `webkitgtk_4_0` (libsoup2 / webkit2gtk-4.0 ABI).
- **Pin:** `nixos-25.05` (rev `ac62194c…`); last release shipping cog. Don't bump without
  replacing the browser.
- **Cache reality:** `webkitgtk_4_0` is **not** on cache.nixos.org for this rev → source build.
- **Env caps:** `/etc/nix/nix.custom.conf` → `cores = 4`, `max-jobs = 2`; WSL2 `.wslconfig`
  → `swap=32GB` (+ `wsl --shutdown`).
- **Heavy build target:** `./os#nixosConfigurations.kiosk.config.system.build.toplevel`.
- **Artifacts:** `nix run ./os#iso` → `./dist/mfd-kiosk-flasher.iso`; `nix build ./os#image`
  → `result/*.raw.zst`.
