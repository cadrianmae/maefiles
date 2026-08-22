# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Tmux configuration
ZSH_TMUX_CONFIG="$HOME/.tmux.conf"
# Check if there's an unattached session to connect to
if tmux list-sessions -F "#{session_attached}" 2>/dev/null | grep -q "^0$"; then
  ZSH_TMUX_AUTOCONNECT=true
else
  ZSH_TMUX_AUTOCONNECT=false
fi
ZSH_TMUX_AUTOSTART=false

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  zoxide
  tmux
  vi-mode
  docker
  docker-compose
  zsh-autosuggestions
  # zsh-syntax-highlighting
  fast-syntax-highlighting
  zsh-claude-code-completions
  zsh-autocomplete
)

# Drop plugins whose backing command is absent. Toolbox/distrobox containers
# share $HOME but not the host's packages, so this same .zshrc runs in shells
# where zoxide and tmux do not exist. Filtering preserves array order, which
# matters -- fast-syntax-highlighting and zsh-autocomplete must stay last.
for _p in zoxide tmux; do
  (( $+commands[$_p] )) || plugins=(${plugins:#$_p})
done
unset _p

source $ZSH/oh-my-zsh.sh

# lumae/base16 fix: FSH styles comments fg=black, but base16 themes map
# color0 -> background, making comments invisible. Use a visible grey.
typeset -gA FAST_HIGHLIGHT_STYLES ZSH_HIGHLIGHT_STYLES
FAST_HIGHLIGHT_STYLES[comment]='fg=242'
ZSH_HIGHLIGHT_STYLES[comment]='fg=242'

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# EDITOR/VISUAL/MANPAGER are set in ~/.zshenv (prefer nvim if available).

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
alias zshconfig="nvim ~/.zshrc"
alias ohmyzsh="nvim ~/.oh-my-zsh"

source $HOME/.zsh_aliases
source $HOME/.zsh_functions

export MANWIDTH=$(( $(tput cols) - 4 ))

# PYENV_ROOT and its PATH entries are set in ~/.zshenv.
eval "$(pyenv init - bash)"
eval "$(pyenv virtualenv-init -)"

# autoload -U edit-command-line
# zle -N edit-command-line
# bindkey '^v' edit-command-line
MODE_INDICATOR="%F{blue}■%f"
INSERT_MODE_INDICATOR="%F{green}▼%f"
# Container indicator. podman writes /run/.containerenv with name="<container>";
# toolbox additionally creates /run/.toolboxenv. Resolved once at startup rather
# than per-prompt -- a shell cannot change container mid-life, so a static string
# avoids a subprocess on every redraw. Empty on the host, so the segment vanishes.
_toolbox_segment=""
if [[ -r /run/.containerenv ]]; then
  _toolbox_name=$(sed -n 's/^name="\(.*\)"$/\1/p' /run/.containerenv)
  [[ -z $_toolbox_name ]] && _toolbox_name="container"
  _toolbox_segment="%F{magenta}[${_toolbox_name}]%f "
  unset _toolbox_name
fi

# Override robbyrussell's PROMPT char: green ➜ on success, red ✗ on failure
PROMPT="${_toolbox_segment}%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{✘%} ) %{$fg[cyan]%}%c%{$reset_color%} \$(git_prompt_info)\$(vi_mode_prompt_info) \$(direnv_prompt_info) "
RPROMPT="%F{green}%D{%Y-%m-%d %H:%M:%S}%f \$(direnv_rprompt_info) $RPROMPT"

zstyle ':autocomplete:*' min-input 3
compdef _cheat cheat

# Force file completion for okular
zstyle ':completion:*:*:okular:*' file-patterns '*.{pdf,md,txt,doc}:documents'

# NVM_DIR is set in ~/.zshenv. Loader remains here (defines `nvm` function).
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

alias odino-index='odino index . --model BAAI/bge-small-en-v1.5'

# eza: modern ls with icons + git status. Aliases only bind if installed,
# so this file stays portable to machines without it (coreutils ls remains).
if (( $+commands[eza] )); then
  _eza_base='--icons=auto --group-directories-first --git'
  alias ls="eza ${_eza_base}"
  alias ll="eza ${_eza_base} --long --header"
  alias la="eza ${_eza_base} --long --header --all"
  alias lt="eza ${_eza_base} --tree --level=2"
  alias llt="eza ${_eza_base} --long --tree --level=2"
  unset _eza_base
fi

# maefiles on-demand key model:
#   Secrets live in `pass`, loaded explicitly via `env-key load <path>` or
#   per-project via direnv `.envrc`. No auto-load here.
# Nudge only: if the daily timer flagged stale secrets, warn on shell open.
if [[ -f ~/.cache/yadm-secrets-stale ]]; then
  _stale_count=$(wc -l < ~/.cache/yadm-secrets-stale 2>/dev/null)
  echo "[WARN] ${_stale_count} secret(s) stale. Run: yadm-refresh-secrets"
  unset _stale_count
fi

# Greeting and direnv are host-only; see the plugin filter above for why.
if (( $+commands[fortune] && $+commands[cowsay] && $+commands[lolcat] )); then
  fortune | cowsay -f $(cowsay -l | tail -n +2 | tr ' ' '\n' | shuf -n 1) | lolcat -b
fi
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"

# bun completions
[ -s "/home/cadrianmae/.oh-my-zsh/completions/_bun" ] && source "/home/cadrianmae/.oh-my-zsh/completions/_bun"

# BUN_INSTALL and GOPATH are set in ~/.zshenv.

[ -f "/home/cadrianmae/.ghcup/env" ] && . "/home/cadrianmae/.ghcup/env" # ghcup-env

# Catppuccin Macchiato TTY colours
if tty | grep -q '/dev/tty[0-9]'; then
    printf '\e]P0181926'
    printf '\e]P1ED8796'
    printf '\e]P2A6DA95'
    printf '\e]P3EED49F'
    printf '\e]P48AADF4'
    printf '\e]P5F5BDE6'
    printf '\e]P691D7E3'
    printf '\e]P7CAD3F5'
    printf '\e]P8363A4F'
    printf '\e]P9ED8796'
    printf '\e]PAA6DA95'
    printf '\e]PBEED49F'
    printf '\e]PC8AADF4'
    printf '\e]PDF5BDE6'
    printf '\e]PE91D7E3'
    printf '\e]PFF4DBD6'
    clear
fi

# Ensure proper terminal input handling (convert CR to LF)
stty icrnl
