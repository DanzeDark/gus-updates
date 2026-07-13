const DEFAULT_OWNER = 'DanzeDark';
const DEFAULT_REPO = 'gus-updates';
const DEFAULT_BRANCH = 'main';
const ACCOUNTS_PATH = 'gus_accounts.json';
const PAYMENTS_PATH = 'gus_payments.json';
const REQUESTS_PATH = 'gus_registration_requests.json';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Key',
  'Access-Control-Max-Age': '86400'
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8'
    }
  });
}

function textResponse(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/plain; charset=utf-8'
    }
  });
}

function getEnv(env, name, fallback = '') {
  const value = env && env[name] ? String(env[name]).trim() : '';
  return value || fallback;
}

function requireAdmin(request, env) {
  const expected = getEnv(env, 'ADMIN_KEY');
  if (!expected) throw new Error('ADMIN_KEY is not configured.');
  const actual = request.headers.get('X-Admin-Key') || '';
  if (actual !== expected) {
    const error = new Error('No admin access.');
    error.status = 403;
    throw error;
  }
}

function sanitizeLogin(value) {
  return String(value || '').replace(/\s+/g, '').trim().toLowerCase();
}

function cleanText(value, maxLength = 200) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, maxLength);
}

function nowStamp() {
  return new Date().toISOString();
}

function bytesToHex(bytes) {
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function sha256Hex(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return bytesToHex(new Uint8Array(hash));
}

async function accountKeyHash(login, password) {
  return sha256Hex(`GUS-ACCOUNT-V1|${login}|${password}`);
}

function base64EncodeUtf8(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.slice(i, i + chunkSize));
  }
  return btoa(binary);
}

function base64DecodeUtf8(text) {
  const binary = atob(String(text || '').replace(/\s+/g, ''));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

function githubConfig(env) {
  const token = getEnv(env, 'GITHUB_TOKEN');
  if (!token) throw new Error('GITHUB_TOKEN is not configured.');
  return {
    token,
    owner: getEnv(env, 'REPO_OWNER', DEFAULT_OWNER),
    repo: getEnv(env, 'REPO_NAME', DEFAULT_REPO),
    branch: getEnv(env, 'BRANCH', DEFAULT_BRANCH)
  };
}

async function githubRequest(env, path, options = {}) {
  const cfg = githubConfig(env);
  const url = `https://api.github.com/repos/${encodeURIComponent(cfg.owner)}/${encodeURIComponent(cfg.repo)}/${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${cfg.token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'gus-registration-worker',
      ...(options.headers || {})
    }
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
  if (!response.ok) {
    const error = new Error(data && data.message ? data.message : `GitHub HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function readGitFile(env, filePath, fallback) {
  const cfg = githubConfig(env);
  try {
    const data = await githubRequest(env, `contents/${encodeURIComponent(filePath)}?ref=${encodeURIComponent(cfg.branch)}`, { method: 'GET' });
    const content = base64DecodeUtf8(data.content || '');
    return { json: JSON.parse(content), sha: data.sha || null };
  } catch (error) {
    if (error.status === 404) return { json: fallback, sha: null };
    throw error;
  }
}

async function writeGitFile(env, filePath, json, sha, message) {
  const cfg = githubConfig(env);
  const body = {
    message,
    content: base64EncodeUtf8(JSON.stringify(json, null, 2)),
    branch: cfg.branch
  };
  if (sha) body.sha = sha;
  return githubRequest(env, `contents/${encodeURIComponent(filePath)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
}

function defaultAccounts() {
  return { enabled: true, updatedAt: nowStamp(), accounts: [] };
}

function defaultPayments() {
  return { updatedAt: nowStamp(), accounts: [] };
}

function defaultRequests() {
  return { updatedAt: nowStamp(), requests: [] };
}

function findByLogin(items, login) {
  return (items || []).find((item) => String(item.login || '').toLowerCase() === login);
}

async function createRequest(request, env) {
  const body = await request.json().catch(() => null);
  if (!body) return jsonResponse({ ok: false, error: 'Bad JSON.' }, 400);

  const login = sanitizeLogin(body.login);
  const name = cleanText(body.name, 120);
  const password = String(body.password || '');
  const note = cleanText(body.note, 300);

  if (!/^[a-z0-9._-]{2,64}$/.test(login)) {
    return jsonResponse({ ok: false, error: 'Логин: только латиница, цифры, точка, _ или -, от 2 символов.' }, 400);
  }
  if (!password || password.length < 4) {
    return jsonResponse({ ok: false, error: 'Пароль должен быть минимум 4 символа.' }, 400);
  }

  const accountsFile = await readGitFile(env, ACCOUNTS_PATH, defaultAccounts());
  if (findByLogin(accountsFile.json.accounts, login)) {
    return jsonResponse({ ok: false, error: 'Такой аккаунт уже есть.' }, 409);
  }

  const requestsFile = await readGitFile(env, REQUESTS_PATH, defaultRequests());
  const existingPending = (requestsFile.json.requests || []).find((item) => (
    String(item.login || '').toLowerCase() === login && String(item.status || '') === 'pending'
  ));
  if (existingPending) {
    return jsonResponse({ ok: true, id: existingPending.id, status: 'pending', message: 'Заявка уже ожидает подтверждения.' });
  }

  const createdAt = nowStamp();
  const newRequest = {
    id: crypto.randomUUID(),
    login,
    name: name || login,
    keyHash: await accountKeyHash(login, password),
    note,
    status: 'pending',
    createdAt,
    decidedAt: '',
    decisionNote: ''
  };

  requestsFile.json.updatedAt = createdAt;
  requestsFile.json.requests = [newRequest, ...(requestsFile.json.requests || [])];
  await writeGitFile(env, REQUESTS_PATH, requestsFile.json, requestsFile.sha, `Create Gus registration request ${login}`);
  return jsonResponse({ ok: true, id: newRequest.id, status: 'pending', message: 'Заявка отправлена владельцу.' });
}

async function listRequests(request, env) {
  requireAdmin(request, env);
  const requestsFile = await readGitFile(env, REQUESTS_PATH, defaultRequests());
  return jsonResponse({ ok: true, ...requestsFile.json });
}

async function approveRequest(request, env, id) {
  requireAdmin(request, env);
  const requestsFile = await readGitFile(env, REQUESTS_PATH, defaultRequests());
  const item = (requestsFile.json.requests || []).find((entry) => String(entry.id) === id);
  if (!item) return jsonResponse({ ok: false, error: 'Заявка не найдена.' }, 404);
  if (item.status !== 'pending') return jsonResponse({ ok: false, error: 'Заявка уже обработана.' }, 409);

  const accountsFile = await readGitFile(env, ACCOUNTS_PATH, defaultAccounts());
  accountsFile.json.enabled = true;
  accountsFile.json.updatedAt = nowStamp();
  accountsFile.json.accounts = accountsFile.json.accounts || [];
  if (!findByLogin(accountsFile.json.accounts, item.login)) {
    accountsFile.json.accounts.push({
      login: item.login,
      name: item.name || item.login,
      keyHash: item.keyHash,
      active: true,
      createdAt: item.createdAt || nowStamp(),
      note: item.note ? `Регистрация с сайта. ${item.note}` : 'Регистрация с сайта'
    });
  }

  const paymentsFile = await readGitFile(env, PAYMENTS_PATH, defaultPayments());
  paymentsFile.json.updatedAt = nowStamp();
  paymentsFile.json.accounts = paymentsFile.json.accounts || [];
  if (!findByLogin(paymentsFile.json.accounts, item.login)) {
    paymentsFile.json.accounts.push({
      login: item.login,
      name: item.name || item.login,
      active: true,
      startedAt: '',
      paidAt: '',
      dueAt: '',
      amount: '',
      debt: '',
      status: 'Не задано',
      note: item.note || ''
    });
  }

  item.status = 'approved';
  item.decidedAt = nowStamp();
  item.decisionNote = 'approved';
  requestsFile.json.updatedAt = item.decidedAt;

  await writeGitFile(env, ACCOUNTS_PATH, accountsFile.json, accountsFile.sha, `Approve Gus account ${item.login}`);
  await writeGitFile(env, PAYMENTS_PATH, paymentsFile.json, paymentsFile.sha, `Add Gus payment row ${item.login}`);
  await writeGitFile(env, REQUESTS_PATH, requestsFile.json, requestsFile.sha, `Approve Gus registration request ${item.login}`);

  return jsonResponse({ ok: true, account: { login: item.login, name: item.name, active: true } });
}

async function denyRequest(request, env, id) {
  requireAdmin(request, env);
  const body = await request.json().catch(() => ({}));
  const requestsFile = await readGitFile(env, REQUESTS_PATH, defaultRequests());
  const item = (requestsFile.json.requests || []).find((entry) => String(entry.id) === id);
  if (!item) return jsonResponse({ ok: false, error: 'Заявка не найдена.' }, 404);
  if (item.status !== 'pending') return jsonResponse({ ok: false, error: 'Заявка уже обработана.' }, 409);
  item.status = 'denied';
  item.decidedAt = nowStamp();
  item.decisionNote = cleanText(body.reason, 200) || 'denied';
  requestsFile.json.updatedAt = item.decidedAt;
  await writeGitFile(env, REQUESTS_PATH, requestsFile.json, requestsFile.sha, `Deny Gus registration request ${item.login}`);
  return jsonResponse({ ok: true, id: item.id, status: item.status });
}

async function writeAdminFile(request, env) {
  requireAdmin(request, env);
  const body = await request.json().catch(() => null);
  if (!body || !body.path || typeof body.content !== 'string') {
    return jsonResponse({ ok: false, error: 'Need path and content.' }, 400);
  }
  const allowed = new Set([PAYMENTS_PATH, 'payments_config.json', ACCOUNTS_PATH]);
  const filePath = String(body.path);
  if (!allowed.has(filePath)) return jsonResponse({ ok: false, error: 'Path is not allowed.' }, 403);
  let parsed = null;
  try { parsed = JSON.parse(body.content); } catch (_) { return jsonResponse({ ok: false, error: 'Content must be JSON.' }, 400); }
  const current = await readGitFile(env, filePath, {});
  await writeGitFile(env, filePath, parsed, current.sha, cleanText(body.message, 140) || `Update ${filePath}`);
  return jsonResponse({ ok: true, path: filePath });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });
    const url = new URL(request.url);
    try {
      if (url.pathname === '/health') return jsonResponse({ ok: true, name: 'gus-registration-worker' });
      if (url.pathname === '/request' && request.method === 'POST') return createRequest(request, env);
      if (url.pathname === '/requests' && request.method === 'GET') return listRequests(request, env);
      const approveMatch = url.pathname.match(/^\/requests\/([^/]+)\/approve$/);
      if (approveMatch && request.method === 'POST') return approveRequest(request, env, approveMatch[1]);
      const denyMatch = url.pathname.match(/^\/requests\/([^/]+)\/deny$/);
      if (denyMatch && request.method === 'POST') return denyRequest(request, env, denyMatch[1]);
      if (url.pathname === '/admin/file' && request.method === 'PUT') return writeAdminFile(request, env);
      return textResponse('Not found', 404);
    } catch (error) {
      return jsonResponse({ ok: false, error: error.message || String(error) }, error.status || 500);
    }
  }
};
