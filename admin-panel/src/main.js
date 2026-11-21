import { initializeApp } from '@firebase/app';
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from '@firebase/auth';
import {
  collection,
  doc,
  getDoc,
  getFirestore,
  limit,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  getDocs,
} from '@firebase/firestore';
import { firebaseConfig } from './firebase-config.js';
import './styles.css';

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const settingsRef = doc(db, 'appConfig', 'current');
const versionsRef = collection(db, 'appConfig', 'current', 'versions');

const root = document.querySelector('#app');
const state = {
  user: null,
  template: null,
  loadError: '',
  savedTemplateJson: '',
  versions: [],
  catalog: [],
  catalogHistory: [],
  route: 'overview',
  busy: false,
  notice: null,
};

const parameters = {
  llm_model: { type: 'STRING', fallback: 'nvidia/nemotron-3.5-super-vl:free' },
  llm_max_output_tokens: { type: 'NUMBER', fallback: '8000' },
  llm_timeout_seconds: { type: 'NUMBER', fallback: '120' },
  splash_ad_enabled: { type: 'BOOLEAN', fallback: 'false' },
  splash_ad_image_url: { type: 'STRING', fallback: '' },
  splash_ad_link_url: { type: 'STRING', fallback: '' },
  splash_ad_campaign_id: { type: 'STRING', fallback: '' },
  splash_ad_label: { type: 'STRING', fallback: 'Sponsored' },
  toast_bar_enabled: { type: 'BOOLEAN', fallback: 'false' },
  toast_bar_subject: { type: 'STRING', fallback: '' },
  toast_bar_tagline: { type: 'STRING', fallback: '' },
  toast_bar_link_url: { type: 'STRING', fallback: '' },
  toast_bar_image_url: { type: 'STRING', fallback: '' },
};

const navItems = [
  ['overview', 'Overview', 'grid'],
  ['app-controls', 'AI controls', 'spark'],
  ['strategy-catalog', 'Strategies & specialists', 'spark'],
  ['diagnostics', 'Analytics & diagnostics', 'history'],
  ['splash-ad', 'Splash promotion', 'image'],
  ['toast-bar', 'In-app message bar', 'message'],
  ['template', 'Settings editor', 'code'],
  ['history', 'Change history', 'clock'],
];

function icon(name, size = 19) {
  const paths = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
    spark: '<path d="m12 3 1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z"/><path d="m19 14 .8 2.2L22 17l-2.2.8L19 20l-.8-2.2L16 17l2.2-.8L19 14Z"/>',
    image: '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="8.5" cy="9" r="1.5"/><path d="m21 15-5-5L5 20"/>',
    code: '<path d="m8 8-4 4 4 4M16 8l4 4-4 4m-3-10-2 12"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    refresh: '<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.6 9a7 7 0 0 1 11.6-2L20 12M4 12l2.8 5a7 7 0 0 0 11.6-2"/>',
    arrow: '<path d="M7 17 17 7M7 7h10v10"/>',
    shield: '<path d="M12 22s8-4 8-11V5l-8-3-8 3v6c0 7 8 11 8 11Z"/><path d="m9 12 2 2 4-4"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    close: '<path d="m18 6-12 12M6 6l12 12"/>',
    eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
    bolt: '<path d="m13 2-3 8H5l6 12 3-8h5L13 2Z"/>',
    cloud: '<path d="M20 16.2A4.5 4.5 0 0 0 18.5 7H17a6 6 0 0 0-11.6 1.8A4.5 4.5 0 0 0 6.5 18H18"/><path d="m12 12-3 4h4l-1 4 4-5h-4l1-3Z"/>',
    logout: '<path d="M10 17l5-5-5-5M15 12H3"/><path d="M12 3h6a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-6"/>',
    chevron: '<path d="m9 18 6-6-6-6"/>',
    sliders: '<path d="M4 21v-7m0-4V3m8 18v-9m0-4V3m8 18v-5m0-4V3M2 14h4m4-6h4m4 8h4"/>',
    history: '<path d="M3 12a9 9 0 1 0 2.6-6.4L3 8"/><path d="M3 3v5h5m4-1v5l3 2"/>',
    message: '<path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5Z"/>',
  };
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.grid}</svg>`;
}

function escapeHtml(value = '') {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

function readValue(key) {
  const value = state.template?.parameters?.[key]?.defaultValue;
  if (!value) return parameters[key]?.fallback ?? '';
  if (typeof value === 'object' && 'value' in value) return String(value.value);
  return parameters[key]?.fallback ?? '';
}

function defaultTemplate() {
  return {
    conditions: [],
    parameters: Object.fromEntries(Object.entries(parameters).map(([key, config]) => [key, {
      valueType: config.type,
      defaultValue: { value: config.fallback },
    }])),
  };
}

function templateFromSettings(settings) {
  const template = defaultTemplate();
  for (const [key, config] of Object.entries(parameters)) {
    const value = settings?.[key];
    if (value !== undefined && value !== null) {
      template.parameters[key].defaultValue.value = String(value);
    }
  }
  return template;
}

function settingsFromTemplate(template) {
  const settings = {};
  for (const [key, config] of Object.entries(parameters)) {
    const value = template?.parameters?.[key]?.defaultValue?.value;
    if (value === undefined || value === null) {
      settings[key] = config.fallback;
    } else if (config.type === 'NUMBER') {
      settings[key] = Number(value);
    } else if (config.type === 'BOOLEAN') {
      settings[key] = String(value).toLowerCase() === 'true';
    } else {
      settings[key] = String(value);
    }
  }
  return settings;
}

function versionFromSnapshot(snapshot) {
  const data = snapshot.data();
  return {
    versionNumber: String(data.versionNumber || ''),
    updateTime: data.publishedAt?.toDate?.().toISOString() || null,
    description: data.description || 'Settings update',
    updateOrigin: 'ADMIN CONSOLE',
    updateUser: data.publishedBy || '',
    templateJson: data.templateJson,
  };
}

function writeValue(key, value) {
  if (!state.template.parameters) state.template.parameters = {};
  const prior = state.template.parameters[key] || {};
  state.template.parameters[key] = {
    ...prior,
    valueType: parameters[key]?.type || prior.valueType || 'STRING',
    defaultValue: { value: String(value) },
  };
  updateDirtyState();
}

function updateDirtyState() {
  const current = JSON.stringify(state.template);
  const dirty = current !== state.savedTemplateJson;
  document.querySelectorAll('[data-dirty]').forEach((element) => {
    element.textContent = dirty ? 'Unsaved changes' : 'All changes published';
    element.classList.toggle('is-dirty', dirty);
    element.classList.toggle('is-clean', !dirty);
  });
  document.querySelectorAll('[data-publish]').forEach((button) => {
    button.disabled = !dirty || state.busy;
  });
  return dirty;
}

function notify(message, type = 'success') {
  state.notice = { message, type };
  const existing = document.querySelector('.toast');
  existing?.remove();
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `${icon(type === 'error' ? 'close' : 'check', 17)}<span>${escapeHtml(message)}</span>`;
  document.body.appendChild(toast);
  window.setTimeout(() => toast.remove(), 4600);
}

function getErrorMessage(error) {
  const code = String(error?.code || '').toLowerCase();
  const message = String(error?.message || '');
  if (code.includes('permission-denied')) return 'Firestore denied this request. Confirm the account is verified and the current Firestore rules are deployed.';
  if (code.includes('unauthenticated')) return 'Your session expired. Sign in again.';
  if (code.includes('unavailable')) return 'Firestore is offline or temporarily unavailable. Your local draft is still here; try again when the connection returns.';
  return message.replace(/^FirebaseError:\s*/, '') || 'Something went wrong. Please try again.';
}

function renderLogin(message = '') {
  root.innerHTML = `
    <main class="login-page">
      <div class="login-orb login-orb-one"></div><div class="login-orb login-orb-two"></div>
      <section class="login-aside">
        <a class="brand-lockup" href="#" aria-label="TenX Admin home">
          <span class="brand-mark"><span></span><span></span><span></span></span>
          <span><strong>TenX</strong><small>ADMIN CONSOLE</small></span>
        </a>
        <div class="login-story">
          <div class="eyebrow"><span class="pulse-dot"></span> APP OPERATIONS</div>
          <h1>Everything in<br />sync<span>.</span></h1>
          <p>One calm workspace to tune the app, manage promotions, and ship configuration changes safely.</p>
          <div class="story-stat-row">
            <div><strong>Live</strong><span>runtime controls</span></div>
            <div class="story-divider"></div>
            <div><strong>Versioned</strong><span>every publish</span></div>
          </div>
        </div>
        <div class="login-footnote">TENX MARKETS <span>·</span> PRIVATE ADMIN ACCESS</div>
      </section>
      <section class="login-main">
        <div class="login-card">
          <div class="mobile-brand brand-lockup">
            <span class="brand-mark"><span></span><span></span><span></span></span>
            <span><strong>TenX</strong><small>ADMIN CONSOLE</small></span>
          </div>
          <div class="login-icon">${icon('shield', 24)}</div>
          <p class="eyebrow muted">ADMINISTRATOR SIGN IN</p>
          <h2>Welcome back</h2>
          <p class="login-subtitle">Sign in with your approved TenX admin account.</p>
          ${message ? `<div class="inline-error" role="alert">${icon('close', 16)}<span>${escapeHtml(message)}</span></div>` : ''}
          <button class="button button-google" id="google-login" type="button"><span class="google-mark"><svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.5 0 6.7 1.2 9.2 3.6l6.8-6.8C35.9 2.4 30.5 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.9 6.1C12.4 13.6 17.7 9.5 24 9.5Z"/><path fill="#4285F4" d="M46.1 24.5c0-1.6-.2-3.2-.5-4.8H24v9h12.4c-.5 2.9-2.1 5.4-4.6 7.1l7.4 5.7c4.3-4 6.9-9.9 6.9-17Z"/><path fill="#FBBC05" d="M10.5 28.7a14.5 14.5 0 0 1 0-9.4l-7.9-6.1a24 24 0 0 0 0 21.6l7.9-6.1Z"/><path fill="#34A853" d="M24 48c6.5 0 12-2.1 16-5.8l-7.4-5.7c-2.1 1.4-4.9 2.3-8.6 2.3-6.3 0-11.6-4.1-13.5-9.8l-7.9 6.1C6.5 42.6 14.6 48 24 48Z"/></svg></span>Continue with Google</button>
          <div class="form-divider"><span></span><em>or use email</em><span></span></div>
          <form id="login-form" class="login-form">
            <label>Email address<input id="email" type="email" autocomplete="username" placeholder="you@company.com" required /></label>
            <label>Password<div class="password-field"><input id="password" type="password" autocomplete="current-password" placeholder="Enter your password" required minlength="6" /><button type="button" class="eye-button" id="toggle-password" aria-label="Show password">${icon('eye', 18)}</button></div></label>
            <div class="form-meta"><span>Access is restricted to approved admins.</span><button type="button" class="text-button" id="forgot-password">Forgot password?</button></div>
            <button class="button button-primary button-wide" id="email-login" type="submit">Sign in <span>${icon('chevron', 17)}</span></button>
          </form>
          <p class="login-security">${icon('shield', 14)} Protected with Firebase Authentication</p>
        </div>
      </section>
    </main>`;

  document.querySelector('#google-login').addEventListener('click', async (event) => {
    setButtonLoading(event.currentTarget, true, 'Connecting…');
    try {
      await signInWithPopup(auth, new GoogleAuthProvider());
    } catch (error) {
      renderLogin(error.code === 'auth/popup-closed-by-user' ? '' : getErrorMessage(error));
    }
  });
  document.querySelector('#login-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = document.querySelector('#email-login');
    setButtonLoading(button, true, 'Signing in…');
    try {
      await signInWithEmailAndPassword(
        auth,
        document.querySelector('#email').value.trim(),
        document.querySelector('#password').value,
      );
    } catch (error) {
      renderLogin(getErrorMessage(error));
    }
  });
  document.querySelector('#forgot-password').addEventListener('click', async () => {
    const email = document.querySelector('#email').value.trim();
    if (!email) return renderLogin('Enter your email address first, then choose “Forgot password?”.');
    try {
      await sendPasswordResetEmail(auth, email);
      renderLogin('If that email belongs to an account, a password reset link has been sent.');
    } catch (error) {
      renderLogin(getErrorMessage(error));
    }
  });
  document.querySelector('#toggle-password').addEventListener('click', () => {
    const password = document.querySelector('#password');
    password.type = password.type === 'password' ? 'text' : 'password';
  });
}

function renderAdminSetup(user) {
  const uid = user.uid;
  const email = user.email || '(no email on this account)';
  const setupUrl = 'https://console.firebase.google.com/project/tenx-markets/firestore/databases/-default-/data';
  root.innerHTML = `
    <main class="login-page">
      <div class="login-orb login-orb-one"></div><div class="login-orb login-orb-two"></div>
      <section class="login-aside"><a class="brand-lockup" href="#"><span class="brand-mark"><span></span><span></span><span></span></span><span><strong>TenX</strong><small>ADMIN CONSOLE</small></span></a><div class="login-story"><div class="eyebrow"><span class="pulse-dot"></span> ACCOUNT SETUP</div><h1>One secure<br />admin role<span>.</span></h1><p>Admin access is assigned to Firebase accounts by UID, so it follows your account without relying on a guessed email address.</p></div><div class="login-footnote">TENX MARKETS <span>·</span> PRIVATE ADMIN ACCESS</div></section>
      <section class="login-main"><div class="login-card setup-card"><div class="mobile-brand brand-lockup"><span class="brand-mark"><span></span><span></span><span></span></span><span><strong>TenX</strong><small>ADMIN CONSOLE</small></span></div><div class="login-icon">${icon('shield', 24)}</div><p class="eyebrow muted">ADMIN ACCESS SETUP</p><h2>Register this account</h2><p class="login-subtitle">You’re signed in as <strong>${escapeHtml(email)}</strong>, but this Firebase account has no admin role yet.</p><div class="setup-uid"><span>FIREBASE USER UID</span><code>${escapeHtml(uid)}</code><button class="button button-secondary button-small" id="copy-admin-uid">Copy UID</button></div><ol class="setup-steps"><li>Open the project’s <a href="${setupUrl}" target="_blank" rel="noreferrer">Firestore Data page</a>.</li><li>Create a top-level collection named <code>adminUsers</code>.</li><li>Add a document whose ID is the UID above, with fields <code>role</code> = <code>admin</code>, <code>uid</code> = your UID, and <code>email</code> = <code>${escapeHtml(email)}</code>.</li><li>Return here and reload. The deployed Security Rules prevent client-side accounts from granting themselves this role.</li></ol><button class="button button-primary setup-reload" id="reload-admin-role">Check admin access ${icon('refresh', 15)}</button><button class="text-button setup-signout" id="setup-signout">Sign out</button></div></section>
    </main>`;
  document.querySelector('#copy-admin-uid').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(uid);
      notify('Firebase UID copied.');
    } catch (_) {
      notify('Select and copy the UID shown above.', 'error');
    }
  });
  document.querySelector('#reload-admin-role').addEventListener('click', () => loadConsoleData(true));
  document.querySelector('#setup-signout').addEventListener('click', () => signOut(auth));
}

function setButtonLoading(button, loading, text = 'Please wait…') {
  if (!button) return;
  if (loading) {
    button.dataset.originalHtml = button.innerHTML;
    button.disabled = true;
    button.innerHTML = `<span class="spinner"></span>${escapeHtml(text)}`;
  } else if (button.dataset.originalHtml) {
    button.innerHTML = button.dataset.originalHtml;
    button.disabled = false;
    delete button.dataset.originalHtml;
  }
}

function getDateLabel(value) {
  if (!value) return 'Not published yet';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Recently';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

function getCurrentVersion() {
  return state.template?.version?.versionNumber ?? '0';
}

function getCurrentUpdateTime() {
  return state.template?.version?.updateTime || null;
}

function renderShell() {
  const title = navItems.find(([route]) => route === state.route)?.[1] || 'Overview';
  const initials = (state.user?.displayName || state.user?.email || 'A')
    .split(/[\s@.]+/).filter(Boolean).slice(0, 2).map((word) => word[0]).join('').toUpperCase();
  root.innerHTML = `
    <div class="console-layout">
      <aside class="sidebar" id="sidebar">
        <a class="brand-lockup sidebar-brand" href="#overview" aria-label="TenX admin overview">
          <span class="brand-mark"><span></span><span></span><span></span></span>
          <span><strong>TenX</strong><small>CONTROL ROOM</small></span>
        </a>
        <div class="project-pill"><span class="project-dot"></span><span><strong>tenx-markets</strong><small>PRODUCTION PROJECT</small></span><span class="project-chevron">⌄</span></div>
        <p class="nav-caption">WORKSPACE</p>
        <nav class="side-nav" aria-label="Admin sections">
          ${navItems.map(([route, label, glyph]) => `<button class="nav-item ${state.route === route ? 'active' : ''}" data-route="${route}">${icon(glyph, 18)}<span>${label}</span>${route === 'history' ? `<span class="nav-count">${Math.min(state.versions.length, 99)}</span>` : ''}</button>`).join('')}
        </nav>
        <div class="sidebar-spacer"></div>
        <div class="sidebar-help"><div class="help-icon">${icon('bolt', 17)}</div><strong>Changes go live fast</strong><p>Settings sync to signed-in app users through Firestore.</p><button data-route="template">Review the template ${icon('arrow', 14)}</button></div>
        <div class="sidebar-user"><div class="avatar">${escapeHtml(initials)}</div><div class="user-copy"><strong>${escapeHtml(state.user?.displayName || 'Admin')}</strong><small>${escapeHtml(state.user?.email || '')}</small></div><button class="icon-button signout" aria-label="Sign out" title="Sign out">${icon('logout', 17)}</button></div>
      </aside>
      <main class="main-area">
        <header class="topbar">
          <button id="mobile-menu" class="icon-button mobile-menu" aria-label="Open menu">${icon('sliders', 18)}</button>
          <div class="breadcrumbs"><span>TenX</span>${icon('chevron', 14)}<strong>${escapeHtml(title)}</strong></div>
          <div class="topbar-actions"><div class="secure-pill">${icon('shield', 14)} <span>Secure session</span></div><button class="icon-button top-refresh" id="refresh" title="Refresh Firestore settings">${icon('refresh', 18)}</button><div class="avatar top-avatar">${escapeHtml(initials)}</div></div>
        </header>
        <div class="page-wrap">
          ${state.notice ? `<div class="banner banner-${state.notice.type}">${icon(state.notice.type === 'error' ? 'close' : 'check', 16)}<span>${escapeHtml(state.notice.message)}</span></div>` : ''}
          ${renderRoute()}
          <footer class="page-footer"><span>TENX ADMIN CONSOLE</span><span>Settings history is stored in Firestore</span></footer>
        </div>
      </main>
    </div>`;

  document.querySelectorAll('[data-route]').forEach((button) => {
    button.addEventListener('click', () => {
      state.route = button.dataset.route;
      state.notice = null;
      renderShell();
      document.querySelector('#sidebar')?.classList.remove('sidebar-open');
    });
  });
  document.querySelector('.signout').addEventListener('click', () => signOut(auth));
  document.querySelector('#refresh').addEventListener('click', loadConsoleData);
  document.querySelector('#retry-load')?.addEventListener('click', loadConsoleData);
  document.querySelector('#mobile-menu').addEventListener('click', () => document.querySelector('#sidebar').classList.toggle('sidebar-open'));
  bindRouteEvents();
}

function renderRoute() {
  if (!state.template) {
    if (state.loadError) {
      return `<section class="loading-panel"><div class="load-error-icon">${icon('cloud', 23)}</div><h2>Couldn’t connect to Firestore settings</h2><p>${escapeHtml(state.loadError)}</p><button class="button button-primary retry-load" id="retry-load">Try again ${icon('refresh', 15)}</button></section>`;
    }
    return `<section class="loading-panel"><div class="loading-mark"><span></span><span></span><span></span></div><h2>Connecting to Firestore settings</h2><p>Loading the current settings and change history…</p></section>`;
  }
  switch (state.route) {
    case 'app-controls': return renderAppControls();
    case 'strategy-catalog': return renderStrategyCatalog();
    case 'diagnostics': return renderDiagnostics();
    case 'splash-ad': return renderSplashAd();
    case 'toast-bar': return renderToastBar();
    case 'template': return renderTemplateEditor();
    case 'history': return renderHistory();
    default: return renderOverview();
  }
}

function pageHeader(eyebrow, title, description, action = '') {
  return `<div class="page-heading"><div><p class="eyebrow">${eyebrow}</p><h1>${title}</h1><p class="page-description">${description}</p></div>${action}</div>`;
}

function renderOverview() {
  const version = getCurrentVersion();
  const adOn = readValue('splash_ad_enabled') === 'true';
  return `${pageHeader('TENX / APP SETTINGS', 'Good to see you.', 'Your app controls, promotions, and release history at a glance.', `<button class="button button-secondary" id="overview-refresh">${icon('refresh', 16)} Refresh data</button>`)}
    <section class="welcome-band"><div class="welcome-copy"><div class="welcome-badge"><span class="pulse-dot"></span> LIVE PROJECT</div><h2>Keep your app<br /><em>in its best shape.</em></h2><p>Make a change, review the draft, then save it for your users.</p><button class="button button-white" data-route="app-controls">Manage app controls ${icon('chevron', 16)}</button></div><div class="welcome-art" aria-hidden="true"><div class="art-orbit orbit-a"></div><div class="art-orbit orbit-b"></div><div class="art-glass"><span class="art-spark">✳</span><div class="art-line"></div><div class="art-wave"></div><div class="art-check">${icon('check', 21)}</div></div><div class="art-chip chip-top">${icon('cloud', 15)} Cloud synced</div><div class="art-chip chip-bottom">${icon('bolt', 14)} Live updates</div></div></section>
    <div class="metric-grid"><article class="metric-card"><div class="metric-top"><span>ACTIVE VERSION</span><span class="metric-icon blue">${icon('cloud', 17)}</span></div><strong class="metric-value">${escapeHtml(version)}</strong><small>Current shared app settings</small></article><article class="metric-card"><div class="metric-top"><span>CONFIGURATION KEYS</span><span class="metric-icon violet">${icon('sliders', 17)}</span></div><strong class="metric-value">${Object.keys(state.template.parameters || {}).length}</strong><small>Available runtime parameters</small></article><article class="metric-card"><div class="metric-top"><span>SPLASH PROMOTION</span><span class="metric-icon ${adOn ? 'green' : 'gray'}">${icon('image', 17)}</span></div><strong class="metric-value metric-status">${adOn ? 'Enabled' : 'Off'}</strong><small>${adOn ? 'Image promotion is active' : 'No promotion will be shown'}</small></article><article class="metric-card"><div class="metric-top"><span>LAST PUBLISH</span><span class="metric-icon amber">${icon('clock', 17)}</span></div><strong class="metric-value metric-date">${escapeHtml(getDateLabel(getCurrentUpdateTime()))}</strong><small>${state.versions.length ? `${state.versions.length} recent settings versions available` : 'No settings history yet'}</small></article></div>
    <div class="section-row"><div><p class="eyebrow">QUICK ACCESS</p><h2>App controls</h2></div><span class="subtle-count">${Object.keys(state.template.parameters || {}).length} settings</span></div>
    <div class="quick-grid"><button class="quick-card" data-route="app-controls"><span class="quick-icon quick-blue">${icon('spark', 20)}</span><span class="quick-text"><strong>AI behavior</strong><small>Model, output size, and timeout</small></span>${icon('chevron', 17)}</button><button class="quick-card" data-route="splash-ad"><span class="quick-icon quick-purple">${icon('image', 20)}</span><span class="quick-text"><strong>Splash promotion</strong><small>Image, destination, and visibility</small></span>${icon('chevron', 17)}</button><button class="quick-card" data-route="history"><span class="quick-icon quick-green">${icon('history', 20)}</span><span class="quick-text"><strong>Change history</strong><small>Review or restore an earlier version</small></span>${icon('chevron', 17)}</button></div>
    <div class="bottom-grid"><section class="surface-card recent-card"><div class="card-heading"><div><p class="eyebrow">CHANGE HISTORY</p><h3>Recent publishes</h3></div><button class="text-button" data-route="history">View all ${icon('chevron', 14)}</button></div>${renderRecentVersions(3)}</section><section class="surface-card readiness-card"><div class="readiness-icon">${icon('shield', 21)}</div><div><p class="eyebrow">ACCESS CONTROL</p><h3>Admin access is protected</h3><p>Only verified accounts on the admin allowlist can read or publish Firestore settings.</p><span class="ready-status"><i></i> Authentication active</span></div></section></div>`;
}

function renderAppControls() {
  return `${pageHeader('RUNTIME / AI', 'AI controls', 'Tune the model and request limits without shipping a new app build.', `<span class="dirty-pill" data-dirty></span>`)}
    <section class="info-strip">${icon('bolt', 18)}<div><strong>Changes update the app remotely</strong><p>Users receive the active values the next time the app fetches Firestore settings. Built-in defaults keep the app usable offline.</p></div></section>
    <section class="surface-card form-card"><div class="card-heading"><div class="card-title-icon blue">${icon('spark', 19)}</div><div><h3>AI request behavior</h3><p>Set the model and response budget used across the app.</p></div><span class="section-tag">AI SERVICE</span></div>
      ${textField('llm_model', 'Model identifier', 'nvidia/nemotron-3.5-super-vl:free', 'Use a model ID supported by your configured provider.', 'text')}
      <div class="field-grid two">${numberField('llm_max_output_tokens', 'Maximum output tokens', 8000, 256, 32000, 'Higher values allow longer analysis responses.')}${numberField('llm_timeout_seconds', 'Request timeout', 120, 30, 300, 'Seconds before the app reports a timed-out response.')}</div>
    </section>
    ${publishBar()}`;
}

function renderSplashAd() {
  const enabled = readValue('splash_ad_enabled') === 'true';
  const imageUrl = readValue('splash_ad_image_url');
  return `${pageHeader('APP EXPERIENCE / SPLASH', 'Splash promotion', 'Manage the optional image and destination shown on the splash screen.', `<span class="dirty-pill" data-dirty></span>`)}
    <div class="ad-layout"><div class="ad-editor-column">
      <section class="surface-card form-card"><div class="card-heading"><div class="card-title-icon purple">${icon('image', 19)}</div><div><h3>Promotion status</h3><p>The promotion appears only when it is enabled and has a valid image and link.</p></div></div>
        <label class="switch-row"><span class="switch-copy"><strong>Show splash promotion</strong><small>Users see the card when a campaign is available.</small></span><span class="switch"><input id="field-splash_ad_enabled" type="checkbox" ${enabled ? 'checked' : ''}/><i></i></span></label>
        ${textField('splash_ad_label', 'Card label', 'Sponsored', 'Short label shown above the image.', 'text')}
        ${textField('splash_ad_campaign_id', 'Campaign ID', '', 'Optional identifier used for impression and click analytics.', 'text')}
      </section>
      <section class="surface-card form-card"><div class="card-heading"><div class="card-title-icon blue">${icon('arrow', 18)}</div><div><h3>Creative & destination</h3><p>Use a public HTTPS image URL and the page you want the card to open.</p></div></div>
        ${textField('splash_ad_image_url', 'Image URL', 'https://example.com/campaign.jpg', 'Recommended: a wide image at least 1200 × 600 px.', 'url')}
        ${textField('splash_ad_link_url', 'Destination URL', 'https://example.com', 'The destination opens outside the app when tapped.', 'url')}
      </section>
    </div><aside class="ad-preview-column"><section class="preview-sticky"><div class="preview-header"><div><p class="eyebrow">LIVE PREVIEW</p><h3>Splash placement</h3></div><span class="preview-device">iPhone</span></div><div class="phone-frame"><div class="phone-notch"></div><div class="phone-screen"><div class="phone-topline"><span>9:41</span><span>●●● ◒</span></div><div class="phone-logo"><div class="mini-brand-mark"><i></i><i></i><i></i></div><strong>TENX</strong></div><div class="phone-tagline">Alerts and<br/>multi agent analysis</div><div class="ad-preview-card ${enabled ? '' : 'preview-disabled'}" id="ad-preview-card"><div class="preview-card-top"><span class="preview-label" id="preview-label">${escapeHtml(readValue('splash_ad_label') || 'Sponsored')}</span>${icon('arrow', 14)}</div><div class="preview-image" id="preview-image">${imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="Campaign preview" onerror="this.parentElement.classList.add('image-error');this.remove()"/>` : `<div class="image-placeholder">${icon('image', 24)}<span>Your image appears here</span></div>`}</div></div><div class="preview-hidden-note" id="preview-hidden-note">Promotion hidden while disabled</div><div class="phone-footer"><span class="phone-progress"></span><span class="phone-progress active"></span><span class="phone-progress"></span></div></div></div><p class="preview-caption">Preview updates as you edit. The app hides the card when an image or destination is missing.</p></section></aside></div>
    ${publishBar()}`;
}

function renderToastBar() {
  const enabled = readValue('toast_bar_enabled') === 'true';
  const imageUrl = readValue('toast_bar_image_url');
  return `${pageHeader('APP EXPERIENCE / IN-APP', 'Message bar', 'Publish a linked promotion or admin message that appears 30 seconds after app launch.', `<span class="dirty-pill" data-dirty></span>`)}
    <div class="ad-layout"><div class="ad-editor-column">
      <section class="surface-card form-card"><div class="card-heading"><div class="card-title-icon green">${icon('message', 19)}</div><div><h3>Message status</h3><p>Enable the bar to show this content to signed-in app users.</p></div></div>
        <label class="switch-row"><span class="switch-copy"><strong>Show in-app message bar</strong><small>Users see the active bar 30 seconds after opening the app.</small></span><span class="switch"><input id="field-toast_bar_enabled" type="checkbox" ${enabled ? 'checked' : ''}/><i></i></span></label>
        ${textField('toast_bar_subject', 'Subject', 'A short headline', 'Required when enabled. Up to 120 characters.', 'text')}
        ${textAreaField('toast_bar_tagline', 'Tagline', 'A brief supporting message', 'Required when enabled. Up to 240 characters.')}
      </section>
      <section class="surface-card form-card"><div class="card-heading"><div class="card-title-icon blue">${icon('arrow', 18)}</div><div><h3>Link & image</h3><p>The whole bar opens the destination. The image is optional.</p></div></div>
        ${textField('toast_bar_link_url', 'Active link', 'https://example.com', 'Required when enabled. Use an HTTPS destination.', 'url')}
        ${textField('toast_bar_image_url', 'Image URL (optional)', 'https://example.com/message.jpg', 'Use a public HTTPS image URL. Suggested landscape image: 1200 × 600 px.', 'url')}
      </section>
    </div><aside class="ad-preview-column"><section class="preview-sticky"><div class="preview-header"><div><p class="eyebrow">LIVE PREVIEW</p><h3>In-app message</h3></div><span class="preview-device">iPhone</span></div><div class="toast-preview-device"><div class="toast-preview-status">9:41 <span>●●● ◒</span></div><div class="toast-preview-app"><span class="mini-brand-mark"><i></i><i></i><i></i></span><strong>TENX MARKETS</strong></div><div class="toast-preview-chart"><i></i><i></i><i></i><i></i><i></i><i></i></div><article class="toast-bar-preview ${enabled ? '' : 'preview-disabled'}" id="toast-bar-preview">${imageUrl ? `<img id="toast-bar-preview-image" src="${escapeHtml(imageUrl)}" alt="Message image"/>` : ''}<div class="toast-bar-preview-copy"><span class="toast-preview-icon">${icon('message', 18)}</span><div><strong id="toast-preview-subject">${escapeHtml(readValue('toast_bar_subject') || 'Your subject')}</strong><p id="toast-preview-tagline">${escapeHtml(readValue('toast_bar_tagline') || 'Your tagline appears here.')}</p></div>${icon('arrow', 17)}</div><span class="toast-preview-close">${icon('close', 14)}</span></article><div class="toast-preview-nav"><i></i><i></i><i></i></div></div></div><p class="preview-caption">Dismissal lasts until the user opens the app again.</p></section></aside></div>
    ${publishBar()}`;
}

function renderTemplateEditor() {
  return `${pageHeader('APP SETTINGS / ADVANCED', 'Settings editor', 'Inspect or edit every parameter, condition, and group in the active app settings.', `<span class="dirty-pill" data-dirty></span>`)}
    <section class="info-strip">${icon('shield', 18)}<div><strong>Advanced editing keeps advanced settings control</strong><p>The editor preserves conditions and parameter groups. Validate your JSON before publishing; the app validates the settings before saving.</p></div></section>
    <section class="surface-card editor-card"><div class="editor-toolbar"><div><span class="editor-file-dot"></span><span>app-settings.json</span></div><div class="editor-actions"><span class="editor-valid" id="json-status">${icon('check', 14)} Ready to edit</span><button class="button button-secondary button-small" id="format-json">Format JSON</button></div></div><textarea id="template-json" spellcheck="false" aria-label="Firestore settings JSON template">${escapeHtml(JSON.stringify(state.template, null, 2))}</textarea><div class="editor-footer"><span>JSON · Firebase Firestore settings</span><button class="button button-secondary button-small" id="apply-json">Apply to draft</button></div></section>
    <div class="editor-notes"><div>${icon('history', 17)}<span>Every save creates a version snapshot in Firestore.</span></div><div>${icon('cloud', 17)}<span>All settings are saved in a single Firestore transaction.</span></div></div>
    ${publishBar()}`;
}

function renderHistory() {
  return `${pageHeader('APP SETTINGS / AUDIT', 'Change history', 'Every saved change is versioned. Restore a previous settings version if you need to roll back.', `<button class="button button-secondary" id="history-refresh">${icon('refresh', 16)} Refresh</button>`)}
    <section class="history-summary"><div class="history-summary-icon">${icon('history', 21)}</div><div><strong>${state.versions.length} recent versions</strong><p>Firebase retains version history and records which admin saved each change.</p></div><span class="history-live">CURRENT · ${escapeHtml(getCurrentVersion())}</span></section>
    <section class="surface-card history-list-card"><div class="card-heading"><div><p class="eyebrow">AUDIT TRAIL</p><h3>Settings versions</h3></div><span class="section-tag">NEWEST FIRST</span></div><div class="version-list">${renderVersions()}</div></section>
    <div class="history-tip">${icon('shield', 17)}<span>Restoring a version saves it as a new current version. Existing history remains intact.</span></div>`;
}

function renderStrategyCatalog() {
  const rows = state.catalog.map((entry) => `<article class="surface-card catalog-entry"><div class="catalog-entry-head"><div><p class="eyebrow">${escapeHtml(entry.type)} · ${escapeHtml(entry.status)}</p><h3>${escapeHtml(entry.name)}</h3><small>${escapeHtml(entry.id)}</small></div><button class="button button-secondary button-small" data-catalog-delete="${escapeHtml(entry.id)}">Delete</button></div><textarea class="catalog-json" data-catalog-payload="${escapeHtml(entry.id)}" spellcheck="false">${escapeHtml(entry.payload)}</textarea><div class="catalog-actions"><label class="field-label">Status<select data-catalog-status="${escapeHtml(entry.id)}"><option ${entry.status === 'draft' ? 'selected' : ''}>draft</option><option ${entry.status === 'published' ? 'selected' : ''}>published</option><option ${entry.status === 'archived' ? 'selected' : ''}>archived</option></select></label><button class="button button-primary button-small" data-catalog-save="${escapeHtml(entry.id)}">Save entry</button></div></article>`).join('');
  return `${pageHeader('APP CONTENT / CATALOG', 'Strategies & specialists', 'Manage shared AI definitions. Drafts are private to admins; publishing makes them available to signed-in app users and cached for offline use.', '<button class="button button-secondary" id="catalog-import">Import my saved items</button>')}
    <section class="info-strip">${icon('shield', 18)}<div><strong>Review before publishing</strong><p>Entries are versioned in an append-only audit collection. The app reads only published entries. Import copies your account’s definitions as drafts.</p></div></section>
    <section class="surface-card catalog-create"><div class="card-heading"><div><p class="eyebrow">NEW SHARED ENTRY</p><h3>Create strategy or specialist</h3></div></div><div class="catalog-create-grid"><label class="field"><span class="field-label">Type</span><select id="catalog-type"><option value="strategy">Strategy</option><option value="specialist">Specialist</option></select></label><label class="field"><span class="field-label">Document ID</span><input id="catalog-id" placeholder="strategy_my_strategy" maxlength="120" /></label><label class="field"><span class="field-label">Display name</span><input id="catalog-name" placeholder="Strategy name" maxlength="120" /></label></div><label class="field"><span class="field-label">Payload JSON</span><textarea id="catalog-new-payload" class="catalog-json" spellcheck="false" placeholder='Paste the strategy or specialist JSON'></textarea></label><button class="button button-primary" id="catalog-create">Save as draft</button></section>
    <div class="catalog-list">${rows || '<section class="surface-card empty-state"><strong>No shared entries yet</strong><p>Create an entry or import your own saved strategies and specialists as drafts.</p></section>'}</div>
    <section class="surface-card history-list-card"><div class="card-heading"><div><p class="eyebrow">CATALOG AUDIT</p><h3>Recent catalog changes</h3></div><span class="section-tag">${state.catalogHistory.length} RECORDS</span></div><div class="catalog-audit">${state.catalogHistory.map((item) => `<div class="catalog-audit-row"><strong>${escapeHtml(item.action)}</strong><span>${escapeHtml(item.name)} · ${escapeHtml(item.type)}</span><small>${escapeHtml(item.recordedBy || '')}</small></div>`).join('') || '<p class="subtle-count">No catalog changes yet.</p>'}</div></section>`;
}

function renderDiagnostics() {
  const crashUrl = 'https://console.firebase.google.com/project/tenx-markets/crashlytics';
  const analyticsUrl = 'https://console.firebase.google.com/project/tenx-markets/analytics';
  return `${pageHeader('APP OPERATIONS / HEALTH', 'Analytics & diagnostics', 'Review app stability and feature usage in Firebase. Analytics events avoid account email, symbols, prices, prompts, and provider responses.')}
    <div class="quick-grid"><a class="quick-card" href="${crashUrl}" target="_blank" rel="noreferrer"><span class="quick-icon quick-purple">${icon('shield', 20)}</span><span class="quick-text"><strong>Crashlytics</strong><small>Crash-free users, fatal and non-fatal reports</small></span>${icon('arrow', 17)}</a><a class="quick-card" href="${analyticsUrl}" target="_blank" rel="noreferrer"><span class="quick-icon quick-blue">${icon('history', 20)}</span><span class="quick-text"><strong>Google Analytics</strong><small>Screen views, alerts, and AI analysis usage</small></span>${icon('arrow', 17)}</a></div>
    <section class="surface-card diagnostics-note"><p class="eyebrow">AI CONNECTION CHECK</p><h3>Run provider tests in the app</h3><p>The LLM key stays out of this web console. Use the app’s AI settings connection check, then run an analysis. This page links to Firebase telemetry; it does not send a provider request.</p></section>`;
}

function textField(key, label, placeholder, hint, type = 'text') {
  return `<label class="field"><span class="field-label">${escapeHtml(label)}</span><input data-config-key="${key}" type="${type}" value="${escapeHtml(readValue(key))}" placeholder="${escapeHtml(placeholder)}" autocomplete="off"/><small>${escapeHtml(hint)}</small></label>`;
}

function textAreaField(key, label, placeholder, hint) {
  return `<label class="field"><span class="field-label">${escapeHtml(label)}</span><textarea data-config-key="${key}" rows="3" maxlength="240" placeholder="${escapeHtml(placeholder)}">${escapeHtml(readValue(key))}</textarea><small>${escapeHtml(hint)}</small></label>`;
}

function numberField(key, label, fallback, min, max, hint) {
  return `<label class="field"><span class="field-label">${escapeHtml(label)}</span><div class="number-input"><input data-config-key="${key}" type="number" value="${escapeHtml(readValue(key) || fallback)}" min="${min}" max="${max}" step="1"/><span>${key.includes('timeout') ? 'SEC' : 'TOKENS'}</span></div><small>${escapeHtml(hint)}</small></label>`;
}

function publishBar() {
  return `<div class="publish-bar"><div class="publish-state"><span class="dirty-indicator"></span><span data-dirty></span></div><label class="publish-description">Change note<input id="change-description" type="text" maxlength="120" placeholder="What changed in this publish?" /></label><div class="publish-buttons"><button class="button button-secondary" id="validate-template">Validate</button><button class="button button-primary" data-publish disabled>Save changes ${icon('arrow', 15)}</button></div></div>`;
}

function renderRecentVersions(count) {
  if (!state.versions.length) return '<div class="empty-state"><span class="empty-icon">⌁</span><strong>No saved versions yet</strong><p>Your settings change history will appear here.</p></div>';
  return `<div class="recent-list">${state.versions.slice(0, count).map((version, index) => `<div class="recent-row"><div class="timeline-dot ${index === 0 ? 'current' : ''}"></div><div><strong>Version ${escapeHtml(version.versionNumber)}</strong><small>${escapeHtml(getDateLabel(version.updateTime))} ${version.updateUser ? `· ${escapeHtml(version.updateUser)}` : ''}</small></div><span class="version-note">${escapeHtml(version.description || 'Firestore settings update')}</span>${index === 0 ? '<span class="current-badge">CURRENT</span>' : ''}</div>`).join('')}</div>`;
}

function renderVersions() {
  if (!state.versions.length) return '<div class="empty-state"><span class="empty-icon">⌁</span><strong>No version history yet</strong><p>Saved settings snapshots will appear here.</p></div>';
  return state.versions.map((version, index) => `<article class="version-item"><div class="version-rail"><span class="version-dot ${index === 0 ? 'current' : ''}"></span>${index < state.versions.length - 1 ? '<span class="version-line"></span>' : ''}</div><div class="version-content"><div class="version-title-row"><div><span class="version-kicker">VERSION ${escapeHtml(version.versionNumber)}</span>${index === 0 ? '<span class="current-badge">CURRENT</span>' : ''}<h4>${escapeHtml(version.description || 'Firestore settings update')}</h4></div>${index === 0 ? '<span class="current-label">Active version</span>' : `<button class="button button-secondary button-small" data-rollback="${escapeHtml(version.versionNumber)}">Restore version</button>`}</div><div class="version-meta"><span>${icon('clock', 14)} ${escapeHtml(getDateLabel(version.updateTime))}</span><span>${icon('shield', 14)} ${escapeHtml(version.updateOrigin || 'Firebase')}</span>${version.updateUser ? `<span>${icon('grid', 14)} ${escapeHtml(version.updateUser)}</span>` : ''}</div></div></article>`).join('');
}

function bindRouteEvents() {
  document.querySelector('#overview-refresh')?.addEventListener('click', loadConsoleData);
  document.querySelector('#history-refresh')?.addEventListener('click', loadConsoleData);
  document.querySelector('#catalog-import')?.addEventListener('click', importMyCatalog);
  document.querySelector('#catalog-create')?.addEventListener('click', createCatalogEntry);
  document.querySelectorAll('[data-catalog-save]').forEach((button) => button.addEventListener('click', () => saveCatalogEntry(button.dataset.catalogSave)));
  document.querySelectorAll('[data-catalog-delete]').forEach((button) => button.addEventListener('click', () => removeCatalogEntry(button.dataset.catalogDelete)));
  document.querySelectorAll('[data-config-key]').forEach((field) => {
    field.addEventListener('input', () => {
      const { configKey } = field.dataset;
      let value = field.value;
      if (field.type === 'number') {
        const min = Number(field.min);
        const max = Number(field.max);
        const parsed = Number(value);
        if (!Number.isFinite(parsed)) return;
        value = String(Math.min(max, Math.max(min, Math.round(parsed))));
      }
      writeValue(configKey, value);
      if (configKey === 'splash_ad_image_url') updatePreviewImage(value);
      if (configKey === 'toast_bar_image_url') updateToastPreviewImage(value);
      if (configKey === 'toast_bar_subject') updateText('#toast-preview-subject', value, 'Your subject');
      if (configKey === 'toast_bar_tagline') updateText('#toast-preview-tagline', value, 'Your tagline appears here.');
      if (configKey === 'splash_ad_label') {
        const label = document.querySelector('#preview-label');
        if (label) label.textContent = value || 'Sponsored';
      }
    });
    field.addEventListener('change', () => {
      if (field.type === 'number') field.value = readValue(field.dataset.configKey);
    });
  });

  document.querySelector('#field-splash_ad_enabled')?.addEventListener('change', (event) => {
    writeValue('splash_ad_enabled', event.currentTarget.checked);
    document.querySelector('#ad-preview-card')?.classList.toggle('preview-disabled', !event.currentTarget.checked);
    const note = document.querySelector('#preview-hidden-note');
    if (note) note.textContent = event.currentTarget.checked ? '' : 'Promotion hidden while disabled';
  });

  document.querySelector('#field-toast_bar_enabled')?.addEventListener('change', (event) => {
    writeValue('toast_bar_enabled', event.currentTarget.checked);
    document.querySelector('#toast-bar-preview')?.classList.toggle('preview-disabled', !event.currentTarget.checked);
  });

  document.querySelectorAll('[data-publish]').forEach((button) => button.addEventListener('click', confirmPublish));
  document.querySelector('#validate-template')?.addEventListener('click', validateCurrentDraft);
  document.querySelector('#format-json')?.addEventListener('click', formatJsonEditor);
  document.querySelector('#apply-json')?.addEventListener('click', applyJsonEditor);
  document.querySelectorAll('[data-rollback]').forEach((button) => button.addEventListener('click', () => confirmRollback(button.dataset.rollback)));
}

async function createCatalogEntry() {
  try {
    const type = document.querySelector('#catalog-type').value;
    const id = document.querySelector('#catalog-id').value.trim();
    const name = document.querySelector('#catalog-name').value.trim();
    const json = JSON.parse(document.querySelector('#catalog-new-payload').value);
    await writeCatalogEntry({ id, type, name, json, status: 'draft' }, 'created');
    notify('Catalog entry saved as a draft.');
    await loadConsoleData();
  } catch (error) { notify(getErrorMessage(error), 'error'); }
}

async function saveCatalogEntry(id) {
  try {
    const old = state.catalog.find((entry) => entry.id === id);
    if (!old) throw new Error('Catalog entry no longer exists. Refresh and try again.');
    const json = JSON.parse(document.querySelector(`[data-catalog-payload="${CSS.escape(id)}"]`).value);
    const status = document.querySelector(`[data-catalog-status="${CSS.escape(id)}"]`).value;
    const action = status === 'published' && old.status !== 'published' ? 'published' : status === 'archived' && old.status !== 'archived' ? 'archived' : 'updated';
    await writeCatalogEntry({ ...old, json, status }, action);
    notify('Catalog entry updated.');
    await loadConsoleData();
  } catch (error) { notify(getErrorMessage(error), 'error'); }
}

async function removeCatalogEntry(id) {
  if (!confirm('Delete this catalog entry? The app will stop receiving it after the next sync.')) return;
  try {
    const old = state.catalog.find((entry) => entry.id === id);
    if (!old) return;
    const ref = doc(db, 'strategyCatalog', id);
    const historyRef = doc(collection(db, 'strategyCatalogHistory'));
    await runTransaction(db, async (tx) => {
      const current = await tx.get(ref);
      if (!current.exists()) return;
      const data = current.data();
      tx.set(historyRef, catalogHistoryRecord(id, data.type, 'deleted', data.name, data.payload, 'deleted'));
      tx.delete(ref);
    });
    notify('Catalog entry deleted and recorded in the audit trail.');
    await loadConsoleData();
  } catch (error) { notify(getErrorMessage(error), 'error'); }
}

async function importMyCatalog() {
  const button = document.querySelector('#catalog-import');
  setButtonLoading(button, true, 'Importing…');
  try {
    const uid = auth.currentUser.uid;
    const [strategies, specialists] = await Promise.all([
      getDocs(collection(db, 'users', uid, 'aiStrategies')),
      getDocs(collection(db, 'users', uid, 'aiSpecialists')),
    ]);
    const existing = new Set(state.catalog.map((entry) => entry.id));
    let imported = 0;
    for (const [type, snapshot] of [['strategy', strategies], ['specialist', specialists]]) {
      for (const item of snapshot.docs) {
        const data = item.data();
        if (typeof data.payload !== 'string') continue;
        const json = JSON.parse(data.payload);
        const id = `${type}_${String(json.id || item.id).replace(/[^a-zA-Z0-9_-]/g, '_')}`;
        if (existing.has(id)) continue;
        await writeCatalogEntry({ id, type, name: String(json.name || item.id).slice(0, 120), json, status: 'draft' }, 'created');
        existing.add(id);
        imported += 1;
      }
    }
    notify(`Imported ${imported} draft entr${imported === 1 ? 'y' : 'ies'}.`);
    await loadConsoleData();
  } catch (error) { notify(getErrorMessage(error), 'error'); }
  finally { setButtonLoading(button, false); }
}

function catalogHistoryRecord(id, type, action, name, payload, status) {
  return { catalogId: id, type, action, name: String(name).slice(0, 120), payload, status, schemaVersion: 1, recordedAt: serverTimestamp(), recordedBy: auth.currentUser.email };
}

async function writeCatalogEntry({ id, type, name, json, status }, action) {
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(id)) throw new Error('Document ID must use letters, numbers, hyphens, or underscores (up to 120 characters).');
  if (!['strategy', 'specialist'].includes(type) || !['draft', 'published', 'archived'].includes(status)) throw new Error('Choose a valid catalog type and status.');
  if (!json || typeof json !== 'object' || typeof json.id !== 'string' || typeof json.name !== 'string') throw new Error('Payload JSON must include string fields "id" and "name".');
  if (type === 'strategy' && !Array.isArray(json.specialists)) throw new Error('A strategy payload must include a specialists array.');
  if (type === 'specialist' && typeof json.systemPrompt !== 'string') throw new Error('A specialist payload must include systemPrompt.');
  const payload = JSON.stringify(json);
  if (payload.length > 190000) throw new Error('Payload is too large for this catalog entry.');
  const ref = doc(db, 'strategyCatalog', id);
  const historyRef = doc(collection(db, 'strategyCatalogHistory'));
  await runTransaction(db, async (tx) => {
    const current = await tx.get(ref);
    const old = current.exists() ? current.data() : null;
    const now = serverTimestamp();
    tx.set(ref, { type, status, name: String(name || json.name).slice(0, 120), payload, schemaVersion: 1, createdAt: old?.createdAt || now, updatedAt: now, createdBy: old?.createdBy || auth.currentUser.email, updatedBy: auth.currentUser.email });
    tx.set(historyRef, catalogHistoryRecord(id, type, action, name || json.name, payload, status));
  });
}

function updateText(selector, value, fallback) {
  const element = document.querySelector(selector);
  if (element) element.textContent = value || fallback;
}

function updateToastPreviewImage(value) {
  const preview = document.querySelector('#toast-bar-preview');
  if (!preview) return;
  preview.querySelector('img')?.remove();
  if (!value) return;
  const image = document.createElement('img');
  image.id = 'toast-bar-preview-image';
  image.alt = 'Message image';
  image.src = value;
  image.addEventListener('error', () => image.remove(), { once: true });
  preview.prepend(image);
}

function updatePreviewImage(value) {
  const container = document.querySelector('#preview-image');
  if (!container) return;
  if (!value) {
    container.innerHTML = `<div class="image-placeholder">${icon('image', 24)}<span>Your image appears here</span></div>`;
    return;
  }
  container.classList.remove('image-error');
  container.innerHTML = `<img src="${escapeHtml(value)}" alt="Campaign preview"/>`;
  container.querySelector('img').addEventListener('error', () => {
    container.classList.add('image-error');
    container.innerHTML = `<div class="image-placeholder">${icon('image', 24)}<span>Image could not be loaded</span></div>`;
  }, { once: true });
}

function formatJsonEditor() {
  const editor = document.querySelector('#template-json');
  try {
    editor.value = JSON.stringify(JSON.parse(editor.value), null, 2);
    setJsonStatus('JSON formatted', 'good');
  } catch (error) {
    setJsonStatus(error.message, 'bad');
  }
}

function setJsonStatus(message, kind = 'good') {
  const status = document.querySelector('#json-status');
  if (!status) return;
  status.className = `editor-valid ${kind === 'bad' ? 'status-error' : ''}`;
  status.innerHTML = `${icon(kind === 'bad' ? 'close' : 'check', 14)} ${escapeHtml(message)}`;
}

function applyJsonEditor() {
  try {
    const draft = JSON.parse(document.querySelector('#template-json').value);
    validateSettingsTemplate(draft);
    state.template = draft;
    setJsonStatus('Draft applied', 'good');
    updateDirtyState();
    notify('Settings JSON applied to the draft.');
  } catch (error) {
    setJsonStatus(error.message, 'bad');
    notify(error.message, 'error');
  }
}

function validateSettingsTemplate(template) {
  if (!template || typeof template !== 'object' || !template.parameters || typeof template.parameters !== 'object') {
    throw new Error('Settings JSON must contain a parameters object.');
  }
  for (const [key, config] of Object.entries(parameters)) {
    const raw = template.parameters[key]?.defaultValue?.value;
    if (raw === undefined || raw === null) throw new Error(`Missing setting: ${key}`);
    if (config.type === 'NUMBER') {
      const value = Number(raw);
      const bounds = key === 'llm_max_output_tokens' ? [256, 32000] : [30, 300];
      if (!Number.isInteger(value) || value < bounds[0] || value > bounds[1]) {
        throw new Error(`${key} must be a whole number from ${bounds[0]} to ${bounds[1]}.`);
      }
    }
    if (config.type === 'BOOLEAN' && !['true', 'false'].includes(String(raw).toLowerCase())) {
      throw new Error(`${key} must be true or false.`);
    }
    const maxLength = key.endsWith('_url') ? 2048
      : key === 'llm_model' ? 200
        : key === 'splash_ad_campaign_id' || key === 'toast_bar_subject' ? 120
          : key === 'toast_bar_tagline' ? 240 : 60;
    if (typeof raw === 'string' && raw.length > maxLength) {
      throw new Error(`${key} is too long.`);
    }
    if (key === 'llm_model' && !String(raw).trim()) throw new Error('llm_model cannot be empty.');
    if (key.endsWith('_url') && raw) {
      let url;
      try { url = new URL(raw); } catch (_) { throw new Error(`${key} must be a valid HTTPS URL.`); }
      if (url.protocol !== 'https:') throw new Error(`${key} must use HTTPS.`);
    }
  }
  const settings = settingsFromTemplate(template);
  if (settings.toast_bar_enabled) {
    if (!settings.toast_bar_subject.trim()) throw new Error('Enter a subject before enabling the message bar.');
    if (!settings.toast_bar_tagline.trim()) throw new Error('Enter a tagline before enabling the message bar.');
    if (!settings.toast_bar_link_url.trim()) throw new Error('Enter an active link before enabling the message bar.');
  }
}

async function publishSettings(template, description) {
  validateSettingsTemplate(template);
  const historyRef = doc(versionsRef);
  const templateJson = JSON.stringify(template);
  const settings = settingsFromTemplate(template);
  const publishedBy = auth.currentUser?.email || '';
  if (new TextEncoder().encode(templateJson).length > 700000) throw new Error('Settings JSON exceeds the Firestore document size limit.');
  await runTransaction(db, async (transaction) => {
    const current = await transaction.get(settingsRef);
    const versionNumber = (Number(current.data()?.versionNumber) || 0) + 1;
    const version = {
      settings,
      templateJson,
      description: description.slice(0, 256) || 'Settings update',
      versionNumber,
      publishedAt: serverTimestamp(),
      publishedBy,
    };
    transaction.set(settingsRef, version);
    transaction.set(historyRef, version);
  });
}

async function validateCurrentDraft() {
  const button = document.querySelector('#validate-template');
  setButtonLoading(button, true, 'Validating…');
  try {
    validateSettingsTemplate(state.template);
    setButtonLoading(button, false);
    notify('Settings are valid and ready to save.');
  } catch (error) {
    setButtonLoading(button, false);
    notify(getErrorMessage(error), 'error');
  }
}

function confirmPublish() {
  if (!updateDirtyState()) return;
  const description = document.querySelector('#change-description')?.value.trim() || '';
  const dlg = document.createElement('dialog');
  dlg.className = 'confirm-dialog';
  dlg.innerHTML = `<div class="dialog-icon">${icon('cloud', 21)}</div><p class="eyebrow">SAVE APP SETTINGS</p><h2>Make these changes live?</h2><p>Signed-in app users receive settings through Firestore sync. A version snapshot lets you restore it later.</p>${description ? `<div class="dialog-note"><span>CHANGE NOTE</span><strong>${escapeHtml(description)}</strong></div>` : ''}<div class="dialog-actions"><button class="button button-secondary" data-cancel>Cancel</button><button class="button button-primary" data-confirm>Save now ${icon('arrow', 15)}</button></div>`;
  document.body.appendChild(dlg);
  dlg.showModal();
  dlg.querySelector('[data-cancel]').addEventListener('click', () => dlg.close());
  dlg.querySelector('[data-confirm]').addEventListener('click', async () => {
    const button = dlg.querySelector('[data-confirm]');
    setButtonLoading(button, true, 'Publishing…');
    try {
      await publishSettings(state.template, description);
      dlg.close();
      state.notice = null;
      notify('Settings saved to Firestore.');
      await loadConsoleData();
    } catch (error) {
      setButtonLoading(button, false);
      notify(getErrorMessage(error), 'error');
    }
  });
  dlg.addEventListener('close', () => dlg.remove(), { once: true });
}

function confirmRollback(versionNumber) {
  const dlg = document.createElement('dialog');
  dlg.className = 'confirm-dialog';
  dlg.innerHTML = `<div class="dialog-icon warn">${icon('history', 21)}</div><p class="eyebrow">RESTORE VERSION</p><h2>Restore version ${escapeHtml(versionNumber)}?</h2><p>Firebase will publish this saved settings as a new current version. Your current version will remain in history.</p><div class="dialog-actions"><button class="button button-secondary" data-cancel>Keep current</button><button class="button button-primary" data-confirm>Restore version</button></div>`;
  document.body.appendChild(dlg);
  dlg.showModal();
  dlg.querySelector('[data-cancel]').addEventListener('click', () => dlg.close());
  dlg.querySelector('[data-confirm]').addEventListener('click', async (event) => {
    setButtonLoading(event.currentTarget, true, 'Restoring…');
    try {
      const selected = state.versions.find((version) => version.versionNumber === String(versionNumber));
      if (!selected?.templateJson) throw new Error('This version is missing its settings snapshot.');
      await publishSettings(JSON.parse(selected.templateJson), `Restore version ${versionNumber}`);
      dlg.close();
      notify(`Version ${versionNumber} restored as the latest version.`);
      await loadConsoleData();
    } catch (error) {
      setButtonLoading(event.currentTarget, false);
      notify(getErrorMessage(error), 'error');
    }
  });
  dlg.addEventListener('close', () => dlg.remove(), { once: true });
}

async function loadConsoleData() {
  if (!state.user || state.busy) return;
  state.loadError = '';
  const button = document.querySelector('#refresh, #overview-refresh, #history-refresh');
  setButtonLoading(button, true, 'Refreshing…');
  state.busy = true;
  let accessChecked = false;
  try {
    await state.user.reload();
    const freshUser = auth.currentUser;
    if (!freshUser) {
      state.busy = false;
      renderLogin();
      return;
    }
    await freshUser?.getIdToken(true);
    if (!freshUser.emailVerified) {
      renderLogin('Verify the email address on this Firebase account, then sign in again to request admin access.');
      state.busy = false;
      return;
    }
    const roleSnapshot = await getDoc(doc(db, 'adminUsers', freshUser.uid));
    const role = roleSnapshot.exists() ? roleSnapshot.data() : null;
    if (role?.role !== 'admin'
      || role?.uid !== freshUser.uid
      || role?.email !== freshUser.email) {
      state.busy = false;
      renderAdminSetup(freshUser);
      return;
    }
    accessChecked = true;
    const [currentSnapshot, historySnapshot, catalogSnapshot, catalogAuditSnapshot] = await Promise.all([
      getDoc(settingsRef),
      getDocs(query(versionsRef, orderBy('publishedAt', 'desc'), limit(12))),
      getDocs(collection(db, 'strategyCatalog')),
      getDocs(query(collection(db, 'strategyCatalogHistory'), orderBy('recordedAt', 'desc'), limit(30))),
    ]);
    const current = currentSnapshot.exists() ? currentSnapshot.data() : null;
    state.template = templateFromSettings(current?.settings);
    state.template.version = {
      versionNumber: current?.versionNumber || 0,
      updateTime: current?.publishedAt?.toDate?.().toISOString() || null,
      description: current?.description || '',
    };
    state.savedTemplateJson = JSON.stringify(state.template);
    state.versions = historySnapshot.docs.map(versionFromSnapshot);
    state.catalog = catalogSnapshot.docs.map((snapshot) => ({ id: snapshot.id, ...snapshot.data() }));
    state.catalogHistory = catalogAuditSnapshot.docs.map((snapshot) => snapshot.data());
    state.loadError = '';
    state.busy = false;
    state.notice = null;
    renderShell();
  } catch (error) {
    state.busy = false;
    state.template = null;
    if (String(error?.code || '').includes('permission-denied') && !accessChecked) {
      renderLogin('Firestore denied the admin role lookup. Deploy the current Firestore Security Rules, then reload this page.');
      return;
    }
    state.loadError = getErrorMessage(error);
    state.notice = { type: 'error', message: getErrorMessage(error) };
    renderShell();
  }
}

onAuthStateChanged(auth, async (user) => {
  state.user = user;
  if (!user) {
    state.template = null;
    state.loadError = '';
    renderLogin();
    return;
  }
  state.template = null;
  renderShell();
  await loadConsoleData();
});
