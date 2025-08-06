# ScanMate - AI-Powered Document Scanner

An intelligent Flutter document scanner with offline AI summarization powered by Google's Gemma 3 model. Features ML Kit Document Scanner API and VisionKit integration.

[![pub package](https://img.shields.io/pub/v/flutter_doc_scanner.svg)](https://pub.dev/packages/flutter_doc_scanner)

## Example

Check out the `example` directory for a sample Flutter app using `flutter_doc_scanner`.

## Document Scanner Demo
<p align="center">
	<img src="https://github.com/shirsh94/flutter_doc_scanner/blob/main/demo/doc_scan_demo.gif?raw=true" width="200"  />
</p>

## Screenshots
| ![Screenshot 1](https://raw.githubusercontent.com/shirsh94/flutter_doc_scanner/main/demo/screen_shot_1.jpg?raw=true) | ![Screenshot 2](https://raw.githubusercontent.com/shirsh94/flutter_doc_scanner/main/demo/screen_shot_2.jpg?raw=true) | ![Screenshot 3](https://raw.githubusercontent.com/shirsh94/flutter_doc_scanner/main/demo/screen_shot_3.jpg?raw=true) |
|----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| ![Screenshot 4](https://raw.githubusercontent.com/shirsh94/flutter_doc_scanner/main/demo/screen_shot_4.jpg?raw=true) | ![Screenshot 5](https://raw.githubusercontent.com/shirsh94/flutter_doc_scanner/main/demo/screen_shot_5.jpg?raw=true) | ![Screenshot 6](https://raw.githubusercontent.com/shirsh94/flutter_doc_scanner/main/demo/screen_shot_6.jpg?raw=true) |


## Features

- High-quality and consistent user interface for digitizing physical documents.
- Accurate document detection with precise corner and edge detection for optimal scanning results.
- Flexible functionality allows users to crop scanned documents, apply filters, remove fingers, remove stains and other blemishes.
- On-device processing helps preserve privacy.
- Support for sending digitized files in PDF and JPEG formats back to your app.
- Ability to set a scan page limit.
- Support for image(png,jpeg) format and PDF has been added through various methods.


## Installation

To use this plugin, add `flutter_doc_scanner` as a dependency in your `pubspec.yaml` file.

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_doc_scanner: ^0.0.16

```
Got it! Here's a more detailed explanation:

## Usage

Use the following function for document scanning on Android and iOS:

```dart
  Future<void> scanDocument() async {
  //by default way they fetch pdf for android and png for iOS
  dynamic scannedDocuments;
  try {
    scannedDocuments = await FlutterDocScanner().getScanDocuments(page: 3) ??
        'Unknown platform documents';
  } on PlatformException {
    scannedDocuments = 'Failed to get scanned documents.';
  }
  print(scannedDocuments.toString());
}
```
**Note-: If you want to obtain only a PDF scanned document, call getScannedDocumentAsPdf(). Similarly, if you want to get a scanned document in image format, use getScannedDocumentAsImages().**


## Project Setup
Follow the steps below to set up your Flutter project on Android, iOS, and Web.

### Android

#### Minimum Version Configuration
Ensure you meet the minimum version requirements to run the application on Android devices.
In the `android/app/build.gradle` file, verify that `minSdkVersion` is at least 21. This setting specifies the minimum Android API level required to run your app, ensuring compatibility with a wide range of Android devices.

```gradle
android {
    ...
    defaultConfig {
        ...
        minSdkVersion 21
        ...
    }
    ...
}
```

### iOS
#### Minimum Version Configuration
Ensure you meet the minimum version requirements to run the application on iOS devices.
In the `ios/Podfile` file, make sure the iOS platform version is at least 13.0. This setting specifies the minimum iOS version required to run your app, ensuring compatibility with a wide range of iOS devices.

```ruby
platform :ios, '13.0'
```

#### Permission Configuration
1. Add a String property to the app's Info.plist file with the key `NSCameraUsageDescription` and the value as the description for why your app needs camera access. This step is required by Apple to explain to users why the app needs access to the camera, and it's crucial for App Store approval.

```ruby
  <key>NSCameraUsageDescription</key>
  <string>Camera Permission Description</string>
```

2. The `permission_handler` dependency used by `flutter_doc_scanner` uses macros to control whether a permission is enabled. To enable camera permission, add the following to your `Podfile` file. This step ensures that your app can request and handle camera permissions on iOS devices:

 ```ruby
   post_install do |installer|
     installer.pods_project.targets.each do |target|
       ... # Here are some configurations automatically generated by flutter

       # Start of the permission_handler configuration
       target.build_configurations.each do |config|

         # You can enable the permissions needed here. For example, to enable camera
         # permission, just remove the `#` character in front so it looks like this:
         #
         # ## dart: PermissionGroup.camera
         # 'PERMISSION_CAMERA=1'
         #
         #  Preprocessor definitions can be found at: https://github.com/Baseflow/flutter-permission-handler/blob/master/permission_handler_apple/ios/Classes/PermissionHandlerEnums.h
         config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
           '$(inherited)',

           ## dart: PermissionGroup.camera
           'PERMISSION_CAMERA=1',
         ]

       end
       # End of the permission_handler configuration
     end
   end
   ```

### Web
Currently, we have removed web support for this library. For document scanning on the web, you can use the following library: [flutter_doc_scanner_web](https://pub.dev/packages/flutter_doc_scanner_web).

## Cover Page Feature Setup

To use the cover page feature, you need to:

1. Add the NSU logo to the assets folder:
   - Create a directory named `assets` in your project root
   - Save the North South University logo as `nsu_logo.png` in that directory
   - Make sure the image is added to pubspec.yaml under the assets section

2. The cover page feature allows students to add:
   - Name and ID 
   - Course name and section
   - Faculty initial (limited to 5 characters)
   - Submission details

3. This generates a professional cover page that will be added to your scanned documents.

## Issues and Feedback

Please file [issues](https://github.com/shirsh94/flutter_doc_scanner/issues) to send feedback or report a bug. Thank you!

## License

The MIT License (MIT) Copyright (c) 2024 Shirsh Shukla

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
