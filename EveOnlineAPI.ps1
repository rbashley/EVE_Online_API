# EveOnlineAPI.ps1 - Functions for interacting with EVE Online's ESI API

# Retrieves all system IDs from EVE Online's ESI API
function Get-EveOnlineSystems {
    Write-Host "[INFO] Connecting to EVE Online API to retrieve all system IDs..."
    $uri = "https://esi.evetech.net/dev/universe/systems/?datasource=tranquility"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get
        Write-Host "[INFO] Successfully retrieved system IDs."
        return $response
    } catch {
        Write-Error "Failed to retrieve systems: $_"
        return $null
    }
}

# Retrieves detailed information for one or more EVE Online systems
# If SystemId is provided, gets info for that system; otherwise, gets info for all systems
function Get-EveOnlineSystemInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [int]$SystemId
    )
    $baseUri = "https://esi.evetech.net/dev/universe/systems/"
    $datasource = "?datasource=tranquility"
    $systemIds = @()
    if ($SystemId) {
        # Single system lookup
        Write-Host "[INFO] Looking up information for system ID: $SystemId"
        $systemIds = @($SystemId)
    } else {
        # Lookup all systems
        Write-Host "[INFO] Looking up information for all systems..."
        $systemIds = Get-EveOnlineSystems
    }
    $results = @()
    foreach ($id in $systemIds) {
        $uri = "$baseUri$id/$datasource"
        try {
            $info = Invoke-RestMethod -Uri $uri -Method Get
            $results += $info
        } catch {
            Write-Warning "Failed to retrieve info for system ID ${$id}: $_"
        }
    }
    Write-Host "[INFO] System information retrieval complete."
    return $results
}

# Searches for a system by name (case-insensitive) using parallel jobs (100 at a time)
# Each job processes a chunk of 100 system IDs, looping inside the job to find the target system
# A progress bar is displayed to show the completion status of all jobs
# Returns the system info if found, otherwise warns and returns $null
function Find-EveOnlineSystemByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$SystemName
    )
    Write-Host "[INFO] Starting search for system named '$SystemName'..."
    # Get all system IDs
    Write-Host "[INFO] Retrieving all system IDs from EVE Online..."
    $systems = Get-EveOnlineSystems
    $chunkSize = 100
    $totalChunks = [math]::Ceiling($systems.Count / $chunkSize)
    $jobs = @()
    Write-Host "[INFO] Launching parallel jobs to search for the system name..."
    # Launch a job for each chunk of 100 system IDs
    for ($i = 0; $i -lt $systems.Count; $i += $chunkSize) {
        $chunk = $systems[$i..([Math]::Min($i + $chunkSize - 1, $systems.Count - 1))]
        $jobs += Start-Job -ScriptBlock {
            param($chunkIds, $targetName)
            foreach ($sysId in $chunkIds) {
                $uri = "https://esi.evetech.net/dev/universe/systems/$sysId/?datasource=tranquility"
                try {
                    $info = Invoke-RestMethod -Uri $uri -Method Get
                    if ($info.name -and ($info.name.ToLower() -eq $targetName.ToLower())) {
                        return $info
                    }
                } catch {}
            }
            return $null
        } -ArgumentList $chunk, $SystemName
    }
    # Progress bar for jobs completed
    $completed = 0
    $jobCount = $jobs.Count
    $found = $null
    while ($completed -lt $jobCount -and -not $found) {
        # Count jobs that are finished (Completed, Failed, or Stopped)
        $completed = ($jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' -or $_.State -eq 'Stopped' }).Count
        Write-Progress -Activity "Searching EVE Systems" -Status "Chunk $completed of $totalChunks" -PercentComplete (($completed / $jobCount) * 100)
        # Check if any job has already found the system
        $partialResults = Receive-Job -Job $jobs -Keep | Where-Object { $_ -ne $null }
        if ($partialResults) {
            $found = $partialResults[0]
            break
        }
        Start-Sleep -Milliseconds 200
    }
    # If found, stop all other jobs
    if ($found) {
        Write-Host "[INFO] System '$SystemName' found. Stopping remaining jobs..."
        $jobs | Where-Object { $_.State -eq 'Running' } | ForEach-Object { Stop-Job $_ }
        Remove-Job -Job $jobs | Out-Null
        Write-Progress -Activity "Searching EVE Systems" -Completed
        Write-Host "[INFO] Search complete. Returning system information."
        return $found
    }
    # Otherwise, collect all results and clean up
    Write-Host "[INFO] System not found in current jobs. Waiting for all jobs to complete..."
    $results = Receive-Job -Job $jobs -Wait | Where-Object { $_ -ne $null }
    Remove-Job -Job $jobs | Out-Null
    Write-Progress -Activity "Searching EVE Systems" -Completed
    if ($results) {
        Write-Host "[INFO] System '$SystemName' found after all jobs completed."
        return $results[0]
    }
    Write-Warning "System with name '$SystemName' not found."
    return $null
}