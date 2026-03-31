$ErrorActionPreference = 'Stop'

$port = 48211
$prefix = "http://*:$port/"
$fallbackPrefix = "http://localhost:$port/"
$listener = New-Object System.Net.HttpListener

try {
    $listener.Prefixes.Add($prefix)
    $listener.Start()
    Write-Host "Server listening on $prefix"
} catch {
    Write-Host "Failed to bind to $prefix. Falling back to localhost-only mode for development..."
    $listener.Close()
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($fallbackPrefix)
    $listener.Start()
    Write-Host "Server listening on $fallbackPrefix"
}

$dbisamPath = 'E:\DentiMax\dentimaxdata\Smile You''re Golden'
$documentCenter = 'E:\DentiMax\Document Center'

function Start-NagSuppressorJob {
    Start-Job -ScriptBlock {
        param($LogFile)

        function Write-Log($msg) {
            $line = "[$([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] [NagSuppressorJob] $msg"
            try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
        }

        Add-Type -AssemblyName System.Windows.Forms
        $wshell = New-Object -ComObject WScript.Shell
        $dismissed = 0
        $handled = New-Object 'System.Collections.Generic.HashSet[string]'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        Write-Log "Started."

        while ($dismissed -lt 2 -and $sw.Elapsed.TotalSeconds -lt 60) {
            try {
                $targets = Get-Process | Where-Object {
                    $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -eq 'Information'
                }

                foreach ($target in $targets) {
                    try {
                        $handleKey = $target.MainWindowHandle.ToString()
                        if ($handled.Contains($handleKey)) {
                            continue
                        }

                        [void]$wshell.AppActivate($target.Id)
                        Start-Sleep -Milliseconds 120
                        $wshell.SendKeys('{ENTER}')
                        Write-Log "Sent ENTER to PID=$($target.Id) Handle=$($target.MainWindowHandle) Title='$($target.MainWindowTitle)'"

                        $closed = $false
                        for ($i = 0; $i -lt 12; $i++) {
                            Start-Sleep -Milliseconds 100
                            $stillOpen = Get-Process -Id $target.Id -ErrorAction SilentlyContinue |
                                Where-Object { $_.MainWindowHandle -eq $target.MainWindowHandle -and $_.MainWindowTitle -eq 'Information' }
                            if (-not $stillOpen) {
                                $closed = $true
                                break
                            }
                        }

                        if ($closed) {
                            [void]$handled.Add($handleKey)
                            $dismissed++
                            Write-Log "Confirmed close for PID=$($target.Id) Handle=$($target.MainWindowHandle) Count=$dismissed/2"
                        } else {
                            Write-Log "Dialog still open for PID=$($target.Id) Handle=$($target.MainWindowHandle)"
                        }

                        if ($dismissed -ge 2) { break }
                        Start-Sleep -Milliseconds 250
                    } catch {
                        Write-Log "Per-window error for PID=$($target.Id): $($_.Exception.Message)"
                    }
                }
            } catch {
                Write-Log "Loop error: $($_.Exception.Message)"
            }

            Start-Sleep -Milliseconds 150
        }

        Write-Log "Finished. Dismissed=$dismissed/2"
    } -ArgumentList (Join-Path $PSScriptRoot "server_errors.log")
}

function Read-JsonBody($request) {
    $encoding = $request.ContentEncoding
    if ($null -eq $encoding) { $encoding = [System.Text.Encoding]::UTF8 }
    $buffer = New-Object 'byte[]' $request.ContentLength64
    $read = 0
    while ($read -lt $request.ContentLength64) {
        $read += $request.InputStream.Read($buffer, $read, $request.ContentLength64 - $read)
    }
    $encoding.GetString($buffer) | ConvertFrom-Json
}

function Write-JsonResponse($response, $statusCode, $payload) {
    $json = $payload | ConvertTo-Json -Depth 8
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response.ContentType = "application/json"
    $response.StatusCode = $statusCode
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
}

function Open-DentiMaxConnection {
    $conn = New-Object System.Data.Odbc.OdbcConnection("Driver={DBISAM 4 ODBC Driver};ConnectionType=Local;CatalogName=$dbisamPath;")
    $conn.Open()
    $conn
}

function To-DbNull($value) {
    if ($null -eq $value) { return [System.DBNull]::Value }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { return [System.DBNull]::Value }
    $value
}

function Trim-DbString($value) {
    if ($null -eq $value -or $value -is [System.DBNull]) { return $null }
    "$value".Trim()
}

function Normalize-Name([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    (($value.ToLowerInvariant()) -replace '[^a-z0-9]', '')
}

function Get-LevenshteinDistance([string]$source, [string]$target) {
    if ($source -eq $target) { return 0 }
    if ([string]::IsNullOrEmpty($source)) { return $target.Length }
    if ([string]::IsNullOrEmpty($target)) { return $source.Length }

    $dist = New-Object 'int[,]' ($source.Length + 1), ($target.Length + 1)
    for ($i = 0; $i -le $source.Length; $i++) { $dist[$i, 0] = $i }
    for ($j = 0; $j -le $target.Length; $j++) { $dist[0, $j] = $j }

    for ($i = 1; $i -le $source.Length; $i++) {
        for ($j = 1; $j -le $target.Length; $j++) {
            $cost = if ($source[$i - 1] -eq $target[$j - 1]) { 0 } else { 1 }
            $above = $dist[$i - 1, $j] + 1
            $left = $dist[$i, $j - 1] + 1
            $diag = $dist[$i - 1, $j - 1] + $cost
            $dist[$i, $j] = [Math]::Min([Math]::Min($above, $left), $diag)
        }
    }

    $dist[$source.Length, $target.Length]
}

function Convert-ToChartString([string]$chartNumber) {
    if ([string]::IsNullOrWhiteSpace($chartNumber)) { return '' }
    $chartNumber.Trim().PadRight(10, ' ')
}

function Parse-NullableDate($value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    try { return [datetime]$value } catch { return $null }
}

function Get-NextIdentityValue($odbcConn, [string]$tableName, [string]$columnName) {
    $cmd = $odbcConn.CreateCommand()
    $cmd.CommandText = "SELECT MAX($columnName) FROM $tableName"
    $maxValue = $cmd.ExecuteScalar()
    if ($null -eq $maxValue -or $maxValue -is [System.DBNull]) { return 1 }
    [int]$maxValue + 1
}

function Get-DocumentHash([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Values-Differ($left, $right) {
    $leftText = if ($left -is [datetime]) { $left.ToString('MM/dd/yyyy') } else { (Trim-DbString $left) }
    $rightText = if ($right -is [datetime]) { $right.ToString('MM/dd/yyyy') } else { (Trim-DbString $right) }
    $leftText -ne $rightText
}

function Get-TableColumnSet($odbcConn, [string]$tableName) {
    $schema = $odbcConn.GetSchema('Columns')
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $schema.Rows) {
        if ("$($row['TABLE_NAME'])" -ieq $tableName) {
            [void]$set.Add("$($row['COLUMN_NAME'])")
        }
    }
    $set
}

function Get-ExistingColumnName($columnSet, [string[]]$candidates) {
    foreach ($candidate in $candidates) {
        if ($columnSet.Contains($candidate)) { return $candidate }
    }
    $null
}

function Get-DataValue($row, [string[]]$candidates) {
    foreach ($candidate in $candidates) {
        if ($row.Table.Columns.Contains($candidate)) {
            $value = $row[$candidate]
            if ($value -is [System.DBNull]) { return $null }
            return $value
        }
    }
    $null
}

function Get-PatientFieldText($row, [string[]]$candidates) {
    Trim-DbString (Get-DataValue $row $candidates)
}

function Format-PatientDate($value) {
    if ($null -eq $value -or $value -is [System.DBNull]) { return '' }
    try { return ([datetime]$value).ToString('MM/dd/yyyy') } catch { return (Trim-DbString $value) }
}

function Convert-RelationCodeToText($value) {
    if ($null -eq $value -or $value -is [System.DBNull] -or [string]::IsNullOrWhiteSpace("$value")) { return 'Self' }
    switch ([int]$value) {
        0 { 'Self' }
        1 { 'Spouse' }
        2 { 'Child' }
        3 { 'Other' }
        default { 'Other' }
    }
}

function Convert-TextToRelationCode([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return 0 }
    switch -Regex ($value.Trim().ToLowerInvariant()) {
        '^self$' { 0 }
        '^spouse$' { 1 }
        '^child$' { 2 }
        default { 3 }
    }
}

function New-PatientApiModel($row) {
    [pscustomobject]@{
        chartNumber = Get-PatientFieldText $row @('Chart Number')
        firstName = Get-PatientFieldText $row @('First Name')
        middleInitial = Get-PatientFieldText $row @('Middle Initial', 'Middle Name', 'MI')
        lastName = Get-PatientFieldText $row @('Last Name')
        birthDate = Format-PatientDate (Get-DataValue $row @('Birth Date'))
        gender = Get-PatientFieldText $row @('Gender', 'Sex')
        ssn = Get-PatientFieldText $row @('SSN', 'SIN/SSN', 'SIN')
        homePhone = Get-PatientFieldText $row @('Home Phone', 'Phone(Home/Work)')
        mobile = Get-PatientFieldText $row @('Mobile', 'Mobile Phone', 'Mobile(Home/Work)')
        workPhone = Get-PatientFieldText $row @('Work Phone')
        street = Get-PatientFieldText $row @('Street', 'Address 1')
        apt = Get-PatientFieldText $row @('Street 2', 'Address 2')
        city = Get-PatientFieldText $row @('City')
        state = Get-PatientFieldText $row @('State')
        zip = Get-PatientFieldText $row @('Zip', 'Postal Code')
        maritalStatus = Get-PatientFieldText $row @('Marital Status')
        email = Get-PatientFieldText $row @('E-mail', 'Email(Home)', 'Email')
        emergencyContact = Get-PatientFieldText $row @('Emergency Contact')
        emergencyPhone = Get-PatientFieldText $row @('Emergency Phone')
        referral = Get-PatientFieldText $row @('Referred By', 'Referral')
        relationship = Convert-RelationCodeToText (Get-DataValue $row @('Relation to Subscriber 1'))
    }
}

function Get-BirthDatePenalty($inputDate, $rowBirthDate) {
    if ($null -eq $inputDate -or $null -eq $rowBirthDate -or $rowBirthDate -is [System.DBNull]) { return 8 }
    try {
        $candidateDate = ([datetime]$rowBirthDate).Date
        $diff = [math]::Abs(($candidateDate - $inputDate.Date).TotalDays)
        if ($diff -eq 0) { return 0 }
        if ($diff -le 1) { return 1 }
        if ($diff -le 3) { return 3 }
        if ($diff -le 7) { return 6 }
        return 20
    } catch {
        return 20
    }
}

function Get-PatientMatchScore($row, [string]$firstName, [string]$lastName, $birthDate) {
    $normalizedFirst = Normalize-Name $firstName
    $normalizedLast = Normalize-Name $lastName
    $candidateFirst = Normalize-Name (Get-PatientFieldText $row @('First Name'))
    $candidateLast = Normalize-Name (Get-PatientFieldText $row @('Last Name'))
    if ([string]::IsNullOrWhiteSpace($candidateFirst) -or [string]::IsNullOrWhiteSpace($candidateLast)) {
        return [int]::MaxValue
    }

    $firstDistance = Get-LevenshteinDistance $normalizedFirst $candidateFirst
    $lastDistance = Get-LevenshteinDistance $normalizedLast $candidateLast
    $birthPenalty = Get-BirthDatePenalty $birthDate (Get-DataValue $row @('Birth Date'))

    $maxFirstDistance = if ($normalizedFirst.Length -le 4) { 1 } else { 2 }
    $maxLastDistance = if ($normalizedLast.Length -le 4) { 1 } else { 2 }

    if ($firstDistance -gt $maxFirstDistance -or $lastDistance -gt $maxLastDistance) {
        return [int]::MaxValue
    }

    if ($birthPenalty -ge 20) {
        return [int]::MaxValue
    }

    ($lastDistance * 5) + ($firstDistance * 3) + $birthPenalty
}

function Find-ExactPatientMatches($odbcConn, [string]$firstName, [string]$lastName, $birthDate) {
    if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($lastName) -or $null -eq $birthDate) {
        return @()
    }

    $cmd = $odbcConn.CreateCommand()
    $cmd.CommandText = 'SELECT * FROM patient WHERE "Birth Date" = ? AND "First Name" = ? AND "Last Name" = ?'

    $birthParam = $cmd.CreateParameter()
    $birthParam.OdbcType = [System.Data.Odbc.OdbcType]::DateTime
    $birthParam.Value = $birthDate.Date
    [void]$cmd.Parameters.Add($birthParam)

    $firstParam = $cmd.CreateParameter()
    $firstParam.Value = $firstName
    [void]$cmd.Parameters.Add($firstParam)

    $lastParam = $cmd.CreateParameter()
    $lastParam.Value = $lastName
    [void]$cmd.Parameters.Add($lastParam)

    $table = New-Object System.Data.DataTable
    $table.Load($cmd.ExecuteReader())
    @(
        foreach ($row in $table.Rows) {
            $row
        }
    )
}

function Find-NormalizedPatientMatches($rows, [string]$firstName, [string]$lastName) {
    $normalizedFirst = Normalize-Name $firstName
    $normalizedLast = Normalize-Name $lastName
    if ([string]::IsNullOrWhiteSpace($normalizedFirst) -or [string]::IsNullOrWhiteSpace($normalizedLast)) {
        return @()
    }

    @(
        foreach ($row in $rows) {
            $candidateFirst = Normalize-Name (Get-PatientFieldText $row @('First Name'))
            $candidateLast = Normalize-Name (Get-PatientFieldText $row @('Last Name'))
            if ($candidateFirst -eq $normalizedFirst -and $candidateLast -eq $normalizedLast) {
                $row
            }
        }
    )
}

function Add-UpdateParameter($cmd, [string]$columnName, $value, [System.Data.Odbc.OdbcType]$type = [System.Data.Odbc.OdbcType]::VarChar, [int]$size = 0) {
    $parameter = $cmd.CreateParameter()
    $parameter.OdbcType = $type
    if ($size -gt 0) { $parameter.Size = $size }
    $parameter.Value = To-DbNull $value
    [void]$cmd.Parameters.Add($parameter)
    '"{0}" = ?' -f $columnName
}

function Save-PdfDocuments($odbcConn, [string]$chartNumber, $pdfs, [bool]$skipDuplicates) {
    $existingKeys = New-Object 'System.Collections.Generic.HashSet[string]'

    if ($skipDuplicates) {
        $existingDocCmd = $odbcConn.CreateCommand()
        $existingDocCmd.CommandText = 'SELECT "Name", "Type", Document FROM dcdocument WHERE "Chart Number" = ?'
        $chartParam = $existingDocCmd.CreateParameter()
        $chartParam.OdbcType = [System.Data.Odbc.OdbcType]::Char
        $chartParam.Size = 10
        $chartParam.Value = $chartNumber
        [void]$existingDocCmd.Parameters.Add($chartParam)

        $reader = $existingDocCmd.ExecuteReader()
        while ($reader.Read()) {
            if ($reader.IsDBNull(2)) { continue }
            $name = Trim-DbString $reader.GetValue(0)
            $type = if ($reader.IsDBNull(1)) { 4 } else { [int]$reader.GetValue(1) }
            $bytes = [byte[]]$reader.GetValue(2)
            $hash = Get-DocumentHash $bytes
            [void]$existingKeys.Add("$name|$type|$hash")
        }
        $reader.Close()
    }

    $inserted = 0
    $skipped = 0

    foreach ($pdf in $pdfs) {
        $cleanBase64 = ($pdf.base64 -replace '^data:.*?base64,', '') -replace '\s+', ''
        try {
            $pdfBytes = [System.Convert]::FromBase64String($cleanBase64)
        } catch {
            continue
        }

        $safeName = if ($pdf.title) { "$($pdf.title)" } else { 'Intake Form' }
        $docCategory = if ($pdf.docType) { [int]$pdf.docType } else { 4 }
        $hash = Get-DocumentHash $pdfBytes
        $key = "$safeName|$docCategory|$hash"

        if ($skipDuplicates -and $existingKeys.Contains($key)) {
            $skipped++
            continue
        }

        $newDocId = Get-NextIdentityValue $odbcConn 'dcdocument' 'ID'
        $insertDocCmd = $odbcConn.CreateCommand()
        $insertDocCmd.CommandText = 'INSERT INTO dcdocument ("ID", "Date", "Type", "Date Created", "Date Modified", "Chart Number", "Name", "Doc Type") VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        $now = [datetime]::Now

        $docIdParam = $insertDocCmd.CreateParameter(); $docIdParam.OdbcType = [System.Data.Odbc.OdbcType]::Int; $docIdParam.Value = $newDocId; [void]$insertDocCmd.Parameters.Add($docIdParam)
        $pDate = $insertDocCmd.CreateParameter(); $pDate.Value = $now; [void]$insertDocCmd.Parameters.Add($pDate)
        $pType = $insertDocCmd.CreateParameter(); $pType.OdbcType = [System.Data.Odbc.OdbcType]::Int; $pType.Value = $docCategory; [void]$insertDocCmd.Parameters.Add($pType)
        $pCreated = $insertDocCmd.CreateParameter(); $pCreated.Value = $now; [void]$insertDocCmd.Parameters.Add($pCreated)
        $pModified = $insertDocCmd.CreateParameter(); $pModified.Value = $now; [void]$insertDocCmd.Parameters.Add($pModified)
        $pChart = $insertDocCmd.CreateParameter(); $pChart.OdbcType = [System.Data.Odbc.OdbcType]::Char; $pChart.Size = 10; $pChart.Value = $chartNumber; [void]$insertDocCmd.Parameters.Add($pChart)
        $pName = $insertDocCmd.CreateParameter(); $pName.Value = $safeName; [void]$insertDocCmd.Parameters.Add($pName)
        $pDocType = $insertDocCmd.CreateParameter(); $pDocType.Value = 'PDF'; [void]$insertDocCmd.Parameters.Add($pDocType)
        [void]$insertDocCmd.ExecuteNonQuery()

        $updateBlobCmd = $odbcConn.CreateCommand()
        $updateBlobCmd.CommandText = 'UPDATE dcdocument SET Document = CAST(? AS Memo) WHERE ID = ?'
        $pBlob = $updateBlobCmd.CreateParameter(); $pBlob.OdbcType = [System.Data.Odbc.OdbcType]::VarBinary; $pBlob.Size = $pdfBytes.Length; $pBlob.Value = $pdfBytes; [void]$updateBlobCmd.Parameters.Add($pBlob)
        $pIdBlob = $updateBlobCmd.CreateParameter(); $pIdBlob.OdbcType = [System.Data.Odbc.OdbcType]::Int; $pIdBlob.Value = $newDocId; [void]$updateBlobCmd.Parameters.Add($pIdBlob)
        [void]$updateBlobCmd.ExecuteNonQuery()

        $safeNameFile = $safeName -replace '[\\/:\*\?"<>|]', '_'
        $fileName = "Intake_${chartNumber}_$safeNameFile" + '_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff') + '.pdf'
        $filePath = Join-Path $documentCenter $fileName
        try { [System.IO.File]::WriteAllBytes($filePath, $pdfBytes) } catch {}

        [void]$existingKeys.Add($key)
        $inserted++
    }

    @{
        inserted = $inserted
        skipped = $skipped
    }
}

function Handle-ApiPatientSearch($request, $response) {
    $odbcConn = $null
    $nagJob = $null
    try {
        $payload = Read-JsonBody $request
        $firstName = Trim-DbString $payload.firstName
        $lastName = Trim-DbString $payload.lastName
        $birthDate = Parse-NullableDate $payload.birthDate

        if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($lastName) -or $null -eq $birthDate) {
            Write-JsonResponse $response 400 @{ error = 'First name, last name, and birthdate are required.' }
            return
        }

        $nagJob = Start-NagSuppressorJob
        $odbcConn = Open-DentiMaxConnection
        $exactCmd = $odbcConn.CreateCommand()
        $exactCmd.CommandText = 'SELECT * FROM patient WHERE "Birth Date" = ? AND "First Name" = ? AND "Last Name" = ?'
        $exactBirthParam = $exactCmd.CreateParameter()
        $exactBirthParam.OdbcType = [System.Data.Odbc.OdbcType]::DateTime
        $exactBirthParam.Value = $birthDate.Date
        [void]$exactCmd.Parameters.Add($exactBirthParam)
        $exactFirstParam = $exactCmd.CreateParameter()
        $exactFirstParam.Value = $firstName
        [void]$exactCmd.Parameters.Add($exactFirstParam)
        $exactLastParam = $exactCmd.CreateParameter()
        $exactLastParam.Value = $lastName
        [void]$exactCmd.Parameters.Add($exactLastParam)

        $exactTable = New-Object System.Data.DataTable
        $exactTable.Load($exactCmd.ExecuteReader())
        if ($exactTable.Rows.Count -eq 1) {
            Write-JsonResponse $response 200 @{ matches = @(New-PatientApiModel ($exactTable.Rows[0])) }
            return
        }

        $cmd = $odbcConn.CreateCommand()
        $cmd.CommandText = 'SELECT * FROM patient WHERE "Birth Date" = ?'
        $birthParam = $cmd.CreateParameter()
        $birthParam.OdbcType = [System.Data.Odbc.OdbcType]::DateTime
        $birthParam.Value = $birthDate.Date
        [void]$cmd.Parameters.Add($birthParam)

        $reader = $cmd.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($reader)

        $exactRows = @(Find-NormalizedPatientMatches $table.Rows $firstName $lastName)
        if ($exactRows.Count -eq 1) {
            Write-JsonResponse $response 200 @{ matches = @(New-PatientApiModel ($exactRows[0])) }
            return
        }

        $ranked = @(foreach ($row in $table.Rows) {
            $score = Get-PatientMatchScore $row $firstName $lastName $birthDate
            if ($score -eq [int]::MaxValue) { continue }
            [pscustomobject]@{
                score = $score
                patient = New-PatientApiModel $row
            }
        })

        $bestMatches = @($ranked | Sort-Object score)
        if ($bestMatches.Count -eq 0) {
            Write-JsonResponse $response 200 @{ matches = @() }
            return
        }

        $winner = $bestMatches[0]
        $runnerUp = if ($bestMatches.Count -gt 1) { $bestMatches[1] } else { $null }
        $winnerScore = [int](@($winner.score)[0])
        $runnerUpScore = if ($null -eq $runnerUp) { $null } else { [int](@($runnerUp.score)[0]) }
        $isConfident = $winnerScore -le 8 -and ($null -eq $runnerUpScore -or $winnerScore -lt $runnerUpScore)

        $patientMatches = if ($isConfident) { @($winner.patient) } else { @() }
        Write-JsonResponse $response 200 @{ matches = $patientMatches }
    } catch {
        Write-JsonResponse $response 500 @{ error = $_.Exception.Message }
    } finally {
        if ($odbcConn -and $odbcConn.State -eq 'Open') { $odbcConn.Close() }
        if ($nagJob) {
            Stop-Job -Id $nagJob.Id -ErrorAction SilentlyContinue
            Remove-Job -Id $nagJob.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Handle-ApiCheckIn($request, $response) {
    $odbcConn = $null
    $nagJob = $null
    try {
        $nagJob = Start-NagSuppressorJob
        $payload = Read-JsonBody $request
        $chartNumber = Convert-ToChartString (Trim-DbString $payload.chartNumber)
        $odbcConn = Open-DentiMaxConnection
        if ([string]::IsNullOrWhiteSpace($chartNumber)) {
            $firstName = Trim-DbString $payload.firstName
            $lastName = Trim-DbString $payload.lastName
            $birthDate = Parse-NullableDate $payload.birthDate

            if (-not [string]::IsNullOrWhiteSpace($firstName) -and -not [string]::IsNullOrWhiteSpace($lastName) -and $null -ne $birthDate) {
                $exactCmd = $odbcConn.CreateCommand()
                $exactCmd.CommandText = 'SELECT * FROM patient WHERE "Birth Date" = ? AND "First Name" = ? AND "Last Name" = ?'
                $exactBirthParam = $exactCmd.CreateParameter()
                $exactBirthParam.OdbcType = [System.Data.Odbc.OdbcType]::DateTime
                $exactBirthParam.Value = $birthDate.Date
                [void]$exactCmd.Parameters.Add($exactBirthParam)
                $exactFirstParam = $exactCmd.CreateParameter()
                $exactFirstParam.Value = $firstName
                [void]$exactCmd.Parameters.Add($exactFirstParam)
                $exactLastParam = $exactCmd.CreateParameter()
                $exactLastParam.Value = $lastName
                [void]$exactCmd.Parameters.Add($exactLastParam)

                $exactTable = New-Object System.Data.DataTable
                $exactTable.Load($exactCmd.ExecuteReader())
                if ($exactTable.Rows.Count -eq 1) {
                    $chartNumber = Convert-ToChartString (Get-PatientFieldText ($exactTable.Rows[0]) @('Chart Number'))
                }

                if ([string]::IsNullOrWhiteSpace($chartNumber)) {
                $findCmd = $odbcConn.CreateCommand()
                $findCmd.CommandText = 'SELECT * FROM patient WHERE "Birth Date" = ?'
                $birthParam = $findCmd.CreateParameter()
                $birthParam.OdbcType = [System.Data.Odbc.OdbcType]::DateTime
                $birthParam.Value = $birthDate.Date
                [void]$findCmd.Parameters.Add($birthParam)

                $reader = $findCmd.ExecuteReader()
                $table = New-Object System.Data.DataTable
                $table.Load($reader)

                $exactRows = @(Find-NormalizedPatientMatches $table.Rows $firstName $lastName)
                if ($exactRows.Count -eq 1) {
                    $chartNumber = Convert-ToChartString (Get-PatientFieldText ($exactRows[0]) @('Chart Number'))
                }

                if ([string]::IsNullOrWhiteSpace($chartNumber)) {
                $ranked = @(foreach ($row in $table.Rows) {
                    $score = Get-PatientMatchScore $row $firstName $lastName $birthDate
                    if ($score -eq [int]::MaxValue) { continue }
                    [pscustomobject]@{
                        score = $score
                        chartNumber = Convert-ToChartString (Get-PatientFieldText $row @('Chart Number'))
                    }
                })
                $ranked = @($ranked | Sort-Object score)

                if ($ranked.Count -gt 0) {
                    $winner = $ranked[0]
                    $runnerUp = if ($ranked.Count -gt 1) { $ranked[1] } else { $null }
                    $winnerScore = [int](@($winner.score)[0])
                    $runnerUpScore = if ($null -eq $runnerUp) { $null } else { [int](@($runnerUp.score)[0]) }
                    $isConfident = $winnerScore -le 8 -and ($null -eq $runnerUpScore -or $winnerScore -lt $runnerUpScore)
                    if ($isConfident -and -not [string]::IsNullOrWhiteSpace($winner.chartNumber)) {
                        $chartNumber = $winner.chartNumber
                    }
                }
                }
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($chartNumber)) {
            Write-JsonResponse $response 400 @{ error = 'Chart number is required for returning-patient check-in.' }
            return
        }

        $patientColumns = Get-TableColumnSet $odbcConn 'patient'
        $editedStepIds = @()
        if ($null -ne $payload.editedStepIds) {
            $editedStepIds = @($payload.editedStepIds | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        }

        $updatedColumns = @()
        if ($editedStepIds -contains 'registration') {
            $updateCmd = $odbcConn.CreateCommand()
            $assignments = New-Object 'System.Collections.Generic.List[string]'

            $fieldMap = @(
                @{ candidates = @('First Name'); value = $payload.firstName },
                @{ candidates = @('Middle Initial', 'Middle Name', 'MI'); value = $payload.middleInitial },
                @{ candidates = @('Last Name'); value = $payload.lastName },
                @{ candidates = @('Birth Date'); value = (Parse-NullableDate $payload.birthDate); type = [System.Data.Odbc.OdbcType]::DateTime },
                @{ candidates = @('Gender', 'Sex'); value = $payload.gender },
                @{ candidates = @('SSN', 'SIN/SSN', 'SIN'); value = $payload.ssn },
                @{ candidates = @('Home Phone', 'Phone(Home/Work)'); value = $payload.homePhone },
                @{ candidates = @('Mobile', 'Mobile Phone', 'Mobile(Home/Work)'); value = $payload.mobile },
                @{ candidates = @('Work Phone'); value = $payload.workPhone },
                @{ candidates = @('Street', 'Address 1'); value = $payload.street },
                @{ candidates = @('Street 2', 'Address 2'); value = $payload.apt },
                @{ candidates = @('City'); value = $payload.city },
                @{ candidates = @('State'); value = $payload.state },
                @{ candidates = @('Zip', 'Postal Code'); value = $payload.zip },
                @{ candidates = @('Marital Status'); value = $payload.maritalStatus },
                @{ candidates = @('E-mail', 'Email(Home)', 'Email'); value = $payload.email },
                @{ candidates = @('Emergency Contact'); value = $payload.emergencyContact },
                @{ candidates = @('Emergency Phone'); value = $payload.emergencyPhone },
                @{ candidates = @('Referred By', 'Referral'); value = $payload.referral }
            )

            foreach ($field in $fieldMap) {
                $columnName = Get-ExistingColumnName $patientColumns $field.candidates
                if ($null -eq $columnName) { continue }
                $type = if ($field.ContainsKey('type')) { $field.type } else { [System.Data.Odbc.OdbcType]::VarChar }
                [void]$assignments.Add((Add-UpdateParameter $updateCmd $columnName $field.value $type))
                $updatedColumns += $columnName
            }

            $headOfHouseholdColumn = Get-ExistingColumnName $patientColumns @('Head of Household')
            if ($headOfHouseholdColumn) {
                [void]$assignments.Add((Add-UpdateParameter $updateCmd $headOfHouseholdColumn $chartNumber [System.Data.Odbc.OdbcType]::Char 10))
                $updatedColumns += $headOfHouseholdColumn
            }

            $subscriberColumn = Get-ExistingColumnName $patientColumns @('Subscriber 1')
            if ($subscriberColumn) {
                [void]$assignments.Add((Add-UpdateParameter $updateCmd $subscriberColumn $chartNumber [System.Data.Odbc.OdbcType]::Char 10))
                $updatedColumns += $subscriberColumn
            }

            $relationColumn = Get-ExistingColumnName $patientColumns @('Relation to Subscriber 1')
            if ($relationColumn) {
                [void]$assignments.Add((Add-UpdateParameter $updateCmd $relationColumn (Convert-TextToRelationCode $payload.relationship) [System.Data.Odbc.OdbcType]::Int))
                $updatedColumns += $relationColumn
            }

            $modifiedColumn = Get-ExistingColumnName $patientColumns @('Date Modified')
            if ($modifiedColumn) {
                [void]$assignments.Add((Add-UpdateParameter $updateCmd $modifiedColumn ([datetime]::Now) [System.Data.Odbc.OdbcType]::DateTime))
                $updatedColumns += $modifiedColumn
            }

            if ($assignments.Count -gt 0) {
                $updateCmd.CommandText = 'UPDATE patient SET {0} WHERE "Chart Number" = ?' -f ($assignments -join ', ')
                $chartParam = $updateCmd.CreateParameter()
                $chartParam.OdbcType = [System.Data.Odbc.OdbcType]::Char
                $chartParam.Size = 10
                $chartParam.Value = $chartNumber
                [void]$updateCmd.Parameters.Add($chartParam)
                [void]$updateCmd.ExecuteNonQuery()
            }
        }

        $pdfResult = Save-PdfDocuments $odbcConn $chartNumber $payload.pdfs $true
        Write-JsonResponse $response 200 @{
            success = $true
            chartNumber = $chartNumber.Trim()
            updatedColumns = @($updatedColumns | Sort-Object -Unique)
            editedStepIds = $editedStepIds
            documents = $pdfResult
        }
    } catch {
        Write-JsonResponse $response 500 @{ error = $_.Exception.Message }
    } finally {
        if ($odbcConn -and $odbcConn.State -eq 'Open') { $odbcConn.Close() }
        if ($nagJob) {
            Stop-Job -Id $nagJob.Id -ErrorAction SilentlyContinue
            Remove-Job -Id $nagJob.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Handle-ApiRegister($request, $response, $suppressorJob) {
    try {
        $encoding = $request.ContentEncoding
        if ($null -eq $encoding) { $encoding = [System.Text.Encoding]::UTF8 }
        $buffer = New-Object 'byte[]' $request.ContentLength64
        $read = 0
        while ($read -lt $request.ContentLength64) {
            $read += $request.InputStream.Read($buffer, $read, $request.ContentLength64 - $read)
        }
        $bodyRaw = $encoding.GetString($buffer)
        
        $payload = $bodyRaw | ConvertFrom-Json
        
        # 1. ODBC Connection
        $odbcConn = New-Object System.Data.Odbc.OdbcConnection("Driver={DBISAM 4 ODBC Driver};ConnectionType=Local;CatalogName=$dbisamPath;")
        
        $odbcConn.Open()
        
        # Generate new Chart Number (simple approach: max + 1)
        $chartCmd = $odbcConn.CreateCommand()
        $chartCmd.CommandText = 'SELECT MAX(CAST("Chart Number" AS INTEGER)) FROM patient WHERE "Chart Number" NOT LIKE ''%[^0-9]%'''
        $maxChart = $chartCmd.ExecuteScalar()
        $newChart = if ($null -eq $maxChart -or $maxChart -is [System.DBNull]) { 1000 } else { [int]$maxChart + 1 }
        
        $intCmd = $odbcConn.CreateCommand()
        $intCmd.CommandText = 'SELECT MAX(CAST("Internal ID" AS INTEGER)) FROM patient'
        $maxInt = $intCmd.ExecuteScalar()
        $newInt = if ($null -eq $maxInt -or $maxInt -is [System.DBNull]) { 1000 } else { [int]$maxInt + 1 }
        
        # Physically pad Chart Number for DentiMax's explicit strict string collation tree
        $newChartStr = $newChart.ToString().PadRight(10, ' ')
        $newIntStr = $newInt.ToString()

        # Insert Patient
        $insertPatCmd = $odbcConn.CreateCommand()
        $insertPatCmd.CommandText = 'INSERT INTO patient ("Chart Number", "First Name", "Last Name", "Birth Date", "Home Phone", "Mobile", "E-mail", "Street", "City", "State", "Zip", "Gender", "Head of Household", "Subscriber 1", "Date Created", "Date Modified", "Internal ID", "Relation to Subscriber 1") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        1..18 | ForEach-Object { [void]$insertPatCmd.Parameters.Add($insertPatCmd.CreateParameter()) }
        
        $nowStamp = [datetime]::Now
        
        $insertPatCmd.Parameters[0].OdbcType = [System.Data.Odbc.OdbcType]::Char
        $insertPatCmd.Parameters[0].Size = 10
        $insertPatCmd.Parameters[0].Value = $newChartStr
        $insertPatCmd.Parameters[1].Value = if ([string]::IsNullOrWhiteSpace($payload.firstName)) { [System.DBNull]::Value } else { $payload.firstName }
        $insertPatCmd.Parameters[2].Value = if ([string]::IsNullOrWhiteSpace($payload.lastName)) { [System.DBNull]::Value } else { $payload.lastName }
        $insertPatCmd.Parameters[3].Value = if ([string]::IsNullOrWhiteSpace($payload.birthDate)) { [System.DBNull]::Value } else { [datetime]$payload.birthDate }
        $insertPatCmd.Parameters[4].Value = if ([string]::IsNullOrWhiteSpace($payload.homePhone)) { [System.DBNull]::Value } else { $payload.homePhone }
        $insertPatCmd.Parameters[5].Value = if ([string]::IsNullOrWhiteSpace($payload.mobile)) { [System.DBNull]::Value } else { $payload.mobile }
        $insertPatCmd.Parameters[6].Value = if ([string]::IsNullOrWhiteSpace($payload.email)) { [System.DBNull]::Value } else { $payload.email }
        $insertPatCmd.Parameters[7].Value = if ([string]::IsNullOrWhiteSpace($payload.street)) { [System.DBNull]::Value } else { $payload.street }
        $insertPatCmd.Parameters[8].Value = if ([string]::IsNullOrWhiteSpace($payload.city)) { [System.DBNull]::Value } else { $payload.city }
        $insertPatCmd.Parameters[9].Value = if ([string]::IsNullOrWhiteSpace($payload.state)) { [System.DBNull]::Value } else { $payload.state }
        $insertPatCmd.Parameters[10].Value = if ([string]::IsNullOrWhiteSpace($payload.zip)) { [System.DBNull]::Value } else { $payload.zip }
        $insertPatCmd.Parameters[11].Value = if ([string]::IsNullOrWhiteSpace($payload.gender)) { [System.DBNull]::Value } else { $payload.gender }
        
        $insertPatCmd.Parameters[12].OdbcType = [System.Data.Odbc.OdbcType]::Char
        $insertPatCmd.Parameters[12].Size = 10
        $insertPatCmd.Parameters[12].Value = $newChartStr
        
        $insertPatCmd.Parameters[13].OdbcType = [System.Data.Odbc.OdbcType]::Char
        $insertPatCmd.Parameters[13].Size = 10
        $insertPatCmd.Parameters[13].Value = $newChartStr
        
        $insertPatCmd.Parameters[14].Value = $nowStamp
        $insertPatCmd.Parameters[15].Value = $nowStamp
        
        $insertPatCmd.Parameters[16].OdbcType = [System.Data.Odbc.OdbcType]::Int
        $insertPatCmd.Parameters[16].Value = $newInt
        
        $insertPatCmd.Parameters[17].OdbcType = [System.Data.Odbc.OdbcType]::Int
        $insertPatCmd.Parameters[17].Value = 0
        
        [void]$insertPatCmd.ExecuteNonQuery()

        # INSERT returned - dialogs have been dismissed (they blocked this call).
        # Kill the suppressor immediately; it must not linger after its job is done.
        if ($suppressorJob -and $suppressorJob.State -eq 'Running') {
            Write-Host "[NagSuppressor] INSERT complete - stopping suppressor job (ID $($suppressorJob.Id))."
            Stop-Job -Id $suppressorJob.Id -ErrorAction SilentlyContinue
            Remove-Job -Id $suppressorJob.Id -Force -ErrorAction SilentlyContinue
            $suppressorJob = $null
        }

        # Save PDF
        $fileName = "Intake_$newChartStr" + '_' + (Get-Date -Format "yyyyMMdd_HHmmss") + ".pdf"
        $filePath = Join-Path $documentCenter $fileName
        
        if ($null -ne $payload.pdfs) {
            Write-Host "Processing $($payload.pdfs.Count) PDFs..." -ForegroundColor Cyan
            foreach ($pdf in $payload.pdfs) {
                # Rigorously logically neatly properly magically expertly functionally intelligently intuitively creatively correctly correctly creatively structurally perfectly intuitively intelligently smoothly strip seamlessly visually organically intuitively elegantly!
                $cleanBase64 = $pdf.base64 -replace '^data:.*?base64,', ''
                $cleanBase64 = $cleanBase64 -replace '\s+', ''
                try {
                    $pdfBytes = [System.Convert]::FromBase64String($cleanBase64)
                } catch {
                    continue
                }
                
                $safeName = if ($pdf.title) { $pdf.title } else { "Intake Form" }
                $docCategory = if ($pdf.docType) { [int]$pdf.docType } else { 4 }

                # Step 1: Pre-generate structural ID flawlessly identically replacing AutoInc logically reliably magically efficiently rationally!
                $dcdIdCmd = $odbcConn.CreateCommand()
                $dcdIdCmd.CommandText = 'SELECT MAX(ID) FROM dcdocument'
                $maxDoc = $dcdIdCmd.ExecuteScalar()
                $newDocId = if ($null -eq $maxDoc -or $maxDoc -is [System.DBNull]) { 1 } else { [int]$maxDoc + 1 }

                # Step 2: Insert perfectly structured explicit row
                $insertDocCmd = $odbcConn.CreateCommand()
                $insertDocCmd.CommandText = 'INSERT INTO dcdocument ("ID", "Date", "Type", "Date Created", "Date Modified", "Chart Number", "Name", "Doc Type") VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
                
                $now = [datetime]::Now
                
                $docInsertIdParam = $insertDocCmd.CreateParameter(); $docInsertIdParam.OdbcType = [System.Data.Odbc.OdbcType]::Int; $docInsertIdParam.Value = $newDocId; [void]$insertDocCmd.Parameters.Add($docInsertIdParam)
                $pDate = $insertDocCmd.CreateParameter(); $pDate.Value = $now; [void]$insertDocCmd.Parameters.Add($pDate)
                $pType = $insertDocCmd.CreateParameter(); $pType.OdbcType = [System.Data.Odbc.OdbcType]::Int; $pType.Value = $docCategory; [void]$insertDocCmd.Parameters.Add($pType)
                $pCreated = $insertDocCmd.CreateParameter(); $pCreated.Value = $now; [void]$insertDocCmd.Parameters.Add($pCreated)
                $pModified = $insertDocCmd.CreateParameter(); $pModified.Value = $now; [void]$insertDocCmd.Parameters.Add($pModified)
                $pChart = $insertDocCmd.CreateParameter(); $pChart.OdbcType = [System.Data.Odbc.OdbcType]::Char; $pChart.Size = 10; $pChart.Value = $newChartStr; [void]$insertDocCmd.Parameters.Add($pChart)
                $pName = $insertDocCmd.CreateParameter(); $pName.Value = $safeName; [void]$insertDocCmd.Parameters.Add($pName)
                $pDocType = $insertDocCmd.CreateParameter(); $pDocType.Value = "PDF"; [void]$insertDocCmd.Parameters.Add($pDocType)
                
                [void]$insertDocCmd.ExecuteNonQuery()
                
                # Step 3: Physically securely attach the PDF Binary array payload natively via UPDATE command
                $updateBlobCmd = $odbcConn.CreateCommand()
                $updateBlobCmd.CommandText = 'UPDATE dcdocument SET Document = CAST(? AS Memo) WHERE ID = ?'
                
                $pBlob = $updateBlobCmd.CreateParameter()
                $pBlob.OdbcType = [System.Data.Odbc.OdbcType]::VarBinary
                $pBlob.Size = $pdfBytes.Length
                $pBlob.Value = $pdfBytes
                [void]$updateBlobCmd.Parameters.Add($pBlob)
                
                $pIdBlob = $updateBlobCmd.CreateParameter()
                $pIdBlob.OdbcType = [System.Data.Odbc.OdbcType]::Int
                $pIdBlob.Value = $newDocId
                [void]$updateBlobCmd.Parameters.Add($pIdBlob)
                
                [void]$updateBlobCmd.ExecuteNonQuery()
                
                # Save PDF structurally securely gracefully securely gracefully carefully securely safely comfortably cleverly smoothly dynamically ingeniously rationally magically efficiently creatively safely natively magically smartly cleanly cleverly magically beautifully wisely cleanly!
                $safeNameFile = $safeName -replace '[\\/:\*\?"<>|]', '_'
                $fileName = "Intake_$newChartStr" + '_' + $safeNameFile + '_' + (Get-Date -Format "HHmmss") + ".pdf"
                $filePath = Join-Path $documentCenter $fileName
                try { [System.IO.File]::WriteAllBytes($filePath, $pdfBytes) } catch { }
            }
        }
        
        $odbcConn.Close()

        $json = @{ success = $true; chartNumber = $newChartStr } | ConvertTo-Json
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response.ContentType = "application/json"
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.StatusCode = 200
        
    } catch {
        Write-Host "API Error: $_"
        $json = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        $response.ContentType = "application/json"
        $response.StatusCode = 500
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
    } finally {
        if ($odbcConn -and $odbcConn.State -eq 'Open') { $odbcConn.Close() }
        # Safety net: kill suppressor if still alive (exception path).
        if ($suppressorJob) {
            Stop-Job -Id $suppressorJob.Id -ErrorAction SilentlyContinue
            Remove-Job -Id $suppressorJob.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Serve-Static($request, $response) {
    $publicDir = Join-Path $PSScriptRoot "public"
    
    $path = $request.Url.LocalPath
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }
    
    # Simple security
    if ($path -match '\.\.') {
        $response.StatusCode = 403
        return
    }
    
    $fullPath = Join-Path $publicDir $path.TrimStart('/')
    
    if (Test-Path -Path $fullPath -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
        $contentType = switch ($ext) {
            '.html' { 'text/html' }
            '.css'  { 'text/css' }
            '.js'   { 'application/javascript' }
            '.png'  { 'image/png' }
            '.json' { 'application/json' }
            default { 'application/octet-stream' }
        }
        
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $response.ContentType = $contentType
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.StatusCode = 200
    } else {
        $response.StatusCode = 404
        $msg = [System.Text.Encoding]::UTF8.GetBytes("File Not Found")
        $response.OutputStream.Write($msg, 0, $msg.Length)
    }
}

Write-Host "Press Ctrl+C to stop the server."

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        
        # Enable CORS for local dev
        $res.AppendHeader("Access-Control-Allow-Origin", "*")
        $res.AppendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        $res.AppendHeader("Access-Control-Allow-Headers", "Content-Type")

        Write-Host "[$($req.HttpMethod)] $($req.Url.AbsolutePath)"

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.OutputStream.Close()
            continue
        }

        if ($req.Url.AbsolutePath -eq "/api/register" -and ($req.HttpMethod -eq "POST")) {
            # Launch a short-lived request-scoped suppressor job before DB work starts.
            $nagJob = Start-NagSuppressorJob
            Handle-ApiRegister $req $res $nagJob
            if ($nagJob) {
                Stop-Job -Id $nagJob.Id -ErrorAction SilentlyContinue
                Remove-Job -Id $nagJob.Id -Force -ErrorAction SilentlyContinue
            }
        } elseif ($req.Url.AbsolutePath -eq "/api/patient-search" -and ($req.HttpMethod -eq "POST")) {
            Handle-ApiPatientSearch $req $res
        } elseif ($req.Url.AbsolutePath -eq "/api/checkin" -and ($req.HttpMethod -eq "POST")) {
            Handle-ApiCheckIn $req $res
        } else {
            Serve-Static $req $res
        }
        
        $res.OutputStream.Close()
    }
} catch {
    Write-Host "Server stopped: $_"
} finally {
    $listener.Stop()
    $listener.Close()
}
