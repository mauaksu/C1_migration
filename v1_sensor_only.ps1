# Require PowerShell 5.0 or later

# Set log path
$env:LogPath = "$env:appdata\Trend Micro\V1ES"
New-Item -path $env:LogPath -type directory -Force
Start-Transcript -path "$env:LogPath\v1es_install.log" -append

# Proxy_Addr_Port and Proxy_User/Proxy_Password define proxy for software download and Agent activation
$PROXY_ADDR_PORT="sglab.lab.lan:8080" ## ProxyAddrPort: 10.10.10.2:8080
$PROXY_USERNAME="098783d4-2da6-4714-a6aa-468ef155f7b5;V1ESDeploymentScript;"
$PROXY_PASSWORD="6769879e63fd85fc1824f530c4eb02d1c2ad56c6"

## Pre-Check
# Check authorization
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "$(Get-Date -format T) You are not running as an Administrator. Please try again with admin privileges." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Check if Invoke-WebRequest is available
if (-not (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) {
    Write-Host "$(Get-Date -format T) Invoke-WebRequest is not available. Please install PowerShell 3.0 or later." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Check if Expand-Archive is available
if (-not (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) {
    Write-Host "$(Get-Date -format T) Expand-Archive is not available. Please install PowerShell 5.0 or later." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "$(Get-Date -format T) Start deploying." -ForegroundColor White

# Compose proxy credential and URI
$PROXY_CREDENTIAL=""
$PROXY_URI="http://${PROXY_ADDR_PORT}"
if (-NOT ($PROXY_PASSWORD.Length -eq 0)) {
    $PROXY_CREDENTIAL="${PROXY_USERNAME}:${PROXY_PASSWORD}"
    $PROXY_CREDENTIAL_OBJ = New-Object System.Management.Automation.PSCredential ($PROXY_USERNAME, (ConvertTo-SecureString -String $PROXY_PASSWORD -AsPlainText -Force))
    $CREDENTIAL_ENCODE=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(${PROXY_CREDENTIAL}))
    $PROXY_URI="${CREDENTIAL_ENCODE}@${PROXY_ADDR_PORT}"
} elseif (-NOT ($PROXY_USERNAME.Length -eq 0)) {
    $PROXY_CREDENTIAL="${PROXY_USERNAME}:"
    $PROXY_CREDENTIAL_OBJ = New-Object System.Management.Automation.PSCredential ($PROXY_USERNAME, (new-object System.Security.SecureString))
    $CREDENTIAL_ENCODE=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(${PROXY_CREDENTIAL}))
    $PROXY_URI="${CREDENTIAL_ENCODE}@${PROXY_ADDR_PORT}"
}

## Download XBC installer
$XBC_FQDN="api-eu1.xbc.trendmicro.com"
$GET_INSTALLER_URL="https://$XBC_FQDN/apk/installer"
$XBC_INSTALLER_PATH = "$env:TEMP\XBC_Installer.zip"
$HTTP_BODY='{"company_id":"bada91cb-90e4-474d-90d9-6b5d2f39d9d2","platform":"win32","scenario_ids":["9525d860-ebfd-47a8-8bc3-90479d5b29c6"]}'

Write-Host "$(Get-Date -format T) Start downloading the installer." -ForegroundColor White
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    if ($PROXY_ADDR_PORT.Length -eq 0) {
		$response = Invoke-WebRequest -Uri "$GET_INSTALLER_URL" -Method Post -Body "$HTTP_BODY" -ContentType "application/json" -OutFile "$XBC_INSTALLER_PATH"
	}
	elseif ($PROXY_CREDENTIAL.Length -eq 0) {
		$response = Invoke-WebRequest -Uri "$GET_INSTALLER_URL" -Method Post -Body "$HTTP_BODY" -ContentType "application/json" -Proxy "http://${PROXY_ADDR_PORT}" -OutFile "$XBC_INSTALLER_PATH"
	} 
	else {
		$response = Invoke-WebRequest -Uri "$GET_INSTALLER_URL" -Method Post -Body "$HTTP_BODY" -ContentType "application/json" -Proxy "http://${PROXY_ADDR_PORT}" -ProxyCredential $PROXY_CREDENTIAL_OBJ -OutFile "$XBC_INSTALLER_PATH"
	}
    if ($response.StatusCode -ge 400) {
        Write-Host "$(Get-Date -format T) Failed to download the installer." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
} catch {
    Write-Host "$(Get-Date -format T) Failed to download the installer." -ForegroundColor Red
    Stop-Transcript
    exit 1
}
Write-Host "$(Get-Date -format T) The installer was downloaded to $XBC_INSTALLER_PATH." -ForegroundColor White

## Unzip XBC installer
$XBC_INSTALLER_DIR = "$env:TEMP\XBC_Installer"
Write-Host "$(Get-Date -format T) Start unzipping the installer." -ForegroundColor White
try {
    Expand-Archive -Path $XBC_INSTALLER_PATH -DestinationPath $XBC_INSTALLER_DIR -Force
    Write-Host "$(Get-Date -format T) The installer was unzipped to $XBC_INSTALLER_DIR." -ForegroundColor White
} catch {
    Write-Host "$(Get-Date -format T) Failed to unzip the installer. Error: $_.Exception.Message." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

## Install XBC
$ARCH_TYPE = if ([System.Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
$XBC_INSTALLER_EXE = "$XBC_INSTALLER_DIR\EndpointBasecamp.exe" 
if ( (Get-AuthenticodeSignature "$XBC_INSTALLER_EXE").Status -ne "Valid" ) {
    Write-Host "$(Get-Date -format T) The digital signature of agent is invalid." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$AGENT_TOKEN_WIN64 = "9525d860-ebfd-47a8-8bc3-90479d5b29c6"
$AGENT_TOKEN_WIN32 = "9525d860-ebfd-47a8-8bc3-90479d5b29c6"
Write-Host "$(Get-Date -format T) Start installing the agent." -ForegroundColor White
try {
    if ($PROXY_ADDR_PORT.Length -eq 0) {
        $CONNECT_CONFIG = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"fps":[{"connections": [{"type": "DIRECT_CONNECT"}]}]}'))
    } else {
        $CONNECT_CONFIG = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"fps":[{"connections": [{"type": "USER_INPUT"}]}]}'))
    }

    if ($ARCH_TYPE -eq "x86_64") {
        $XBC_AGENT_TOKEN = $AGENT_TOKEN_WIN64
    } else {
        $XBC_AGENT_TOKEN = $AGENT_TOKEN_WIN32
    }

    if ($PROXY_URI.Length -ne 0) {
		$result = & "$XBC_INSTALLER_EXE" /connection $CONNECT_CONFIG /agent_token $XBC_AGENT_TOKEN /is_full_package true /proxy_server_port $PROXY_URI
	} else {
		$result = & "$XBC_INSTALLER_EXE" /connection $CONNECT_CONFIG /agent_token $XBC_AGENT_TOKEN /is_full_package true
	}
    $exitCode = $LASTEXITCODE
	if ($exitCode -ne 0) {
		Write-Host "$(Get-Date -format T) Failed to install the agent. Error: $result" -ForegroundColor Red
		Stop-Transcript
		exit 1
	}
    Write-Host "$(Get-Date -format T) The agent is installed." -ForegroundColor White
} catch {
    Write-Host "$(Get-Date -format T) Failed to install the agent." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

## Check XBC registration
$XBC_DEVICE_ID = reg query "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\TrendMicro\TMSecurityService"
$RETRY_COUNT = 0
$MAX_RETRY = 30
while ($XBC_DEVICE_ID.Length -eq 0) {
    $RETRY_COUNT++
    if ($RETRY_COUNT -eq $MAX_RETRY) {
        Write-Host "$(Get-Date -format T) The agent registration failed. Please see the EndpointBasecamp.log for more details." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "$(Get-Date -format T) The agent is not registered yet. Please wait 10 seconds." -ForegroundColor White
    Start-Sleep -Seconds 10
    $XBC_DEVICE_ID = reg query "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\TrendMicro\TMSecurityService"
}
Write-Host "$(Get-Date -format T) The agent is registered." -ForegroundColor White

Write-Host "$(Get-Date -format T) Finish deploying." -ForegroundColor White
Stop-Transcript
exit 0
