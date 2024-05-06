#!/usr/bin/env sh
# sudo apt install sharutils

dd if=/dev/urandom count=1 2> /dev/null | uuencode -m - | sed -ne 2p | cut -c-12
