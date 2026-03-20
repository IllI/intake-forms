# DentiMax Database Integration Guide

This guide explains how to interface with the DentiMax DBISAM database for the Patient Intake Application.

## 1. Connection Details

DentiMax uses **DBISAM v4**. To connect via PowerShell, you must use the **DBISAM 4 ODBC Driver** (which is installed on this machine).

### Connection String Template:
```powershell
$dbPath = "E:\DentiMax\dentimaxdata\Smile You're Golden"
$connString = "Driver={DBISAM 4 ODBC Driver};ConnectionType=Local;CatalogName=$dbPath;"
$odbcConn = New-Object System.Data.Odbc.OdbcConnection($connString)
```

## 2. Key Tables & Schemas

| Table | Purpose | Key Fields |
| :--- | :--- | :--- |
| **patient** | Main patient records | `Chart Number`, `First Name`, `Last Name`, `Birth Date`, `Mobile`, `Gender` |
| **dcdocument** | Document Center links | `Chart Number`, `Date`, `Type`, `Document` (filename), `File Link` |
| **guarantor** | Billing responsibility | Linked via `Chart Number` or `Guarantor ID` |

### Identifying New Fields
DentiMax occasionally uses "Custom Fields" or specific ID links that aren't obvious. Always check the `Watch_DentiMax_DB.ps1` results if you notice data isn't showing up in the UI.

## 3. The "Sniffing" Workflow (0 Mistakes Strategy)

To ensure the SQL inserts perfectly match what DentiMax expects:

1. **Run the Watcher**: Execute `e:\MogoMigration\Watch_DentiMax_DB.ps1`.
2. **Perform Action**: Open the DentiMax desktop software and manually create a "Perfect" patient with all the fields you want to automate.
3. **Capture Diff**: The script will show you exactly which `.dat` files were touched and show you the JSON of the last 2 rows added.
4. **Update Code**: Copy the field names and values from the script output into the `INSERT` statements in `server.ps1`.

## 4. File References

- **`server.ps1`**: The main API bridge. Handles the `Handle-ApiRegister` function which performs the SQL inserts.
- **`public/app.js`**: Frontend logic. Sends the JSON payload to the server.
- **`Watch_DentiMax_DB.ps1`**: Your diagnostic tool for schema discovery.

## 5. Document Center Storage
- Physical PDFs should be saved to: `E:\DentiMax\Document Center\`
- The `dcdocument` table must have the `File Link` pointing to the full absolute path of the PDF.

---
*Note: Ensure DentiMax is not performing a heavy backup when running direct ODBC writes to prevent table locks.*
