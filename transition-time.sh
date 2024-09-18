#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
# Uncomment to enable debugging
set -x


while read -r node; do
  oc get ${node} -o jsonpath='{.spec.node.name} {.status.conditions[?(@.type=="PinnedImageSetsProgressing")].status} {.status.conditions[?(@.type=="PinnedImageSetsProgressing")].lastTransitionTime} {.status.conditions[?(@.type=="PinnedImageSetsProgressing")].message}'
done < <(oc get machineconfignode --no-headers -o name)

