#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
# Uncomment to enable debugging
# set -x

# Substitute `<LIST OF IMAGES>` with the content of the images.txt file
cat <<EOL > images.txt
<LIST OF IMAGES>
EOL

while read -r image; do
  crictl images --digests --no-trunc -o json | grep -q "${image}" || echo "${image} not found"
done < <(cat images.txt)

# Get last pulled image time
journalctl -u crio |grep "Pulled image" | grep ocp-v4.0-art-dev@sha256