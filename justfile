# Local Android APK builder for Expo projects. Called from a project's own justfile, e.g.
#   just -f ~/Documents/02_personal/expo-apk-builder/justfile build my-app apps/mobile preview
# Paths are relative to the caller's git checkout (just's invocation directory).

builder := justfile_directory()
compose := builder / "compose.yaml"
image := "expo-apk-builder:local"

# Build the builder image (cached by Docker; the first build takes about 15 min).
image:
    #!/usr/bin/env bash
    set -euo pipefail
    [ "$(id -u)" != 0 ] || { echo "image: run as your user, not root"; exit 1; }
    # The TLS-inspecting proxy CA (Aikido safe-chain); override with APK_BUILD_CA (one certificate:
    # keytool imports only the first of a bundle), empty to skip.
    ca_file="${APK_BUILD_CA-/usr/local/share/ca-certificates/aikido-endpoint-protection.crt}"
    ca=(); if [ -n "$ca_file" ] && [ -f "$ca_file" ]; then ca=(--secret "id=host_ca,src=$ca_file"); fi
    # Plain docker build: compose builds through bake, which refuses a secret outside the context.
    # amd64 only: the Linux NDK host toolchain ships for x86_64 alone (emulated on ARM64 hosts).
    DOCKER_BUILDKIT=1 docker build --platform linux/amd64 "${ca[@]}" --build-arg BUILDER_UID="$(id -u)" -t {{image}} {{quote(builder)}}

# `project` names the Compose project (`<project>-apk`), the container (`<project>-apk-build`),
# the Gradle cache volume and the token file. Expo auth: ~/.config/expo-tokens/<project>
# (EXPO_TOKEN=...) when present, else the host `eas login` session, read-only.
# EAS builds the working tree, so a dirty tree is refused.
# Build <app>/build/<profile>.apk with `eas build --local`
build project app profile="preview": image
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{quote(invocation_directory())}}
    project={{quote(project)}} app={{quote(app)}} profile={{quote(profile)}}
    [[ "$project" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "build: project must be a lowercase Compose name"; exit 1; }
    # A relative path inside the checkout; `:` would break the short volume syntax of compose.yaml.
    [[ "$app" != /* && "$app" != *..* && "$app" != *:* ]] || { echo "build: app must be a relative path inside the checkout"; exit 1; }
    [[ "$profile" =~ ^[A-Za-z0-9._-]+$ && "$profile" != -* ]] || { echo "build: invalid profile name"; exit 1; }
    repo="$(git rev-parse --show-toplevel)"
    [ -f "$repo/$app/app.json" ] || [ -f "$repo/$app/app.config.ts" ] || [ -f "$repo/$app/app.config.js" ] \
      || { echo "build: $app is not an Expo app folder (no app.json or app.config.*)"; exit 1; }
    if [ -n "$(git status --porcelain)" ]; then
      echo "build: working tree not clean, commit or set the changes aside first"; exit 1
    fi
    # Per-project token file only: a global override would hand one project's token to another.
    token="$HOME/.config/expo-tokens/$project"
    if [ -s "$token" ]; then export EXPO_TOKEN_FILE="$token"
    elif [ -f "$HOME/.expo/state.json" ]; then export EXPO_STATE="$HOME/.expo/state.json"; unset EXPO_TOKEN_FILE
    else echo "build: no Expo auth, run eas login or create $token"; exit 1; fi
    export REPO="$repo" APP_DIR="$app" PROJECT="$project" PROFILE="$profile"
    export GITDIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
    mkdir -p "$repo/$app/build"
    name="$project-apk-build"
    # A second run would hit the name conflict and its cleanup `down` would kill the running build.
    if docker container inspect "$name" >/dev/null 2>&1; then
      echo "build: $name already exists (a build is running, or stop it first)"; exit 1
    fi
    dc=(docker compose -p "$project-apk" -f {{quote(compose)}})
    trap '"${dc[@]}" down --remove-orphans >/dev/null 2>&1' EXIT
    "${dc[@]}" run --rm --name "$name" apk-build

# Uninstalls <package> first: an APK signed with another key does not install over it.
# Install <app>/build/<profile>.apk on the USB device
install package app profile="preview":
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{quote(invocation_directory())}}
    app={{quote(app)}} profile={{quote(profile)}}
    apk="$(git rev-parse --show-toplevel)/$app/build/$profile.apk"
    [ -f "$apk" ] || { echo "install: $apk not found, run build first"; exit 1; }
    adb uninstall {{quote(package)}} || true
    adb install "$apk"

# Lint and scan the image recipe and the history (tools pinned in mise.toml): run before every push.
check:
    hadolint --config .hadolint.yaml Dockerfile
    trivy config --exit-code 1 --severity HIGH,CRITICAL --misconfig-scanners dockerfile .
    gitleaks git --redact --no-banner .
