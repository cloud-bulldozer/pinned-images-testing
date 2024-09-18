#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
# Uncomment to enable debugging
set -x


export ocp_version_channel=${OCP_VERSION_CHANNEL:-candidate}
export ocp_version="4.17"
export VERSION="4.17.0-rc.2"
export _es_index=${ES_INDEX:-managedservices-timings}
export control_plane_waiting_iterations=${OCP_CONTROL_PLANE_WAITING:-100}
export waiting_per_worker=${OCP_WORKER_UPGRADE_TIME:-5}
export OCP_CLUSTER_NAME=$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r '.status.infrastructureName | sub("-[^-]+$"; "")')
export UUID="${UUID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
export KUBECONFIG="${PWD}/kubeconfig.yaml"
export ES_SERVER="${ES_SERVER=}"
export _es_index="${ES_INDEX:-}"

ocp_upgrade(){
  if [ ${ocp_version_channel} == "nightly" ] ; then
    echo "ERROR: Invalid channel group. Nightly versions cannot be upgraded. Exiting..."
    exit 1
  fi
  echo "OCP Cluster: ${OCP_CLUSTER_NAME}"
  echo "OCP Channel Group: ${ocp_version_channel}"

  if [ -z ${VERSION} ] ; then
    echo "ERROR: No version to upgrade is given for the cluster ${OCP_CLUSTER_NAME}"
    exit 1
  else
    echo "INFO: Upgrading cluster ${OCP_CLUSTER_NAME} to ${VERSION} version..."
  fi

  echo "INFO: Patching the 4.17 Admin Acks"
  echo "INFO: Check if we need them"
#   oc -n openshift-config patch cm admin-acks --patch '{"data":{"ack-4.12-kube-1.26-api-removals-in-4.13":"true"}}' --type=merge

  echo "INFO: Upgrading to 4.17 ${ocp_version_channel} Channel"
  oc adm upgrade channel ${ocp_version_channel}-${ocp_version}

  echo "INFO: OCP Upgrade to 4.17 kick-started"
  CURRENT_VERSION=$(oc get clusterversion | grep ^version | awk '{print $2}')
  oc adm upgrade --to-image=quay.io/openshift-release-dev/ocp-release@sha256:1bab1d84ec69f8c7bc72ca5e60fda16ea49d42598092b8afd7b50378b6ede8ed --allow-not-recommended=true --allow-explicit-upgrade=true

  ocp_cp_upgrade_active_waiting ${VERSION}
  if [ $? -eq 0 ] ; then
    CONTROLPLANE_UPGRADE_RESULT="OK"
  else
    CONTROLPLANE_UPGRADE_RESULT="Failed"
  fi

  WORKERS_UPGRADE_DURATION="250"
  WORKERS_UPGRADE_RESULT="NA"
  ocp_workers_active_waiting
  if [ $? -eq 0 ] ; then
    WORKERS_UPGRADE_RESULT="OK"
  else
    WORKERS_UPGRADE_RESULT="Failed"
  fi
  ocp_upgrade_index_results ${CONTROLPLANE_UPGRADE_DURATION} ${CONTROLPLANE_UPGRADE_RESULT} ${WORKERS_UPGRADE_DURATION} ${WORKERS_UPGRADE_RESULT} ${CURRENT_VERSION} ${VERSION}
  exit 0
}

ocp_workers_active_waiting() {
  start_time=$(date +%s)
  WORKERS=$(oc get node --no-headers -l node-role.kubernetes.io/workload!="",node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker="" 2>/dev/null | wc -l)
  # Giving waiting_per_worker minutes per worker
  ITERATIONWORKERS=0
  VERSION_STATUS=($(oc get clusterversion | sed -e 1d | awk '{print $2" "$3" "$4}'))
  while [ ${ITERATIONWORKERS} -le $(( ${WORKERS}*${waiting_per_worker} )) ] ; do
    if [ ${VERSION_STATUS[0]} == $1 ] && [ ${VERSION_STATUS[1]} == "True" ] && [ ${VERSION_STATUS[2]} == "False" ]; then
      echo "INFO: Upgrade finished for OCP, continuing..."
      end_time=$(date +%s)
      export WORKERS_UPGRADE_DURATION=$((${end_time} - ${start_time}))
      return 0
    else
      echo "INFO: ${ITERATIONWORKERS}/$(( ${WORKERS}*${waiting_per_worker} ))."
      echo "INFO: Waiting 60 seconds for the next check..."
      ITERATIONWORKERS=$((${ITERATIONWORKERS}+1))
      sleep 60
    fi
  done
  echo "ERROR: ${ITERATIONWORKERS}/$(( ${WORKERS}*${waiting_per_worker} )). Workers upgrade not finished after $(( ${WORKERS}*${waiting_per_worker} )) iterations. Exiting..."
  end_time=$(date +%s)
  export WORKERS_UPGRADE_DURATION=$((${end_time} - ${start_time}))
  return 1
}

ocp_cp_upgrade_active_waiting() {
    # Giving control_plane_waiting_iterations minutes for controlplane upgrade
    start_time=$(date +%s)
    ITERATIONS=0
    while [ ${ITERATIONS} -le ${control_plane_waiting_iterations} ]; do
        VERSION_STATUS=($(oc get clusterversion | sed -e 1d | awk '{print $2" "$3" "$4}'))
        if [ ${VERSION_STATUS[0]} == $1 ] && [ ${VERSION_STATUS[1]} == "True" ] && [ ${VERSION_STATUS[2]} == "False" ]; then
            # Version is upgraded, available=true, progressing=false -> Upgrade finished
            echo "INFO: OCP upgrade to $1 is finished for OCP, now waiting for OCP..."
            end_time=$(date +%s)
            export CONTROLPLANE_UPGRADE_DURATION=$((${end_time} - ${start_time}))
            return 0
        else
            echo "INFO: ${ITERATIONS}/${control_plane_waiting_iterations}. AVAILABLE: ${VERSION_STATUS[1]}, PROGRESSING: ${VERSION_STATUS[2]}. Waiting 60 seconds for the next check..."
            ITERATIONS=$((${ITERATIONS} + 1))
            sleep 60
        fi
    done
    echo "ERROR: ${ITERATIONS}/${control_plane_waiting_iterations}. OCP Version is ${VERSION_STATUS[0]}, not upgraded to $1 after ${control_plane_waiting_iterations} iterations. Exiting..."
    oc get clusterversion
    end_time=$(date +%s)
    export CONTROLPLANE_UPGRADE_DURATION=$((${end_time} - ${start_time}))
    return 1
}

ocp_upgrade_index_results() {
    METADATA=$(grep -v "^#" <<EOF
{
  "uuid": "${UUID}",
  "platform": "OCP",
  "cluster_name": "${OCP_CLUSTER_NAME}",
  "network_type": "$(oc get network cluster -o json 2>/dev/null | jq -r .status.networkType)",
  "controlplane_upgrade_duration": "$1",
  "workers_upgrade_duration": "$3",
  "from_version": "$5",
  "to_version": "$6",
  "controlplane_upgrade_result": "$2",
  "workers_upgrade_result": "$4",
  "master_count": "$(oc get node -l node-role.kubernetes.io/master= --no-headers 2>/dev/null | wc -l)",
  "worker_count": "$(oc get node --no-headers -l node-role.kubernetes.io/infra!="",node-role.kubernetes.io/worker="" 2>/dev/null | wc -l)",
  "infra_count": "$(oc get node -l node-role.kubernetes.io/infra= --no-headers --ignore-not-found 2>/dev/null | wc -l)",
  "total_node_count": "$(oc get nodes 2>/dev/null | wc -l)",
  "ocp_cluster_name": "$(oc get infrastructure.config.openshift.io cluster -o json 2>/dev/null | jq -r .status.infrastructureName)",
  "timestamp": "$(date +%s%3N)",
  "cluster_version": "$5",
  "cluster_major_version": "$(echo $5 | awk -F. '{print $1"."$2}')"
}
EOF
)
    printf "Indexing installation timings to ${ES_SERVER}/${_es_index}"
    echo $METADATA
    # curl -k -sS -X POST -H "Content-type: application/json" ${ES_SERVER}/${_es_index}/_doc -d "${METADATA}" -o /dev/null
    return 0
}

ocp_upgrade
