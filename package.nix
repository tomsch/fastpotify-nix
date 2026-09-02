{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchgit,
  pkg-config,
  cmake,
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

let
  projectmRsSource = fetchgit {
    url = "https://github.com/crmne/projectm-rs";
    rev = "d07af37a41736e1383d5b3d81b93c6352003d901";
    fetchSubmodules = true;
    hash = "sha256-sgI6IOCpQUvdc5acQ1wjCM5mhfz2EPZmoeuyNLGB5UI=";
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "fastpotify";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "crmne";
    repo = "fastpotify";
    rev = "v${finalAttrs.version}";
    hash = "sha256-mXpmzF3GDttcF6d/3vyTyc2kBC1bTFOhnKI6qGBJG2c=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "librespot-audio-0.8.0" = "sha256-RtuFuHywWn5sdAMjjAyv8d3n/pEol6F28HGjdTtWixM=";
      "projectm-sys-1.2.3" = "sha256-682V6R+h9ywkrP81jf8zEivi7chtQT7iK9HNdiuqDZc=";
    };
  };

  # importCargoLock fetches git dependencies without submodules. Restore the
  # exact projectM tree pinned by projectm-rs before Cargo builds projectm-sys.
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

    rm -rf "$projectmVendorDir/libprojectM"
    cp -r ${projectmRsSource}/projectm-sys/libprojectM \
      "$projectmVendorDir/libprojectM"
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
  ];

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
