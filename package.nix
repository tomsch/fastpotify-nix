{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
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
  pname = "fastpotify";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "crmne";
    repo = "fastpotify";
    rev = "v${finalAttrs.version}";
    hash = "sha256-z/g5T2qR7nyBbxeSDEJ8GVRkyrkX/6F6GOLUa7lvgMM=";
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    copyDesktopItems
  ];

  # librespot's rodio audio backend links ALSA and PulseAudio (which covers
  # PipeWire) directly.
  buildInputs = [
    alsa-lib
    libpulseaudio
  ];

  # eframe's glow backend and winit's windowing backends dlopen these at
  # runtime rather than linking them, so they belong on LD_LIBRARY_PATH
  # instead of buildInputs.
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
    wrapProgram $out/bin/fastpotify \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath finalAttrs.runtimeLibs}

    install -Dm644 packaging/macos/icon-1024.png \
      $out/share/icons/hicolor/1024x1024/apps/fastpotify.png
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "fastpotify";
      exec = "fastpotify";
      icon = "fastpotify";
      desktopName = "Fastpotify";
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
      startupWMClass = "fastpotify";
    })
  ];

  meta = {
    description = "Fast, lightweight, native Spotify client built with Rust and egui, playing through librespot";
    homepage = "https://fastpotify.rocks/";
    changelog = "https://github.com/crmne/fastpotify/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "fastpotify";
  };
})
