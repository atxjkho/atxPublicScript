param(
 [string]$gatewayKey
)

# init log setting
$logLoc = "$env:SystemDrive\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\"
if (! (Test-Path($logLoc)))
{
    New-Item -path $logLoc -type directory -Force
}
$logPath = "$logLoc\tracelog.log"
"Start to excute gatewayInstall.ps1. `n" | Out-File $logPath

function nowValue()
{
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

function throwError([string] $msg)
{
	try 
	{
		throw $msg
	} 
	catch 
	{
		$stack = $_.ScriptStackTrace
		traceLog "DMDTTP is failed: $msg`nStack:`n$stack"
	}

	throw $msg
}

function traceLog([string] $msg)
{
    $now = nowValue
    try
    {
        "${now} $msg`n" | Out-File $logPath -Append
    }
    catch
    {
        #ignore any exception during trace
    }

}

function runProcess([string] $process, [string] $arguments)
{
	Write-Verbose "runProcess: $process $arguments"
	
	$errorFile = "$env:tmp\tmp$pid.err"
	$outFile = "$env:tmp\tmp$pid.out"
	"" | Out-File $outFile
	"" | Out-File $errorFile	

	$errVariable = ""

	if ([string]::IsNullOrEmpty($arguments))
	{
		$proc = Start-Process -FilePath $process -Wait -Passthru -NoNewWindow `
			-RedirectStandardError $errorFile -RedirectStandardOutput $outFile -ErrorVariable errVariable
	}
	else
	{
		$proc = Start-Process -FilePath $process -ArgumentList $arguments -Wait -Passthru -NoNewWindow `
			-RedirectStandardError $errorFile -RedirectStandardOutput $outFile -ErrorVariable errVariable
	}
	
	$errContent = [string] (Get-Content -Path $errorFile -Delimiter "!!!DoesNotExist!!!")
	$outContent = [string] (Get-Content -Path $outFile -Delimiter "!!!DoesNotExist!!!")

	Remove-Item $errorFile
	Remove-Item $outFile

	if($proc.ExitCode -ne 0 -or $errVariable -ne "")
	{		
		throwError "Failed to run process: exitCode=$($proc.ExitCode), errVariable=$errVariable, errContent=$errContent, outContent=$outContent."
	}

	traceLog "runProcess: ExitCode=$($proc.ExitCode), output=$outContent"

	if ([string]::IsNullOrEmpty($outContent))
	{
		return $outContent
	}

	return $outContent.Trim()
}

function downloadGateway([string] $url, [string] $gwPath)
{
    try
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ErrorActionPreference = "Stop";
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $gwPath)
        traceLog "Download gateway successfully. Gateway loc: $gwPath"
    }
    catch
    {
        traceLog "Fail to download gateway msi"
        traceLog $_.Exception.ToString()
        throw
    }
}

function installGateway([string] $gwPath)
{
	if ([string]::IsNullOrEmpty($gwPath))
    {
		throwError "Gateway path is not specified"
    }

	if (!(Test-Path -Path $gwPath))
	{
		throwError "Invalid gateway path: $gwPath"
	}
	
	traceLog "Start Gateway installation"
	runProcess "msiexec.exe" "/i gateway.msi INSTALLTYPE=AzureTemplate /quiet /norestart"		
	
	Start-Sleep -Seconds 30	

	traceLog "Installation of gateway is successful"
}

function getRegistryProperty([string] $keyPath, [string] $property)
{
	traceLog "getRegistryProperty: Get $property from $keyPath"
	if (! (Test-Path $keyPath))
	{
		traceLog "getRegistryProperty: $keyPath does not exist"
	}

	$keyReg = Get-Item $keyPath
	if (! ($keyReg.Property -contains $property))
	{
		traceLog "getRegistryProperty: $property does not exist"
		return ""
	}

	return $keyReg.GetValue($property)
}

function Get-InstalledFilePath()
{
	$filePath = getRegistryProperty "hklm:\Software\Microsoft\DataTransfer\DataManagementGateway\ConfigurationManager" "DiacmdPath"
	if ([string]::IsNullOrEmpty($filePath))
	{
		throwError "Get-InstalledFilePath: Cannot find installed File Path"
	}
    traceLog "Gateway installation file: $filePath"

	return $filePath
}

function registerGateway([string] $instanceKey)
{
    traceLog "Register Agent"
	$filePath = Get-InstalledFilePath
	runProcess $filePath "-era 8060"
	runProcess $filePath "-k $instanceKey"
    traceLog "Agent registration is successful!"
}



traceLog "Log file: $logLoc"
$uri = "https://go.microsoft.com/fwlink/?linkid=839822"
traceLog "Gateway download fw link: $uri"
$gwPath= "$PWD\gateway.msi"
traceLog "Gateway download location: $gwPath"


downloadGateway $uri $gwPath
installGateway $gwPath

registerGateway $gatewayKey
