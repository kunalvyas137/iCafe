# iCafe

A Flutter point-of-sale app for a cafe: billing, inventory with recipe-based
stock deduction, Bluetooth thermal receipt printing, and sales reporting,
backed by Firebase Auth and Cloud Firestore.

## Running

```bash
flutter pub get
flutter run -d macos
```

### Invoice scanning (optional)

**Inventory → Scan Invoice** reads a vendor invoice with Gemini and offers the
line items for receiving into raw-material stock. The key is compiled in, never
committed:

```bash
flutter run -d macos --dart-define=GEMINI_API_KEY=<your key>
flutter build macos --dart-define=GEMINI_API_KEY=<your key>
```

Without the key the feature is disabled and says so; the rest of the app is
unaffected.

## Firestore security rules

`firestore.rules` grants access by role, read from the signed-in user's
`users/{uid}` profile document:

| Collection      | Staff                        | Admin      |
| --------------- | ---------------------------- | ---------- |
| `users`         | read own profile             | full       |
| `products`      | read, `currentStock` updates | full       |
| `raw_materials` | read, `currentStock` updates | full       |
| `recipes`       | read                         | full       |
| `orders`        | read, create                 | + void     |
| `counters`      | read, write                  | read/write |
| `settings`      | read                         | full       |

Anything else is denied, and a signed-in account without a profile document has
no access at all.

Deploy the rules with:

```bash
firebase deploy --only firestore:rules
```

## Creating the first admin

The app does not allow self-registration: profiles are created by an admin from
**Settings → Staff Accounts**. Bootstrap the first admin once, out of band:

1. In the Firebase console, **Authentication → Users → Add user**, and create
   the account with an email and password.
2. Copy the new user's UID.
3. In **Firestore → Data**, create a document in the `users` collection whose
   ID is that UID, with fields:
   - `email` (string) — the same email
   - `name` (string) — display name
   - `role` (string) — `admin`

Sign in with that account; further staff and admin accounts can then be created
in the app.
