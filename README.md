# Real-Time Chat Application

## Requirements

- Node.js 20.19 or later
- MongoDB running locally or a MongoDB connection string

Copy `.env.example` to `.env`, generate a JWT signing secret, and put it in
`JWT_SECRET`. For example:

```powershell
Copy-Item .env.example .env
node -e "console.log(require('node:crypto').randomBytes(48).toString('hex'))"
```

Paste the generated value into `.env`, then run:

```sh
npm install
npm run dev
```

The React app runs on port `5173`; Express and Socket.IO run on port `3001`.
Set `MONGODB_URI`, `JWT_SECRET`, `PORT`, or `CLIENT_ORIGIN` in `.env` to
configure the server. If changing `PORT`, update `VITE_API_URL` and
`VITE_SOCKET_URL` to match. `npm start` starts only the server, and
`npm run build` creates the production frontend in `dist/`.

## Authentication and persistence

- `POST /api/auth/register` accepts `{ "username": "...", "password": "..." }`.
  Usernames are 1-32 characters; passwords must be 8-72 UTF-8 bytes.
- `POST /api/auth/login` accepts the same fields. Both endpoints set a
  seven-day, HTTP-only JWT cookie and return a JWT for the Socket.IO handshake;
  passwords are stored as bcrypt hashes.
- `GET /api/auth/me` restores the signed-in user and returns a fresh handshake
  token. `POST /api/auth/logout` clears the cookie and disconnects that user's
  active sockets.
- Authenticated `GET /api/messages` returns the latest 50 messages in
  chronological order.
- Socket.IO verifies `auth.token` in its connection middleware. On `join`
  (currently the `general` room), the server sends the latest 50 stored
  messages as `message:history`.
- The `Message` model stores sender, text, room, and user ID. The server saves
  each valid `message:send` to MongoDB before broadcasting `message:new`; the
  sender name comes from the authenticated account, not the client payload.
- `typing:start` and `typing:stop` are broadcast as `typing:update` to other
  users in the room. The client sends `typing:stop` after two seconds without
  input; a server timeout clears abandoned typing indicators.
- Clients send `messages:read` for messages they display. MongoDB records each
  reader and timestamp, and `messages:read` updates other room members so
  senders see read receipts.

The app's `CLIENT_ORIGIN` defaults to `http://localhost:5173` locally and to Render's
service URL when deployed, with credentialed CORS enabled for the authentication
cookie. Set it to your exact HTTPS origin when using a custom domain. The client
keeps its Socket.IO token in memory and refreshes it from the HTTP-only cookie
after page reload.

## Deploy to Render

The included `render.yaml` builds the React app and serves it from Express with
Socket.IO on the same origin. Push the project to a Git repository, create a
Render Blueprint from that repository, and set `MONGODB_URI` to your production
MongoDB connection string in Render's environment settings. Render generates
`JWT_SECRET`; `PORT` and `CLIENT_ORIGIN` use Render's runtime defaults. The free
web-service plan may spin down while idle.

## Tests

Run `npm test` for API, authentication, persistence-flow, typing, and read
receipt tests. The tests use in-memory model doubles, so they do not require a
running MongoDB instance.
