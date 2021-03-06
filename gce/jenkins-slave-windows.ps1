# This script is executed on every boot. Even though we lack even basic error
# reporting and handling, at least make sure that it is not executed twice.
if (Test-Path "c:\bazel_ci\install_completed.txt") {
  Exit
}

New-Item c:\bazel_ci -type directory
Set-Location c:\bazel_ci

# Install Chocolatey
Invoke-Expression ((New-Object Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))

# Initialize msys
$msysRoot='c:\tools\msys64\'

# Finally initialize and upgrade MSYS2 according to https://msys2.github.io
Write-Host "Initializing MSYS2..."
$msysShell = Join-Path $msysRoot msys2_shell.bat
Start-Process -Wait $msysShell -ArgumentList '-c', exit

$command = 'pacman --noconfirm --needed -Sy bash pacman pacman-mirrors msys2-runtime'
Write-Host "Updating system packages with '$command'..."
Start-Process -Wait $msysShell -ArgumentList '-c', "'$command'"

$command = 'pacman --noconfirm -Su'
Write-Host "Upgrading full system with '$command'..."
Start-Process -Wait $msysShell -ArgumentList '-c', "'$command'"

# Download and install Python
New-Item c:\temp -type directory
(New-Object Net.WebClient).DownloadFile("https://www.python.org/ftp/python/2.7.11/python-2.7.11.amd64.msi",
                                        "c:\temp\python-2.7.11.amd64.msi")
& msiexec /qn TARGETDIR=c:\python_27_amd64\files\ /i c:\temp\python-2.7.11.amd64.msi

[Environment]::SetEnvironmentVariable("Path", $env:Path + ";c:\python_27_amd64\files",
                                      [System.EnvironmentVariableTarget]::Machine)

# Install all the Windows software we need:
#   - JDK, because, Bazel is written in Java
#   - NSSM, because that's the easiest way to create services
#   - Chrome, because the default IE setup is way too crippled by security measures
& choco install nssm -y
& choco install jdk8 -y
& choco install googlechrome -y

# Save the Jenkins slave.jar to a suitable location
Invoke-WebRequest http://jenkins/jnlpJars/slave.jar -OutFile slave.jar

# Install the necessary packages in msys2
$bash_installer=@'
pacman -Syyu --noconfirm
pacman -S --noconfirm git curl gcc zip unzip zlib-devel isl
'@
Write-Output $bash_installer | Out-File -Encoding ascii install.sh
# -l is required so that PATH in bash is set properly
& c:\tools\msys64\usr\bin\bash -l /c/bazel_ci/install.sh

# Find the JDK. The path changes frequently, so hardcoding it is not enough.
$java=Get-ChildItem "c:\Program Files\Java\jdk*" | Select-Object -Index 0 | foreach { $_.FullName }

# Fetch the instance ID from GCE
$webclient=(New-Object Net.WebClient)
$webclient.Headers.Add("Metadata-Flavor", "Google")
$jenkins_node=$webclient.DownloadString("http://metadata/computeMetadata/v1/instance/attributes/jenkins_node")
Write-Output $jenkins_node | Out-File -Encoding ascii jenkins_node.txt

# Replace the host name in the JNLP file, because Jenkins, in its infinite
# wisdom, does not let us change that separately from its external hostname.
$jnlp=((New-Object Net.WebClient).DownloadString("http://jenkins/computer/${jenkins_node}/slave-agent.jnlp"))
$internal_jnlp=$jnlp -replace "http://ci.bazel.io", "http://jenkins"
Write-Output $internal_jnlp | Out-File -Encoding ascii slave-agent.jnlp

# Create the service that runs the Jenkins slave
# We can't execute Java directly because then it mysteriously fails with
# "Sockets error: 10106: create", so we redirect through Powershell
# The path change is needed because Jenkins cannot execute a different git
# binary on different slaves, so we need to simply use "git"
$agent_script=@"
`$env:path="`$env:path;c:\tools\msys64\usr\bin"
cd c:\bazel_ci
# A path name with c:\ in the JNLP URL makes Java hang. I don't know why.
# Jenkins tries to reconnect to the wrong port if the server is restarted.
# -noReconnect makes the agent die, and it is then subsequently restarted by
# Windows because it is a service, and then all is well.
& "$java\bin\java" -jar c:\bazel_ci\slave.jar -jnlpUrl file:///bazel_ci/slave-agent.jnlp -noReconnect
"@
Write-Output $agent_script | Out-File -Encoding ascii agent_script.ps1

& nssm install bazel_ci powershell c:\bazel_ci\agent_script.ps1
& nssm set bazel_ci AppStdout c:\bazel_ci\stdout.log
& nssm set bazel_ci AppStderr c:\bazel_ci\stderr.log
& nssm start bazel_ci

Write-Output "DONE" | Out-File -Encoding ascii "c:\bazel_ci\install_completed.txt"
