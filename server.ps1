# ============================================================
# EagleSoft Patient Intake Server
# Runs as a Windows Scheduled Task on D16WNH03
# All paths are absolute local server paths (not UNC)
# ============================================================

$ErrorActionPreference = 'Continue'

# --- Absolute paths (safe for Task Scheduler / Service context) ---
$scriptRoot  = "D:\EagleSoft\Golden Rule Dental Patient Intake Form\intake-forms"
$publicDir   = "$scriptRoot\public"
$logFile     = "D:\EagleSoft\Golden Rule Dental Patient Intake Form\intake-server.log"
$apiPath     = "D:\EagleSoft\API"
$sharedPath  = "D:\EagleSoft\Shared Files"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    try {
        $stream = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
        $writer.WriteLine($line)
        $writer.Close()
        $stream.Close()
    } catch { }
    Write-Output $line
}

Write-Log "Server starting..."

# --- Prepend SQL Anywhere native DLL directory to PATH so SAConnectionStringBuilder can find dblib17.dll etc. ---
$sqlAnyNativePath = "$sharedPath\x64"
if ($env:PATH -notlike "*$sqlAnyNativePath*") {
    $env:PATH = "$sqlAnyNativePath;" + $env:PATH
}
Write-Log "PATH updated with SQL Anywhere native libs"

# --- Load Patterson SDK DLLs (must be local paths for .NET CAS policy) ---
$sdkDlls = @(
    "$sharedPath\x64\Sap.Data.SQLAnywhere.v4.5.dll",
    "$apiPath\Patterson.PTCBaseObjects.SharedObjects.dll",
    "$apiPath\Patterson.PTCBaseObjects.BaseObjects.dll",
    "$apiPath\Patterson.Eaglesoft.Library.Dtos.dll",
    "$sharedPath\PattersonSDK.dll",
    "$sharedPath\Patterson.Services.PatientService.dll",
    "$sharedPath\Patterson.Services.DocumentService.dll"
)
foreach ($dll in $sdkDlls) {
    if (Test-Path $dll) {
        try {
            Add-Type -Path $dll -ErrorAction SilentlyContinue
            Write-Log "Loaded: $(Split-Path $dll -Leaf)"
        } catch {
            Write-Log "WARNING: Could not load $dll - $_" "WARN"
        }
    } else {
        Write-Log "WARNING: DLL not found: $dll" "WARN"
    }
}

# --- HTTP Listener ---
$port           = 5001
$listener       = New-Object System.Net.HttpListener
$primaryPrefix  = "http://+:$port/"
$fallbackPrefix = "http://localhost:$port/"

try {
    $listener.Prefixes.Add($primaryPrefix)
    $listener.Start()
    Write-Log "Listening on $primaryPrefix"
} catch {
    Write-Log "Could not bind to $primaryPrefix (may need netsh urlacl or admin). Falling back to localhost only." "WARN"
    $listener.Close()
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($fallbackPrefix)
    $listener.Start()
    Write-Log "Listening on $fallbackPrefix"
}

# --- API Handler ---
function Handle-ApiRegister {
    param($request, $response)
    try {
        $encoding = if ($request.ContentEncoding) { $request.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
        $buffer   = New-Object byte[] $request.ContentLength64
        $read     = 0
        while ($read -lt $request.ContentLength64) {
            $read += $request.InputStream.Read($buffer, $read, $request.ContentLength64 - $read)
        }
        $payload = [System.Text.Encoding]::UTF8.GetString($buffer) | ConvertFrom-Json

        Write-Log "Received submission: $($payload.firstName) $($payload.lastName)"

        # Build the native Patient object (NOT PatientDto)
        $patient                = New-Object Patterson.Services.PatientService.Patient
        $patient.FirstName      = $payload.firstName
        $patient.LastName       = $payload.lastName
        $patient.MiddleInitial  = $payload.middleInitial
        if ($payload.birthDate -and $payload.birthDate -ne '') {
            $patient.BirthDate  = [datetime]::Parse($payload.birthDate)
        }
        $patient.Address1       = $payload.street
        $patient.City           = $payload.city
        $patient.State          = $payload.state
        $patient.Zipcode        = $payload.zip
        $patient.EmailAddress   = $payload.email
        $patient.HomePhone      = $payload.homePhone
        $patient.CellPhone      = $payload.mobile
        $patient.WorkPhone      = $payload.workPhone
        $patient.Sex            = $payload.gender
        $patient.MaritalStatus  = $payload.maritalStatus
        $patient.Status         = "A"   # A = Active
        $patient.PatientStatus  = "P"   # P = Patient
        $patient.DateEntered    = [datetime]::Now
        $patient.PracticeId     = 1

        $workerExe = "D:\EagleSoft\Shared Files\IntakeWorker.exe"
        $patientId = $null

        Write-Log "Attempting Patient creation via IntakeWorker native payload..."
        
        $output = & $workerExe "patient" "$($payload.firstName)" "$($payload.lastName)" "$($payload.dob)" "$($payload.address)" "$($payload.city)" "$($payload.state)" "$($payload.zip)" "$($payload.phone)" "$($payload.email)"
        
        # Log the output
        $output | ForEach-Object { Write-Log $_ }

        # Extract Patient ID
        $matched = $output | Select-String "Patient ID: (\w+)"
        if ($matched) {
            $patientId = $matched.Matches[0].Groups[1].Value
        }

        if (-not $patientId) {
            throw "Failed to create patient. Worker output: $output"
        }

        Write-Log "Patient created. ID=$patientId Name=$($payload.firstName) $($payload.lastName)"

        # --- Save PDFs to Eaglesoft SmartDocs via Worker ---
        if ($payload.pdfs -and $payload.pdfs.Count -gt 0) {
            $smartDocRoot      = "D:\EagleSoft\Data\SmartDocs"
            $patientDocFolder  = "$smartDocRoot\$patientId"

            if (-not (Test-Path $patientDocFolder)) {
                [System.IO.Directory]::CreateDirectory($patientDocFolder) | Out-Null
            }

            foreach ($pdf in $payload.pdfs) {
                $cleanB64 = ($pdf.base64 -replace '^data:.*?base64,','') -replace '\s+',''
                try {
                    $pdfBytes = [System.Convert]::FromBase64String($cleanB64)
                } catch {
                    Write-Log "Could not decode PDF base64 for '$($pdf.title)': $_" "WARN"
                    continue
                }

                $safeTitle  = ($pdf.title -replace '[\\/:*?"<>|]', '_')
                $timestamp  = (Get-Date).ToString('yyyyMMdd_HHmmss')
                $pdfPath    = "$patientDocFolder\${safeTitle}_${timestamp}.pdf"

                [System.IO.File]::WriteAllBytes($pdfPath, $pdfBytes)
                Write-Log "Wrote PDF to disk: $pdfPath"

                try {
                    Write-Log "Attempting SmartDoc SDK registration via Worker..."
                    $docOutput = & $workerExe "doc" $patientId $pdfPath
                    $docOutput | ForEach-Object { Write-Log $_ }
                } catch {
                    Write-Log "Worker SmartDoc registration failed: $_" "ERROR"
                }
            }
        }

        $jsonOut = "{`"success`":true,`"patientId`":`"$patientId`"}"
        $buf     = [System.Text.Encoding]::UTF8.GetBytes($jsonOut)
        $response.ContentType      = "application/json"
        $response.StatusCode       = 200
        $response.ContentLength64  = $buf.Length
        $response.OutputStream.Write($buf, 0, $buf.Length)

    } catch {
        Write-Log "API Error: $_" "ERROR"
        $jsonOut = [pscustomobject]@{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
        $buf     = [System.Text.Encoding]::UTF8.GetBytes($jsonOut)
        $response.ContentType      = "application/json"
        $response.StatusCode       = 500
        $response.ContentLength64  = $buf.Length
        $response.OutputStream.Write($buf, 0, $buf.Length)
    }
}

# --- Static File Handler ---
function Serve-Static {
    param($request, $response)
    $urlPath = $request.Url.LocalPath
    if ($urlPath -eq '/' -or $urlPath -eq '') { $urlPath = '/index.html' }
    if ($urlPath -match '\.\.') { $response.StatusCode = 403; return }

    $fullPath = "$publicDir" + $urlPath.Replace('/', '\')
    if ([System.IO.File]::Exists($fullPath)) {
        $ext         = [System.IO.Path]::GetExtension($fullPath).ToLower()
        $contentType = switch ($ext) {
            '.html' { 'text/html; charset=utf-8' }
            '.css'  { 'text/css' }
            '.js'   { 'application/javascript' }
            '.png'  { 'image/png' }
            '.jpg'  { 'image/jpeg' }
            '.gif'  { 'image/gif' }
            '.json' { 'application/json' }
            '.svg'  { 'image/svg+xml' }
            '.woff2'{ 'font/woff2' }
            default { 'application/octet-stream' }
        }
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $response.ContentType     = $contentType
        $response.ContentLength64 = $bytes.Length
        $response.StatusCode      = 200
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $response.StatusCode = 404
        $msg = [System.Text.Encoding]::UTF8.GetBytes("Not Found: $urlPath")
        $response.OutputStream.Write($msg, 0, $msg.Length)
    }
}

# --- Main Loop (self-recovering) ---
Write-Log "Server ready."

while ($true) {
    try {
        $context = $listener.GetContext()
        $req     = $context.Request
        $res     = $context.Response

        $res.AppendHeader("Access-Control-Allow-Origin",  "*")
        $res.AppendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        $res.AppendHeader("Access-Control-Allow-Headers", "Content-Type")

        Write-Log "[$($req.HttpMethod)] $($req.Url.AbsolutePath)"

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
        } elseif ($req.Url.AbsolutePath -eq "/api/register" -and $req.HttpMethod -eq "POST") {
            Handle-ApiRegister $req $res
        } else {
            Serve-Static $req $res
        }

        try { $res.OutputStream.Close() } catch {}

    } catch [System.Net.HttpListenerException] {
        Write-Log "Listener exception (shutting down?): $_" "WARN"
        break
    } catch {
        Write-Log "Unhandled request error: $_" "ERROR"
        # Continue serving — don't let one bad request kill the server
    }
}

Write-Log "Server stopped."
$listener.Stop()
$listener.Close()
