# Mashbash

Mashbash is a Flutter Android food-delivery and restaurant-operations app built around the tagline **Meet.Eat.Repeat**.

The single APK routes users after authentication using the `role` field in Firestore:

- Customers can register with mobile number and password or continue with Google.
- Owners, managers, and counters sign in with mobile number and password.
- Owners control manager and counter rights.
- Customers browse the live menu, order, and track delivery status.
- Staff manage orders, products, deals, reports, and team access according to their rights.

## Firebase setup

1. Create a Firebase project and add an Android app with package name `com.mashbash.app`.
2. Download `google-services.json` and place it at `android/app/google-services.json`.
3. In Firebase Authentication, enable **Email/Password** and **Google** providers.
4. Add the Android SHA-1 and SHA-256 fingerprints in Firebase project settings. Google Sign-In will not work without the SHA-1 fingerprint.
5. Create Firestore and Firebase Storage, then deploy the included rules and indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

6. Generate production Firebase options:

```bash
flutterfire configure --platforms=android --android-package-name=com.mashbash.app
```

The checked-in `firebase_options.dart` uses compile-time values so the project compiles before local Firebase configuration. Replace it with the generated file before release, or pass the required `--dart-define` values.

## Initial owner

Create the first owner in Firebase Authentication using the phone-derived email format:

```text
923001234567@phone.mashbash.app
```

Then create `users/{uid}` in Firestore:

```json
{
  "name": "Mashbash Owner",
  "phone": "+923001234567",
  "address": "Mashbash restaurant",
  "email": "",
  "role": "owner",
  "rights": {
    "viewOrders": true,
    "updateOrderStatus": true,
    "manageMenu": true,
    "manageDeals": true,
    "viewReports": true
  }
}
```

The app seeds the complete Mashbash menu and launch deal into Firestore on first authenticated run.

## Run and build

Flutter stable and Android SDK are required. Android 6.0/API 23 is the minimum supported version.

```bash
flutter create --platforms=android .
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

For release builds, configure a private Android signing key and replace the debug signing configuration in `android/app/build.gradle`.

## Security model

- Customers can only create and read their own orders.
- Only staff with the matching right can manage menu items, deals, orders, or reports.
- Counter accounts always receive order-view and status-update rights.
- Product and deal images are restricted by file type, size, and staff permissions.
- Passwords are handled only by Firebase Authentication and are never stored in Firestore.
