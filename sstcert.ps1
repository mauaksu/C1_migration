cd C:\Temp

certutil.exe -generateSSTFromWU .\rootcerts.sst
$sstFile = (Get-ChildItem -Path .\rootcerts.sst)
$sstFile | Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root
