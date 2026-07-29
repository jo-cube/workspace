[ -r /etc/profile.d/workspace.sh ] && . /etc/profile.d/workspace.sh
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
[ -r "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"
command -v fnm >/dev/null 2>&1 && eval "$(fnm env --use-on-cd)"
