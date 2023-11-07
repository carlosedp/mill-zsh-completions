
# This function is used by Zsh P10k prompt. To use, add `mill_version` in the `p10k.zsh` file:
#       typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
#       status # already exists
#       ...
#       mill_version
#       ...
#       )
function prompt_mill_version() {
    # local millver
    if [ -f ".mill-version" ] ; then
        millver="$(<.mill-version)"
    else
        # Check if this is a mill project
        if [ -f "build.sc" ] ; then
          millver="$(mill --version | head -1 | cut -d' ' -f5) || echo 'unknown'"
        else
          return
        fi
    fi
    #If keepMajor is true, functions will only use major versions (no daily builds)
    keepMajorMillVersion=true

    local cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/p10k-${(%):-%n}
    mkdir -p "$cache_dir" # just ensuring that it exists
    local cache_file="$cache_dir/latest_mill_version"
    local cache_file_snap="$cache_dir/latest_mill_version_snapshot"

    # Keep cache for 24 hours
    local timeout_in_hours=24
    local timeout_in_seconds=$(($timeout_in_hours*60*60))

    # Get latest version from maven repo if cache is older than timeout
    if [[ ! (-f "$cache_file" && -f "$cache_file_snap" && $(($(date +%s) - $(stat -c '%Y' "$cache_file") < $timeout_in_seconds)) -gt 0) ]]; then
        local latest_mill_version_maven
        latest_mill_version_maven=$(curl -sL https://repo1.maven.org/maven2/com/lihaoyi/mill-scalalib_2.13/maven-metadata.xml | grep "<version>" |grep -v "\-M" |tail -1 |sed -e 's/<[^>]*>//g' |tr -d " ")
        echo "$latest_mill_version_maven" > "$cache_file_snap"
        if [ "$keepMajorMillVersion" = true ]; then
            latest_mill_version_maven=$(echo "$latest_mill_version_maven" | cut -d- -f1)
        fi

        if [[ -n "$latest_mill_version_maven" ]]; then
            echo "$latest_mill_version_maven" > "$cache_file"
        else
            touch "$cache_file"
        fi
    fi

    local latest_mill_version
    latest_mill_version=$(<"$cache_file")
    latest_mill_version_snap=$(<"$cache_file_snap")

    if [[ -n "$latest_mill_version" && $millver == *"-"* && "$millver" == "$latest_mill_version_snap" && "$millver" != $(echo "$latest_mill_version" | cut -d- -f1) ]]
    then
        # Project uses a snapshot version which is up-to-date, show current version in yellow
        p10k segment -s "NOT_UP_TO_DATE" -f yellow -i '' -t "⇡ Mill $millver"
    elif [[ -n "$latest_mill_version" && $millver == *"-"* && "$millver" != "$latest_mill_version_snap" && "$millver" != $(echo "$latest_mill_version" | cut -d- -f1) ]]; then
        # Project uses a snapshot version which is outdated, show current version and latest available snapshot in yellow
        p10k segment -s "UP_TO_DATE" -f yellow -i '' -t "⇣ Mill $millver  [$latest_mill_version_snap]"
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
    if [ "$snapshotBuilds" = "-s" ] ; then
        keepMajorMillVersion=false
    else
        keepMajorMillVersion=true
    fi
    if [ -f ".mill-version" ] ; then
        rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/p10k-${(%):-%n}/millversion/latest_mill_version
        latest_mill_version=$(curl -sL https://repo1.maven.org/maven2/com/lihaoyi/mill-scalalib_2.13/maven-metadata.xml | grep "<version>" |grep -v "\-M" |tail -1 |sed -e 's/<[^>]*>//g' |tr -d " ")
        echo "Latest mill version is $latest_mill_version..."
        if [ "$keepMajorMillVersion" = true ]; then
            latest_mill_version=$(echo "$latest_mill_version" | cut -d- -f1)
            echo "Will stick to major version $latest_mill_version"
        fi
        millver=$(cat .mill-version || echo 'bug')
        if [[ -n "$latest_mill_version" && "$millver" != "$latest_mill_version" ]]; then
            echo "Version differs, currently in $millver... updating .mill-version to $latest_mill_version."
            echo "$latest_mill_version" > .mill-version
        else
            echo "Mill is already up-to-date."
        fi
    else
      return
    fi
}
