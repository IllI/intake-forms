# DentiMax Intake App: Implementation Plan & Tasks

This plan addresses migrating the iPad patient intake application to a modern Vue 3 Single Page Application (SPA), handling dynamic form construction and PDF generation while addressing the branding changes.

> [!TIP]
> **DBISAM Trial Nag-Screen**: The trial driver shows a popup every time it's called. We've added a background process to `server.ps1` to automatically dismiss these.

For detailed database connection info, see [DENTIMAX_DB_GUIDE.md](file:///e:/MogoMigration/DentiMax_Intake_App/DENTIMAX_DB_GUIDE.md).

## 1. Project Overview
- **Goal**: Reconstruct patient intake forms in Vue 3, generate signed PDFs, and automate patient creation in DentiMax.
- **Branding**: Update all forms to **Smile You're Golden** (Chicago Ave, Oak Park).
- **Architecture**: Vue 3 (CDN-based for portability) + local PowerShell API server.

## 2. Implementation Plan

### Architecture Decision: Vue Reconstruction vs. DocuSign
We are proceeding with **reconstructing the forms natively in Vue**. 
- **Reason**: DocuSign requires internet-accessible webhooks which the local PowerShell server cannot easily receive. 
- **Benefit**: 100% local, no subscription costs, and instant data extraction.

### Components
#### [NEW] `public/index.html` & `public/app.js`
- Vue 3 implementation using CDN.
- Modern aesthetic (glassmorphism, outfit typography).
- Logo integration using `smileYou'reGoldenLogo.png`.

#### [NEW] `Watch_DentiMax_DB.ps1`
- A utility to "sniff" DBISAM table changes to ensure 100% accuracy when the API creates a patient.

### Integration
- **Frontend**: Uses `html2pdf.js` for PDF generation.
- **Backend**: `server.ps1` updated with precise SQL inserts based on sniffing results.

---

## 3. Checklist / Tasks

- [x] Plan Reconstruction Approach (Vue vs. DocuSign)
- [ ] Initialize Vue 3 (CDN-based) in `public/app.js`
- [ ] Elegantly integrate `smileYou'reGoldenLogo.png` into the design.
- [ ] Scaffold the Multi-step Wizard interface.
- [ ] **Form 1: Dental Treatment Consent Form**
  - [ ] Build UI with interactive checkboxes and signatures.
  - [ ] Apply "Smile You're Golden" branding.
- [x] Implement HTML-to-PDF logic.
- [x] **Database Sniffing**: Run `Watch_DentiMax_DB.ps1` to validate table schema.
- [x] Update `server.ps1` with verified 100% accurate SQL inserts.
- [ ] Test end-to-end registration flow.
New-NetFirewallRule -DisplayName "DentiMax Intake App 5001" -Direction Inbound -Protocol TCP -LocalPort 5001 -Action Allow
