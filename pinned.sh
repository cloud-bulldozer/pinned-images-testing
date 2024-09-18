#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
# Uncomment to enable debugging
set -x

export ocp_version_channel=${OCP_VERSION_CHANNEL:-candidate}
export ocp_version="4.17"
export rel=4.17.0-rc.2
export rel_dir=release-$rel
export tempalte_dir=templates
export processed_dir=processed
export work_dir=$(pwd)

clone_and_install_dittybopper() {
    rm -rf performance-dashboards
    # Clone and install dittybopper
    git clone --depth 1 https://github.com/cloud-bulldozer/performance-dashboards.git
    cd performance-dashboards/dittybopper
    ./deploy.sh
    cd ../..
}

disable_cluster_protections() {
    RESOURCE_NAME="sre-techpreviewnoupgrade-validation" # Enable Alpha features
    API_GROUP="admissionregistration.k8s.io"
    API_RESOURCE="validatingwebhookconfigurations"

    (
        OUTPUT=$(oc get $API_RESOURCE.$API_GROUP/$RESOURCE_NAME -o json)

        if echo "$OUTPUT" | jq '.items' &>/dev/null; then
            echo "Resource found, deleting..."
            oc delete $API_RESOURCE.$API_GROUP/$RESOURCE_NAME
        else
            echo "Resource not found"
        fi
    ) 2>&1 || true # If the subshell exits with a non-zero status (i.e., an error), we'll still continue running the script.
}

oc adm upgrade channel ${ocp_version_channel}-${ocp_version}
rm -rf $rel_dir
rm -f $work_dir/$processed_dir/images.txt
oc adm release extract $rel --to=$rel_dir

# Analize images
cd $rel_dir
# export IMAGES=$(cat image-references | jq -r '.spec.tags[].from.name' | sed 's/^/  - /; s/$/,/' | sed '$ s/,$//')
export IMAGES=$(cat image-references | jq -r '.spec.tags[].from.name' | sed 's/^/  - name: /')
cat image-references | jq -r '.spec.tags[] | "\(.from.name)"' >> $work_dir/$processed_dir/images.txt


# Build pinned images yamls
cd ..
export input="$tempalte_dir/pinned-images.yaml.template"
export output="$processed_dir/pinned-images.yaml"
envsubst <"$input" >"$output"

clone_and_install_dittybopper

disable_cluster_protections

# Enable beta features
oc apply -f featuregate.yaml

# Configuration
RETRY_DELAY=60  # Delay between retries in seconds
MAX_RETRIES=5
COMMAND="oc apply -f $processed_dir/pinned-images.yaml --dry-run=server --validate"
continue="false"
retry_count=0

# Retry loop
while [[ "$continue" != "true" && $retry_count -lt $MAX_RETRIES ]]; do
    # Validate Pinned image set
    if $COMMAND; then
        continue="true"
    else
        retry_count=$((retry_count + 1))
        echo "Command failed with exit code $?. Retrying ($retry_count/$MAX_RETRIES) in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
    fi
done

if [[ $retry_count -eq $MAX_RETRIES ]]; then
    echo "Max retry count reached"
    exit 1
fi

# Apply Pinned image set
date --rfc-3339=seconds
oc apply -f $output

# oc get PinnedImageSet -o wide
oc project openshift-machine-config-operator
oc get pinnedimageset -o wide --all-namespaces
oc get all
oc get machineconfigpool -o wide

sleep 60
completed1="False"
skip1="False"
completed2="False"
skip2="False"
while [[ "$completed1" != "True" && "$completed2" != "True" ]]; do
    completed1=$(oc get machineconfigpool master -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}')
    completed2=$(oc get machineconfigpool worker -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}')
    if [[ $completed1 = "True" && "$skip1" = "False" ]]; then
        lasttransitiontime1=$(oc get machineconfigpool master -o jsonpath='{.status.conditions[?(@.type=="Updated")].lastTransitionTime}')
        echo "Master Completion at: $lasttransitiontime1"
        skip1="True"
    fi
    if [[ $completed2 = "True" && "$skip2" = "False" ]]; then
        lasttransitiontime2=$(oc get machineconfigpool worker -o jsonpath='{.status.conditions[?(@.type=="Updated")].lastTransitionTime}')
        echo "Worker Completion at: $lasttransitiontime2"
        skip2="True"
    fi
    if [[ "$skip1" = "False" || "$skip2" = "False" ]]; then
        echo "Sleeping for 60 seconds..."
        sleep 60
    fi
done


## Login into etcd pod to disable feature gate
# oc -n openshift-etcd rsh $(oc -n openshift-etcd get pod --no-headers -o Name | grep etcd-ip | head -n 1)

## Get the value
# etcdctl get /kubernetes.io/config.openshift.io/featuregates/cluster

## Edit and set the value, upgrade generation remove spec
# etcdctl put /kubernetes.io/config.openshift.io/featuregates/cluster '{"apiVersion":"config.openshift.io/v1","kind":"FeatureGate","metadata":{"annotations":{"include.release.openshift.io/ibm-cloud-managed":"true","include.release.openshift.io/self-managed-high-availability":"true","include.release.openshift.io/single-node-developer":"true","release.openshift.io/create-only":"true"},"creationTimestamp":"2023-02-15T14:42:26Z","generation":3,"managedFields":[{"apiVersion":"config.openshift.io/v1","fieldsType":"FieldsV1","fieldsV1":{"f:metadata":{"f:annotations":{".":{},"f:include.release.openshift.io/ibm-cloud-managed":{},"f:include.release.openshift.io/self-managed-high-availability":{},"f:include.release.openshift.io/single-node-developer":{},"f:release.openshift.io/create-only":{}}},"f:spec":{}},"manager":"cluster-version-operator","operation":"Update","time":"2023-02-15T14:42:26Z"},{"apiVersion":"config.openshift.io/v1","fieldsType":"FieldsV1","fieldsV1":{"f:spec":{"f:featureSet":{}}},"manager":"kubectl-patch","operation":"Update","time":"2023-02-15T16:21:37Z"}],"name":"cluster","uid":"5db70a17-59ee-49c4-ae5e-8867214957c0"},"spec": {}}'

## Check
# oc get featuregate -o yaml

## Wait for machineconfigpools to get upgraded
# oc get machineconfigpool -o wide -w

