# syntax=docker/dockerfile:1
# Android APK builder for any Expo project (`just build`, see README): runs `eas build --local`
# in its own environment (JDK 17, Android SDK, NDK, Node, eas-cli) instead of on the host.
# The SDK, NDK and tool versions are build arguments: override them when an Expo SDK needs others.
# Build-time downloads trust the host CA (TLS-inspecting proxy) through a BuildKit secret, combined
# into a temporary CA bundle and Java trust store per RUN: the CA is never added to the image's trust store.
FROM eclipse-temurin:25-jdk-noble@sha256:95e350ad1eb738f943e141640f7e3d797e483359a3b33c3864255bfd1ad71f8a

ARG NODE_VERSION=24.21.0
ARG NODE_SHA256=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
ARG CMDLINE_TOOLS=13114758
ARG CMDLINE_TOOLS_SHA256=7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee
ARG EAS_CLI_VERSION=27.3.0
ARG ANDROID_PLATFORM=android-36
ARG BUILD_TOOLS=36.0.0
ARG NDK_VERSION=27.1.12297006
ARG CMAKE_VERSION=3.22.1
# Same uid as the host user, so the bind-mounted repo and build/ output are owned by them.
ARG BUILDER_UID=1000

ENV ANDROID_HOME=/opt/android-sdk \
    PATH=/opt/node/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Ubuntu packages track the noble archive; pinning their versions would break on every point release.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN --mount=type=secret,id=host_ca,required=false \
    cat /etc/ssl/certs/ca-certificates.crt /run/secrets/host_ca > /tmp/ca.pem 2>/dev/null || true; \
    export CURL_CA_BUNDLE=/tmp/ca.pem NODE_EXTRA_CA_CERTS=/run/secrets/host_ca \
    JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStore=/tmp/cacerts -XX:-UsePerfData" \
 && cp "$JAVA_HOME/lib/security/cacerts" /tmp/cacerts \
 && if [ -s /run/secrets/host_ca ]; then \
      keytool -importcert -noprompt -alias host-ca -file /run/secrets/host_ca -keystore /tmp/cacerts -storepass changeit > /dev/null; \
    fi \
 && curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/node && tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1 && rm /tmp/node.tar.xz \
 && curl -fsSL -o /tmp/tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" \
 && echo "${CMDLINE_TOOLS_SHA256}  /tmp/tools.zip" | sha256sum -c - \
 && mkdir -p "$ANDROID_HOME/cmdline-tools" && unzip -q /tmp/tools.zip -d /tmp/tools \
 && mv /tmp/tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" && rm -rf /tmp/tools /tmp/tools.zip \
 && { yes || true; } | sdkmanager --licenses > /dev/null \
 && sdkmanager --install "platforms;${ANDROID_PLATFORM}" "build-tools;${BUILD_TOOLS}" "ndk;${NDK_VERSION}" "cmake;${CMAKE_VERSION}" "platform-tools" \
 && npm install -g --ignore-scripts "eas-cli@${EAS_CLI_VERSION}" \
 && { userdel --remove ubuntu 2>/dev/null || true; } \
 && useradd --create-home --uid "${BUILDER_UID}" builder \
 && chown -R builder:builder "$ANDROID_HOME" \
 && rm -rf /tmp/ca.pem /tmp/cacerts /tmp/node-compile-cache

USER ${BUILDER_UID}
WORKDIR /home/builder
# Created as the builder: the Gradle cache volume inherits this ownership, and the state.json
# bind mount does not leave a root-owned ~/.expo behind.
RUN mkdir -p /home/builder/.gradle /home/builder/.expo

# One-shot build container, not a service: nothing to probe.
HEALTHCHECK NONE

ENTRYPOINT ["eas"]
