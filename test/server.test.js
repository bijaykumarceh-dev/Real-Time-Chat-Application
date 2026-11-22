const assert = require("node:assert/strict");
const { once } = require("node:events");
const { after, before, test } = require("node:test");
const { io: createClient } = require("socket.io-client");
const { createChatServer } = require("../server");

const clients = [];
let httpServer;
let io;
let serverUrl;
let users;
let messages;

function createMemoryStores() {
  const userRecords = [];
  const messageRecords = [];

  const User = {
    async findOne({ usernameNormalized }) {
      return userRecords.find(
        (user) => user.usernameNormalized === usernameNormalized,
      ) || null;
    },
    async create(values) {
      const user = { ...values, _id: `user-${userRecords.length + 1}` };
      userRecords.push(user);
      return user;
    },
  };

  const Message = {
    async create(values) {
      const message = {
        ...values,
        _id: String(messageRecords.length + 1).padStart(24, "0"),
        createdAt: new Date(),
      };
      messageRecords.push(message);
      return message;
    },
    find(query = {}) {
      let limit = 50;
      let direction = -1;
      return {
        sort(sortOptions) {
          direction = sortOptions.createdAt;
          return this;
        },
        limit(count) {
          limit = count;
          return this;
        },
        select() {
          return this;
        },
        async lean() {
          return messageRecords
            .filter((message) => {
              if (query.room && message.room !== query.room) return false;
              if (
                query._id?.$in &&
                !query._id.$in.map(String).includes(String(message._id))
              ) {
                return false;
              }
              if (
                query.sender?.$ne &&
                message.sender === query.sender.$ne
              ) {
                return false;
              }
              return true;
            })
            .slice()
            .sort((first, second) =>
              direction === -1
                ? second.createdAt - first.createdAt
                : first.createdAt - second.createdAt,
            )
            .slice(0, limit);
        },
      };
    },
    async updateMany(query, update) {
      const ids = new Set(query._id.$in.map(String));
      const readerId = String(query["readBy.userId"].$ne);
      let modifiedCount = 0;
      for (const message of messageRecords) {
        if (
          ids.has(String(message._id)) &&
          !message.readBy?.some((receipt) => String(receipt.userId) === readerId)
        ) {
          message.readBy = [
            ...(message.readBy || []),
            update.$push.readBy,
          ];
          modifiedCount += 1;
        }
      }
      return { modifiedCount };
    },
  };

  return { User, Message, userRecords, messageRecords };
}

before(async () => {
  const stores = createMemoryStores();
  users = stores.userRecords;
  messages = stores.messageRecords;
  ({ httpServer, io } = createChatServer({
    User: stores.User,
    Message: stores.Message,
    jwtSecret: "test-secret-with-more-than-thirty-two-bytes",
  }));
  httpServer.listen(0);
  await once(httpServer, "listening");
  serverUrl = `http://localhost:${httpServer.address().port}`;
});

after(async () => {
  clients.forEach((client) => client.disconnect());
  await new Promise((resolve, reject) => {
    httpServer.close((error) => (error ? reject(error) : resolve()));
  });
});

async function postJson(path, body, cookie) {
  const headers = { "Content-Type": "application/json" };
  if (cookie) headers.Cookie = cookie;
  return fetch(`${serverUrl}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function cookieFrom(response) {
  const setCookie = response.headers.get("set-cookie");
  assert.ok(setCookie, "authentication response should set an HTTP-only cookie");
  assert.match(setCookie, /HttpOnly/i);
  return setCookie.split(";")[0];
}

function nextEvent(client, event) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Timed out waiting for ${event}`)),
      2000,
    );
    client.once(event, (payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

async function connectClient(token) {
  const client = createClient(serverUrl, {
    auth: { token },
    reconnection: false,
  });
  clients.push(client);
  const initialUsers = nextEvent(client, "users:update");
  await Promise.all([
    new Promise((resolve, reject) => {
      client.once("connect", resolve);
      client.once("connect_error", reject);
    }),
    initialUsers,
  ]).then(([, online]) => {
    client.initialUsers = online;
  });
  const history = nextEvent(client, "message:history");
  client.emit("join", "general");
  client.initialHistory = await history;
  return client;
}

test("authenticates users, persists messages, and protects chat sockets", async () => {
  const registerAvery = await postJson("/api/auth/register", {
    username: "Avery",
    password: "avery-password-123",
  });
  assert.equal(registerAvery.status, 201);
  const averyCookie = cookieFrom(registerAvery);
  const averyResult = await registerAvery.json();
  assert.deepEqual(averyResult.user, { id: "user-1", username: "Avery" });
  assert.notEqual(users[0].passwordHash, "avery-password-123");

  const duplicate = await postJson("/api/auth/register", {
    username: "AVERY",
    password: "another-password-123",
  });
  assert.equal(duplicate.status, 409);

  const badLogin = await postJson("/api/auth/login", {
    username: "avery",
    password: "wrong-password",
  });
  assert.equal(badLogin.status, 401);

  const login = await postJson("/api/auth/login", {
    username: "avery",
    password: "avery-password-123",
  });
  assert.equal(login.status, 200);
  const loginCookie = cookieFrom(login);
  const loginResult = await login.json();
  assert.equal((await (await fetch(`${serverUrl}/api/auth/me`, {
    headers: { Cookie: loginCookie },
  })).json()).user.username, "Avery");

  const registerJordan = await postJson("/api/auth/register", {
    username: "Jordan",
    password: "jordan-password-123",
  });
  assert.equal(registerJordan.status, 201);
  const jordanCookie = cookieFrom(registerJordan);
  const jordanResult = await registerJordan.json();

  const unauthenticatedHistory = await fetch(`${serverUrl}/api/messages`);
  assert.equal(unauthenticatedHistory.status, 401);

  const firstSeedDate = Date.parse("2025-01-01T00:00:00.000Z");
  for (let index = 0; index < 52; index += 1) {
    messages.push({
      _id: String(index + 1).padStart(24, "0"),
      userId: "seed-user",
      sender: "Earlier",
      text: `seed-${index}`,
      room: "general",
      createdAt: new Date(firstSeedDate + index * 1000),
      readBy: [],
    });
  }

  const first = await connectClient(loginResult.token);
  assert.deepEqual(first.initialUsers, ["Avery"]);
  assert.equal(first.initialHistory.length, 50);
  assert.equal(first.initialHistory[0].text, "seed-2");
  const firstUsersUpdate = nextEvent(first, "users:update");
  const second = await connectClient(jordanResult.token);
  assert.deepEqual(second.initialUsers, ["Avery", "Jordan"]);
  assert.deepEqual(await firstUsersUpdate, ["Avery", "Jordan"]);
  assert.equal(second.initialHistory.length, 50);

  const typingStarted = nextEvent(second, "typing:update");
  first.emit("typing:start");
  assert.deepEqual(await typingStarted, {
    username: "Avery",
    isTyping: true,
  });
  const typingStopped = nextEvent(second, "typing:update");
  first.emit("typing:stop");
  assert.deepEqual(await typingStopped, {
    username: "Avery",
    isTyping: false,
  });

  const firstMessage = nextEvent(first, "message:new");
  const secondMessage = nextEvent(second, "message:new");
  first.emit("message:send", { text: "Persistent hello" });
  const [messageForSender, messageForRecipient] = await Promise.all([
    firstMessage,
    secondMessage,
  ]);
  assert.equal(messageForSender.text, "Persistent hello");
  assert.equal(messageForSender.sender, "Avery");
  assert.equal(messageForSender.room, "general");
  assert.deepEqual(messageForRecipient, messageForSender);
  assert.equal(messages.length, 53);

  const readReceipt = nextEvent(first, "messages:read");
  second.emit("messages:read", { messageIds: [messageForSender.id] });
  const receiptUpdate = await readReceipt;
  assert.deepEqual(receiptUpdate.messageIds, [messageForSender.id]);
  assert.equal(receiptUpdate.reader.username, "Jordan");
  assert.equal(messages.at(-1).readBy[0].username, "Jordan");

  const historyResponse = await fetch(`${serverUrl}/api/messages`, {
    headers: { Cookie: loginCookie },
  });
  assert.equal(historyResponse.status, 200);
  const history = await historyResponse.json();
  assert.equal(history.messages.length, 50);
  assert.equal(history.messages[0].text, "seed-3");
  assert.equal(history.messages.at(-1).text, "Persistent hello");
  assert.equal(history.messages.at(-1).readBy[0].username, "Jordan");

  const firstUsersAfterDisconnect = nextEvent(first, "users:update");
  second.disconnect();
  assert.deepEqual(await firstUsersAfterDisconnect, ["Avery"]);

  const firstDisconnected = nextEvent(first, "disconnect");
  const logout = await postJson("/api/auth/logout", {}, loginCookie);
  assert.equal(logout.status, 204);
  assert.equal(await firstDisconnected, "io server disconnect");
});

test("rejects Socket.IO connections without a JWT handshake token", async () => {
  const client = createClient(serverUrl, { reconnection: false });
  clients.push(client);
  const error = await nextEvent(client, "connect_error");
  assert.match(error.message, /Authentication required/);
});
