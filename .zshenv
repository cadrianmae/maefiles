. "$HOME/.cargo/env"

# Dedupe PATH automatically (zsh tied-variable idiom)
typeset -U path PATH fpath FPATH

# Editor — prefer nvim if available, fall back to vim
if command -v nvim >/dev/null 2>&1; then
  export EDITOR='nvim'
  export MANPAGER='nvim +Man!'
else
  export EDITOR='vim'
fi
export VISUAL="$EDITOR"

# Tool homes
export PYENV_ROOT="$HOME/.pyenv"
export NVM_DIR="$HOME/.nvm"
export BUN_INSTALL="$HOME/.bun"
export GOPATH="$HOME/go"

# PATH (earlier = higher priority)
path=(
  "$GOPATH/bin"
  "$BUN_INSTALL/bin"
  "$HOME/.local/bin"
  "$HOME/.claude/bin"
  "/usr/local/cuda-13.0/bin"
  "$HOME/bin"
  "$HOME/.local/share/JetBrains/Toolbox/apps/intellij-idea-ultimate/bin"
  "$PYENV_ROOT/plugins/pyenv-virtualenv/shims"
  "$PYENV_ROOT/shims"
  "$PYENV_ROOT/bin"
  $path
)

# Cuda libraries
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/usr/local/cuda-13.0/lib64"

# Zoxide
export _ZO_ECHO=1
export _ZO_RESOLVE_SYMLINKS=1

# Tool flags
export CHEAT_USE_FZF=true
