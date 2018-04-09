#
#   Backup to network and prune old local files script
#

Param(
# Paths
    [string]$basesrc ="D:\cctv\", # Source folder
    [string]$basedst = "Y:\processed cctv\", # Destination folder
    [string]$backup_log_dir = "C:\backuplogs", # Log folder
    [string]$ffmpeg = "C:\ffmpeg.exe", # Path to ffmpeg.exe (can be relative to script location)
# Flags
    [bool]$backup = $true, # If set to false, only create ffmpeg output files
    [bool]$delete = $true, # Enable or disable deletion of files marked older than above
    [bool]$concat = $true, # Enable or disable concat with ffmpeg video output
    [bool]$outputonly = $true, # Copy source and output files to destination or just the ffmpeg output
# Variables
    [int]$threads = "2", # Robocopy threadcount for copying
    [int]$days = "5", # Delete files older than
    [string]$output_prefix = "output_" # Filename prefix for the concatinated video to be used to copy (not used yet)
)

Set-Location -Path $PSScriptRoot
$process = Get-Process -Id $pid
$process.PriorityClass = 'Idle' # Set process as lowest cpu priority, backup isn't as important as new data

Write-Host "###### Starting backup script ######"

$processFiles_block = {
    param($basesrc,$ffmpeg,$log)
    New-Item -Force $log | Out-Null
    # Execute ffmpeg command to generate a file list after some lengthy if checks
    Get-ChildItem -Path $basesrc -Recurse -Directory -Exclude 'meta' | ForEach-Object {
    $filelistParent= $_.FullName
    $filelistPath = $_.FullName | Join-Path -ChildPath "filelist.txt"
    $outputPath = $_.FullName | Join-Path -ChildPath "output.mp4"
    $sourcefiles = $_.FullName | Join-Path -ChildPath "*.mp4"
    $checkfile = $_.FullName | Join-Path -ChildPath ".complete"


    if (Test-Path "$checkfile") {
        Add-Content $log "## Checkfile found, folder skipped ($filelistParent)"}
        else { if (Test-Path "$sourcefiles") {
            Add-Content $log "`n## Sourcefiles found in $filelistParent"
            if ((Test-Path "$filelistPath") -And (Test-Path "$outputPath")) { 
                Add-Content $log "## Do nothing in $filelistParent" }
                else {                
                Add-Content $log "## Filelist or output missing in $filelistParent, generating filelist..."
                Get-ChildItem -Path "$filelistParent" | Where-Object {$_.FullName -like '*.mp4' } | Where-Object {$_.FullName -notlike 'output*'} | ForEach-Object { "file '" + $_.FullName + "'" } | Out-File -encoding ASCII "$FilelistPath"
                Add-Content $log "## FFMPEG called to concatinate the filelist to $outputPath..."
                Invoke-Expression "$ffmpeg -loglevel panic -f concat -safe 0 -i '$Filelistpath' -c copy '$outputPath'"
                echo $null >> $checkfile                
                }
            }
        }
    }
}

$backup_block = {
    param($basesrc,$basedst,$log,$outputonly)
    New-Item -Force $log | Out-Null
    # Execute backup based on flag 
    if ($outputonly) {
        robocopy $basesrc $basedst /B /LOG:$log /TEE /XJ /R:3 /NP /E /XD "temp" "meta" /XF "?????????????_?????????????_??????????_*.mp4" ".complete"
        } else {
        robocopy $basesrc $basedst /B /MT:$threads /LOG:$log /XJ /R:3 /NP /E /XD "temp" 
        }
 
    # /MT   # copies using multiple cores, good for many small files
    # /XJ   # Ignoring junctions, they can cause infinite loops when recursing through folders
    # /R:3  # Retrying a file only 3 times, we don't want bad permissions or other dumb stuff to halt the entire backup
    # /LOG:$log # Logging to a file internally, the best way to log with the /MT flag
    # /NP   # Removing progress from the log
    # /E    # Recursive
    "Backup directory is complete. [$src -> $dst] ($log)"
}

$deleteFiles_block = {
    param($basesrc,$days,$log)
    New-Item -Force $log | Out-Null
    $currentDate = Get-Date
    $datetoDelete = $currentDate.AddDays(-$days)

    # Delete files older than days set in the source folder
    Get-ChildItem -Path $basesrc -Recurse -File | Where-Object { $_.LastWriteTime -lt $datetoDelete } | Remove-Item -Recurse -Force -Verbose
    # Delete any empty directories left behind after deleting the old files.
    Get-ChildItem -Path $basesrc -Recurse -Force | Where-Object { $_.PSIsContainer -and (Get-ChildItem -Path $_.FullName -Recurse -Force | Where-Object { !$_.PSIsContainer }) -eq $null } | Remove-Item -Force -Recurse -Verbose
    Write-Host "###### Deleted source files older than $days days ######"
}

if ($concat -eq $true) {
    Write-Host "Concatinating video files from $basesrc ..."
    $log = Join-Path $backup_log_dir "process_$(get-date -f yyyy-MM-dd_HH-mm-ss).log"
    Invoke-Command $processFiles_block -ArgumentList $basesrc,$ffmpeg,$log 

    # Wait for all to complete
    While (Get-Job -State "Running") { Start-Sleep 2 }
    # Display output from all jobs
    Get-Job | Receive-Job
    # Cleanup
    Remove-Job *

    Write-Host "###### Processing of source files is complete ######"
    }

if ($backup -eq $true) {
    Write-Host "Backing up $basesrc -> $basedst..."
    $log = Join-Path $backup_log_dir "backup_$(get-date -f yyyy-MM-dd_HH-mm-ss).log"
    Invoke-Command $backup_block -ArgumentList $basesrc,$basedst,$log,$outputonly

    # Wait for all to complete
    While (Get-Job -State "Running") { Start-Sleep 2 }
    # Display output from all jobs
    Get-Job | Receive-Job
    # Cleanup
    Remove-Job *

    Write-Host "###### Backup is complete ######"
    }

if ($delete -eq $true) {
    # Backup one dir
    Write-Host "Deleting old files from $basesrc ..."
    $log = Join-Path $backup_log_dir "delete_$(get-date -f yyyy-MM-dd_HH-mm-ss).log"
    Invoke-Command $deleteFiles_block -ArgumentList $basesrc,$days,$log 

    # Wait for all to complete
    While (Get-Job -State "Running") { Start-Sleep 2 }
    # Display output from all jobs
    Get-Job | Receive-Job
    # Cleanup
    Remove-Job *

    Write-Host "###### Deletion of source files is complete ######"
    }
