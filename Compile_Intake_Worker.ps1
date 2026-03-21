$baseDir = "D:\EagleSoft\Golden Rule Dental Patient Intake Form\intake-forms"
$csPath = "$baseDir\IntakeWorker.cs"
$exePath = "D:\EagleSoft\Shared Files\IntakeWorker.exe"
$configPath = "D:\EagleSoft\Shared Files\IntakeWorker.exe.config"

# 1. Provide the C# Code for the Worker
$csCode = @"
using System;
using System.IO;
using Patterson.Services.PatientService;
using Patterson.Services.DocumentService;
using Patterson.EagleSoft.Library.Dtos;

namespace EaglesoftIntake
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Length == 0) {
                Console.WriteLine("No arguments provided.");
                return;
            }

            if (args[0] == "test") {
                try {
                    var svc = new PatientSvc();
                    Console.WriteLine("[IntakeWorker] SUCCESS! PatientSvc instantiated successfully.");
                    return;
                } catch (Exception ex) {
                    Console.WriteLine("TEST_FAIL: " + ex.ToString());
                    return;
                }
            }

            if (args[0] == "doc") {
                if (args.Length < 3) {
                    Console.WriteLine("ERROR: Not enough arguments for doc.");
                    return;
                }
                string patientId = args[1];
                string pdfPath = args[2];
                try {
                    Console.WriteLine("[IntakeWorker] Registering PDF into SmartDocs for patient " + patientId + "...");
                    var docSvc = new DocumentService();
                    var doc = new DocumentDto();
                    doc.PatientId = patientId;
                    doc.Description = "Intake Form";
                    doc.DateCreated = DateTime.Now;
                    
                    docSvc.CreateDocumentFromFile(doc, pdfPath);
                    Console.WriteLine("[IntakeWorker] PDF attached. SmartDoc return data: " + doc.DocumentId);
                } catch (Exception ex) {
                    Console.WriteLine("ERROR: " + ex.Message);
                }
                return;
            }

            if (args[0] == "patient") {
                // Args: 0=patient, 1=FirstName, 2=LastName, 3=DOB, 4=Address, 5=City, 6=State, 7=Zip, 8=Phone, 9=Email
                try 
                {
                    var patient = new Patient();
                    patient.FirstName = args.Length > 1 ? args[1] : "";
                    patient.LastName = args.Length > 2 ? args[2] : "";
                    
                    if (args.Length > 3 && !string.IsNullOrEmpty(args[3])) {
                        DateTime dob;
                        if (DateTime.TryParse(args[3], out dob)) {
                            patient.BirthDate = dob;
                        }
                    }
                    
                    if (args.Length > 4 && !string.IsNullOrEmpty(args[4])) patient.Address1 = args[4];
                    if (args.Length > 5 && !string.IsNullOrEmpty(args[5])) patient.City = args[5];
                    if (args.Length > 6 && !string.IsNullOrEmpty(args[6])) patient.State = args[6];
                    if (args.Length > 7 && !string.IsNullOrEmpty(args[7])) patient.Zipcode = args[7];
                    if (args.Length > 8 && !string.IsNullOrEmpty(args[8])) patient.HomePhone = args[8];
                    if (args.Length > 9 && !string.IsNullOrEmpty(args[9])) patient.EmailAddress = args[9];

                    Console.WriteLine("[IntakeWorker] Creating Patient " + patient.FirstName + " " + patient.LastName + "...");
                    var patientSvc = new PatientSvc();
                    
                    // Call CreatePatient. ignoreMatchingName = true to avoid stops
                    patientSvc.CreatePatient(ref patient, true);
                    Console.WriteLine("[IntakeWorker] Patient created successfully. Patient ID: " + patient.PatientId);
                } 
                catch (Exception ex) 
                {
                    Console.WriteLine("ERROR: " + ex.Message);
                }
                return;
            }
        }
    }
}
"@
[System.IO.File]::WriteAllText($csPath, $csCode)

# 2. Provide the Application Config for the EXE. We physically force Min Pool Size
$configXml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings>
    <add key="Min Pool Size" value="1" />
    <add key="Max Pool Size" value="100" />
    <!-- Re-routing it to the WCF if needed -->
    <add key="Host" value="localhost" />
    <add key="Port" value="2010" />
    <add key="Binding" value="net.tcp" />
  </appSettings>
  <startup>
    <supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.6" />
  </startup>
</configuration>
"@
[System.IO.File]::WriteAllText($configPath, $configXml)

# 3. Locate the .NET Framework Compiler
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

# 4. Compile the native payload
$ptcBase = "D:\EagleSoft\Shared Files\Patterson.PTCBaseObjects.SharedObjects.dll"
$ptcSvc = "D:\EagleSoft\Shared Files\Patterson.Services.PatientService.dll"
$ptcDocSvc = "D:\EagleSoft\Shared Files\Patterson.Services.DocumentService.dll"
$ptcContracts = "D:\EagleSoft\Shared Files\Patterson.Services.ServiceContracts.dll"
$ptcLibrary = "D:\EagleSoft\Shared Files\Patterson.EagleSoft.Library.dll"

Write-Host "Compiling FULL native C# Worker Payload..."
$compileArgs = @(
    "/t:exe", 
    "/out:$exePath",
    "/r:`"$ptcBase`"",
    "/r:`"$ptcSvc`"",
    "/r:`"$ptcDocSvc`"",
    "/r:`"$ptcContracts`"",
    "/r:`"$ptcLibrary`"",
    "`"$csPath`""
)

& $csc $compileArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "Compile Succeeded! Testing the native payload..."
    & $exePath "test"
} else {
    Write-Host "Compilation failed."
}
