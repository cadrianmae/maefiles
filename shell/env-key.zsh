# env-key - load/clear API keys from pass into environment on demand
# Convention: pass path "api/foo" -> env var FOO_API_KEY
# Usage:
#   env-key load api/anthropic    # single entry -> ANTHROPIC_API_KEY
#   env-key load api              # all entries under api/ (dir)
#   env-key load 'api/*'          # same (glob)
#   env-key load '*'              # everything in the store, recursively
#   env-key list                  # show all pass entries + loaded status
#   env-key clear api/anthropic   # unset one
#   env-key clear                 # unset all loaded via env-key
# ---------------------------------------------------------------------------
typeset -gA _ENV_KEY_MAP

_env_key_varname() {
  # NOTE: 'entry' not 'path' — zsh ties $path to $PATH array; shadowing it in
  # a function breaks external commands (pass, gpg) that depend on $PATH.
  local entry="$1"
  local name="${entry##*/}"
  echo "${name:u}_API_KEY"
}

# Expand "api", "api/*", "*", or exact entry into a list of pass paths
_env_key_expand() {
  local arg="$1"
  local store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  local -a files=()
  local f rel

  if [[ "$arg" == "*" ]]; then
    files=( "$store"/**/*.gpg(N) )
  elif [[ "$arg" == */\* ]]; then
    files=( "$store"/${arg%/\*}/*.gpg(N) )
  elif [[ -d "$store/$arg" ]]; then
    files=( "$store/$arg"/*.gpg(N) )
  else
    # exact entry - just echo it if present
    [[ -f "$store/$arg.gpg" ]] && { echo "$arg"; return; }
    return 1
  fi

  for f in "${files[@]}"; do
    rel="${f#$store/}"
    echo "${rel%.gpg}"
  done
}

_env_key_load_one() {
  local entry="$1" var
  var=$(_env_key_varname "$entry")
  if ! pass show "$entry" >/dev/null 2>&1; then
    echo "env-key: pass entry '$entry' not found" >&2
    return 1
  fi
  export "$var"="$(pass show "$entry")"
  _ENV_KEY_MAP[$entry]="$var"
  echo "env-key: loaded \$$var  ($entry)"
}

env-key() {
  local cmd="$1" entry="$2" var p
  case "$cmd" in
    load)
      [[ -z "$entry" ]] && { echo "usage: env-key load <pass-path|dir|glob|*>" >&2; return 1; }
      local -a expanded
      expanded=( ${(f)"$(_env_key_expand "$entry")"} )
      if (( ${#expanded} == 0 )); then
        echo "env-key: no entries matched '$entry'" >&2
        return 1
      fi
      for p in "${expanded[@]}"; do
        _env_key_load_one "$p"
      done
      ;;
    clear)
      if [[ -n "$entry" ]]; then
        var="${_ENV_KEY_MAP[$entry]:-$(_env_key_varname "$entry")}"
        unset "$var"
        unset "_ENV_KEY_MAP[$entry]"
        echo "env-key: cleared \$$var"
      else
        for p v in "${(@kv)_ENV_KEY_MAP}"; do
          unset "$v"
          echo "env-key: cleared \$$v ($p)"
        done
        _ENV_KEY_MAP=()
      fi
      ;;
    list)
      local store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
      local entry rel v marker
      echo "env-key: pass entries (* = loaded in this shell)"
      for entry in "$store"/**/*.gpg(N); do
        rel="${entry#$store/}"
        rel="${rel%.gpg}"
        v=$(_env_key_varname "$rel")
        if [[ -n "${_ENV_KEY_MAP[$rel]}" ]]; then
          marker="*"
        else
          marker=" "
        fi
        printf "  [%s] %-24s -> \$%s\n" "$marker" "$rel" "$v"
      done
      ;;
    *)
      echo "usage: env-key {load|clear|list} [pass-path]" >&2
      return 1
      ;;
  esac
}
