#!/bin/bash

# The update link of the panel, in a terminal as Omarchy updates itself: the engine
# and the map from the latest release, then this plugin from its repository.

set -euo pipefail

repo=alrubearb-sys/peakcast
plugin=io.github.alrubearb-sys.peakcast
export PATH="$HOME/.local/bin:$PATH"

version=$(peakcast outdated)
if [[ -z $version ]]; then
  echo "Peakcast is up to date."
  exit 0
fi

case $(uname -m) in
x86_64) arch=x86_64 ;;
aarch64 | arm64) arch=aarch64 ;;
*)
  echo "There is no Peakcast release for $(uname -m)." >&2
  exit 1
  ;;
esac

# Where the engine already is, so that the new one takes its place. A folder the
# user cannot write belongs to a package, which its package manager updates.
target=$(dirname "$(command -v peakcast)")
if [[ -w $target ]]; then
  name="peakcast-$version-$arch-linux"
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  echo "Downloading Peakcast $version..."
  curl -fsSL "https://github.com/$repo/releases/download/v$version/$name.tar.gz" | tar xz -C "$work"
  # Copied aside and renamed, so that a map still open keeps running the old one.
  for program in peakcast peakcast-map; do
    install -m 755 "$work/$name/$program" "$target/.$program.new"
    mv "$target/.$program.new" "$target/$program"
  done
  echo "Installed Peakcast $version in $target."
else
  echo "Peakcast was installed by a package in $target; update it with your package manager."
fi

if [[ -d $HOME/.config/omarchy/plugins/$plugin/.git ]]; then
  omarchy plugin update "$plugin" --yes
else
  echo "The plugin is not a git checkout; add it again with: omarchy plugin add https://github.com/alrubearb-sys/peakcast-omarchy"
fi

# The link goes once the panel has checked again.
omarchy-shell -q "$plugin" refresh
