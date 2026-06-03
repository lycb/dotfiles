#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_SRC="$DOTFILES_DIR/dotfiles"

# Mapping: source file|target location (pipe-delimited)
FILE_MAP=(
    "config.fish|$HOME/.config/fish/config.fish"
    "config.ghostty|$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    "tmux.conf|$HOME/.tmux.conf"
)

info() { printf "\033[1;34m::\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m::\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m::\033[0m %s\n" "$1"; }

install_brew() {
    if command -v brew &>/dev/null; then
        ok "Homebrew is already installed"
        return
    fi

    info "Homebrew not found, installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ok "Homebrew installed"
}

install_git() {
    if command -v git &>/dev/null; then
        ok "git is already installed: $(git --version)"
        return
    fi

    info "git not found, installing..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install git
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm git
    else
        warn "Could not detect package manager. Please install git manually."
        exit 1
    fi
    ok "git installed: $(git --version)"
}

install_fish() {
    if command -v fish &>/dev/null; then
        ok "fish is already installed: $(fish --version)"
        return
    fi

    info "fish not found, installing..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install fish
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y fish
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y fish
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm fish
    else
        warn "Could not detect package manager. Please install fish manually."
        exit 1
    fi
    ok "fish installed: $(fish --version)"
}

install_tmux() {
    if command -v tmux &>/dev/null; then
        ok "tmux is already installed: $(tmux -V)"
        return
    fi

    info "tmux not found, installing..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install tmux
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y tmux
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y tmux
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm tmux
    else
        warn "Could not detect package manager. Please install tmux manually."
        exit 1
    fi
    ok "tmux installed: $(tmux -V)"
}

install_copilot_cli() {
    if command -v copilot &>/dev/null; then
        ok "Copilot CLI is already installed"
        return
    fi

    read -rp "Install Copilot CLI? (Y/n) " answer
    answer="${answer:-Y}"
    if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
        info "Skipping Copilot CLI installation"
        return
    fi

    info "Installing Copilot CLI..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install copilot-cli
    else
        curl -fsSL https://gh.io/copilot-install | bash
    fi
    ok "Copilot CLI installed"
}

install_pup() {
    if command -v pup &>/dev/null; then
        ok "pup is already installed"
        return
    fi

    read -rp "Install pup? (Y/n) " answer
    answer="${answer:-Y}"
    if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
        info "Skipping pup installation"
        return
    fi

    info "Installing pup..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew tap datadog-labs/pack
        brew install datadog-labs/pack/pup
    else
        git clone https://github.com/DataDog/pup.git && cd pup
        cargo build --release
        cp target/release/pup /usr/local/bin/pup
    fi
    ok "pup installed"
    info "Run \`pup auth login\` to login"
}

backup_and_link() {
    local src="$1" dest="$2"
    local dest_dir
    dest_dir="$(dirname "$dest")"

    # Create parent directory if needed
    if [[ ! -d "$dest_dir" ]]; then
        info "Creating directory: $dest_dir"
        mkdir -p "$dest_dir"
    fi

    # Back up existing file (skip if already a symlink to src)
    if [[ -L "$dest" ]]; then
        local current_target
        current_target="$(readlink "$dest")"
        if [[ "$current_target" == "$src" ]]; then
            ok "Already linked: $dest -> $src"
            return
        fi
        warn "Removing existing symlink: $dest -> $current_target"
        rm "$dest"
    elif [[ -e "$dest" ]]; then
        warn "Backing up: $dest -> ${dest}.bak"
        mv "$dest" "${dest}.bak"
    fi

    ln -s "$src" "$dest"
    ok "Linked: $dest -> $src"
}

main() {
    install_brew
    install_git
    install_fish
    install_tmux
    install_copilot_cli
    install_pup

    # Set fish as default shell
    local fish_path
    fish_path="$(command -v fish)"
    if [[ "$SHELL" != "$fish_path" ]]; then
        info "Setting fish as default shell..."
        if ! grep -qx "$fish_path" /etc/shells; then
            echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
        fi
        chsh -s "$fish_path"
        ok "Default shell set to $fish_path"
    else
        ok "fish is already the default shell"
    fi

    info "Installing dotfiles from $DOTFILES_SRC"
    echo

    for entry in "${FILE_MAP[@]}"; do
        local file="${entry%%|*}"
        local dest="${entry#*|}"
        local src="$DOTFILES_SRC/$file"

        if [[ ! -f "$src" ]]; then
            warn "Source not found, skipping: $src"
            continue
        fi

        backup_and_link "$src" "$dest"
    done

    echo
    ok "Done! Restart your shell or source config to apply changes."
}

main
