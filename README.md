# Mashbash

Mashbash is a Flutter Android food-delivery and restaurant-operations app built around **Meet.Eat.Repeat**. A single APK silently routes customers, owners, managers, counters, and riders from `public.profiles.role`.

Customers use email/password or Google OAuth. Staff sign in with their mobile number and password; the app converts the number to a private Auth email alias, while passwords remain entirely inside Supabase Auth.

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

5. Deploy the owner-only staff provisioning function:

```bash
supabase functions deploy create-staff
```

Supabase automatically provides the function with the project URL, anonymous key, and service-role key. Never expose the service-role key to Flutter or commit it.

## Authentication providers

Email/password authentication is enabled by default. Decide whether customers must confirm email under **Authentication > Providers > Email**.

To enable Google:

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
- Orders follow Received, Accepted, Preparing, Ready for Delivery, Assigned to Rider, Out for Delivery, and Completed.
- Ready orders can be assigned only to active, available riders.
- Dashboard and reports support Today, Yesterday, This Week, This Month, Last Month, and custom date ranges.
- Reports use live order data for revenue, total/completed/pending/cancelled orders, top items, and category sales.
- Customer home slides can link to products, categories, or deals; linked deals can be added directly to cart.

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

For release builds, configure a private Android signing key and replace the debug signing configuration in `android/app/build.gradle`.

## Quality checks

```bash
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions runs all three checks and uploads `mashbash-debug-apk` as a seven-day workflow artifact. The default placeholder Supabase URL/key allow CI to compile without repository secrets; use real `--dart-define` values for a working backend.

Add repository Actions secrets named `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` so CI builds an APK connected to the test project.

## Security model

- Customers can read active products and deals, create orders through a validated database function, and read only their own orders.
- Owners can manage all restaurant data and manage staff through a service-role Edge Function.
- Managers can access only capabilities enabled in `staff_permissions`.
- Counters receive the required order-operation capabilities.
- Riders can read only orders assigned to them and can use only guarded delivery-status RPC transitions.
- Product image writes require menu-management permission; public reads use the `product-images` bucket.
- Role changes are protected in the database, and passwords are handled only by Supabase Auth.
