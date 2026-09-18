#!/bin/zsh
# Run TypeVoice with TYPEVOICE_DEBUG=1 and pipe stdout here to get per-stage medians.
#   TYPEVOICE_DEBUG=1 build/TypeVoice.app/Contents/MacOS/TypeVoice | Tools/latency.sh
awk -F'[= ]' '/^stage=/{ v[$2]=v[$2] " " $4 } END {
  for (s in v) { n=split(v[s], a, " "); asort(a); printf "%-28s n=%-3d median=%6.1fms  max=%6.1fms\n", s, n, a[int((n+1)/2)], a[n] }
}' | sort
