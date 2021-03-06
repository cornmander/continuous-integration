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

# Configuration for our Jenkins instance
load("@bazel_tools//tools/build_defs/docker:docker.bzl", "docker_build")
load(":jenkins.bzl", "jenkins_node", "jenkins_build", "jenkins_job")
load("//jenkins/jobs:jobs.bzl", "JOBS_SUBSTITUTIONS")

exports_files(glob(["github-jobs*.tpl"]))

#
# Nodes
#

# Physical machines
jenkins_node(
    name = "darwin-x86_64-1",
    labels = [
        "darwin-x86_64",
        "install-bazel",
        "safe",
    ],
    remote_fs = "/Users/ci",
)

jenkins_node(
    name = "darwin-x86_64-2",
    labels = [
        "darwin-x86_64",
        "install-bazel",
        "safe",
    ],
    num_executors = 3,
    preference = 4,
    remote_fs = "/Users/ci",
)

# GCE machines
[jenkins_node(
    name = "windows-x86_64" + ext,
    labels = [
        "windows-x86_64",
        "install-bazel",
        "safe",
    ],
    num_executors = 1,
    preference = 1,
    remote_fs = "c:\\jenkins",
) for ext in [
    "-1",
    "-2",
]]

[jenkins_node(
    name = "ubuntu_14.04-x86_64" + ext,
    labels = [
        "ubuntu_14.04-x86_64",
        "linux-x86_64",
        "install-bazel",
        "safe",
    ],
) for ext in [
    "-1",
    "-2",
    "-3",
    "-4",
]]

jenkins_node(
    name = "ubuntu_15.10-x86_64-docker-1",
    labels = [
        "install-bazel",
        "docker",
    ],
)

# Non-release nodes
[jenkins_node(
    name = "ubuntu_15.10-x86_64" + ext,
    labels = [
        "ubuntu_15.10-x86_64",
        "no-release",
        "install-bazel",
        "safe",
    ],
) for ext in [
    "-1",
    "-2",
    "-3",
    "-4",
]]


jenkins_node(
    name = "ubuntu_15.10-x86_64-staging",
    labels = [
        "ubuntu_15.10-x86_64",
        "no-release",
        "install-bazel",
        "safe",
    ],
)

#
# A deploy slave used for release work and syncing
# our repositories.
#

# A little hack to remove path consideration
DEPLOY_FILES = [
    "hoedown",
    "github_release",
]

genrule(
    name = "deploy-files",
    srcs = ["@%s//file" % f for f in DEPLOY_FILES],
    outs = ["%s.tar.gz" % f for f in DEPLOY_FILES],
    cmd = "\n".join([
        "cp $(location @%s//file) $(location %s.tar.gz)" % (f, f)
        for f in DEPLOY_FILES
    ]),
)

docker_build(
    name = "deploy-base",
    base = "//base:ubuntu-wily-amd64-deploy",
    directory = "/opt/data",
    env = {
        # We have to put those files on some secrets volume.
        "BOTO_CONFIG": "/opt/secrets/boto_config",
        "GITHUB_TOKEN_FILE": "/opt/secrets/github_token",
        "GSUTIL": "/opt/data/gsutil/gsutil",
        "GITHUB_RELEASE": "/opt/data/github-release/github-release",
        "HOEDOWN": "/opt/data/hoedown/hoedown",
        "APT_GPG_KEY_PATH": "/opt/secrets/apt-key.sec.gpg",
        "APT_GPG_KEY_ID_FILE": "/opt/secrets/apt-key.id",
    },
    files = [":deploy-files"],
    volumes = ["/opt/secrets"],
)

docker_build(
    name = "deploy-full",
    base = ":deploy-base",
    directory = "/opt/run",
    files = ["setup-deploy.sh"],
)

jenkins_node(
    name = "deploy",
    base = "deploy-full",
    num_executors = 2,
    visibility = ["//visibility:public"],
)

jenkins_node(
    name = "ubuntu-docker",
    base = "//base:ubuntu-wily-amd64-deploy",
    labels = [
        "linux-x86_64",
        "install-bazel",
        "safe",
    ],
)

# Jenkins job for Gerrit vetting
jenkins_job(
    name = "gerrit-verifier-flow",
    config = "gerrit-verifier-flow.xml.tpl",
    project_url = "https://bazel-review.googlesource.com",
    deps = ["gerrit-verifier-flow.groovy"],
)

#
# Jenkins permissions
#

# Public permissions
PUBLIC_PERMS = [
    "Hudson.Read",  # Read the public dashboard
    "Item.Read",  # Read the result of a build
    "Item.Workspace",  # Read a job workspace
    "View.Read",  # Read views
    "Computer.Connect",  # Connect a new slave, needed by slaves
]

# Permissions for @google.com emails
AUTHENTICATED_PERMS = PUBLIC_PERMS + [
    # Special permissions
    "Item.Build",  # Launch a build
    "Item.Cancel",  # Cancel a build
]

# Permissions for admin users (Beware it is dangerous)
ADMIN_PERMS = AUTHENTICATED_PERMS + [
    "Run.Delete",  # Delete one build's information
    "Run.Update",  # Run one build's information
    "View.Configure",  # Configure views
    "View.Create",  # Create a new view
    "View.Delete",  # Delete existing view
    # Dangerous area: touch to slaves
    "Computer.Disconnect",  # Disconnect a slave, normally never needed
    "Computer.Configure",  # Configure a slave, normally never needed
    "Computer.Delete",  # Delete a slave, almost never needed
    "Computer.Build",  # Build on a slave, needed for debugging
    # Very dangerous area, administer jenkins
    "Hudson.Administer",  # Only used for restarting jenkins.
]

PERMS_TEMPLATE = "<permission>hudson.model.%s:%s</permission>"

#
# Creates the permissions info
#
# This is a config file generated by the build.sh script.
load(":config.bzl", "ADMIN_USERS")

SECURITY_CONFIG = """
  <useSecurity>true</useSecurity>
  <authorizationStrategy class="hudson.security.GlobalMatrixAuthorizationStrategy">
    %s
  </authorizationStrategy>
  <securityRealm class="org.jenkinsci.plugins.googlelogin.GoogleOAuth2SecurityRealm" plugin="google-login@1.1">
    <clientId>##SECRET:google.oauth.clientid##</clientId>
    <clientSecret>##SECRET:google.oauth.secret##</clientSecret>
    <domain>google.com</domain>
  </securityRealm>
""" % "\n".join([
    PERMS_TEMPLATE % (perm, "anonymous")
    for perm in PUBLIC_PERMS
] + [
    PERMS_TEMPLATE % (perm, "authenticated")
    for perm in AUTHENTICATED_PERMS
] + [
    PERMS_TEMPLATE % (perm, user)
    for user in ADMIN_USERS
    for perm in ADMIN_PERMS
])

#
# Finally the Jenkins image
#
jenkins_build(
    name = "jenkins",
    configs = [
        ":jenkins-common-configs",
        ":windows-x86_64-1",
        ":windows-x86_64-2",
        ":darwin-x86_64-1",
        ":darwin-x86_64-2",
        ":ubuntu_14.04-x86_64-1",
        ":ubuntu_14.04-x86_64-2",
        ":ubuntu_14.04-x86_64-3",
        ":ubuntu_14.04-x86_64-4",
        ":ubuntu_15.10-x86_64-1",
        ":ubuntu_15.10-x86_64-2",
        ":ubuntu_15.10-x86_64-3",
        ":ubuntu_15.10-x86_64-4",
        ":ubuntu_15.10-x86_64-docker-1",
        ":deploy",
    ],
    jobs = [
        "//jenkins/jobs",
        ":gerrit-verifier-flow",
    ],
    substitutions = {
        "SECURITY_CONFIG": SECURITY_CONFIG,
        "PUBLIC_JENKINS_URL": "http://ci.bazel.io/",
    } + JOBS_SUBSTITUTIONS,
    visibility = ["//visibility:public"],
)

jenkins_build(
    name = "jenkins-staging",
    configs = [
        ":jenkins-common-configs",
        ":ubuntu_15.10-x86_64-staging",
    ],
    jobs = [
        "//jenkins/jobs:staging-jobs",
    ],
    substitutions = {
        "SECURITY_CONFIG": SECURITY_CONFIG,
        "PUBLIC_JENKINS_URL": "http://ci-staging.bazel.io/",
    } + JOBS_SUBSTITUTIONS,
    visibility = ["//gcr:__pkg__"],
)

#
# A jenkins image for testing purpose
jenkins_build(
    name = "jenkins-test",
    configs = [
        ":jenkins-common-configs",
        ":ubuntu-docker",
        ":deploy",
    ],
    jobs = [
        "//jenkins/jobs:test-jobs",
        ":gerrit-verifier-flow",
    ],
    substitutions = {
        "SECURITY_CONFIG": "<useSecurity>false</useSecurity>",
        "PUBLIC_JENKINS_URL": "##ENV:JENKINS_SERVER##",
    } + JOBS_SUBSTITUTIONS,
)

filegroup(
    name = "jenkins-common-configs",
    srcs = glob(["config/**"]),
)

sh_binary(
    name = "test",
    srcs = ["test-runner.sh"],
    data = [
        ":deploy.docker",
        ":jenkins-test",
        ":ubuntu-docker.docker",
    ],
)
