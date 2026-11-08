#!/usr/bin/env bash
# Checks docker/templates.json and the compose files it points to:
# - every stack template points to a compose file that exists
# - every compose file is valid (`docker compose config`)
# - every compose file has a top-level `name:`, unique across templates:
#   local-env uses it to find the template a deployed stack came from
# Run by the pre-commit hook. Needs docker and jq (mise.toml). Works with the
# bash 3.2 of macOS.
set -uo pipefail

templates_file=docker/templates.json
errors=()
# The names found so far, one "name<TAB>stackfile" line each
names=''

if ! version=$(jq -er '.version' "$templates_file" 2>&1); then
  errors+=("$templates_file: $version")
elif [[ $version != 3 ]]; then
  errors+=("$templates_file: \"version\" must be \"3\" (Portainer format)")
fi
count=$(jq '.templates | length' "$templates_file" 2>/dev/null || echo 0)

# One line per stack template: title, then stackfile (empty if missing)
while IFS=$'\t' read -r title stackfile; do
  if [[ -z $stackfile || ! -f $stackfile ]]; then
    errors+=("$title: stackfile \"$stackfile\" doesn't exist")
    continue
  fi

  # Do not replace the variables: local-env sets ${HOST_HOME}, the user sets
  # the others, and a required variable (${NAME:?error}) has no value here
  if ! output=$(docker compose -f "$stackfile" config --no-interpolate --quiet 2>&1); then
    errors+=("$stackfile: $output")
    continue
  fi

  # Without a top-level name, compose names the project after the folder.
  # The file is valid YAML (checked above), so a top-level key is a line that
  # starts with it. Removes a comment, spaces and quotes around the value.
  name=$(sed -nE 's/^name:[[:space:]]*([^#]*).*/\1/p' "$stackfile" | head -n1 |
    sed -E 's/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')
  if [[ -z $name ]]; then
    errors+=("$stackfile: add a top-level name: (unique)")
    continue
  fi
  other=$(printf '%s' "$names" | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }')
  if [[ -n $other ]]; then
    errors+=("$stackfile: name \"$name\" is also used by $other")
  fi
  names+="$name"$'\t'"$stackfile"$'\n'
done < <(jq -r '.templates[]? | select(.type == 3) | [.title, .repository.stackfile // ""] | @tsv' "$templates_file" 2>/dev/null)

if ((${#errors[@]})); then
  printf '✗ %s\n' "${errors[@]}" >&2
  exit 1
fi
echo "✓ $count templates"
