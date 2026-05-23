# Stuff Tracker Mobile Web

This is a static mobile-first web shell modeled after the iOS app. It opens with editable local demo data and can connect to the local backend through `/auth/dev`.

From the repo root:

```sh
python3 -m http.server 5173
```

Then open `http://127.0.0.1:5173/web/`.

To use live backend data, start the API on `http://localhost:3002`, open the Account sheet in the web app, and use Dev Sign In.

In production, the backend container serves this folder from the same origin as the API. The deploy workflow syncs both `backend/` and `web/`, and the `../deploy` Compose project rebuilds the `stuff` service from the repository root.
