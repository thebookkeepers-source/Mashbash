# Mashbash

Mashbash is a Flutter Android food-delivery and restaurant-operations app built around **Meet.Eat.Repeat**. A single APK silently routes customers, owners, managers, counters, and riders from `public.profiles.role`.

Customers and owners use email/password. Manager, counter, and rider accounts sign in with their mobile number and password; the app converts the number to a private Auth email alias, while passwords remain entirely inside Supabase Auth. Google OAuth code remains available but its login button is currently hidden behind a disabled feature flag until provider setup is completed.

## Supabase setup

1. Create a free [Supabase project](https://supabase.com/dashboard).
2. In **Project Settings > API**, copy the Project URL and publishable key.
3. Install the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), sign in, and link the project:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

4. Apply the schema, Row Level Security policies, `product-images` public bucket, and complete Mashbash menu seed:

```bash
supabase db push
```

The initial schema and production workflow migrations are in `supabase/migrations/`. They create the complete menu, three customer home slides, product-image bucket, rider workflow, secure order RPCs, and Row Level Security policies. Product records include public fallback image URLs, so the menu remains usable before custom images are uploaded.

5. Deploy the owner-only staff provisioning and FCM delivery functions:

```bash
supabase functions deploy create-staff
supabase functions deploy send-notification
```

Supabase automatically provides the function with the project URL, anonymous key, and service-role key. Never expose the service-role key to Flutter or commit it.

## Free push notifications with FCM

Supabase remains the only backend, database, and authentication provider. Firebase is used only by the Android client and the `send-notification` Supabase Edge Function for free Firebase Cloud Messaging delivery. The app does not use Firebase Auth, Firestore, or Firebase Storage.

1. Create a Firebase project and register Android application ID `com.mashbash.app`.
2. Enable the Firebase Cloud Messaging HTTP v1 API.
3. Create a Firebase service account key. Put its complete one-line JSON value in an ignored local environment file:

```dotenv
FIREBASE_SERVICE_ACCOUNT_JSON=<one-line JSON from the downloaded service account file>
```

Store that file only as a Supabase Edge Function secret:

```bash
supabase secrets set --env-file supabase/.env.fcm
```

`supabase/.env.fcm` must stay uncommitted. Never put the service account JSON or private key in Flutter, GitHub Actions, or the repository. Existing deployments using the legacy split `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, and `FIREBASE_PRIVATE_KEY` secrets remain supported while rotating to the single JSON secret.

4. Download the Android `google-services.json` for application ID `com.mashbash.app` and place it at `android/app/google-services.json`. The Google Services Gradle plugin supplies the public Android Firebase configuration to the app.

On supported builds the app requests notification permission, stores active FCM tokens in Supabase after every role login, refreshes them, deactivates them on logout, shows foreground alerts through the high-priority `mashbash_orders` Android channel, and opens related order tracking from notification taps. Owners can verify the complete path with **Settings > Send test notification to me**. Firebase service-account secrets are still required in Supabase before the Edge Function can deliver pushes.

## Authentication providers

Email/password authentication is enabled by default. Decide whether customers must confirm email under **Authentication > Providers > Email**.

Google login is currently hidden by `FeatureFlags.googleSignIn` in `lib/utils/feature_flags.dart`. To enable Google later, complete the provider setup below and then enable that flag:

1. Create a Google OAuth web client in Google Cloud.
2. Add Supabase's callback URL, shown under **Authentication > Providers > Google**, as an authorized redirect URI.
3. Enable Google in Supabase and enter the client ID and secret.
4. Add `com.mashbash.app://login-callback` under **Authentication > URL Configuration > Redirect URLs**.

The Android manifest already handles `com.mashbash.app://login-callback`.

## Initial owner

Create an email/password user in **Authentication > Users**. The database trigger creates its customer profile. Promote that profile once in the SQL editor:

```sql
update public.profiles
set role = 'owner', name = 'Mashbash Owner', phone = '+923001234567',
    address = 'Mashbash restaurant'
where email = 'owner@example.com';
```

The owner can then create, edit, disable, and delete manager, counter, and rider accounts inside the app. Staff sign in with the same mobile number and password the owner assigned. Internally, the secure Edge Function maps staff numbers to `digits@staff.mashbash.app`; the Flutter app never receives the service-role key.

Counters always receive View Orders, Update Order Status, and Assign Riders rights. Riders can toggle availability, see only assigned deliveries, move them to Out for Delivery and Delivered, and review delivery history.

## Operations

- Owner and permitted manager/counter accounts can manage every active or inactive category, product, deal, and home slide.
- Owners can upload category, product, deal, and slide images to the public `product-images` bucket or keep an optional image URL fallback.
- Owners control customer category sequence with each category's sort order.
- Owners configure the delivery charge under Settings. New installations default to **Rs. 120**, and the database enforces the configured charge when an order is created.
- Orders follow Received, Accepted, Preparing, Ready for Delivery, Assigned to Rider, Out for Delivery, and Completed.
- Ready orders can be assigned only to active, available riders.
- Dashboard and reports support Today, Yesterday, This Week, This Month, Last Month, and custom date ranges.
- Reports use live order data for revenue, total/completed/pending/cancelled orders, top items, and category sales.
- Menu disable/hide is reversible. Archive/delete is always a soft archive, and database triggers block hard deletion of categories, products, and deals.
- Order items store immutable name, price, quantity, image, category, and line-total snapshots, so archived or edited menu records never change historical orders or reports.
- Customer home slides can link to products, categories, or deals; linked deals can be added directly to cart.
- Global connectivity handling retries failed Supabase polling and requests. When no cached live data is available, every role sees a Mashbash-branded `Connection Error` screen with a Retry button; otherwise the current screen remains usable with an offline banner.

## Run and build

Flutter stable and Android SDK are required. Android 6.0/API 23 is the minimum supported version.

```bash
flutter create --platforms=android .
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Build a release APK with the same compile-time values:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## Signed release APK and AAB

Release signing reads private values from ignored `android/key.properties`. Debug builds and CI continue to work when this file is absent.

Generate a private keystore:

```bash
keytool -genkey -v -keystore mashbash-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mashbash
```

Keep the `.jks` outside the repository or place it at ignored path `android/mashbash-release-key.jks`. Create ignored `android/key.properties`:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=mashbash
storeFile=../mashbash-release-key.jks
```

Build a signed release APK or Play Store AAB:

```bash
flutter build apk --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY
flutter build appbundle --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY
```

A signed release APK is optimized, installable as a stable application, and suitable for sharing. Debug APKs are larger, slower, and intended only for testing. Back up the release keystore securely; future updates must use the same key.

The `Signed Android Release` GitHub Actions workflow runs manually or for `v*` tags. Add these repository Actions secrets before running it:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Create `ANDROID_KEYSTORE_BASE64` from the binary keystore without committing it. The workflow decodes the key only on the runner, builds signed `mashbash-release-apk` and `mashbash-release-aab` artifacts, then removes the temporary signing files.

## Quality checks

```bash
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions runs analyze, tests, debug APK build, and release APK/AAB compile checks. It uploads `mashbash-debug-apk` as a seven-day workflow artifact. The signed release workflow uploads release APK/AAB artifacts only when all signing and Supabase secrets are configured.

Add repository Actions secrets named `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` so CI builds an APK connected to the test project.

## Play Protect and distribution

Mashbash uses the stable `com.mashbash.app` package name, disables Android backups and cleartext traffic, requests only internet and notification permissions, and contains no installer, SMS, contacts, location, overlay, or storage-management behavior. Distribute signed release builds instead of debug APKs. Android may still warn about any APK sideloaded outside Google Play; Google Play internal testing is the preferred client-testing route and removes most sideload trust friction.

## Security model

- Customers can read active products and deals, create orders through a validated database function, and read only their own orders.
- Owners can manage all restaurant data and manage staff through a service-role Edge Function.
- Managers can access only capabilities enabled in `staff_permissions`.
- Counters receive the required order-operation capabilities.
- Riders can read only orders assigned to them and can use only guarded delivery-status RPC transitions.
- Product image writes require menu-management permission; public reads use the `product-images` bucket.
- FCM service-account credentials exist only in Supabase secrets. The JWT-protected notification Edge Function validates the caller and resolves recipients through protected `device_tokens`.
- Active owner/manager/counter sessions detect orders that exceed the configured pending-alert time; the backend deduplicates each delayed-order notification.
- Device tokens can be read only by their owning user; registration and deactivation use guarded database functions.
- Role changes are protected in the database, and passwords are handled only by Supabase Auth.
- Enable **Leaked Password Protection** under Supabase **Authentication > Attack Protection** before production launch.
