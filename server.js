require("dotenv").config();

const bcrypt = require("bcryptjs");
const cookieParser = require("cookie-parser");
const cors = require("cors");
const express = require("express");
const { rateLimit } = require("express-rate-limit");
const { createServer } = require("node:http");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");
const path = require("node:path");
const { Server } = require("socket.io");
const User = require("./models/User");
const Message = require("./models/Message");

const AUTH_COOKIE = "chat_token";
const TOKEN_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_MESSAGE_LENGTH = 2000;

function getIdentity(token, secret) {
  const claims = jwt.verify(token, secret);
  if (
    typeof claims !== "object" ||
    claims === null ||
    typeof claims.sub !== "string" ||
    typeof claims.username !== "string" ||
    typeof claims.exp !== "number"
  ) {
    throw new Error("Invalid authentication token.");
  }
  return {
    id: claims.sub,
    username: claims.username,
    expiresAt: claims.exp * 1000,
  };
}

function serializeMessage(message) {
  return {
    id: String(message._id),
    sender: message.sender,
    text: message.text,
    room: message.room,
    timestamp: new Date(message.createdAt).toISOString(),
    readBy: (message.readBy || []).map((receipt) => ({
      userId: String(receipt.userId),
      username: receipt.username,
      readAt: new Date(receipt.readAt).toISOString(),
    })),
  };
}

function createChatServer(options = {}) {
  const UserStore = options.User || User;
  const MessageStore = options.Message || Message;
  const jwtSecret = options.jwtSecret || process.env.JWT_SECRET;
  const port = process.env.PORT || 3001;
  const allowedOrigin =
    options.allowedOrigin ||
    process.env.CLIENT_ORIGIN ||
    process.env.RENDER_EXTERNAL_URL ||
    "http://localhost:5173";

  if (!jwtSecret || Buffer.byteLength(jwtSecret) < 32) {
    throw new Error("JWT_SECRET must be set to a random value of at least 32 bytes.");
  }

  const app = express();
  app.use(cors({ origin: allowedOrigin, credentials: true }));
  app.use(express.json({ limit: "10kb" }));
  app.use(cookieParser());
  if (process.env.NODE_ENV === "production") {
    app.use(express.static(path.join(__dirname, "dist")));
  }

  const httpServer = createServer(app);
  const io = new Server(httpServer, {
    cors: { origin: allowedOrigin, credentials: true },
  });

  const onlineUsers = new Map();
  const cookieOptions = {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
  };

  function signIn(response, user) {
    const identity = { id: String(user._id), username: user.username };
    const token = jwt.sign(
      { username: identity.username },
      jwtSecret,
      { subject: identity.id, expiresIn: "7d" },
    );
    response.cookie(AUTH_COOKIE, token, {
      ...cookieOptions,
      maxAge: TOKEN_LIFETIME_MS,
    });
    return { user: identity, token };
  }

  function requireAuth(request, response, next) {
    const token = request.cookies?.[AUTH_COOKIE];
    if (!token) {
      response.status(401).json({ error: "Authentication required." });
      return;
    }

    let identity;
    try {
      identity = getIdentity(token, jwtSecret);
    } catch {
      response.status(401).json({ error: "Session is invalid or expired." });
      return;
    }
    request.auth = identity;
    next();
  }

  app.get("/health", (_request, response) => {
    response.json({ status: "ok" });
  });

  const authRateLimit = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 10,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: "Too many authentication attempts. Try again later." },
  });
  app.use("/api/auth", authRateLimit);

  app.post("/api/auth/register", async (request, response) => {
    const body = request.body && typeof request.body === "object"
      ? request.body
      : {};
    const username =
      typeof body.username === "string" ? body.username.trim() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const passwordBytes = Buffer.byteLength(password, "utf8");

    if (username.length === 0 || username.length > 32) {
      response.status(400).json({ error: "Username must be 1-32 characters." });
      return;
    }
    if (passwordBytes < 8 || passwordBytes > 72) {
      response.status(400).json({
        error: "Password must be between 8 and 72 bytes.",
      });
      return;
    }

    const usernameNormalized = username.toLowerCase();
    if (await UserStore.findOne({ usernameNormalized })) {
      response.status(409).json({ error: "That username is already in use." });
      return;
    }

    try {
      const passwordHash = await bcrypt.hash(password, 12);
      const user = await UserStore.create({
        username,
        usernameNormalized,
        passwordHash,
      });
      response.status(201).json(signIn(response, user));
    } catch (error) {
      if (error.code === 11000) {
        response.status(409).json({ error: "That username is already in use." });
        return;
      }
      throw error;
    }
  });

  app.post("/api/auth/login", async (request, response) => {
    const body = request.body && typeof request.body === "object"
      ? request.body
      : {};
    const username =
      typeof body.username === "string" ? body.username.trim() : "";
    const password = typeof body.password === "string" ? body.password : "";

    if (!username || !password) {
      response.status(400).json({ error: "Username and password are required." });
      return;
    }

    const user = await UserStore.findOne({
      usernameNormalized: username.toLowerCase(),
    });
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      response.status(401).json({ error: "Incorrect username or password." });
      return;
    }

    response.json(signIn(response, user));
  });

  app.get("/api/auth/me", requireAuth, (request, response) => {
    response.json(signIn(response, {
      _id: request.auth.id,
      username: request.auth.username,
    }));
  });

  app.post("/api/auth/logout", (request, response) => {
    const token = request.cookies?.[AUTH_COOKIE];
    let userId;
    if (token) {
      try {
        const identity = getIdentity(token, jwtSecret);
        userId = identity.id;
      } catch {
        // Expired or invalid cookies are still cleared below.
      }
    }
    response.clearCookie(AUTH_COOKIE, cookieOptions);
    response.status(204).end();
    if (userId) {
      response.once("finish", () => {
        setTimeout(() => io.in(userId).disconnectSockets(true), 100);
      });
    }
  });

  app.get("/api/messages", requireAuth, async (_request, response) => {
    const storedMessages = await MessageStore.find({ room: "general" })
      .sort({ createdAt: -1 })
      .limit(50)
      .lean();

    response.json({
      messages: storedMessages.reverse().map(serializeMessage),
    });
  });

  app.use((error, _request, response, next) => {
    console.error("HTTP request failed:", error);
    if (response.headersSent) {
      next(error);
      return;
    }
    const status =
      Number.isInteger(error.status) && error.status >= 400 && error.status < 500
        ? error.status
        : 500;
    response.status(status).json({
      error: status === 400 ? "Invalid request body." : "Request failed.",
    });
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (typeof token !== "string") {
      next(new Error("Authentication required."));
      return;
    }

    try {
      socket.data.user = getIdentity(token, jwtSecret);
      next();
    } catch {
      next(new Error("Session is invalid or expired."));
    }
  });

  io.on("connection", (socket) => {
    const { username, id, expiresAt } = socket.data.user;
    console.log(`User connected: ${username} (${socket.id})`);
    socket.join(id);
    onlineUsers.set(socket.id, { id, username });
    const expiryTimer = setTimeout(
      () => socket.disconnect(true),
      Math.max(0, expiresAt - Date.now()),
    );
    let typingTimer;
    function stopTyping() {
      if (!socket.data.isTyping || !socket.data.room) return;
      socket.data.isTyping = false;
      clearTimeout(typingTimer);
      socket.to(socket.data.room).emit("typing:update", {
        username,
        isTyping: false,
      });
    }

    io.emit(
      "users:update",
      Array.from(onlineUsers.values(), (user) => user.username),
    );

    socket.on("join", async (payload) => {
      const room =
        typeof payload === "string" ? payload : payload?.room;
      if (room !== "general") {
        socket.emit("chat:error", { message: "Unknown chat room." });
        return;
      }

      try {
        await socket.join(room);
        socket.data.room = room;
        const recentMessages = await MessageStore.find({ room })
          .sort({ createdAt: -1 })
          .limit(50)
          .lean();
        socket.emit("message:history", recentMessages.reverse().map(serializeMessage));
      } catch (error) {
        console.error("Could not load chat history:", error);
        socket.emit("chat:error", {
          message: "Chat history could not be loaded.",
        });
      }
    });

    socket.on("typing:start", () => {
      if (!socket.data.room) return;
      if (!socket.data.isTyping) {
        socket.data.isTyping = true;
        socket.to(socket.data.room).emit("typing:update", {
          username,
          isTyping: true,
        });
      }
      clearTimeout(typingTimer);
      typingTimer = setTimeout(stopTyping, 3000);
    });

    socket.on("typing:stop", stopTyping);

    socket.on("messages:read", async (payload) => {
      const messageIds = Array.isArray(payload?.messageIds)
        ? Array.from(new Set(payload.messageIds.filter(
          (messageId) =>
            typeof messageId === "string" &&
            /^[\da-f]{24}$/i.test(messageId),
        )))
        : [];
      if (!socket.data.room || messageIds.length === 0 || messageIds.length > 50) {
        socket.emit("chat:error", {
          message: "Read receipts require up to 50 valid message IDs in a joined room.",
        });
        return;
      }

      try {
        const messagesToMark = await MessageStore.find({
          _id: { $in: messageIds },
          room: socket.data.room,
          sender: { $ne: username },
        }).select("_id").lean();
        const validIds = messagesToMark.map((message) => message._id);
        if (validIds.length === 0) return;

        const readAt = new Date();
        const result = await MessageStore.updateMany(
          {
            _id: { $in: validIds },
            "readBy.userId": { $ne: id },
          },
          {
            $push: {
              readBy: { userId: id, username, readAt },
            },
          },
        );
        if (result.modifiedCount > 0) {
          socket.to(socket.data.room).emit("messages:read", {
            messageIds: validIds.map(String),
            reader: { id, username, readAt: readAt.toISOString() },
          });
        }
      } catch (error) {
        console.error("Could not save read receipts:", error);
        socket.emit("chat:error", {
          message: "Read receipts could not be saved.",
        });
      }
    });

    socket.on("message:send", async (payload) => {
      const text =
        typeof payload === "string"
          ? payload.trim()
          : typeof payload?.text === "string"
            ? payload.text.trim()
            : "";

      const room = socket.data.room;
      if (room !== "general") {
        socket.emit("chat:error", { message: "Join a chat room first." });
        return;
      }
      if (text.length === 0 || text.length > MAX_MESSAGE_LENGTH) {
        socket.emit("chat:error", {
          message: "Message must be 1-2000 characters.",
        });
        return;
      }
      stopTyping();

      try {
        const savedMessage = await MessageStore.create({
          userId: id,
          sender: username,
          text,
          room,
          readBy: [],
        });
        io.to(room).emit("message:new", serializeMessage(savedMessage));
      } catch (error) {
        console.error("Could not persist chat message:", error);
        socket.emit("chat:error", {
          message: "Message could not be saved. Please try again.",
        });
      }
    });

    socket.on("disconnect", (reason) => {
      clearTimeout(typingTimer);
      if (socket.data.isTyping && socket.data.room) {
        io.to(socket.data.room).emit("typing:update", {
          username,
          isTyping: false,
        });
      }
      clearTimeout(expiryTimer);
      console.log(`User disconnected: ${username} (${reason})`);
      onlineUsers.delete(socket.id);
      io.emit(
        "users:update",
        Array.from(onlineUsers.values(), (user) => user.username),
      );
    });
  });

  return { app, httpServer, io };
}

async function startServer() {
  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret || Buffer.byteLength(jwtSecret) < 32) {
    throw new Error("JWT_SECRET must be set to a random value of at least 32 bytes.");
  }

  const mongoUri = process.env.MONGODB_URI;
  if (!mongoUri) {
    throw new Error("MONGODB_URI must be set before starting the server.");
  }

  await mongoose.connect(mongoUri);
  const { httpServer } = createChatServer();
  const port = process.env.PORT || 3001;
  try {
    await new Promise((resolve, reject) => {
      httpServer.once("error", reject);
      httpServer.listen(port, resolve);
    });
  } catch (error) {
    await mongoose.disconnect();
    throw error;
  }
  console.log(`Server listening on port ${port}`);
  return httpServer;
}

if (require.main === module) {
  startServer().catch((error) => {
    console.error("Server startup failed:", error);
    process.exitCode = 1;
  });
}

module.exports = { createChatServer, startServer };
