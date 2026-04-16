export const AUTH_CONFIG = {
  cognitoDomain: "https://REPLACE_WITH_COGNITO_DOMAIN",
  region: "REPLACE_WITH_AWS_REGION",
  userPoolId: "REPLACE_WITH_USER_POOL_ID",
  clientId: "REPLACE_WITH_APP_CLIENT_ID",
  scope: "openid",
  redirectPath: "/callback.html",
  defaultProtectedPath: "/dashboard.html",
  signedOutPath: "/index.html"
};

const STORAGE = {
  accessToken: "access_token",
  idToken: "id_token",
  refreshToken: "refresh_token",
  oauthState: "oauth_state",
  pkceVerifier: "pkce_verifier",
  postLoginPath: "post_login_path"
};

function isPlaceholder(value) {
  return typeof value !== "string" || !value.trim() || value.includes("REPLACE_WITH_");
}

function assertConfig() {
  const missing = [];

  if (isPlaceholder(AUTH_CONFIG.cognitoDomain)) missing.push("cognitoDomain");
  if (isPlaceholder(AUTH_CONFIG.region)) missing.push("region");
  if (isPlaceholder(AUTH_CONFIG.userPoolId)) missing.push("userPoolId");
  if (isPlaceholder(AUTH_CONFIG.clientId)) missing.push("clientId");

  if (missing.length) {
    throw new Error(`Missing auth config: ${missing.join(", ")}`);
  }
}

function getIssuer() {
  return `https://cognito-idp.${AUTH_CONFIG.region}.amazonaws.com/${AUTH_CONFIG.userPoolId}`;
}

function getRedirectUri() {
  return new URL(AUTH_CONFIG.redirectPath, window.location.origin).toString();
}

function getLogoutUri() {
  return new URL(AUTH_CONFIG.signedOutPath, window.location.origin).toString();
}

function clearAuthStorage() {
  sessionStorage.removeItem(STORAGE.accessToken);
  sessionStorage.removeItem(STORAGE.idToken);
  sessionStorage.removeItem(STORAGE.refreshToken);
  sessionStorage.removeItem(STORAGE.oauthState);
  sessionStorage.removeItem(STORAGE.pkceVerifier);
  sessionStorage.removeItem(STORAGE.postLoginPath);
}

function sanitizeRelativePath(path) {
  if (typeof path !== "string" || !path.startsWith("/")) {
    return AUTH_CONFIG.defaultProtectedPath;
  }

  if (path.startsWith("//")) {
    return AUTH_CONFIG.defaultProtectedPath;
  }

  return path;
}

function base64UrlEncode(arrayBuffer) {
  return btoa(String.fromCharCode(...new Uint8Array(arrayBuffer)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

async function sha256(text) {
  const data = new TextEncoder().encode(text);
  return crypto.subtle.digest("SHA-256", data);
}

function decodeJwtPayload(token) {
  if (!token || typeof token !== "string") {
    return {};
  }

  const parts = token.split(".");
  if (parts.length < 2) {
    return {};
  }

  try {
    const encoded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = encoded + "=".repeat((4 - (encoded.length % 4)) % 4);
    return JSON.parse(atob(padded));
  } catch (error) {
    return {};
  }
}

function isExpired(payload) {
  if (!payload || typeof payload.exp !== "number") {
    return true;
  }

  const now = Math.floor(Date.now() / 1000);
  return payload.exp <= now;
}

function verifyAccessTokenClaims(token) {
  const payload = decodeJwtPayload(token);

  if (!Object.keys(payload).length) {
    throw new Error("Invalid access token.");
  }

  if (isExpired(payload)) {
    throw new Error("Access token has expired.");
  }

  if (payload.iss !== getIssuer()) {
    throw new Error("Access token issuer mismatch.");
  }

  if (payload.token_use !== "access") {
    throw new Error("Expected an access token.");
  }

  if (payload.client_id !== AUTH_CONFIG.clientId) {
    throw new Error("Access token client ID mismatch.");
  }

  return payload;
}

function verifyIdTokenClaims(token) {
  const payload = decodeJwtPayload(token);

  if (!Object.keys(payload).length) {
    throw new Error("Invalid ID token.");
  }

  if (isExpired(payload)) {
    throw new Error("ID token has expired.");
  }

  if (payload.iss !== getIssuer()) {
    throw new Error("ID token issuer mismatch.");
  }

  if (payload.token_use !== "id") {
    throw new Error("Expected an ID token.");
  }

  if (payload.aud !== AUTH_CONFIG.clientId) {
    throw new Error("ID token audience mismatch.");
  }

  return payload;
}

export async function getSession() {
  try {
    assertConfig();
  } catch (configError) {
    return {
      isValid: false,
      error: configError
    };
  }

  const accessToken = sessionStorage.getItem(STORAGE.accessToken);
  const idToken = sessionStorage.getItem(STORAGE.idToken);
  const refreshToken = sessionStorage.getItem(STORAGE.refreshToken);

  if (!accessToken) {
    return { isValid: false };
  }

  try {
    const accessClaims = verifyAccessTokenClaims(accessToken);
    const idClaims = idToken ? verifyIdTokenClaims(idToken) : {};

    return {
      isValid: true,
      accessToken,
      idToken,
      refreshToken,
      accessClaims,
      idClaims
    };
  } catch (error) {
    clearAuthStorage();

    return {
      isValid: false,
      error
    };
  }
}

export async function beginLogin(options = {}) {
  assertConfig();

  const requestedPath = sanitizeRelativePath(
    options.requestedPath || AUTH_CONFIG.defaultProtectedPath
  );

  const verifierBytes = crypto.getRandomValues(new Uint8Array(32));
  const codeVerifier = Array.from(
    verifierBytes,
    (byte) => byte.toString(16).padStart(2, "0")
  ).join("");
  const challengeBytes = await sha256(codeVerifier);
  const codeChallenge = base64UrlEncode(challengeBytes);
  const state = crypto.randomUUID();

  sessionStorage.setItem(STORAGE.pkceVerifier, codeVerifier);
  sessionStorage.setItem(STORAGE.oauthState, state);
  sessionStorage.setItem(STORAGE.postLoginPath, requestedPath);

  const authorizeUrl = new URL(`${AUTH_CONFIG.cognitoDomain}/oauth2/authorize`);
  authorizeUrl.searchParams.set("response_type", "code");
  authorizeUrl.searchParams.set("client_id", AUTH_CONFIG.clientId);
  authorizeUrl.searchParams.set("redirect_uri", getRedirectUri());
  authorizeUrl.searchParams.set("scope", AUTH_CONFIG.scope);
  authorizeUrl.searchParams.set("state", state);
  authorizeUrl.searchParams.set("code_challenge_method", "S256");
  authorizeUrl.searchParams.set("code_challenge", codeChallenge);

  window.location.assign(authorizeUrl.toString());
}

export async function requireAuth(options = {}) {
  const session = await getSession();

  if (session.isValid) {
    return session;
  }

  if (options.redirectToLogin !== false) {
    await beginLogin({
      requestedPath: options.requestedPath || window.location.pathname
    });
  }

  throw session.error || new Error("Authentication required.");
}

export async function handleCallback(options = {}) {
  assertConfig();

  const statusCallback =
    typeof options.onStatusChange === "function" ? options.onStatusChange : null;

  const searchParams = new URLSearchParams(window.location.search);
  const code = searchParams.get("code");
  const returnedState = searchParams.get("state");
  const error = searchParams.get("error");
  const errorDescription = searchParams.get("error_description");

  if (error) {
    throw new Error(errorDescription || error);
  }

  const expectedState = sessionStorage.getItem(STORAGE.oauthState);
  const codeVerifier = sessionStorage.getItem(STORAGE.pkceVerifier);

  if (!code || !returnedState || !expectedState || returnedState !== expectedState || !codeVerifier) {
    throw new Error("Missing or invalid authorization response.");
  }

  if (statusCallback) {
    statusCallback("Exchanging authorization code for tokens...");
  }

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: AUTH_CONFIG.clientId,
    code,
    redirect_uri: getRedirectUri(),
    code_verifier: codeVerifier
  });

  const response = await fetch(`${AUTH_CONFIG.cognitoDomain}/oauth2/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: body.toString()
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(result.error_description || result.error || "Token exchange failed.");
  }

  sessionStorage.setItem(STORAGE.idToken, result.id_token || "");
  sessionStorage.setItem(STORAGE.accessToken, result.access_token || "");
  sessionStorage.setItem(STORAGE.refreshToken, result.refresh_token || "");
  sessionStorage.removeItem(STORAGE.oauthState);
  sessionStorage.removeItem(STORAGE.pkceVerifier);

  const nextPath = sanitizeRelativePath(
    sessionStorage.getItem(STORAGE.postLoginPath) || AUTH_CONFIG.defaultProtectedPath
  );
  sessionStorage.removeItem(STORAGE.postLoginPath);

  window.location.replace(nextPath);
}

export function signOut(options = {}) {
  clearAuthStorage();

  const useHostedUiLogout = options.useHostedUiLogout !== false;

  try {
    assertConfig();

    if (useHostedUiLogout) {
      const logoutUrl = new URL(`${AUTH_CONFIG.cognitoDomain}/logout`);
      logoutUrl.searchParams.set("client_id", AUTH_CONFIG.clientId);
      logoutUrl.searchParams.set("logout_uri", getLogoutUri());
      window.location.assign(logoutUrl.toString());
      return;
    }
  } catch (error) {
    // Fall back to a local redirect below.
  }

  window.location.assign(AUTH_CONFIG.signedOutPath);
}

export function getUserDisplayName(session) {
  return (
    session?.idClaims?.email ||
    session?.idClaims?.name ||
    session?.idClaims?.["cognito:username"] ||
    session?.accessClaims?.username ||
    "Authenticated user"
  );
}

export function getUserKey(session) {
  return (
    session?.idClaims?.sub ||
    session?.accessClaims?.sub ||
    session?.idClaims?.email ||
    session?.accessClaims?.username ||
    "anonymous-user"
  );
}

export function readUnsafeTokenClaims() {
  return {
    access: decodeJwtPayload(sessionStorage.getItem(STORAGE.accessToken) || ""),
    id: decodeJwtPayload(sessionStorage.getItem(STORAGE.idToken) || "")
  };
}
