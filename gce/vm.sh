#!/bin/bash
#
# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to easily re-image the various vms on GCE
set -eu

# List of slaves in the following format:
#   GCE-VM-NAME GCE-BASE-IMAGE JENKINS-NODE LOCATION STARTUP-METADATA SETUP-SCRIPTS
# Where
#   GCE-VM-NAME is the VM name on GCE
#   GCE-BASE-IMAGE is the name of the base image in GCE
#                  (see `gcloud compute images list`)
#   JENKINS-NODE is the name of the node in Jenkins
#   LOCATION is the location in GCE (e.g. us-central1-a)
#   STARTUP-METADATA is the metadata argument to gcloud to launch the right
#                    startup script.
#   SETUP-SCRIPTS is a list of shell scripts to adapt the slave. It should
#                create a ci user with its home in /home/ci
#                and ends with writing to /home/ci/node_name the name
#                of the jenkins node.
SLAVES=(
    "ubuntu-14-04-slave ubuntu-14-04 ubuntu_14.04-x86_64-1 us-central1-a startup-script=jenkins-slave.sh ubuntu-14-04-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-15-10-slave https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/ubuntu-1510-wily-v20151026 ubuntu_15.10-x86_64-1 asia-east1-c startup-script=jenkins-slave.sh ubuntu-15-10-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-14-04-slave-2 ubuntu-14-04 ubuntu_14.04-x86_64-2 us-central1-a startup-script=jenkins-slave.sh ubuntu-14-04-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-15-10-slave-2 https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/ubuntu-1510-wily-v20151026 ubuntu_15.10-x86_64-2 asia-east1-c startup-script=jenkins-slave.sh ubuntu-15-10-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-14-04-slave-3 ubuntu-14-04 ubuntu_14.04-x86_64-3 us-east1-c startup-script=jenkins-slave.sh ubuntu-14-04-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-15-10-slave-3 https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/ubuntu-1510-wily-v20151026 ubuntu_15.10-x86_64-3 us-east1-c startup-script=jenkins-slave.sh ubuntu-15-10-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-14-04-slave-4 ubuntu-14-04 ubuntu_14.04-x86_64-4 europe-west1-c startup-script=jenkins-slave.sh ubuntu-14-04-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-15-10-slave-4 https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/ubuntu-1510-wily-v20151026 ubuntu_15.10-x86_64-4 europe-west1-c startup-script=jenkins-slave.sh ubuntu-15-10-slave.sh linux-android.sh cleanup-install.sh"
    "ubuntu-docker-slave-1 https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/ubuntu-1510-wily-v20151026 ubuntu_15.10-x86_64-docker-1 us-east1-c startup-script=jenkins-slave.sh ubuntu-15-10-slave.sh ubuntu-15-10-docker.sh linux-android.sh cleanup-install.sh"
    # Fow Windows, we use a custom image with pre-installed MSVC.
    "windows-slave-1 /bazel-public/windows-server-2012-r2-dc-v20160112-vs2015-cpp-python-msys windows-x86_64-1 europe-west1-c windows-startup-script-ps1=jenkins-slave-windows.ps1"
    "windows-slave-2 /bazel-public/windows-server-2012-r2-dc-v20160112-vs2015-cpp-python-msys windows-x86_64-2 europe-west1-c windows-startup-script-ps1=jenkins-slave-windows.ps1"
)

cd "$(dirname "${BASH_SOURCE[0]}")"

# Test whether $1 is the name of an existing instance on GCE
function test_vm() {
  (( $(gcloud compute instances list "$1" | wc -l) > 1 ))
}

# Create the container engine VM containing the jenkins instance.
function create_master() {
  gcloud compute instances create jenkins --tags jenkins \
         --zone us-central1-a --machine-type n1-standard-4 \
         --image container-vm \
         --metadata-from-file google-container-manifest=jenkins.yml,startup-script=mount-volumes.sh \
         --boot-disk-type pd-ssd --boot-disk-size 40GB \
         --address ci --disk name=jenkins-volumes,device-name=volumes
}

# Wait for a VM $1 in zone $2 to be up and running using ssh.
# This function will wait for at most $3 seconds.
function wait_vm() {
  local vm="$1"
  local zone="$2"
  local timeout="${3-60}"  # Wait for 1 minute maximum by default
  local starttime="$(date +%s)"
  while (( "$(date +%s)" - "$starttime" < "$timeout" )); do
    # gcloud compute ssh forward the return code of the executed command.
    if gcloud compute ssh --zone="$zone" --command /bin/true "$vm" &>/dev/null
    then
      return 0
    fi
  done
  return 1
}

function ssh_command() {
  local TAG="$1"
  local LOCATION="$2"
  local tmpdir="${TMPDIR:-/tmp}"
  local tmp="$(mktemp ${tmpdir%%/}/vm-ssh.XXXXXXXX)"
  trap "rm -f ${tmp}" EXIT
  shift 2
  echo -n >"${tmp}"
  for i in "$@"; do
    if [ -f "$i" ]; then
      cat "$i" >>"${tmp}"
    else
      echo "$i" >>"${tmp}"
    fi
  done
  cat "${tmp}" | gcloud compute ssh --zone="${LOCATION}" \
      --command "cat >/tmp/s.sh; sudo bash /tmp/s.sh; rm /tmp/s.sh" \
      "${TAG}"
  rm -f "${tmp}"
  trap - EXIT
}

# Create a slave named $1 whose image is $2 (see `gcloud compute image list`)
# and whose jenkins node name is $3. The other arguments are a list of setup
# scripts to run as root on instance creation. The `jenkins-slave.sh` script
# will be used as the startup script for the instance.
function create_slave() {
  local TAG="$1"
  local IMAGE="$2"
  local JENKINS_NODE="$3"
  local LOCATION="$4"
  local STARTUP_METADATA="$5"
  shift 5
  gcloud compute instances create "$TAG" \
         --zone "$LOCATION" --machine-type n1-standard-8 \
         --image "$IMAGE" \
         --metadata jenkins_node="$JENKINS_NODE" \
         --metadata-from-file "$STARTUP_METADATA" \
         --boot-disk-type pd-ssd --boot-disk-size 500GB

  case "$TAG" in
    windows-*)  # Windows
      ;;

    *)  # Linux
      wait_vm "$TAG" "$LOCATION"  # Wait a bit for the VM to fully start
      # Create the jenkins user, run additional set-up scripts and mark
      # the install process as finished.
      ssh_command "$TAG" "$LOCATION" \
          "sudo adduser --system --home /home/ci ci" \
          "$@" \
          "su ci -s /bin/bash -c \"echo -n '$JENKINS_NODE' >/home/ci/node_name\""
      ;;
  esac
}

function get_slave_by_name() {
  for i in "${SLAVES[@]}"; do
    if [[ "$i" =~ ^"$1 " ]]; then
      echo "$i"
    fi
  done
}

function create_vm() {
  if [ "$1" = "jenkins" ]; then
    create_master
  else
    local args="$(get_slave_by_name "$1")"
    [ -n "$args" ] || (echo "Unknown vm $1" >&2; exit 1)
    create_slave $args
  fi
}

function action() {
  local action=$1
  shift
  if (( $# == 0 )); then
    $action jenkins
    for i in "${SLAVES[@]}"; do
      $action "${i%% *}"
    done
  else
    for i in "$@"; do
      $action "$i"
    done
  fi
}

function delete_vm() {
  local TAG=$1
  if test_vm $TAG; then
    local location="$(get_slave_by_name "$TAG" | cut -d " " -f 4)"
    gcloud compute instances delete --zone=$location $TAG
  fi
}

command="${1-}"
shift || true

case "${command}" in
  "create")
    action create_vm "$@"
    ;;
  "delete")
    action delete_vm "$@"
    ;;
  "reimage")
    action delete_vm "$@"
    action create_vm "$@"
    ;;
  *)
    echo "Usage: $0 (create|delete|reimage) [vm ... vm]" >&2
    exit 1
    ;;
esac
