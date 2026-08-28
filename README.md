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

## License

This packaging is MIT licensed. Fastpotify itself is
[MIT licensed](https://github.com/crmne/fastpotify/blob/main/LICENSE) by its
authors.
