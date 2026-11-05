# expo-apk-builder

One container image that builds Android APKs for any Expo project on this machine with
`eas build --local`, so no project depends on EAS cloud build credits or a host Android SDK.

## What it is

- **Image `expo-apk-builder:local`:** Eclipse Temurin 17 JDK, Android SDK (platform 36, build
  tools 36.0.0, NDK 27.1.12297006, CMake 3.22.1), Node 24.21.0 and eas-cli 27.3.0, every download
  checksum-pinned. It runs as a non-root `builder` user with your uid, so the APK it writes is yours.
- **Compose file:** one one-shot service per build. Each project gets its own Compose project
  (`<project>-apk`), container (`<project>-apk-build`) and Gradle cache volume
  (`<project>-gradle-cache`), so Dock'n Roll lists the build and can stop it.
- **justfile:** the `image`, `build` and `install` recipes that projects call, and `check`
  (Hadolint, Trivy config, gitleaks, pinned in `mise.toml`) to run before every push.

Extracted from Brasse-Bouillon (benoit-bremaud/brasse-bouillon#2277), its first user.

## Requirements

- Docker 24 or later with BuildKit and the Compose plugin v2.24 or later; [just](https://just.systems);
  [mise](https://mise.jdx.dev) for `just check`.
- The host Java CA bundle `/etc/ssl/certs/java/cacerts` (package `ca-certificates-java`), or set
  `HOST_JAVA_CACERTS`. Gradle trusts the same CAs as the host, a TLS-inspecting proxy included.
- An x86_64 host: the Linux NDK host toolchain ships for x86_64 only.
- Expo auth: `eas login` on the host (read-only mount of `~/.expo/state.json`), or a file
  `~/.config/expo-tokens/<project>` (mode 600) holding `EXPO_TOKEN=...`, which wins when not empty.

## Use it from a project

Clone this repository next to your projects:

```bash
git clone https://github.com/benoit-bremaud/expo-apk-builder ~/Documents/02_personal/expo-apk-builder
```

Then add recipes to the project's `justfile`:

```just
apk_builder := env("EXPO_APK_BUILDER", env("HOME") / "Documents/02_personal/expo-apk-builder/justfile")

apk-local profile="preview":
    just -f {{apk_builder}} build my-app apps/mobile {{profile}}

apk-install profile="preview":
    just -f {{apk_builder}} install com.example.myapp apps/mobile {{profile}}
```

`build <project> <app> [profile]`:

- `project`: a lowercase Compose name (`[a-z0-9][a-z0-9_-]*`), used for the container, the Gradle
  cache and the token file.
- `app`: the Expo app folder, relative to the git checkout root (holds `app.json` or `app.config.*`).
- `profile`: an `eas.json` build profile that produces an APK (`buildType: apk`); default `preview`.

The APK lands in `<app>/build/<profile>.apk`. Add `build/` to the app's `.gitignore`. EAS builds the
working tree, so the recipe refuses a dirty tree. Git worktrees work: the git common directory is
mounted read-only next to the checkout.

The first `build` builds the image (about 15 minutes); later ones reuse it and the Gradle cache.

## Change a version

Every tool version is a build argument in the [Dockerfile](Dockerfile). To move to a new Expo SDK
that needs another NDK or platform, change the `ARG` defaults (and the checksums for Node or the
command-line tools), run `mise x -- just check`, then `just image`. All calling projects pick it up on their
next build; check each of them still builds. Calling projects track this repository's `main`,
they do not pin a commit: a version bump is reviewed here, once, for all of them.

## TLS-inspecting proxy

`just image` passes the proxy CA (default: the Aikido safe-chain one,
`/usr/local/share/ca-certificates/aikido-endpoint-protection.crt`) as a BuildKit secret: it is
trusted during the image build only and never written into an image layer. Override the path with
`APK_BUILD_CA` (one certificate), or set it empty to skip.

## Stop a build

From Dock'n Roll, or `docker stop <project>-apk-build`. Remove a project's Gradle cache with
`docker volume rm <project>-gradle-cache`.
