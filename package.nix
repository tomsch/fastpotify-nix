{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  imagemagick,
  dbus,
  alsa-lib,
  libpulseaudio,
  libxkbcommon,
  wayland,
  libGL,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "spotifast";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "crmne";
    repo = "spotifast";
    rev = "v${finalAttrs.version}";
    hash = "sha256-cX9DXG4u7mBSl6sO768A1vJ9kHZZc12+STzRU0KuWh0=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "librespot-audio-0.8.0" = "sha256-Wmol2ikFPjSetG92nqzcWtl93puO6c+M4IGm5of1vgg=";
      "projectm-sys-1.2.3" = "sha256-btM3/MJ3jP3fvmdYO23sOiELhfpl2tPGnPVOZp4phIM=";
    };
  };

  # importCargoLock includes the projectM submodules in the vendored source.
  # projectm-sys only searches lib, while CMake installs to lib64 on x86_64.
  postPatch = ''
    projectmVendorDir=
    for candidate in "$cargoDepsCopy"/projectm-sys-*; do
      if [ -n "$projectmVendorDir" ] || [ ! -d "$candidate" ]; then
        echo "Expected exactly one vendored projectm-sys directory" >&2
        exit 1
      fi
      projectmVendorDir="$candidate"
    done

    substituteInPlace "$projectmVendorDir/build.rs" \
      --replace-fail \
        'println!("cargo:rustc-link-search=native={}/lib", dst.display());' \
        'println!("cargo:rustc-link-search=native={}/lib64", dst.display());'
  '';

  nativeBuildInputs = [
    pkg-config
    cmake
    rustPlatform.bindgenHook
    makeWrapper
    copyDesktopItems
    imagemagick
  ];

  # Branding integration tests start a private bus with dbus-run-session.
  nativeCheckInputs = [ dbus ];

  # librespot's rodio audio backend links ALSA and PulseAudio (which covers
  # PipeWire) directly; projectM links OpenGL and uses X11 headers.
  buildInputs = [
    alsa-lib
    libpulseaudio
    libGL
    libx11
  ];

  # eframe's glow backend and winit's windowing backends dlopen these at
  # runtime, so they also need to be available on LD_LIBRARY_PATH.
  runtimeLibs = [
    libGL
    libxkbcommon
    wayland
    libx11
    libxcursor
    libxrandr
    libxi
  ];

  postInstall = ''
    # Upstream tests need both commands; only install the primary command.
    rm "$out/bin/fastpotify"
    wrapProgram $out/bin/spotifast \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath finalAttrs.runtimeLibs}

    install -Dm644 packaging/macos/icon-1024.png \
      $out/share/icons/hicolor/1024x1024/apps/spotifast.png
    for size in 512 256 128 64 48; do
      iconDir="$out/share/icons/hicolor/''${size}x''${size}/apps"
      install -d "$iconDir"
      magick packaging/macos/icon-1024.png -resize "''${size}x''${size}" \
        "$iconDir/spotifast.png"
    done
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "spotifast";
      exec = "spotifast";
      icon = "spotifast";
      desktopName = "Spotifast";
      genericName = "Music Player";
      comment = "A fast, native Spotify client";
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
        "Music"
      ];
      keywords = [
        "spotify"
        "music"
        "player"
        "streaming"
      ];
      mimeTypes = [ "x-scheme-handler/spotify" ];
      startupNotify = true;
      # Upstream retains this app-id for existing desktop/window rules.
      startupWMClass = "fastpotify";
    })
  ];

  meta = {
    description = "Fast, lightweight, native Spotify client built with Rust and egui, playing through librespot";
    homepage = "https://spotifast.rocks/";
    changelog = "https://github.com/crmne/spotifast/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "spotifast";
  };
})
