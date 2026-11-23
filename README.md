# Gather - Real-Time Chat Application

Gather is a full-stack chat application with a React interface, an Express and
Socket.IO server, JWT authentication, and MongoDB message persistence. Users
can create an account, join the `general` room, chat in real time, see who is
online, view typing indicators, and see read receipts on their messages.

> **Deployment status:** The project includes a Render Blueprint, but a live
> service must still be created and configured with a production MongoDB URI.
> Do not use the local development URLs as a public app URL.

## Features

- Register and sign in with a username and password.
- Store passwords as bcrypt hashes; authenticate HTTP requests and Socket.IO
  connections with signed JWTs.
- Keep the login cookie HTTP-only and refresh the in-memory Socket.IO token
  after a page reload.
- Send and receive messages in real time in the `general` room.
- Persist messages in MongoDB and load the most recent 50 messages for a user.
- Display online users, typing indicators, timestamps, and read receipts.
- Show your own messages differently from messages sent by other users.
- Automatically scroll to the latest messages.
- Serve the production React build and Socket.IO server from one Render web
  service.

## Technology

- **Frontend:** React 19, Vite 8
- **Backend:** Node.js, Express 5, Socket.IO 4
- **Database:** MongoDB with Mongoose
- **Authentication:** JSON Web Tokens and bcrypt
- **Tests:** Node.js built-in test runner with in-memory model doubles
- **Deployment configuration:** Render Blueprint (`render.yaml`)

## Project structure

```text
.
|-- models/
|   |-- Message.js          # Message and read receipt schema
|   `-- User.js             # User and normalized username schema
|-- src/
|   |-- App.jsx             # Authentication and chat interface
|   |-- main.jsx            # React entry point
|   `-- styles.css          # Responsive application styles
|-- mobile/
|   |-- lib/                # Flutter chat screens and API/Socket.IO client
|   |-- test/               # Flutter model tests
|   `-- README.md           # Mobile setup and APK build instructions
|-- test/
|   `-- server.test.js      # HTTP, auth, persistence, and Socket.IO tests
|-- .env.example            # Local environment variable template
|-- render.yaml             # Render Blueprint
|-- server.js               # Express API and Socket.IO server
|-- vite.config.mjs         # Vite configuration
|-- package.json
`-- README.md
```

## Requirements

- Node.js `20.19` or later
- npm
- MongoDB running locally, or a MongoDB connection string (for example, from
  MongoDB Atlas)

## Run locally

1. Install dependencies:

   ```sh
   npm ci
   ```

2. Copy the environment template:

   **Windows PowerShell**

   ```powershell
   Copy-Item .env.example .env
   ```

   **macOS/Linux**

   ```sh
   cp .env.example .env
   ```

3. Generate a random JWT signing secret:

   ```sh
   node -e "console.log(require('node:crypto').randomBytes(48).toString('hex'))"
   ```

   Put the generated value in `.env` as `JWT_SECRET`. The server requires at
   least 32 bytes. Never commit `.env` or share its values.

4. Make sure MongoDB is running and `MONGODB_URI` in `.env` points to it. The
   example value uses a local database:

   ```dotenv
   MONGODB_URI=mongodb://127.0.0.1:27017/real-time-chat
   ```

5. Start the server and frontend together:

   ```sh
   npm run dev
   ```

6. Open [http://localhost:5173](http://localhost:5173). The Express and
   Socket.IO server listens at [http://localhost:3001](http://localhost:3001).

The development command starts Vite and the Node server. The server connects to
MongoDB before accepting requests; if MongoDB is unavailable, check the
connection string and database availability.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `PORT` | No | `3001` | HTTP and Socket.IO server port. |
| `CLIENT_ORIGIN` | No | `http://localhost:5173` locally; `RENDER_EXTERNAL_URL` on Render | Exact browser origin allowed by HTTP and Socket.IO CORS. Set this to the deployed frontend origin when using a custom domain or separate frontend. |
| `MONGODB_URI` | Yes | None in the server | MongoDB connection string. |
| `JWT_SECRET` | Yes | None | Random signing secret of at least 32 bytes. |
| `VITE_API_URL` | No | `http://localhost:3001` in development; same origin in production | Frontend HTTP API base URL. |
| `VITE_SOCKET_URL` | No | `http://localhost:3001` in development; same origin in production | Frontend Socket.IO server URL. |
| `NODE_ENV` | No | Managed by the runtime | Set to `production` in deployment to enable production cookie settings and static frontend serving. |

`VITE_API_URL` and `VITE_SOCKET_URL` are read by Vite when building the
frontend. Do not leave them pointing to `localhost` in a separately hosted
production frontend.

## npm scripts

| Command | Description |
| --- | --- |
| `npm run dev` | Run the Express server in watch mode and the Vite development server. |
| `npm test` | Run the Node.js test suite. |
| `npm run build` | Create the optimized frontend build in `dist/`. |
| `npm start` | Start the production server. Requires `MONGODB_URI` and `JWT_SECRET`; in production it also serves `dist/`. |
| `npm run preview` | Preview the Vite frontend build. This command does not start the Express or Socket.IO server. |

## Authentication and HTTP API

Endpoints under `/api/auth` are limited to 10 requests per IP address per
15 minutes. Usernames are trimmed, 1-32 characters, and compared without case
sensitivity. Passwords must be 8-72 UTF-8 bytes.

| Method | Path | Authentication | Description |
| --- | --- | --- | --- |
| `GET` | `/health` | No | Health check; returns `{ "status": "ok" }`. |
| `POST` | `/api/auth/register` | No | Create an account and sign in. Body: `{ "username": "...", "password": "..." }`. |
| `POST` | `/api/auth/login` | No | Sign in using the same body as registration. |
| `GET` | `/api/auth/me` | HTTP-only cookie | Restore the current user and return a fresh Socket.IO token. |
| `POST` | `/api/auth/logout` | Optional cookie | Clear the login cookie and disconnect the user's active sockets. |
| `GET` | `/api/messages` | HTTP-only cookie | Return the latest 50 messages in `general`, in chronological order. |

Successful registration and login return a user and a JWT token, and set a
seven-day `chat_token` cookie. The cookie is HTTP-only; it is also marked
`Secure` in production. The frontend keeps the returned socket token in memory
and sends it in the Socket.IO handshake. Passwords are never stored as
plaintext.

Common authentication responses include `400` for invalid input, `401` for
invalid credentials or an expired session, `409` for a duplicate username, and
`429` when the authentication rate limit is exceeded.

## Socket.IO events

The server authenticates every Socket.IO connection using the JWT handshake
option:

```js
const socket = io(SOCKET_URL, {
  auth: { token },
});
```

The sender's username and user ID are derived from the verified JWT. Clients
cannot choose another sender by including a `sender` field in a message.

| Direction | Event | Payload | Behavior |
| --- | --- | --- | --- |
| Server to clients | `users:update` | `string[]` | Current online usernames; broadcast when a socket connects or disconnects. |
| Client to server | `join` | `"general"` | Join the supported room and request recent history. |
| Server to client | `message:history` | `Message[]` | Up to 50 most recent messages, ordered oldest to newest. |
| Client to server | `message:send` | `{ "text": "..." }` | Save and broadcast a message. Text must be 1-2000 characters. |
| Server to room | `message:new` | `Message` | Broadcast a persisted message to all room members. |
| Client to server | `typing:start` | None | Mark the authenticated user as typing in the joined room. |
| Client to server | `typing:stop` | None | Stop that user's typing indicator. The client sends this after 2 seconds without input. |
| Server to room peers | `typing:update` | `{ "username": "...", "isTyping": true }` | Show or hide the typing indicator. A server timeout clears abandoned indicators. |
| Client to server | `messages:read` | `{ "messageIds": ["..."] }` | Persist read receipts for up to 50 valid message IDs in the joined room. |
| Server to room peers | `messages:read` | `{ "messageIds": [...], "reader": { "id": "...", "username": "...", "readAt": "..." } }` | Notify other users that messages were read. |
| Server to client | `chat:error` | `{ "message": "..." }` | Report a rejected event or a persistence error. |

A serialized message has this shape:

```json
{
  "id": "MongoDB message ID",
  "sender": "username",
  "text": "Hello!",
  "room": "general",
  "timestamp": "ISO-8601 timestamp",
  "readBy": []
}
```

The app currently supports the `general` room only. Messages are saved to
MongoDB before they are broadcast. Read receipts are persisted with each
message and are not added for the sender's own messages.

## Data models

- **User:** username, normalized unique username, bcrypt password hash, and
  Mongoose timestamps.
- **Message:** user ID, sender name, text, room, read receipt records, and
  Mongoose timestamps. A room/date index supports loading recent history.
- **Read receipt:** reader's user ID and username plus the read timestamp.

## Tests

Run:

```sh
npm test
```

The tests cover registration and login, JWT-protected Socket.IO connections,
room history limits, message persistence before broadcast, typing events, read
receipts, and logout. They use in-memory model doubles, so MongoDB does not
need to be running for the test suite.

## Deploy to Render

The repository includes [`render.yaml`](./render.yaml), which defines one
Render web service. That service builds the React frontend and serves it from
Express alongside the HTTP API and Socket.IO server, so WebSocket traffic uses
the same origin.

1. Push this repository to GitHub.
2. Sign in to Render and create a new **Blueprint** from this repository.
3. Review the service settings loaded from `render.yaml`.
4. Set `MONGODB_URI` to the production MongoDB connection string in Render's
   environment settings. Keep it secret; do not put it in this file or in
   source control.
5. Render generates `JWT_SECRET` from the Blueprint configuration. Ensure the
   MongoDB service allows connections from the deployed backend.
6. Deploy the Blueprint and wait for the `/health` check to pass.
7. Open the Render service URL and test registration, messaging, typing, and
   read receipts with two separate users or browser sessions.

The Blueprint uses `npm ci --include=dev && npm run build` and `npm start`.
Render supplies `PORT`; the default allowed browser origin uses
`RENDER_EXTERNAL_URL`. If a custom domain is used, set `CLIENT_ORIGIN` to the
exact HTTPS origin. The free web-service plan may spin down while idle.

For a separate frontend host, configure `VITE_API_URL` and `VITE_SOCKET_URL`
with the backend's HTTPS/WSS origin at frontend build time, and set
`CLIENT_ORIGIN` on the backend to the frontend's exact origin. The backend host
must support persistent WebSocket connections.

## Troubleshooting

- **Server exits with a `JWT_SECRET` error:** Set a random secret of at least
  32 bytes in `.env` or the deployment environment.
- **Server exits with a `MONGODB_URI` error or cannot connect:** Verify
  MongoDB is running, the URI is correct, and the database host permits the
  server to connect.
- **Browser reports a CORS or connection error:** Check `CLIENT_ORIGIN`,
  `VITE_API_URL`, and `VITE_SOCKET_URL`. Origins must include the correct
  scheme and hostname; production URLs must not point to `localhost`.
- **Socket connection is rejected:** Sign in again to obtain a valid token and
  confirm the frontend sends it as `auth.token`.
- **Frontend is blank after deployment:** Confirm the build completed and
  `dist/` was created before `npm start` ran.
- **Render reports a failed health check:** Check the service logs and ensure
  `MONGODB_URI` and `JWT_SECRET` are configured.

## Security notes

- Never commit `.env`, MongoDB credentials, or real JWT secrets. `.gitignore`
  excludes local environment files and build output.
- Use HTTPS in production; the authentication cookie is marked `Secure` when
  `NODE_ENV=production`.
- Keep production `CLIENT_ORIGIN` limited to the exact trusted frontend origin.
- Use a unique random `JWT_SECRET` in each environment and store it with the
  hosting provider's secret/environment settings.
