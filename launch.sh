#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
DYLD_INSERT_LIBRARIES="$DIR/libmovechannel.dylib" \
  exec "/Applications/dLive Director V2.11 copy.app/Contents/MacOS/dLive Director V2.11"
