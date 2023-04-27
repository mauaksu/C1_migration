cd C:\temp\certs

certutil -syncWithWU .\
[array]$certs = $null

$crtfiles = Get-Item *.crt

foreach ($file in $crtfiles) {
    $certObj = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($file)
    $certs += $certObj
}

$CertStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "\\$($env:COMPUTERNAME)\My", "LocalMachine"

$CertStore.Open('ReadWrite')

foreach ($cert in $certs){$CertStore.Add($cert)}
$CertStore.Close()
