#!/bin/bash

# Set the hayride directories
HAYRIDE_DIR="$HOME/.hayride"
BIN_DIR="$HAYRIDE_DIR/bin"
COMPOSITIONS_DIR="$HAYRIDE_DIR/compositions"
HAYRIDE_REGISTRY_DIR="$HAYRIDE_DIR/registry/morphs/hayride"
CORE_REGISTRY_DIR="$HAYRIDE_DIR/registry/morphs/hayride-core"
CONFIG_FILE="$HAYRIDE_DIR/config.yaml"

# Create the directories if they don't exist
mkdir -p "$BIN_DIR"
mkdir -p "$COMPOSITIONS_DIR"
mkdir -p "$HAYRIDE_REGISTRY_DIR"
mkdir -p "$CORE_REGISTRY_DIR"

# Write default config.yaml content
cat > "$CONFIG_FILE" <<EOF
version: v0.0.6-alpha
license: alpha
core:
  server:
    bin: "hayride-core:server@0.0.1"
    plugs:
      - hayride-core:cfg@0.0.1
    logging:
      enabled: true
      level: debug
      file: "server.wasm.log"
    http:
      port: 8080
  cli:
    bin: "hayride-core:cli@0.0.1"
    logging:
      enabled: true
      level: debug
      file: "cli.wasm.log"
features:
  ai:
    enabled: false
    bin: "hayride-core:ai-server@0.0.1"
    compose:
      file: "feature-ai.wac"
    logging:
        enabled: true
        level: debug
        file: ""
    websocket:
        port: 8081
    http:
        port: 8082
EOF

# Setup release url and download functions for binaries
release_url() {
  echo "https://github.com/hayride-dev/releases/releases"
}

echo_fexists() {
  [ -f "$1" ] && echo "$1"
}

download_release_from_repo() {
  local version="$1"
  local arch="$2"
  local os_info="$3"
  local tmpdir="$4"
  local postfix="tar.xz"
  local filename="hayride-$version-$arch-$os_info.$postfix"
  local download_file="$tmpdir/$filename"
  local archive_url="$(release_url)/download/$version/$filename"

  curl --progress-bar --show-error --location --fail \
       "$archive_url" --output "$download_file" && echo "$download_file"
}

download_core() {
  local version="$1"
  local tmpdir="$2"
  local postfix="tar.xz"
  local filename="hayride-core.$postfix"
  local download_file="$tmpdir/$filename"
  local archive_url="$(release_url)/download/$version/$filename"

  curl --progress-bar --show-error --location --fail \
       "$archive_url" --output "$download_file" && echo "$download_file"
}

# Download the latest release
get_latest_release() {
  curl --silent "https://api.github.com/repos/hayride-dev/releases/releases/latest" | \
    tr -d '\n' | \
    sed 's/.*tag_name": *"//' | \
    sed 's/".*//'
}
VERSION=$(get_latest_release)
echo "Hayride latest release version: $VERSION"

parse_os_info() {
    local uname_output="$1"
    case "$uname_output" in
        darwin)
            echo "macos"
            ;;
        linux)
            echo "linux-gnu"
            ;;
        *)
            echo "$uname_output"
            ;;
    esac
}

ARCH="$(uname -m)"
OS_INFO="$(parse_os_info "$(uname -s | tr '[:upper:]' '[:lower:]')")"

TMPDIR=$(mktemp -d)
if [ -z "$ARCH" ]; then
  echo "Error: Unable to determine architecture."
  exit 1
fi
if [ -z "$OS_INFO" ]; then
  echo "Error: Unable to determine OS information."
  exit 1
fi

case "$OS_INFO" in
  macos|darwin|linux-gnu)
    ;;
  *)
    echo "Error: Unsupported OS '$OS_INFO'. This installer currently only supports Unix-like systems."
    echo "Visit https://github.com/hayride-dev/releases/releases to download an installer for your OS."
    exit 1
    ;;
esac

DOWNLOAD_FILE=$(download_release_from_repo "$VERSION" "$ARCH" "$OS_INFO" "$TMPDIR")
if [ -z "$DOWNLOAD_FILE" ]; then
  echo "Error: Failed to download the release."
  exit 1
fi

# Extract the downloaded file
tar -xf "$DOWNLOAD_FILE" -C "$BIN_DIR"

# Download the core morphs from the release
CORE_FILE=$(download_core "$VERSION" "$TMPDIR")
if [ -z "$CORE_FILE" ]; then
  echo "Error: Failed to download the core morphs archive."
  exit 1
fi

# Extract core files to a temp directory
TMP_DIR=$(mktemp -d)
tar -xf "$CORE_FILE" -C "$TMP_DIR"

# Add each file in the core directory to the registry with their version
find "$TMP_DIR/core" -type f -name '*.wasm' | while read -r file; do
  # Extract the filename (e.g. server-0.0.1.wasm)
  filename=$(basename "$file")

  # Extract version using semver pattern
  if [[ "$filename" =~ ^([a-zA-Z0-9_-]+)-([0-9]+\.[0-9]+\.[0-9]+)\.wasm$ ]]; then
    base="${BASH_REMATCH[1]}"
    version="${BASH_REMATCH[2]}"

    # Create versioned output directory
    outdir="$CORE_REGISTRY_DIR/$version"
    mkdir -p "$outdir"

    # Move file there
    cp "$file" "$outdir/$base.wasm"
  else
    echo "Warning: Could not extract version from $filename" >&2
  fi
done

# Add each file in the hayride directory to the registry with their version
find "$TMP_DIR/hayride" -type f -name '*.wasm' | while read -r file; do
  # Extract the filename (e.g. server-0.0.1.wasm)
  filename=$(basename "$file")

  # Extract version using semver pattern
  if [[ "$filename" =~ ^([a-zA-Z0-9_-]+)-([0-9]+\.[0-9]+\.[0-9]+)\.wasm$ ]]; then
    base="${BASH_REMATCH[1]}"
    version="${BASH_REMATCH[2]}"

    # Create versioned output directory
    outdir="$HAYRIDE_REGISTRY_DIR/$version"
    mkdir -p "$outdir"

    # Move file there
    cp "$file" "$outdir/$base.wasm"
  else
    echo "Warning: Could not extract version from $filename" >&2
  fi
done

# Add each file in the compositions directory to the compositions directory as is
find "$TMP_DIR/compositions" -type f -name '*.wac' | while read -r file; do
  cp "$file" "$COMPOSITIONS_DIR/"
done

# Clean up
rm -rf "$TMP_DIR"

# Setup hayride binary to Path, using detected shell profile if possible
build_path_str() {
  local profile="$1"

  if [[ $profile =~ \.fish$ ]]; then
    # fish uses a little different syntax to modify the PATH
    cat <<END_FISH_SCRIPT

set -gx HAYRIDE_HOME "$HAYRIDE_DIR"

string match -r ".hayride" "\$PATH" > /dev/null; or set -gx PATH "\$HAYRIDE_HOME/bin" \$PATH
END_FISH_SCRIPT
  else
    # bash and zsh
    cat <<END_BASH_SCRIPT

export HAYRIDE_HOME="$HAYRIDE_DIR"

export PATH="\$HAYRIDE_HOME/bin:\$PATH"
END_BASH_SCRIPT
  fi
}

detect_profile() {
  local shellname="$1"
  local uname="$2"

  if [ -f "$PROFILE" ]; then
    echo "$PROFILE"
    return
  fi

  # try to detect the current shell
  case "$shellname" in
    bash)
      case $uname in
        Darwin)
          echo_fexists "$HOME/.bash_profile" || echo_fexists "$HOME/.bashrc"
        ;;
        *)
          echo_fexists "$HOME/.bashrc" || echo_fexists "$HOME/.bash_profile"
        ;;
      esac
      ;;
    zsh)
      echo "$HOME/.zshrc"
      ;;
    fish)
      echo "$HOME/.config/fish/config.fish"
      ;;
    *)
      # Fall back to checking for profile file existence.
      local profiles
      case $uname in
        Darwin)
          profiles=( .profile .bash_profile .bashrc .zshrc .config/fish/config.fish )
          ;;
        *)
          profiles=( .profile .bashrc .bash_profile .zshrc .config/fish/config.fish )
          ;;
      esac

      for profile in "${profiles[@]}"; do
        echo_fexists "$HOME/$profile" && break
      done
      ;;
  esac
}

detected_profile="$(detect_profile $(basename "/$SHELL") $(uname -s) )"
path_str="$(build_path_str "$detected_profile")"
if [ -z "$detected_profile" ]; then
  echo "Warning: Could not detect profile file. Please add the following to your shell profile manually:"
  echo "$path_str"
else
  if ! command grep -qc 'HAYRIDE_HOME' "$detected_profile"; then
    echo "$path_str" >> "$detected_profile"
    echo "profile $detected_profile updated with HAYRIDE_HOME and PATH, restart your shell or run 'source $detected_profile' to apply changes"
  else
    echo "profile $detected_profile already contains HAYRIDE_HOME and was not updated"
  fi
fi

echo "Hayride installation complete!"
