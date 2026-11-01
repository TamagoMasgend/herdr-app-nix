{
  lib,
  rustPlatform,
  fetchFromGitHub,
  zig_0_16,
  bash,
  coreutils,
  curl,
  gawk,
  git,
  gnused,
  gnutar,
  gzip,
  libarchive,
  python3,
  versionCheckHook,
  nix-update-script,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr-core";
  version = "0.1.16";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr-core";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-TIOXZswCum0g3qcDK+RDZb9Y7lUu+bx+Oyja4EtKKh4=";
  };

  cargoHash = "sha256-hMkych62liZ+Oe5huM2drN5/6ckpF8AEHH2dyskcivo=";

  # The terminal emulator core is libghostty-vt, driven from Cargo through
  # Zig. Its build fetches packages with `zig build --fetch=all`; this is
  # that download, pinned.
  zigDeps = zig_0_16.fetchDeps {
    inherit (finalAttrs) pname version;
    src = "${finalAttrs.src}/vendor/ghostty";
    fetchAll = true;
    hash = "sha256-G9xbZ/pyQTDIfzG0h++i70a45zpwyYpZMBZfAnoOQw0=";
  };

  nativeBuildInputs = [ zig_0_16 ];

  # Cargo drives Zig through the ghostty-vt build script.
  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigInstall = true;

  postPatch =
    let
      # What the tests expect on the other machine.
      remoteBin = lib.makeBinPath [
        bash
        coreutils
        gawk
        python3
      ];
      # What install.sh calls.
      installerBin = lib.makeBinPath [
        bash
        coreutils
        curl
        gnused
        gnutar
        gzip
      ];
    in
    ''
      # hc downloads, checks and unpacks release builds for the machines it
      # adds. bsdtar unpacks gzip itself; GNU tar would look up gzip on PATH.
      # ssh and the systemd tools stay on PATH: they have to match the host.
      substituteInPlace crates/herdr-core/src/releases.rs \
        --replace-fail 'Command::new("curl")' 'Command::new("${lib.getExe curl}")' \
        --replace-fail 'run("sha256sum"' 'run("${lib.getExe' coreutils "sha256sum"}"' \
        --replace-fail '_ => "tar".into()' '_ => "${lib.getExe' libarchive "bsdtar"}".into()'

      # To set up a machine with the same OS and CPU, hc copies its own binary
      # there. This binary loads its libraries from /nix/store and calls the
      # tools pinned above, so the copy fails on any machine that lacks those
      # store paths. Every machine gets this version's statically linked
      # release build instead, as other CPUs already do.
      substituteInPlace crates/herdr-core/src/machines.rs \
        --replace-fail 'let exe = if there == here {' 'let exe = if false {'

      # The tests use /var/tmp, which the build sandbox lacks.
      for f in crates/herdr-core/{src/platform/systemd.rs,src/remote/tests.rs,src/runtime/tests.rs,tests/common/mod.rs,tests/m1.rs}; do
        substituteInPlace "$f" --replace-fail /var/tmp "$TMPDIR"
      done

      # The fake ssh in the tests gives the other machine PATH=/usr/bin:/bin,
      # which the sandbox lacks.
      substituteInPlace crates/herdr-core/tests/common/mod.rs \
        --replace-fail ':/usr/bin:/bin ' ':${remoteBin} ' \
        --replace-fail 'PATH=/usr/bin:/bin ' 'PATH=${remoteBin} '

      # The installer tests hide installed hc with their own PATH. Keep the
      # curl stub first where used, then supply tools the sandbox lacks.
      substituteInPlace crates/herdr-core/tests/distribution.rs \
        --replace-fail '.env("PATH", "/usr/bin:/bin")' '.env("PATH", "${installerBin}")' \
        --replace-fail 'format!("{}:/usr/bin:/bin", stub.display())' 'format!("{}:${installerBin}", stub.display())'

      # tests/distribution.rs runs this python3 script.
      patchShebangs scripts/manifest
    '';

  preBuild = ''
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    ln -s ${finalAttrs.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
  '';

  # hc tells builds apart by their GNU build id, so a byte-identical copy of
  # the binary counts as the same build. Without one it falls back to the
  # file's identity.
  env.NIX_SET_BUILD_ID = "1";
  # The linker hashes the debug sections into the build id, and those hold Zig
  # cache paths that change from build to build. Dropping them at link time
  # keeps the build id reproducible; stdenv strips them anyway.
  env.NIX_LDFLAGS = "--strip-debug";

  nativeCheckInputs = [
    git
    python3
  ];

  # These install hc on a machine like this one, which now downloads a release,
  # and the sandbox has no network.
  checkFlags = [
    "--skip=a_box_without_hc_gets_this_one_when_you_say_yes"
    "--skip=a_machine_reached_through_any_command_works_like_one_over_ssh"
  ];

  # Upstream CI's settings for slow runners: a test binary aborts after 30 s
  # otherwise, and one test checks a 50 ms timing a loaded builder can miss.
  preCheck = ''
    export HC_TEST_WATCHDOG_S=120
    export HC_TEST_SLOW_RUNNER=1
  '';

  postInstall = ''
    ln -s herdr-core $out/bin/hc
    # The agent skill stub, next to the full manual `hc --skill` prints. The
    # two-level path is what the nixpkgs installAgentSkills hook produces.
    install -Dm644 skills/herdr-core/SKILL.md $out/share/skills/herdr-core/herdr-core/SKILL.md
    install -Dm644 LICENSE crates/herdr-core/THIRD-PARTY-NOTICES -t $out/share/doc/herdr-core
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--custom-dep"
      "zigDeps"
    ];
  };

  meta = {
    description = "Terminals for coding agents that keep running after you leave";
    homepage = "https://herdr.dev/core";
    # The binary also includes libghostty-vt and its dependencies under other
    # free licenses; see share/doc/herdr-core/THIRD-PARTY-NOTICES.
    license = lib.licenses.asl20;
    mainProgram = "hc";
    platforms = lib.platforms.linux;
  };
})
