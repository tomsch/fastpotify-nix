# spotifast-nix

[Spotifast](https://spotifast.rocks/) ([crmne/spotifast](https://github.com/crmne/spotifast))
packaged for Nix/NixOS: a fast, native Spotify client written in Rust and
egui, playing through librespot.

Not an official Spotifast project. Automatically updated via GitHub Actions
every 6 hours by tracking upstream releases.

## Usage

### Flake

```nix
{
  inputs.spotifast-nix.url = "github:tomsch/spotifast-nix";
}
```

```nix
environment.systemPackages = [ inputs.spotifast-nix.packages.x86_64-linux.spotifast ];
```

The `default` package is the same package. Alternatively, use the overlay:

```nix
nixpkgs.overlays = [ inputs.spotifast-nix.overlays.default ];
environment.systemPackages = [ pkgs.spotifast ];
```

### Direct build

```bash
nix build github:tomsch/spotifast-nix#spotifast
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
  [upstream README](https://github.com/crmne/spotifast#sign-in) for the
  OAuth/PKCE flow and one-time librespot playback grant.
- Cargo Git hashes include recursive submodules, matching
  [nixpkgs `importCargoLock`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/rust/import-cargo-lock.nix)
  and [`fetchgit`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/fetchgit/default.nix).
  projectM builds directly from that vendored tree; no separate source download
  or downstream hash override is needed.
- Launcher icons are installed at 48, 64, 128, 256, 512, and 1024 pixels in the
  [hicolor theme](https://specifications.freedesktop.org/icon-theme/latest/),
  using [ImageMagick resizing](https://imagemagick.org/command-line-options/#resize).
- The installed command is `spotifast`, wrapped as `bin/.spotifast-wrapped`;
  the launcher is `spotifast.desktop` with icon `spotifast`.
- Upstream 0.8.0 intentionally retains the Cargo package/library identity
  `fastpotify` and the librespot branch `fastpotify-0.8`
  ([Cargo.toml](https://github.com/crmne/spotifast/blob/v0.8.0/Cargo.toml)).
  These are not renamed in `Cargo.lock`. Both upstream commands are built for
  the [branding tests](https://github.com/crmne/spotifast/blob/v0.8.0/tests/branding.rs),
  then the compatibility `fastpotify` binary is removed during installation;
  this flake provides no legacy package or command alias.
- The upstream [window app-id](https://github.com/crmne/spotifast/blob/v0.8.0/src/entrypoint.rs)
  remains `fastpotify`, so `StartupWMClass` and compositor app-id rules must
  retain that value despite the displayed name being Spotifast. Upstream
  [configuration, state, cache and log paths](https://github.com/crmne/spotifast/blob/v0.8.0/src/paths.rs)
  and existing D-Bus identities are also left unchanged to preserve user data
  and communication with the running instance.

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

This packaging is MIT licensed. Spotifast itself is
[MIT licensed](https://github.com/crmne/spotifast/blob/main/LICENSE) by its
authors.
