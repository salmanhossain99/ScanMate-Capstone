# Important Setup for Cover Page Feature

## North South University Logo

To complete the setup for the cover page feature, please:

1. Download or create a copy of the North South University logo
2. Name it `nsu_logo.png`
3. Place it in the following locations:
   - `assets/nsu_logo.png` (for the plugin)
   - `example/assets/nsu_logo.png` (for the example app)

The logo should be in PNG format and preferably around 300x300 pixels in size.

## Cover Page Feature Usage

The cover page feature allows you to add a professional cover page to your scanned documents. This cover page includes:

- North South University logo
- Student information (name, ID)
- Course details (name, section)
- Faculty initial (up to 5 characters)
- Assignment details
- Submission date

To use this feature, call the `scanDocumentWithCoverPage()` method which will:
1. Scan documents using the standard document scanner
2. Present a form to fill in cover page details
3. Generate a PDF with the cover page followed by the scanned documents 