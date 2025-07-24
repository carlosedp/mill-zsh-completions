# Get the available mill binary or script
function mill_executable() {
  local millexec
  if [[ -x "mill" ]]; then
    millexec="./mill"
  elif [ -x "$(command -v mill)" ] >/dev/null 2>&1; then
    millexec="mill"
  else
    echo "No mill executable found in the current directory or in PATH."
    return 1
  fi
  "$millexec" "$@"
}

# This function gets the current mill version from .mill-version file or the build files
function get_mill_version() {
  # Fast path: .mill-version file
  if [ -f ".mill-version" ]; then
    head -1 .mill-version
    return
  fi

  # Next: build.mill file (avoid grep if possible)
  if [ -f "build.mill" ]; then
    awk '/mill-version/ {print $3; exit}' build.mill | tr -d '"' | grep -q . &&
      awk '/mill-version/ {print $3; exit}' build.mill | tr -d '"' && return
  fi

  # Fallback: mill_executable --version (slow)
  if [ -f "build.sc" ] || [ -f "build.mill" ] || [ -f "build.mill.scala" ]; then
    mill_executable --version 2>/dev/null | awk 'NR==1{print $5; exit}'
    return
  fi

  # Not found
  return 1
}


compare_semver() {
  local v1="$1"
  local v2="$2"

  # Parse version components including optional commit count
  parse_version() {
    local version="$1"
    local major minor patch commit_count

    # Split by first dash to separate base version from commit info
    local base_version="${version%%-*}"
    local commit_info="${version#*-}"

    # If no dash found, commit_info will equal version
    if [ "$commit_info" = "$version" ]; then
      commit_count=0
    else
      # Extract just the first field after dash (commit count)
      commit_count="${commit_info%%-*}"
      # Validate it's a number, default to 0 if not
      case "$commit_count" in
      '' | *[!0-9]*) commit_count=0 ;;
      esac
    fi

    # Parse base version (major.minor.patch)
    IFS='.' read major minor patch <<<"$base_version"

    # Set defaults for missing parts
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}

    echo "$major $minor $patch $commit_count"
  }

  # Parse both versions
  v1_parts=$(parse_version "$v1")
  v2_parts=$(parse_version "$v2")

  read v1_major v1_minor v1_patch v1_commits <<<"$v1_parts"
  read v2_major v2_minor v2_patch v2_commits <<<"$v2_parts"

  # Compare major version
  if [ "$v1_major" -gt "$v2_major" ]; then
    echo "$v1"
    return
  elif [ "$v1_major" -lt "$v2_major" ]; then
    echo "$v2"
    return
  fi

  # Compare minor version
  if [ "$v1_minor" -gt "$v2_minor" ]; then
    echo "$v1"
    return
  elif [ "$v1_minor" -lt "$v2_minor" ]; then
    echo "$v2"
    return
  fi

  # Compare patch version
  if [ "$v1_patch" -gt "$v2_patch" ]; then
    echo "$v1"
    return
  elif [ "$v1_patch" -lt "$v2_patch" ]; then
    echo "$v2"
    return
  fi

  # Compare commit count (only if base versions are equal)
  if [ "$v1_commits" -gt "$v2_commits" ]; then
    echo "$v1"
    return
  elif [ "$v1_commits" -lt "$v2_commits" ]; then
    echo "$v2"
    return
  fi

  # Versions are equal
  echo "$v1"
}

# This function is used by Zsh P10k prompt. To use, add `mill_version` in the `p10k.zsh` file:
#       typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
#       status # already exists
#       ...
#       mill_version
#       ...
#       )
function prompt_mill_version() {
  local millver
  millver=$(get_mill_version)
  if [[ -z "$millver" ]]; then
    # If no mill version is found, do not show anything
    return
  fi
  #If keepMajor is true, functions will only use major versions (no daily builds)
  keepMajorMillVersion=true

  local cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/p10k-${USER}
  mkdir -p "$cache_dir" # just ensuring that it exists
  local cache_file="$cache_dir/latest_mill_version"
  local cache_file_snap="$cache_dir/latest_mill_version_snapshot"

  # Keep cache for 24 hours
  local timeout_in_hours=24
  local timeout_in_seconds=$(($timeout_in_hours * 60 * 60))

  # Get latest version from maven repo if cache is older than timeout
  if [[ ! (-f "$cache_file" && -f "$cache_file_snap" && $(($(date +%s) - $(stat -c '%Y' "$cache_file") < $timeout_in_seconds)) -gt 0) ]]; then
    local latest_mill_version_maven
    latest_mill_version_maven=$(curl -sL https://repo1.maven.org/maven2/com/lihaoyi/mill-libs_3/maven-metadata.xml | grep "<version>" | grep -v "\-M" | tail -1 | sed -e 's/<[^>]*>//g' | tr -d " ")
    echo "$latest_mill_version_maven" >"$cache_file_snap"
    if [ "$keepMajorMillVersion" = true ]; then
      latest_mill_version_maven=$(echo "$latest_mill_version_maven" | cut -d- -f1)
    fi

    if [[ -n "$latest_mill_version_maven" ]]; then
      echo "$latest_mill_version_maven" >"$cache_file"
    else
      touch "$cache_file"
    fi
  fi

  local latest_mill_version
  latest_mill_version=$(<"$cache_file")
  latest_mill_version_snap=$(<"$cache_file_snap")

  if [[ -n "$latest_mill_version" && $millver =~ \d+.\d+.\d+-\d+-.* && "$millver" == "$latest_mill_version_snap" && "$millver" != $(echo "$latest_mill_version" | cut -d- -f1) ]]; then
    # Project uses a snapshot version which is up-to-date, show current version in yellow
    p10k segment -s "UP_TO_DATE" -f yellow -i '' -t "⇡ Mill $millver"
  elif [[ -n "$latest_mill_version" && $millver =~ \d+.\d+.\d+-\d+-.* && "$millver" != "$latest_mill_version_snap" && "$millver" != $(echo "$latest_mill_version" | cut -d- -f1) ]]; then
    # Project uses a snapshot version which is outdated, show current version and latest available snapshot in yellow
    p10k segment -s "NOT_UP_TO_DATE" -f red -i '' -t "⇣ Mill $millver  [$latest_mill_version_snap]"
  elif [[ -n "$latest_mill_version" && "$millver" != "$latest_mill_version" ]]; then
    # Mill is not up to date, show current version and latest version brackets in red
    p10k segment -s "NOT_UP_TO_DATE" -f red -i '' -t "⇣ Mill $millver  [$latest_mill_version]"
  else
    # Mill is up to date, show current version in blue
    p10k segment -s "UP_TO_DATE" -f blue -i '' -t "Mill $millver"
  fi
}

# Update Scala Mill `.mill-version` file with latest build
# Usage: `millupd` or `millupd -s` to update with latest snapshot build
millupd() {
  snapshotBuilds="${1:-true}"
  if [ "$snapshotBuilds" = "-s" ]; then
    keepMajorMillVersion=false
  else
    keepMajorMillVersion=true
  fi
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/p10k-${USER}/millversion/latest_mill_version
  latest_mill_version=$(curl -sL https://repo1.maven.org/maven2/com/lihaoyi/mill-scalalib_2.13/maven-metadata.xml | grep "<version>" | grep -v "\-M" | tail -1 | sed -e 's/<[^>]*>//g' | tr -d " ")
  echo "Latest mill version is $latest_mill_version..."
  if [ "$keepMajorMillVersion" = true ]; then
    latest_mill_version=$(echo "$latest_mill_version" | cut -d- -f1)
    echo "Will stick to major version $latest_mill_version"
  fi
  if [ -f ".mill-version" ]; then
    millver=$(cat .mill-version || echo 'bug')
    if [[ -n "$latest_mill_version" && "$millver" != "$latest_mill_version" ]]; then
      echo "Version differs, currently in $millver... updating .mill-version to $latest_mill_version."
      echo "$latest_mill_version" >.mill-version
    else
      echo "Mill is already up-to-date."
    fi
  else
    echo "No .mill-version file found in the current directory, creating one..."
    echo "$latest_mill_version" >.mill-version
  fi
}
