# Project log

Operational logbook of expo-apk-builder, most recent first; releases and code history live in git.

## 2026-11-05

- Repository created from the Brasse-Bouillon local APK builder (benoit-bremaud/brasse-bouillon#2277,
  PR #2298): app folder, profile, Compose project and Gradle cache volume parametrised; SDK, NDK and
  CMake versions turned into build arguments. Owner decision (MCDA 415/500 against 385 for keeping
  it inside Brasse-Bouillon and 315 for a per-project skill template): a dedicated shared repository.
