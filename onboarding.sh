#!/bin/bash
# Onboards a new employee: copy this file with the rest of the template, set
# the values below, and serve it where a new Mac can download it (your
# intranet, GitHub Pages, the raw URL of a public repo). The employee then
# runs, in a terminal:
#
#   /bin/bash -c "$(curl -fsSL https://example.com/local-env/onboarding.sh)"
#
# `curl -fsSL https://example.com/local-env/onboarding.sh | bash` works too.
#
# It installs Homebrew and Docker (Colima) when they are missing, and
# local-env, then `local-env onboard` sets it up, adds your source, starts
# it and asks the employee for their profile. Run it again at any
# time: each step skips what is already done, so after a fix (start Docker,
# log in to GitHub) it goes on from where it stopped.
#
# The guide: https://cgaube.github.io/local-env/write-a-source/onboard-your-team

# ---- Your company's values --------------------------------------------------

# Defaults: a script that sets one of them before running this one wins.

# The git repo of your source: this repo
LOCAL_ENV_SOURCE_URL="${LOCAL_ENV_SOURCE_URL:-https://github.com/cgaube/local-env-templates-example}"

# The domain of the local apps (https://<app>.dev.test). Set on the first
# run only: an employee who changed it later keeps theirs.
LOCAL_ENV_DOMAIN="${LOCAL_ENV_DOMAIN:-dev.test}"

# The profile to install, by name (backend). Empty: the employee picks one.
LOCAL_ENV_PROFILE="${LOCAL_ENV_PROFILE:-}"

# ------------------------------------------------------------------------------

# Everything is in functions, run by the last line: a download cut in the
# middle runs nothing.

set -euo pipefail

bold=$'\033[1m' dim=$'\033[2m' green=$'\033[32m' red=$'\033[31m' reset=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$reset"; }
ok() { printf '%s✓%s %s\n' "$green" "$reset" "$1"; }
fail() {
  printf '\n%s✗ %s%s\n' "$red" "$1" "$reset" >&2
  printf '%sFix it, then run this script again.%s\n' "$dim" "$reset" >&2
  exit 1
}

# With `curl … | bash`, the standard input is the script itself: the commands
# that ask questions read the terminal instead. Its own device (/dev/ttys003),
# not /dev/tty: macOS can't watch /dev/tty with kqueue, which local-env needs.
terminal="/dev/$(ps -o tty= -p $$ | tr -d ' ')"
ask() {
  if [ -t 0 ]; then
    "$@"
  else
    "$@" <"$terminal"
  fi
}

check_machine() {
  [ "$(uname -s)" = Darwin ] || fail 'local-env runs on macOS only.'
  [ "$(uname -m)" = arm64 ] || fail 'local-env needs a Mac with Apple Silicon.'
  # Without a terminal, the questions can't be asked
  [ -t 0 ] || [ -r "$terminal" ] || fail 'Run this script in a terminal.'
}

ensure_brew() {
  step 'Homebrew'
  # Installed, but not in the PATH of this shell
  if ! command -v brew >/dev/null && [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if command -v brew >/dev/null; then
    ok 'Homebrew installed'
    return
  fi
  echo 'Installing Homebrew. It may ask for your password, and to press Enter.'
  echo 'It needs an administrator account, and can take a few minutes.'
  ask /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # This shell, then the next ones, as the installer says
  eval "$(/opt/homebrew/bin/brew shellenv)"
  # shellcheck disable=SC2016 # written as is, run by the next shells
  local line='eval "$(/opt/homebrew/bin/brew shellenv)"'
  grep -qsF "$line" "$HOME/.zprofile" || printf '\n%s\n' "$line" >>"$HOME/.zprofile"
  ok 'Homebrew installed'
}

# Homebrew's docker CLI finds its plugins (Compose, Buildx) in Homebrew's
# folder once its config lists it, as `brew info docker-compose` says
use_homebrew_plugins() {
  local config="$HOME/.docker/config.json" dirs
  dirs="[\"$(brew --prefix)/lib/docker/cli-plugins\"]"
  mkdir -p "$HOME/.docker"
  # plutil keeps the other settings, but can't edit an empty file
  if [ ! -s "$config" ]; then
    echo "{\"cliPluginsExtraDirs\": $dirs}" >"$config"
  elif ! plutil -extract cliPluginsExtraDirs json -o - "$config" &>/dev/null
  then
    plutil -insert cliPluginsExtraDirs -json "$dirs" "$config"
  fi
}

# A Docker engine that runs is kept: to use another engine than Colima,
# install and start it before this script. Otherwise, Colima: installed with
# Homebrew's docker CLI, Compose and Buildx, then started.
ensure_docker() {
  step 'Docker'
  if ! docker info >/dev/null 2>&1; then
    command -v colima >/dev/null ||
      brew install colima docker docker-compose docker-buildx
    docker compose version &>/dev/null || use_homebrew_plugins
    colima start
  fi
  # shellcheck disable=SC2016 # the command, as text
  docker compose version >/dev/null 2>&1 ||
    fail 'local-env needs Docker Compose v2 (`docker compose`).'
  ok 'Docker running'
}

install_local_env() {
  step 'local-env'
  # An older version may not have `local-env onboard`
  if command -v local-env >/dev/null; then
    brew upgrade cgaube/tap/local-env
  else
    brew install cgaube/tap/local-env
  fi
}

main() {
  check_machine
  ensure_brew
  ensure_docker
  install_local_env

  # local-env does the rest: setup (the domain on the first run only), your
  # source, start, then the profile (asked when LOCAL_ENV_PROFILE is empty,
  # the first time only). It asks for your password for the DNS and the
  # certificate, and a private repo asks for your git login.
  local args=("$LOCAL_ENV_SOURCE_URL" --domain "$LOCAL_ENV_DOMAIN")
  if [ -n "$LOCAL_ENV_PROFILE" ]; then
    args+=(--profile "$LOCAL_ENV_PROFILE")
  fi
  ask local-env onboard "${args[@]}"

  echo 'Open a new terminal, so that it finds brew and local-env.'
}

main "$@"
