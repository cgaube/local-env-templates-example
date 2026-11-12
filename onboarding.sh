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
# It installs Homebrew when it is missing, checks Docker and installs
# local-env, then `local-env onboard` sets it up, adds your source, starts it
# and asks the employee for their profile. Run it again at any time: each
# step skips what is already done, so after a fix (start Docker, log in to
# GitHub) it goes on from where it stopped.
#
# The guide: https://cgaube.github.io/local-env/write-a-source/onboard-your-team

# ---- Your company's values --------------------------------------------------

# The git repo of your source: this repo
SOURCE_URL="https://github.com/cgaube/local-env-templates-example"

# The domain of the local apps (https://<app>.dev.test). Set on the first
# run only: an employee who changed it later keeps theirs.
DOMAIN="dev.test"

# The profile to install, by name (backend). Empty: the employee picks one.
PROFILE=""

# A Homebrew cask that installs your Docker engine when `docker` is missing
# (orbstack, docker-desktop…). Empty: the script asks the employee to install
# one.
DOCKER_CASK=""

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

ensure_docker() {
  step 'Docker'
  if ! command -v docker >/dev/null && [ -n "$DOCKER_CASK" ]; then
    brew install --cask "$DOCKER_CASK"
    fail "Open ${DOCKER_CASK} once, so that it starts the Docker engine."
  fi
  command -v docker >/dev/null ||
    fail 'Install a Docker engine (OrbStack, Docker Desktop, Colima…).'
  # shellcheck disable=SC2016 # the command, as text
  docker compose version >/dev/null 2>&1 ||
    fail 'local-env needs Docker Compose v2 (`docker compose`).'
  docker info >/dev/null 2>&1 || fail 'Start your Docker engine.'
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
  # source, start, then the profile (asked when PROFILE is empty, the first
  # time only). It asks for your password for the DNS and the certificate,
  # and a private repo asks for your git login.
  local args=("$SOURCE_URL" --domain "$DOMAIN")
  if [ -n "$PROFILE" ]; then args+=(--profile "$PROFILE"); fi
  ask local-env onboard "${args[@]}"

  echo 'Open a new terminal, so that it finds brew and local-env.'
}

main "$@"
