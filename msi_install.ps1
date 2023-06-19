param (
    
    [string]$Username,
    [string]$Password,
    [string]$Port,
    [string]$Publickey,
    [string]$InstallDir,
    [string]$PackagePath

)



# Function to write output messages
 function Write-Log {
    param (
        [string]$Message
    )

    $outputMessage = "$Message"
    Write-Output $outputMessage
}



# Function to install an MSI package on the remote Windows device
function InstallMsiPackage {
    param (
        [string]$Username,
        [string]$Password,
        [string]$Port,
        [string]$Publickey,
        [string]$InstallDir,
        [string]$PackagePath
    )
    $timeoutInSeconds = 30
            

    try {
        # Install the MSI package    
        $process=Start-Process  msiexec.exe -Wait -ArgumentList "/i `"$PackagePath`" TARGETDIR=`"$InstallDir`" SVCUSERNAME=`"$Username`" PASSWORD=`"$Password`" PORT=`"$Port`" RMMSSHKEY=`"$Publickey`" /quiet" -NoNewWindow -PassThru


         # Wait for the process to complete or until the timeout is reached
        $process.WaitForExit($timeoutInSeconds * 1000)

        # Check if the process completed within the timeout period
        if ($process.HasExited) {
            # Check the exit code of the MSI installation
            if ($process.ExitCode -eq 0) {
                Write-Log "MSI package installed successfully."
            } else {
                Write-Log "Failed to install the MSI package. Exit code: $($process.ExitCode)"
            }
        } else {
            # The process did not complete within the timeout
            Write-Log "Timeout reached. The installation process did not complete."
        }


    } catch {
        Write-Log "An error occurred during the MSI installation: $_"
    }



}


# Write success messages
Write-Log "Starting installation of MSI package..."

# Install the MSI package
InstallMsiPackage -Username $Username -Password $Password -Port $Port -Publickey $Publickey -InstallDir $InstallDir -PackagePath $PackagePath