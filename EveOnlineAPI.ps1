# EveOnlineAPI.ps1 - Functions for interacting with EVE Online's ESI API

# Retrieves all system IDs from EVE Online's ESI API
function Get-EveOnlineSystems {
    Write-Host "[INFO] Connecting to EVE Online API to retrieve all system IDs..." -ForegroundColor Yellow
    $uri = "https://esi.evetech.net/dev/universe/systems/?datasource=tranquility"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get
        Write-Host "[INFO] Successfully retrieved system IDs." -ForegroundColor Yellow
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
        [int[]]$SystemId
    )
    # Ensure Universe\Systems folder structure exists
    $basePath = Join-Path -Path $PSScriptRoot -ChildPath "Universe"
    $systemsPath = Join-Path -Path $basePath -ChildPath "Systems"
    if (-not (Test-Path $basePath)) {
        Write-Host "[INFO] Creating folder: $basePath" -ForegroundColor Yellow
        New-Item -Path $basePath -ItemType Directory | Out-Null
    }
    if (-not (Test-Path $systemsPath)) {
        Write-Host "[INFO] Creating folder: $systemsPath" -ForegroundColor Yellow
        New-Item -Path $systemsPath -ItemType Directory | Out-Null
    }

    $baseUri = "https://esi.evetech.net/dev/universe/systems/"
    $datasource = "?datasource=tranquility"
    $systemIds = @()
    if ($SystemId) {
        # Accept single or multiple system IDs
        Write-Host "[INFO] Looking up information for system ID(s): $($SystemId -join ', ')" -ForegroundColor Yellow
        $systemIds = $SystemId
    } else {
        # Lookup all systems
        Write-Host "[INFO] Looking up information for all systems..." -ForegroundColor Yellow
        $systemIds = Get-EveOnlineSystems
    }

    # Prepare jobs for parallel requests (only for missing or outdated .json files)
    $chunkSize = 100
    $argumentListCollection = @()
    $results = @()
    $toDownload = @()
    foreach ($id in $systemIds) {
        $jsonPath = Join-Path -Path $systemsPath -ChildPath ("$id.json")
        $needsUpdate = $true
        if (Test-Path $jsonPath) {
            $fileInfo = Get-Item $jsonPath
            $age = (Get-Date) - $fileInfo.LastWriteTime
            if ($age.TotalDays -le 1) {
                # Load from disk if less than a day old
                try {
                    $jsonContent = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                    $results += $jsonContent
                    $needsUpdate = $false
                } catch {
                    Write-Warning "Failed to read or parse ${jsonPath}: $_"
                }
            } else {
                # File is too old, delete it
                Write-Host "[INFO] Cached file $jsonPath is older than 1 day. Deleting and refreshing..." -ForegroundColor Yellow
                Remove-Item $jsonPath -Force
            }
        }
        if ($needsUpdate) {
            $toDownload += $id
        }
    }

    # Download missing or outdated system info in parallel and save as .json
    if ($toDownload.Count -gt 0) {
        for ($i = 0; $i -lt $toDownload.Count; $i += $chunkSize) {
            $chunk = $toDownload[$i..([Math]::Min($i + $chunkSize - 1, $toDownload.Count - 1))]
            $argumentListCollection += ,@($chunk, $baseUri, $datasource, $systemsPath)
        }

        $scriptBlock = {
            param($chunkIds, $baseUri, $datasource, $systemsPath)
            $downloaded = @()
            foreach ($id in $chunkIds) {
                $uri = "$baseUri$id/$datasource"
                try {
                    $info = Invoke-RestMethod -Uri $uri -Method Get
                    $jsonPath = Join-Path -Path $systemsPath -ChildPath ("$id.json")
                    $info | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
                    $downloaded += $info
                } catch {
                    Write-Warning "Failed to retrieve or save info for system ID ${id}: $_"
                }
            }
            return $downloaded
        }

        $downloadedResults = Invoke-EveAsyncJobs -ScriptBlock $scriptBlock -ArgumentListCollection $argumentListCollection
        foreach ($result in $downloadedResults) {
            if ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string])) {
                $results += $result
            } elseif ($result) {
                $results += $result
            }
        }
    }

    Write-Host "[INFO] System information retrieval complete." -ForegroundColor Yellow
    return $results
}

# Searches for a system by property, supporting numeric and boolean operations (e.g., "planets > 5", "moons -gt 2", "stargates -ge 1")
function Find-EveOnlineSystemByCriteria {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)]
        [string]$Filter,             # e.g. "planets -gt 5, security_status -ge 0.5, name -eq Jita"
        [Parameter(Mandatory=$false)]
        [string]$Property,
        [Parameter(Mandatory=$false)]
        [ValidateSet('-eq','-ne','-gt','-ge','-lt','-le')]
        [string]$Operator,
        [Parameter(Mandatory=$false)]
        [object]$Value,
        [switch]$CompleteAllJobs
    )
    # Parse filters into an array of criteria
    $criteria = @()
    if ($Filter) {
        $filterParts = $Filter -split '\s*,\s*'
        foreach ($f in $filterParts) {
            if ($f -match '^\s*(\w+)\s+(-eq|-ne|-gt|-ge|-lt|-le)\s+(.+)$') {
                $crit = [PSCustomObject]@{
                    Property = $matches[1]
                    Operator = $matches[2]
                    Value    = $matches[3].Trim('"').Trim("'")
                }
                # Try to convert Value to int or double if possible
                if ($crit.Value -match '^\d+$') { $crit.Value = [int]$crit.Value }
                elseif ($crit.Value -match '^\d+\.\d+$') { $crit.Value = [double]$crit.Value }
                $criteria += $crit
            } else {
                Write-Warning "Filter string format invalid: '$f'. Use: <property> <operator> <value> (e.g. 'planets -gt 5')"
                return $null
            }
        }
    } elseif ($Property -and $Operator -and $null -ne $Value) {
        $criteria += [PSCustomObject]@{
            Property = $Property
            Operator = $Operator
            Value    = $Value
        }
    } else {
        Write-Warning "You must specify either -Filter or all of -Property, -Operator, and -Value."
        return $null
    }

    Write-Host "[INFO] Searching for systems matching all filter criteria..." -ForegroundColor Yellow
    $systems = Get-EveOnlineSystemInfo
    if (-not $systems) {
        Write-Warning "No systems found to search."
        return $null
    }
    $results = @()
    foreach ($system in $systems) {
        $match = $true
        foreach ($crit in $criteria) {
            switch ($crit.Property.ToLower()) {
                'planets' {
                    $count = if ($system.planets) { $system.planets.Count } else { 0 }
                    if (-not (Invoke-Expression "$count $($crit.Operator) $($crit.Value)")) { $match = $false }
                }
                'moons' {
                    $count = 0
                    if ($system.planets) {
                        foreach ($planet in $system.planets) {
                            if ($planet.moons) { $count += $planet.moons.Count }
                        }
                    }
                    if (-not (Invoke-Expression "$count $($crit.Operator) $($crit.Value)")) { $match = $false }
                }
                'asteroid_belts' {
                    $count = 0 
                    if ($system.planets) {
                        foreach ($planet in $system.planets) {
                            if ($planet.asteroid_belts) { $count += $planet.asteroid_belts.Count }
                        }
                    }
                    if (-not (Invoke-Expression "$count $($crit.Operator) $($crit.Value)")) { $match = $false }
                }
                'stations' {
                    $count = if ($system.stations) { $system.stations.Count } else { 0 }
                    if (-not (Invoke-Expression "$count $($crit.Operator) $($crit.Value)")) { $match = $false }
                }
                'stargates' {
                    $count = if ($system.stargates) { $system.stargates.Count } else { 0 }
                    if (-not (Invoke-Expression "$count $($crit.Operator) $($crit.Value)")) { $match = $false }
                }
                'security_status' {
                    $sec = if ($system.security_status) { [double]$system.security_status } else { 0 }
                    if (-not (Invoke-Expression "$sec $($crit.Operator) $($crit.Value)")) { $match = $false }
                }
                'name' {
                    if ($crit.Operator -eq '-eq' -and $system.name -and ($system.name.ToLower() -ne $crit.Value.ToString().ToLower())) { $match = $false }
                    elseif ($crit.Operator -eq '-ne' -and $system.name -and ($system.name.ToLower() -eq $crit.Value.ToString().ToLower())) { $match = $false }
                }
                default { $match = $false }
            }
            if (-not $match) { break }
        }
        if ($match) {
            $results += $system
            if (-not $CompleteAllJobs) { return $system }
        }
    }
    if ($results) {
        Write-Host "[INFO] Found $($results.Count) system(s) matching criteria." -ForegroundColor Yellow
        return $results
    } else {
        Write-Warning "No systems found matching criteria."
        return $null
    }
}

function Get-EveSystemPath {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$startingSystem, # The starting system name or ID
        [Parameter(Mandatory=$true)]
        [object]$destinationSystem, # The destination system name or ID
        [switch]$StringNames        # If set, return system names instead of IDs
    )
    Write-Host "[INFO] Retrieving path from $startingSystem to $destinationSystem..." -ForegroundColor Yellow
    $systemsInfo = Get-EveOnlineSystemInfo

    $startingSystemId = if ($startingSystem -is [int]) { 
        $startingSystem 
    } elseif ($startingSystem -is [string]) {
        ($systemsInfo | Where-Object { $_.name -eq $startingSystem }).system_id
    } else {
        Write-Warning "Invalid starting system type. Must be int or string."
        return $null
    }

    $destinationSystemId = if ($destinationSystem -is [int]) { 
        $destinationSystem 
    } elseif ($destinationSystem -is [string]) {
        ($systemsInfo | Where-Object { $_.name -eq $destinationSystem }).system_id
    } else {
        Write-Warning "Invalid destination system type. Must be int or string."
        return $null
    }

    if (-not $startingSystemId -or -not $destinationSystemId) {
        Write-Warning "Could not resolve system IDs for one or both systems."
        return $null
    }
    $uri = "https://esi.evetech.net/dev/route/$startingSystemId/$destinationSystemId/?datasource=tranquility"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get
        if ($response -and $response.Count -gt 0) {
            Write-Host "[INFO] Successfully retrieved path." -ForegroundColor Yellow
            if ($StringNames) {
                $listIndex = 1;
                # Map IDs to names
                $idToName = @{
                }
                foreach ($sys in $systemsInfo) { $idToName[$sys.system_id] = $sys.name }
                $response | ForEach-Object { 
                    $sysName = $idToName[$_]
                    Write-Host "$listIndex. $sysName"
                    $listIndex++
                }
            } else {
                return $response
            }
        } else {
            Write-Warning "No route found between $startingSystem and $destinationSystem."
            return $null
        }
    } catch {
        Write-Error "Failed to retrieve route: $_"
        return $null
    }
}

# Runs script blocks as jobs asynchronously, with option to cancel others on first result or let all complete
function Invoke-EveAsyncJobs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,          # The script block to run in each job

        [Parameter(Mandatory=$true)]
        [Object[]]$ArgumentListCollection,  # Array of argument arrays for each job

        [switch]$StopOnFirstResult           # If set, cancels all jobs when first non-null result is found
    )
    $jobs = @()
    foreach ($args in $ArgumentListCollection) {
        $jobs += Start-Job -ScriptBlock $ScriptBlock -ArgumentList $args
    }

    $results = @()
    $completed = 0
    $jobCount = $jobs.Count
    $found = $null

    while ($completed -lt $jobCount) {
        $completed = ($jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' -or $_.State -eq 'Stopped' }).Count
        Write-Progress -Activity "Running async jobs" -Status "$completed of $jobCount complete" -PercentComplete (($completed / $jobCount) * 100)

        $partialResults = Receive-Job -Job $jobs -Keep | Where-Object { $_ -ne $null }
        if ($StopOnFirstResult -and $partialResults) {
            $found = $partialResults[0]
            break
        }
        Start-Sleep -Milliseconds 200
    }

    if ($StopOnFirstResult -and $found) {
        Write-Host "[INFO] Result found. Stopping remaining jobs..." -ForegroundColor Yellow
        $jobs | Where-Object { $_.State -eq 'Running' } | ForEach-Object { Stop-Job $_ }
        Remove-Job -Job $jobs | Out-Null
        Write-Progress -Activity "Running async jobs" -Completed
        return $found
    } else {
        $results = Receive-Job -Job $jobs -Wait | Where-Object { $_ -ne $null }
        Remove-Job -Job $jobs | Out-Null
        Write-Progress -Activity "Running async jobs" -Completed
        return $results
    }
}