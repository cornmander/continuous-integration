# Bazel continous integration setup

This workspace contains the setup for the continuous integration
system of Bazel. This setup is based on docker images built by bazel.

Make sure you have a Bazel installed with a recent enough version of
it. Also make sure [gcloud](https://cloud.google.com/sdk/) and
[docker](https://www.docker.com) are correctly configured on your
machine.

The CI system is controlled by a Jenkins instance that is shipped in a
Docker image and run on a dedicated VM. Additional Jenkins slave might
run in that VM in dedicated Docker instances. Each slave is
controlled by the Jenkins instance and might be either Docker
instance (in which case the docker image is built by Bazel, see
`jenkins/BUILD`), GCE virtual machine (in which case the
`gce/vm.sh` should create it and the corresponding `jenkins_node`
should be added to `jenkins/BUILD`) or an actual machine (in which
case the corresponding `jenkins_node` should be created, the firewall
rules adapted, and the setup of the machine documented in that
README.md).

## Deploying to [Google Cloud Registry](https://gcr.io)

Run the `//gcr:deploy` target:
```
bazel run //gcr:deploy
```

## Setting up for local testing

Run the test image with:
```
bazel run //jenkins:test [-- -p port]
```
and it will setup a Jenkins instance without security on port `port`
(8080 by default) and one slave running Ubuntu Wily in Docker. This
should be enough for local testing. To stop the instance, goes to
`http://localhost:8080/safeExit` and this will shutdown cleanly.

You can connect additional instance by modifying the UI to test
for other platforms. This does not enable to test:

  - Synchronization between Gerrit and Github,
  - Adding execution nodes,
  - Interaction with Github or Gerrit.

**Note:** the first build is going to stall for some time while 
building the base images on docker without any output due to
[bazelbuild/bazel#1289](https://github.com/bazelbuild/bazel/issues/1289).

## Running the VM on GCE

We spawn the docker images built by Bazel on servers on GCE in
the `bazel-public` project. A script is available to handle the
VM in GCE: `gce/vm.sh`. It takes one mandatory arguments that is
the command (`create` to create the VMs, `delete` to delete
them and `reimage` to reimage, i.e. to delete then create them).
An optional argument selects which VM to create/delete. By default
it acts on all known VMs.

The following additional set up needs to be performed in the cloud
console to make the project work:

 1. Create a permanent disk `jenkins-volumes` for where the build of
    jenkins are constructed (secrets should be put in its `secrets`
    folder also),
 2. Create a static public IP `ci` for the jenkins front-end,
 3. The following firewall rules should be setted-up:
   - Allow all communication from the internal network (created by
     default),
   - Allow SSH (tcp 22) (created by default),
   - Allow all private network (192.168.0.0/16, 172.16.0.0/12 and
     10.0.0.0/8) to access port 50000 to `jenkins` instance (specify
     the `jenkins` tag). Also allow the public IP `ci` and any
     external slaves you might need to add,
   - Allow HTTP traffic (tcp 80) to `jenkins` tags.


## /volumes/secrets

`/volumes/secrets` on GCE should be filled with the various authentication
token for the CI System: 

 - `boto_config` should be the `.boto` file generated by gcloud login
 - `github_token` should be the GitHub API authentication token
 - `github_trigger_auth_token` should contain an uniq string shared
    between GitHub and Jenkins. A GitHub webhook should be set to use
    the payload url
    `http://ci.bazel.io/job/Github-Trigger/buildWithParameters?token=TOKEN`
    where `TOKEN` is the same string as the content of the
    `github_trigger_auth_token`. This webhook should send its data in
    the `x-www-form-urlencoded` format.
 - `google.oauth.clientid` and `google.oauth.secret` are the client id
    and client secret generated from the
    [Google Developers Console](https://console.developers.google.com)
    (APIs & Auth > Credentials > New Client ID > Web Application,
    authorize `http://ci.bazel.io/securityRealm/finishLogin`).
 - `smtp.auth.username` and `smtp.auth.password` are the SMTP username
    and password. We currently use a jenkins-only identifier to send
    through [SendGrid](https://sendgrid.com).
 - `github_id_rsa` should contain the private key for pushing to
   github for syncing the gerrit repository and the GitHub
   repository. You can generate it by SSH into the jenkins slave and
   typing `ssh-keygen -t rsa -b 4096 -C "noreply@bazel.io"
   -N '' -f /volumes/secrets/github_id_rsa`. You must add the public
   key to the list of deploy keys of all repositories to sync (i.e.,
   for Bazel at `https://github.com/bazelbuild/bazel/settings/keys`).


## Adding the OS X slave

For licensing reasons, the OS X slave has to be set-up manually.

First install [Xcode](https://developer.apple.com/xcode/downloads/)
and [JDK 8](https://jdk8.java.net/download.html). Then create a "ci"
user and just download the `mac/setup_mac.sh` script and run it under
that user (the user should have `sudo` right). This can be
done with a one-liner:

```
curl https://bazel.googlesource.com/continuous-integration/+/master/mac/setup_mac.sh | bash
```

Now the machine should connect automatically to jenkins if the
firewall rule `jenkins` is set to allow the IP address of the machine.

