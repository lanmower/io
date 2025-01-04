FROM debian:bookworm-slim

LABEL author="https://github.com/aBARICHELLO/godot-ci/graphs/contributors"

USER root
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    git-lfs \
    unzip \
    wget \
    zip \
    adb \
    openjdk-17-jdk-headless \
    rsync \
    wine64 \
    osslsigncode \
    && rm -rf /var/lib/apt/lists/*

# Set the desired Godot version and platform
ARG GODOT_VERSION="4.3"
ARG GODOT_PLATFORM="linux.arm64" # Specify the platform for ARM

# Download Godot

RUN wget https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_${GODOT_PLATFORM}.zip \
    && wget https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
    && unzip Godot_v${GODOT_VERSION}-stable_${GODOT_PLATFORM}.zip \
    && mv Godot_v${GODOT_VERSION}-stable_${GODOT_PLATFORM} /usr/local/bin/godot \
    && unzip Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
    && mkdir -p ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ \
    && mv templates/* ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ \
    && rm -f Godot_v${GODOT_VERSION}-stable_export_templates.tpz Godot_v${GODOT_VERSION}-stable_${GODOT_PLATFORM}.zip

# Set up the Android SDK and related configurations
ENV ANDROID_HOME="/usr/lib/android-sdk"

RUN wget https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip \
    && unzip commandlinetools-linux-*_latest.zip -d cmdline-tools \
    && mv cmdline-tools $ANDROID_HOME/ \
    && rm -f commandlinetools-linux-*_latest.zip

ENV PATH="${ANDROID_HOME}/cmdline-tools/cmdline-tools/bin:${PATH}"

RUN yes | sdkmanager --licenses \
    && sdkmanager "platform-tools" "build-tools;33.0.2" "platforms;android-33" "cmdline-tools;latest" "cmake;3.22.1" "ndk;25.2.9519653"

# Generate Android debug keystore
RUN keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 \
    && mv debug.keystore /root/debug.keystore

# Godot editor settings per minor version
RUN echo '[gd_resource type="EditorSettings" format=3]' > ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo '[resource]' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/java_sdk_path = "/usr/lib/jvm/java-17-openjdk-amd64"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/android_sdk_path = "/usr/lib/android-sdk"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/debug_keystore = "/root/debug.keystore"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/debug_keystore_user = "androiddebugkey"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/debug_keystore_pass = "android"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/force_system_user = false' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/timestamping_authority_url = ""' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/android/shutdown_adb_on_exit = true' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres

# Download and set up rcedit for Windows exports
RUN wget https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-arm64.exe -O /opt/rcedit.exe && \
    echo 'export/windows/rcedit = "/opt/rcedit.exe"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres && \
    echo 'export/windows/wine = "/usr/bin/wine64"' >> ~/.config/godot/editor_settings-${GODOT_VERSION:0:3}.tres

# Run Godot to confirm successful installation
RUN godot -v -e --quit --headless
