#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/hetznercloud/cli"
TOOL_NAME="hcloud"
TOOL_TEST="hcloud version"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

curl_opts=(-fsSL)

# NOTE: You might want to remove this if hcloud is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- |
    sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
  list_github_tags
}

download_release() {
  local version filename url
  version="$1"
  filename="$2"

  url="$GH_REPO/releases/download/v${version}/${TOOL_NAME}-$(get_platform)-$(get_arch).tar.gz"

  echo "* Downloading $TOOL_NAME release $version..."
  curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="$3"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    local tool_cmd
    tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"

    mkdir -p "$install_path"/bin
    cp "$ASDF_DOWNLOAD_PATH"/"$tool_cmd" "$install_path"/bin

    test -x "$install_path/bin/$tool_cmd" || fail "Expected $install_path/bin/$tool_cmd to be executable."

    install_completions "$install_path/bin/$tool_cmd"

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error ocurred while installing $TOOL_NAME $version."
  )
}

install_completions() {
  local binary="$1"

  # bash-completion 2.x+ auto-sources from XDG_DATA_HOME
  if command -v bash >/dev/null 2>&1; then
    local bash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
    if mkdir -p "$bash_dir" 2>/dev/null && "$binary" completion bash >"$bash_dir/$TOOL_NAME" 2>/dev/null; then
      echo "* Bash completion installed: $bash_dir/$TOOL_NAME"
    fi
  fi

  # ~/.zfunc is a common user completion dir; needs fpath entry in .zshrc
  if command -v zsh >/dev/null 2>&1; then
    local zsh_dir="${ZDOTDIR:-$HOME}/.zfunc"
    if mkdir -p "$zsh_dir" 2>/dev/null && "$binary" completion zsh >"$zsh_dir/_$TOOL_NAME" 2>/dev/null; then
      echo "* Zsh completion installed: $zsh_dir/_$TOOL_NAME"
      echo "  Ensure .zshrc contains: fpath=(~/.zfunc \$fpath) && autoload -Uz compinit"
    fi
  fi

  # XDG_CONFIG_HOME/fish/completions is auto-sourced by fish
  if command -v fish >/dev/null 2>&1; then
    local fish_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
    if mkdir -p "$fish_dir" 2>/dev/null && "$binary" completion fish >"$fish_dir/$TOOL_NAME.fish" 2>/dev/null; then
      echo "* Fish completion installed: $fish_dir/$TOOL_NAME.fish"
    fi
  fi
}

get_platform() {
  uname -s | tr '[:upper:]' '[:lower:]'
}

get_arch() {
  local arch
  arch=$(uname -m)
  case $arch in
  "x86_64")
    echo "amd64"
    ;;
  "armv7l" | "armv6l" | "arm")
    echo "arm"
    ;;
  "aarch64" | "arm64")
    echo "arm64"
    ;;
  *)
    fail "Architecture $(uname -m) is not supported by asdf-$TOOL_NAME"
    ;;
  esac
}

extract() {
  local file download_path
  file="$1"
  download_path="$2"
  tar -xzf "$file" -C "$download_path" || fail "Could not extract $file — archive may be corrupt or incomplete"
}
