# CubbyLog Mobile Web

This is a static mobile-first web shell modeled after the iOS app. The web surface requires an account before inventory data is shown or edited.

For a static local preview:

```sh
cd web
python3 -m http.server 5173
```

Then open `http://127.0.0.1:5173/`.

To use backend data locally, start the API on `http://localhost:3002` and use Dev Sign In. The dev sign-in button is only shown on localhost.

In production, the backend container serves this folder from the same origin as the API. The deploy workflow syncs both `backend/` and `web/`, and the `../deploy` Compose project rebuilds the `stuff` service from the repository root.

Item share links use `/items/:homeId/:itemId`. The backend serves the web app for those paths so signed-in web users can reveal the linked item, while iOS can claim the same HTTPS links through Universal Links.

The web app reads public provider IDs and the optional App Store fallback URL from `GET /auth/config`. Set `GOOGLE_WEB_CLIENT_ID` for browser Google Sign-In, `APPLE_WEB_CLIENT_ID` for Sign in with Apple JS, and either `IOS_APP_STORE_URL` or `APP_STORE_APP_APPLE_ID` for the iOS App Store link. The iOS `GOOGLE_CLIENT_ID` and `APPLE_BUNDLE_ID` are still used for native sign-in but are not exposed as web client IDs.
