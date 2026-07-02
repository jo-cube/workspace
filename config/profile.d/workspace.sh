export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export SDKMAN_DIR="${SDKMAN_DIR:-/opt/sdkman}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-/cache/uv}"
export UV_TOOL_DIR="${UV_TOOL_DIR:-/opt/uv-tools}"
export UV_TOOL_BIN_DIR="${UV_TOOL_BIN_DIR:-/opt/uv-tools/bin}"
export GOPATH="${GOPATH:-/cache/go}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/cache/gradle}"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rust/rustup}"
export CARGO_HOME="${CARGO_HOME:-/opt/rust/cargo}"
export FNM_DIR="${FNM_DIR:-/opt/fnm}"
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-/etc/starship.toml}"

path_prepend() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH" ;; esac
}

path_prepend "$UV_TOOL_BIN_DIR"
path_prepend /usr/local/go/bin
path_prepend "$GOPATH/bin"
path_prepend "$SDKMAN_DIR/candidates/java/current/bin"
path_prepend "$SDKMAN_DIR/candidates/kotlin/current/bin"
path_prepend "$SDKMAN_DIR/candidates/gradle/current/bin"
path_prepend "$CARGO_HOME/bin"
path_prepend "$FNM_DIR/aliases/default/bin"
path_prepend "$FNM_DIR"
export PATH
