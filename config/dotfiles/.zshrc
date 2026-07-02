# ~/.zshrc — workspace default
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less

# Zoxide
eval "$(zoxide init zsh)"

# Direnv
eval "$(direnv hook zsh)"

# Prompt
eval "$(starship init zsh)"

# FNM (Node version manager)
if command -v fnm >/dev/null 2>&1; then
  export PATH="/opt/fnm:$PATH"
  eval "$(fnm env --use-on-cd)"
fi

# SDKMAN
export SDKMAN_DIR="/opt/sdkman"
if [ -f "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

# Go
if [ -d /usr/local/go ]; then
  export PATH="/usr/local/go/bin:${GOPATH:-/cache/go}/bin:$PATH"
fi

# Rust
if [ -d /opt/rust/cargo ]; then
  export PATH="/opt/rust/cargo/bin:$PATH"
fi

# Aliases
alias ll='eza -la --git'
alias la='eza -la'
alias lt='eza --tree --level=2'
alias cat='bat --paging=never'
alias g='git'
alias k='kubectl'
alias lg='lazygit'
