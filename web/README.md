# Stuff Tracker Mobile Web

This is a static mobile-first web shell modeled after the iOS app. It opens with editable local demo data and can connect to the local backend through `/auth/dev`.

From the repo root:

```sh
python3 -m http.server 5173
```

Then open `http://127.0.0.1:5173/web/`.

To use live backend data locally, start the API on `http://localhost:3002`, open the Account sheet in the web app, and use Dev Sign In.

In production, the backend container serves this folder from the same origin as the API. The deploy workflow syncs both `backend/` and `web/`, and the `../deploy` Compose project rebuilds the `stuff` service from the repository root.

The web app reads public provider IDs from `GET /auth/config`. Set `GOOGLE_WEB_CLIENT_ID` for browser Google Sign-In and `APPLE_WEB_CLIENT_ID` for Sign in with Apple JS. The iOS `GOOGLE_CLIENT_ID` and `APPLE_BUNDLE_ID` are still used for native sign-in but are not exposed as web client IDs.
