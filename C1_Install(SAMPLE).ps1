#requires -version 4.0

# PowerShell 4 or up is required to run this script
# This script detects platform and architecture.  It then downloads and installs the relevant Deep Security Agent package

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
   Write-Warning "You are not running as an Administrator. Please try again with admin privileges."
   exit 1
}

$managerUrl="https://app.deepsecurity.trendmicro.com:443/"

$env:LogPath = "$env:appdata\Trend Micro\Deep Security Agent\installer"
New-Item -path $env:LogPath -type directory
Start-Transcript -path "$env:LogPath\dsa_deploy.log" -append

echo "$(Get-Date -format T) - DSA download started"
if ( [intptr]::Size -eq 8 ) { 
   $sourceUrl=-join($managerUrl, "software/agent/Windows/x86_64/agent.msi") }
else {
   $sourceUrl=-join($managerUrl, "software/agent/Windows/i386/agent.msi") }
echo "$(Get-Date -format T) - Download Deep Security Agent Package" $sourceUrl

$ACTIVATIONURL="dsm://agents.deepsecurity.trendmicro.com:443/"

$WebClient = New-Object System.Net.WebClient

# Add agent version control info
$WebClient.Headers.Add("Agent-Version-Control", "on")
$WebClient.QueryString.Add("tenantID", "NNNNN")
$WebClient.QueryString.Add("windowsVersion", (Get-CimInstance Win32_OperatingSystem).Version)
$WebClient.QueryString.Add("windowsProductType", (Get-CimInstance Win32_OperatingSystem).ProductType)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$WebClient.DownloadFile($sourceUrl,  "$env:temp\agent.msi")

if ( (Get-Item "$env:temp\agent.msi").length -eq 0 ) {
    echo "Failed to download the Deep Security Agent. Please check if the package is imported into the Workload Security Manager. "
 exit 1
}
echo "$(Get-Date -format T) - Downloaded File Size:" (Get-Item "$env:temp\agent.msi").length

echo "$(Get-Date -format T) - DSA install started"
echo "$(Get-Date -format T) - Installer Exit Code:" (Start-Process -FilePath msiexec -ArgumentList "/i $env:temp\agent.msi /qn ADDLOCAL=ALL /l*v `"$env:LogPath\dsa_install.log`"" -Wait -PassThru).ExitCode 
echo "$(Get-Date -format T) - DSA activation started"

Start-Sleep -s 50
& $Env:ProgramFiles"\Trend Micro\Deep Security Agent\dsa_control" -r
& $Env:ProgramFiles"\Trend Micro\Deep Security Agent\dsa_control" -a $ACTIVATIONURL "tenantID:TENANTID" "token:TOKEN"
Stop-Transcript
echo "$(Get-Date -format T) - DSA Deployment Finished"
