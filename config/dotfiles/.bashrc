# ~/.bashrc — workspace default
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less

eval "$(zoxide init bash)"
eval "$(direnv hook bash)"
eval "$(starship init bash)"

if command -v fnm >/dev/null 2>&1; then
  export PATH="/opt/fnm:$PATH"
  eval "$(fnm env --use-on-cd)"
fi

export SDKMAN_DIR="/opt/sdkman"
if [ -f "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

if [ -d /usr/local/go ]; then
  export PATH="/usr/local/go/bin:${GOPATH:-/cache/go}/bin:$PATH"
fi

if [ -d /opt/rust/cargo ]; then
  export PATH="/opt/rust/cargo/bin:$PATH"
fi

alias ll='eza -la --git'
alias la='eza -la'
alias cat='bat --paging=never'
alias g='git'
alias k='kubectl'
alias lg='lazygit'
