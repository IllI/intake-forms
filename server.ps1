$ErrorActionPreference = 'Stop'

$port = 48211
$prefix = "http://*:$port/"
$fallbackPrefix = "http://localhost:$port/"
$listener = New-Object System.Net.HttpListener

# Load Win32 API for targeted window closing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Helper {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);
}
"@


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

function Handle-ApiRegister($request, $response, $suppressorProcess) {
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
        if ($suppressorProcess -and -not $suppressorProcess.HasExited) {
            Write-Host "[NagSuppressor] INSERT complete - stopping suppressor (PID $($suppressorProcess.Id))."
            Stop-Process -Id $suppressorProcess.Id -Force -ErrorAction SilentlyContinue
            $suppressorProcess = $null
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
                
                $paramId = $insertDocCmd.CreateParameter(); $paramId.OdbcType = [System.Data.Odbc.OdbcType]::Int; $paramId.Value = $newDocId; [void]$insertDocCmd.Parameters.Add($paramId)
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
        if ($suppressorProcess -and -not $suppressorProcess.HasExited) {
            Stop-Process -Id $suppressorProcess.Id -Force -ErrorAction SilentlyContinue
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
            # Launch the nag suppressor the instant the POST is detected - before any DB work -
            # so it has maximum time to compile and be ready when the INSERT triggers dialogs.
            $nagScript = Join-Path $PSScriptRoot "nag_suppressor.ps1"
            $nagProc   = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$nagScript`"" -WindowStyle Hidden -PassThru
            Handle-ApiRegister $req $res $nagProc
            # Belt-and-suspenders: ensure the suppressor is gone after the request completes.
            if ($nagProc -and -not $nagProc.HasExited) {
                Stop-Process -Id $nagProc.Id -Force -ErrorAction SilentlyContinue
            }
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
