param(
    [string]$softwareListPath,
    [switch]$upgrade, 
    [switch]$uninstallChocoIfInstalledByScript
)

# Convert relative path to full path
if (-not [System.IO.Path]::IsPathRooted($softwareListPath)) {
    $softwareListPath = (Resolve-Path $softwareListPath).Path
}

# Determine the directory for log file creation
$logDirectory = Split-Path -Path $softwareListPath -Parent
$logFilePath = Join-Path -Path $logDirectory -ChildPath "installation_log.txt"

# Check if the script is running with admin privileges
function Ensure-AdminPrivileges {
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        Write-Host "Restarting script with admin privileges..."
        # Restart as admin with original parameters
        $arguments = "-NoExit -NoProfile -Command `"cd '$pwd'; & '$PSCommandPath'`"" 
        if ($softwareListPath) { $arguments += " -softwareListPath `"$softwareListPath`"" }
        if ($upgrade) { $arguments += " -upgrade" }
        if ($uninstallChocoIfInstalledByScript) { $arguments += " -uninstallChocoIfInstalledByScript" }
        Start-Process powershell -Verb runAs $arguments
        exit
    }
}

# Install Chocolatey if it's not already installed
function Install-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        return $true  # Chocolatey was installed by this script
    }
    return $false  # Chocolatey was already installed
}

# Log messages to the log file
function Log-Message {
    param (
        [string]$message
    )
    Add-Content -Path $logFilePath -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - " + $message)
}

# Parse the software list file
function Parse-SoftwareList {
    $sections = @{ }
    $currentSection = ""
    
    foreach ($line in Get-Content -Path $softwareListPath) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -match '^\[.+\]$') {
            $currentSection = $trimmedLine.TrimStart('[').TrimEnd(']')
            $sections[$currentSection] = @()
        } elseif (-not [string]::IsNullOrWhiteSpace($trimmedLine) -and $trimmedLine -notmatch '^#') {
            $sections[$currentSection] += $trimmedLine
        }
    }

    return $sections
}

# Install software for a section
function Install-Section {
    param (
        [string]$sectionName,
        [string[]]$softwareList
    )
    Write-Host "Installing section: $sectionName..."
    Log-Message "Starting installation for section: $sectionName"

    $softwareStr = $softwareList -join ' '
    $chocoCommand = if ($upgrade) { "choco upgrade" } else { "choco install" }
    $command = "$chocoCommand $softwareStr -y"
    
    try {
        $output = &cmd /c $command 2>&1  # Capture both stdout and stderr
        Log-Message $output  # Log the output of the Chocolatey command
        Log-Message "Section $sectionName installed successfully."
    } catch {
        Log-Message "Error installing section $sectionName : $_"
    }
}

function Main {
    Ensure-AdminPrivileges

    # Install Chocolatey if necessary
    $chocoInstalledByScript = Install-Chocolatey

    # Parse the software list
    $sections = Parse-SoftwareList

    Log-Message "================================================================================"
    Log-Message "Starting installations of you softwares from $softwareListPath"
    Log-Message "================================================================================"

    # Install each section sequentially
    foreach ($section in $sections.Keys) {
        $softwareList = $sections[$section]
        if ($softwareList.Count -gt 0) {
            Install-Section -sectionName $section -softwareList $softwareList
        }
    }

    # Display summary
    Write-Host "Installation complete."
    Write-Host "Check the log file for more details: $logFilePath"

    # Optional: Uninstall Chocolatey if it was installed by this script
    if ($uninstallChocoIfInstalledByScript -and $chocoInstalledByScript) {
        Write-Host "Uninstalling Chocolatey..."
        iex "choco uninstall chocolatey -y"
    }
}

Main