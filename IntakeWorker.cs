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