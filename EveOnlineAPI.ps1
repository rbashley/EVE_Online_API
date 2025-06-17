# EveOnlineAPI.ps1 - Functions for interacting with EVE Online's ESI API

# Retrieves all system IDs from EVE Online's ESI API
function Get-EveOnlineSystems {
    $uri = "https://esi.evetech.net/dev/universe/systems/?datasource=tranquility"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get
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
        $systemIds = @($SystemId)
    } else {
        # Lookup all systems
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
    # Get all system IDs
    $systems = Get-EveOnlineSystems
    $chunkSize = 100
    $totalChunks = [math]::Ceiling($systems.Count / $chunkSize)
    $jobs = @()
    # Launch a job for each chunk of 100 system IDs
    for ($i = 0; $i -lt $systems.Count; $i += $chunkSize) {
        $chunk = $systems[$i..([Math]::Min($i + $chunkSize - 1, $systems.Count - 1))]
        $jobs += Start-Job -ScriptBlock {
            param($chunkIds, $targetName)
            # Loop through each system ID in the chunk
            foreach ($sysId in $chunkIds) {
                $uri = "https://esi.evetech.net/dev/universe/systems/$sysId/?datasource=tranquility"
                try {
                    $info = Invoke-RestMethod -Uri $uri -Method Get
                    # Compare system name (case-insensitive)
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
    while ($completed -lt $jobCount) {
        # Count jobs that are finished (Completed, Failed, or Stopped)
        $completed = ($jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' -or $_.State -eq 'Stopped' }).Count
        Write-Progress -Activity "Searching EVE Systems" -Status "Chunk $completed of $totalChunks" -PercentComplete (($completed / $jobCount) * 100)
        Start-Sleep -Milliseconds 200
    }
    # Collect results from all jobs, filter out nulls
    $results = Receive-Job -Job $jobs -Wait | Where-Object { $_ -ne $null }
    Remove-Job -Job $jobs | Out-Null
    Write-Progress -Activity "Searching EVE Systems" -Completed
    if ($results) {
        # Return the first match found
        return $results[0]
    }
    Write-Warning "System with name '$SystemName' not found."
    return $null
}