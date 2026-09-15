# fastpotify-nix

[Fastpotify](https://fastpotify.rocks/) ([crmne/fastpotify](https://github.com/crmne/fastpotify))
packaged for Nix/NixOS: a fast, native Spotify client written in Rust and
egui, playing through librespot.

Not an official Fastpotify project. Automatically updated via GitHub Actions
every 6 hours by tracking upstream releases.

## Usage

### Flake

```nix
{
  inputs.fastpotify.url = "github:tomsch/fastpotify-nix";
}
```

```nix
environment.systemPackages = [ inputs.fastpotify.packages.x86_64-linux.default ];
```

### Direct build

```bash
nix build github:tomsch/fastpotify-nix
```

## Notes

- Requires a Rust toolchain able to build edition 2024 crates (nixpkgs
  `rustPlatform` on `nixos-unstable` is sufficient; upstream's MSRV is 1.95).
- Audio: ALSA and PulseAudio (covers PipeWire) are linked directly by
  librespot's rodio backend.
- Display: OpenGL, libxkbcommon, Wayland, and X11 (`libX11`, `libXcursor`,
  `libXrandr`, `libXi`) are loaded at runtime via `dlopen`, not linked, and
  are provided through `LD_LIBRARY_PATH` in the wrapped binary.
- Sign-in and Spotify Connect playback work the same as upstream; see the
  [upstream README](https://github.com/crmne/fastpotify#sign-in) for the
  OAuth/PKCE flow and one-time librespot playback grant.
- Cargo Git hashes include recursive submodules, matching
  [nixpkgs `importCargoLock`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/rust/import-cargo-lock.nix)
  and [`fetchgit`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/fetchgit/default.nix).
  projectM builds directly from that vendored tree; no separate source download
  or downstream hash override is needed.
- Launcher icons are installed at 48, 64, 128, 256, and 512 pixels in the
  [hicolor theme](https://specifications.freedesktop.org/icon-theme/latest/),
  using [ImageMagick resizing](https://imagemagick.org/command-line-options/#resize).

## Updating

`./update.sh` updates the release source and Cargo Git hashes, then builds the
package. `./update.sh --no-build` leaves the build to CI.

To refresh Git hashes for the currently pinned release without changing versions:

```bash
python3 scripts/refresh-cargo-git-sources.py Cargo.lock package.nix
```

Run the updater regression checks with `python3 tests/test_updater.py`. The nested
submodule regression uses real local Git repositories and Nix hashing; it requires
Git and Nix, and may fetch `nix-prefetch-git` from the flake's pinned nixpkgs.

The package keeps upstream tests enabled. From 0.8.0, the branding integration
tests need `dbus-run-session`; `dbus` is provided through
[`nativeCheckInputs`](https://nixos.org/manual/nixpkgs/stable/#ssec-check-phase)
inside the Nix sandbox, not installed separately on the CI runner.

## License

This packaging is MIT licensed. Fastpotify itself is
[MIT licensed](https://github.com/crmne/fastpotify/blob/main/LICENSE) by its
authors.
