import { useEffect, useRef, useState } from "react";
import { io } from "socket.io-client";

const DEFAULT_SERVER_URL = import.meta.env.DEV
  ? "http://localhost:3001"
  : window.location.origin;
const API_URL = import.meta.env.VITE_API_URL || DEFAULT_SERVER_URL;
const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || DEFAULT_SERVER_URL;
const avatarColors = ["#d9e8ff", "#fce1d7", "#e7defb", "#d9eee4", "#fae9bd"];

function initials(name) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

function avatarColor(name) {
  return avatarColors[name.charCodeAt(0) % avatarColors.length];
}

function mergeMessages(existing, incoming) {
  const messagesById = new Map();
  for (const message of [...existing, ...incoming]) {
    const previous = messagesById.get(message.id);
    const receipts = new Map(
      [...(previous?.readBy || []), ...(message.readBy || [])].map((receipt) => [
        receipt.userId,
        receipt,
      ]),
    );
    messagesById.set(message.id, {
      ...previous,
      ...message,
      readBy: Array.from(receipts.values()),
    });
  }
  return Array.from(messagesById.values()).sort(
    (first, second) =>
      new Date(first.timestamp).getTime() - new Date(second.timestamp).getTime(),
  );
}

function formatTime(timestamp) {
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function BrandMark() {
  return (
    <div className="brand-mark" aria-hidden="true">
      <span />
      <span />
      <span />
      <span />
    </div>
  );
}

function SendIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="m21 3-7.2 18-3.9-7.9L2 9.2 21 3Z"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinejoin="round"
      />
      <path
        d="M21 3 9.9 13.1"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
    </svg>
  );
}

function App() {
  const [connected, setConnected] = useState(false);
  const [onlineUsers, setOnlineUsers] = useState([]);
  const [messages, setMessages] = useState([]);
  const [typingUsers, setTypingUsers] = useState([]);
  const [user, setUser] = useState(null);
  const [token, setToken] = useState("");
  const [roomJoined, setRoomJoined] = useState(false);
  const [authReady, setAuthReady] = useState(false);
  const [authMode, setAuthMode] = useState("login");
  const [authUsername, setAuthUsername] = useState("");
  const [authPassword, setAuthPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState("");
  const [draft, setDraft] = useState("");
  const [error, setError] = useState("");
  const [historyLoading, setHistoryLoading] = useState(false);
  const socketRef = useRef(null);
  const messagesEndRef = useRef(null);
  const typingTimerRef = useRef(null);
  const typingActiveRef = useRef(false);

  useEffect(() => {
    let active = true;

    async function restoreSession() {
      try {
        const response = await fetch(`${API_URL}/api/auth/me`, {
          credentials: "include",
        });
        if (response.status !== 401 && !response.ok) {
          throw new Error("Could not restore your session.");
        }
        if (response.ok) {
          const result = await response.json();
          if (active) {
            setUser(result.user);
            setToken(result.token);
          }
        }
      } catch {
        if (active) setAuthError("Could not reach the chat server.");
      } finally {
        if (active) setAuthReady(true);
      }
    }

    restoreSession();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!user || !token) {
      setConnected(false);
      setRoomJoined(false);
      setHistoryLoading(false);
      setOnlineUsers([]);
      setMessages([]);
      setTypingUsers([]);
      return undefined;
    }

    setHistoryLoading(true);
    setRoomJoined(false);
    const socket = io(SOCKET_URL, { auth: { token } });
    socketRef.current = socket;
    socket.on("connect", () => {
      setConnected(true);
      setError("");
      setHistoryLoading(true);
      setTypingUsers([]);
      socket.emit("join", "general");
    });
    socket.on("disconnect", (reason) => {
      setConnected(false);
      setRoomJoined(false);
      setHistoryLoading(false);
      setTypingUsers([]);
      clearTimeout(typingTimerRef.current);
      typingTimerRef.current = null;
      typingActiveRef.current = false;
      if (reason === "io server disconnect") {
        setUser(null);
        setToken("");
        setAuthMode("login");
        setAuthError("Your session ended. Please sign in again.");
      }
    });
    socket.on("connect_error", () => {
      setConnected(false);
      setRoomJoined(false);
      setHistoryLoading(false);
      setError("Could not connect to chat. Check your session and try again.");
    });
    socket.on("users:update", (users) => {
      if (Array.isArray(users)) setOnlineUsers(users);
    });
    socket.on("message:history", (history) => {
      if (Array.isArray(history)) {
        setMessages((currentMessages) => mergeMessages(currentMessages, history));
        setRoomJoined(true);
        const unreadIds = history
          .filter(
            (message) =>
              message.sender !== user.username &&
              typeof message.id === "string" &&
              !message.readBy?.some(
                (receipt) => receipt.userId === user.id,
              ),
          )
          .map((message) => message.id);
        if (unreadIds.length > 0) {
          socket.emit("messages:read", { messageIds: unreadIds });
        }
      }
      setHistoryLoading(false);
    });
    socket.on("message:new", (message) => {
      if (
        message &&
        typeof message.id === "string" &&
        typeof message.sender === "string" &&
        typeof message.text === "string"
      ) {
        setMessages((currentMessages) =>
          mergeMessages(currentMessages, [message]),
        );
        if (message.sender !== user.username) {
          socket.emit("messages:read", { messageIds: [message.id] });
        }
      }
    });
    socket.on("messages:read", (payload) => {
      if (
        !Array.isArray(payload?.messageIds) ||
        typeof payload.reader?.id !== "string" ||
        typeof payload.reader.username !== "string"
      ) {
        return;
      }

      const readMessageIds = new Set(payload.messageIds);
      setMessages((currentMessages) =>
        currentMessages.map((message) => {
          if (!readMessageIds.has(message.id)) return message;
          const receipts = message.readBy || [];
          if (receipts.some((receipt) => receipt.userId === payload.reader.id)) {
            return message;
          }
          return {
            ...message,
            readBy: [...receipts, payload.reader],
          };
        }),
      );
    });
    socket.on("typing:update", (payload) => {
      if (
        typeof payload?.username !== "string" ||
        typeof payload.isTyping !== "boolean" ||
        payload.username === user.username
      ) {
        return;
      }
      setTypingUsers((currentUsers) => {
        if (payload.isTyping) {
          return currentUsers.includes(payload.username)
            ? currentUsers
            : [...currentUsers, payload.username];
        }
        return currentUsers.filter((username) => username !== payload.username);
      });
    });
    socket.on("chat:error", (payload) => {
      setError(payload?.message || "Something went wrong. Please try again.");
      setHistoryLoading(false);
    });

    return () => {
      clearTimeout(typingTimerRef.current);
      typingTimerRef.current = null;
      typingActiveRef.current = false;
      socket.disconnect();
      if (socketRef.current === socket) socketRef.current = null;
    };
  }, [user, token]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages]);

  async function submitAuth(event) {
    event.preventDefault();
    setAuthBusy(true);
    setAuthError("");
    try {
      const response = await fetch(`${API_URL}/api/auth/${authMode}`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: authUsername.trim(),
          password: authPassword,
        }),
      });
      const result = await response.json();
      if (!response.ok) {
        throw new Error(result.error || "Authentication failed.");
      }
      setUser(result.user);
      setToken(result.token);
      setAuthPassword("");
    } catch (authRequestError) {
      setAuthError(authRequestError.message || "Could not sign in.");
    } finally {
      setAuthBusy(false);
    }
  }

  async function logout() {
    stopTyping();
    try {
      const response = await fetch(`${API_URL}/api/auth/logout`, {
        method: "POST",
        credentials: "include",
      });
      if (!response.ok) throw new Error("Could not sign out.");
      socketRef.current?.disconnect();
      socketRef.current = null;
      setUser(null);
      setToken("");
      setAuthMode("login");
      setAuthPassword("");
      setAuthError("");
    } catch (logoutError) {
      setAuthError(logoutError.message || "Could not sign out.");
    }
  }

  function stopTyping() {
    clearTimeout(typingTimerRef.current);
    typingTimerRef.current = null;
    if (typingActiveRef.current && socketRef.current?.connected) {
      socketRef.current.emit("typing:stop");
    }
    typingActiveRef.current = false;
  }

  function updateDraft(event) {
    const value = event.target.value;
    setDraft(value);
    if (!value.trim()) {
      stopTyping();
      return;
    }

    if (!typingActiveRef.current && socketRef.current?.connected && roomJoined) {
      socketRef.current.emit("typing:start");
      typingActiveRef.current = true;
    }
    clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(stopTyping, 2000);
  }

  function sendMessage(event) {
    event.preventDefault();
    const text = draft.trim();
    if (!text || !user || !roomJoined || !socketRef.current?.connected) return;

    stopTyping();
    socketRef.current.emit("message:send", { text });
    setDraft("");
    setError("");
  }

  const joinedUsername = user?.username || "";
  const canSend =
    connected && roomJoined && Boolean(user) && Boolean(draft.trim());
  const typingSummary =
    typingUsers.length === 1
      ? `${typingUsers[0]} is typing…`
      : typingUsers.length > 1
        ? `${typingUsers.slice(0, 2).join(" and ")} are typing…`
        : "";

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-top">
          <div className="brand">
            <BrandMark />
            <span>gather</span>
          </div>
          <div className="workspace-label">
            <span className="workspace-dot" />
            <span>YOUR WORKSPACE</span>
          </div>
          <button className="room-link" type="button" aria-current="page">
            <span className="room-hash">#</span>
            <span>general</span>
            <span className="room-active-dot" />
          </button>
        </div>

        <div className="people-section">
          <div className="section-heading">
            <span>IN THIS ROOM</span>
            <span className="people-count">{onlineUsers.length}</span>
          </div>
          <div className="people-list">
            {onlineUsers.length === 0 ? (
              <p className="people-empty">It’s quiet in here. Say hello!</p>
            ) : (
              onlineUsers.map((name, index) => (
                <div className="person" key={`${name}-${index}`}>
                  <div
                    className="avatar person-avatar"
                    style={{ "--avatar-color": avatarColor(name) }}
                    aria-hidden="true"
                  >
                    {initials(name)}
                    <span className="online-dot" />
                  </div>
                  <span className="person-name" title={name}>
                    {name}
                  </span>
                  {name === joinedUsername && (
                    <span className="you-label">you</span>
                  )}
                </div>
              ))
            )}
          </div>
        </div>

        <div className="sidebar-bottom">
          <div className={`connection-indicator ${connected ? "is-live" : ""}`}>
            <span className="connection-dot" />
            <span>
              {historyLoading
                ? "Loading history…"
                : connected
                  ? "Connected"
                  : "Reconnecting…"}
            </span>
          </div>
          <p>Good conversations start here.</p>
        </div>
      </aside>

      <section className="chat-panel" aria-label="General chat">
        <header className="chat-header">
          <div className="room-title">
            <div className="room-title-icon">#</div>
            <div>
              <h1>general</h1>
              <p>A little space for everything</p>
            </div>
          </div>
          <div className="header-status">
            <span className={`status-pulse ${connected ? "" : "is-offline"}`} />
            <span>{connected ? "Live" : "Offline"}</span>
            <span className="header-divider" />
            <span className="header-member-count">
              {onlineUsers.length}{" "}
              {onlineUsers.length === 1 ? "person" : "people"}
            </span>
            {user && (
              <button className="logout-button" onClick={logout} type="button">
                Sign out
              </button>
            )}
          </div>
        </header>

        <div className="message-scroll">
          {messages.length === 0 ? (
            <div className="empty-room">
              <div className="empty-illustration" aria-hidden="true">
                <div className="empty-orbit orbit-one" />
                <div className="empty-orbit orbit-two" />
                <div className="empty-bubble bubble-one">✦</div>
                <div className="empty-bubble bubble-two">·</div>
                <div className="empty-chat-icon">
                  <span />
                  <span />
                  <span />
                </div>
              </div>
              <span className="eyebrow">WELCOME TO YOUR ROOM</span>
              <h2>Make yourself at home.</h2>
              <p>
                Every good conversation starts somewhere.
                <br />
                Why not start this one?
              </p>
            </div>
          ) : (
            <div className="message-list" aria-live="polite">
              <div className="message-day">
                <span>MESSAGES</span>
              </div>
              {messages.map((message, index) => {
                const isOwnMessage = message.sender === joinedUsername;
                return (
                  <article
                    className={`message-row ${isOwnMessage ? "is-own" : ""}`}
                    key={message.id || `${message.timestamp}-${index}`}
                  >
                    {!isOwnMessage && (
                      <div
                        className="avatar message-avatar"
                        style={{
                          "--avatar-color": avatarColor(message.sender),
                        }}
                        aria-hidden="true"
                      >
                        {initials(message.sender)}
                      </div>
                    )}
                    <div className="message-content">
                      <div className="message-meta">
                        <span className="message-author">
                          {message.sender}
                        </span>
                        <time dateTime={message.timestamp}>
                          {formatTime(message.timestamp)}
                        </time>
                      </div>
                      <p className="message-bubble">{message.text}</p>
                      {isOwnMessage && message.readBy?.length > 0 && (
                        <p className="read-receipt">
                          Seen by{" "}
                          {message.readBy
                            .map((receipt) => receipt.username)
                            .join(", ")}
                        </p>
                      )}
                    </div>
                  </article>
                );
              })}
              <div ref={messagesEndRef} />
            </div>
          )}
        </div>

        <div className="composer-area">
          {typingSummary && (
            <div className="typing-indicator" aria-live="polite">
              <span className="typing-dots" aria-hidden="true">
                <span />
                <span />
                <span />
              </span>
              {typingSummary}
            </div>
          )}
          {error && (
            <p className="error-message" role="alert">
              {error}
            </p>
          )}
          {!authReady ? (
            <p className="auth-loading">Checking your session…</p>
          ) : !user ? (
            <form className="auth-card" onSubmit={submitAuth}>
              <div className="auth-heading">
                <span className="join-sparkle">✳</span>
                <div>
                  <strong>
                    {authMode === "login"
                      ? "Welcome back"
                      : "Create your account"}
                  </strong>
                  <span>
                    {authMode === "login"
                      ? "Sign in to join the conversation."
                      : "Your account keeps your chat history with you."}
                  </span>
                </div>
              </div>
              <div className="auth-fields">
                <input
                  aria-label="Username"
                  autoComplete="username"
                  maxLength={32}
                  onChange={(event) => setAuthUsername(event.target.value)}
                  placeholder="Username"
                  required
                  value={authUsername}
                />
                <input
                  aria-label="Password"
                  autoComplete={
                    authMode === "login" ? "current-password" : "new-password"
                  }
                  maxLength={72}
                  minLength={8}
                  onChange={(event) => setAuthPassword(event.target.value)}
                  placeholder="Password (8+ characters)"
                  required
                  type="password"
                  value={authPassword}
                />
              </div>
              {authError && (
                <p className="auth-error" role="alert">
                  {authError}
                </p>
              )}
              <div className="auth-actions">
                <button
                  className="join-button auth-submit"
                  disabled={
                    authBusy || !authUsername.trim() || !authPassword
                  }
                  type="submit"
                >
                  {authBusy
                    ? "Please wait…"
                    : authMode === "login"
                      ? "Sign in"
                      : "Create account"}
                  <span aria-hidden="true">→</span>
                </button>
                <button
                  className="auth-switch"
                  disabled={authBusy}
                  onClick={() => {
                    setAuthMode(authMode === "login" ? "register" : "login");
                    setAuthError("");
                  }}
                  type="button"
                >
                  {authMode === "login"
                    ? "Create account"
                    : "Already registered? Sign in"}
                </button>
              </div>
            </form>
          ) : (
            <form className="composer" onSubmit={sendMessage}>
              <input
                aria-label="Write a message"
                autoComplete="off"
                maxLength={2000}
                onBlur={stopTyping}
                onChange={updateDraft}
                placeholder={
                  connected
                    ? `Message as ${joinedUsername}…`
                    : "Reconnecting to the room…"
                }
                value={draft}
                disabled={!connected}
              />
              <div className="composer-footer">
                <span className="composer-hint">
                  <kbd>↵</kbd> to send
                  <span className="hint-separator">·</span>
                  Be kind to each other
                </span>
                <button
                  className="send-button"
                  disabled={!canSend}
                  type="submit"
                  aria-label="Send message"
                >
                  <SendIcon />
                </button>
              </div>
            </form>
          )}
          <p className="footer-note">
            A little kindness goes a long way <span aria-hidden="true">✦</span>
          </p>
        </div>
      </section>
    </main>
  );
}

export default App;
