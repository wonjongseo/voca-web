# Firebase setup

## 1. Create Firebase project

1. Open Firebase Console.
2. Create a project.
3. Add a Web app.
4. Copy the Firebase config values.

## 2. Local environment

Create `.env.local` from `.env.example`.

```env
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=...
VITE_FIREBASE_PROJECT_ID=...
VITE_FIREBASE_APP_ID=...
VITE_FIREBASE_STORAGE_BUCKET=...
VITE_FIREBASE_MESSAGING_SENDER_ID=...
VITE_FIREBASE_MEASUREMENT_ID=...
```

## 3. Authentication

Enable these sign-in providers:

- Email/Password
- Google

## 4. Firestore

Create a Cloud Firestore database, then publish the rules in `firestore.rules`.

The app uses:

- `users/{uid}/words` for private words
- `users/{uid}/reviews` for private study history
- `groups/{groupId}/words` for shared group words
- `groups/{groupId}/reviews` for shared group study history

The app loads at most 500 words and 2,000 reviews per cloud load to keep reads predictable.

## 5. Hosting environment

Add the same `VITE_FIREBASE_*` values to the production hosting environment before deploying.
