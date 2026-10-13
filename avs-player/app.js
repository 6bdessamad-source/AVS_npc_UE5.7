'use strict';
const form = document.getElementById('connect-form');
const input = document.getElementById('server');
const connectButton = document.getElementById('connect-button');
const stage = document.getElementById('stage');
const viewer = document.getElementById('viewer');
const placeholder = document.getElementById('placeholder');
const status = document.getElementById('status');
const session = document.getElementById('session-state');
const message = document.getElementById('message');
const disconnect = document.getElementById('disconnect');
const fullscreen = document.getElementById('fullscreen');
const direct = document.getElementById('direct');
let frame = null;
let slowTimer = null;
let immersiveScroll = 0;
let activeDialog = null;
let dialogFocus = null;

function setStatus(text, state = 'idle') { status.textContent = text; session.dataset.state = state; }
function setMessage(text, error = false) { message.textContent = text; message.dataset.kind = error ? 'error' : 'info'; }
function playerUrl(value) {
  if (!value.trim()) throw new Error('Paste the streaming link from your launcher first.');
  let url;
  try { url = new URL(value.trim()); } catch (_) { throw new Error('Use the complete link beginning with https:// or http://.'); }
  // Accept the launcher’s complete laptop link as well as its raw main-computer address.
  if ((url.origin === location.origin || url.hostname.endsWith('.github.io')) && url.searchParams.has('server')) {
    try { url = new URL(url.searchParams.get('server')); } catch (_) { throw new Error('This shared link contains an invalid player address.'); }
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new Error('Use an HTTP or HTTPS streaming link without a username or password.');
  }
  if (!url.pathname.endsWith('.html')) url.pathname = url.pathname.replace(/\/$/, '') + '/player.html';
  url.searchParams.delete('ss');
  for (const setting of ['AutoConnect', 'AutoPlayVideo', 'KeyboardInput', 'MouseInput', 'TouchInput', 'GamepadInput', 'FakeMouseWithTouches']) {
    url.searchParams.set(setting, 'true');
  }
  url.hash = '';
  return url;
}
function exitImmersive() {
  if (document.body.classList.contains('immersive')) {
    document.body.classList.remove('immersive');
    window.scrollTo(0, immersiveScroll);
  }
  fullscreen.setAttribute('aria-label', 'Open fullscreen');
  fullscreen.title = 'Fullscreen';
  fullscreen.dataset.expanded = 'false';
}
function resetPlayer() {
  clearTimeout(slowTimer);
  if (frame) { frame.remove(); frame = null; }
  if (document.fullscreenElement && document.exitFullscreen) document.exitFullscreen().catch(() => {});
  exitImmersive();
  placeholder.hidden = false;
  disconnect.disabled = true;
  fullscreen.disabled = true;
  direct.hidden = true;
  document.body.classList.remove('player-open');
}
function connect(userGesture = false) {
  let url;
  try { url = playerUrl(input.value); } catch (error) {
    input.setAttribute('aria-invalid', 'true');
    setStatus('Check your link', 'error');
    setMessage(error.message, true);
    input.focus();
    return;
  }
  resetPlayer();
  input.removeAttribute('aria-invalid');
  try { localStorage.setItem('avs-player-server', input.value.trim()); } catch (_) {}
  const share = new URL(location.href);
  share.searchParams.set('server', input.value.trim());
  try { history.replaceState(null, '', share); } catch (_) {}
  direct.href = url.href;
  direct.hidden = false;
  if (location.protocol === 'https:' && url.protocol === 'http:') {
    setStatus('Local player ready');
    setMessage('Local links open in a separate tab. Use “Open in tab” if your browser blocks the new tab.');
    if (userGesture) window.open(url.href, '_blank', 'noopener,noreferrer');
    return;
  }
  setStatus('Opening player', 'opening');
  setMessage('Autorisez la lecture dans le lecteur. Votre Ordinateur principal peut encore charger le projet.');
  frame = document.createElement('iframe');
  frame.title = 'AMV Explore interactive player';
  frame.allow = 'autoplay; fullscreen; gamepad; clipboard-write';
  frame.allowFullscreen = true;
  frame.referrerPolicy = 'no-referrer';
  const currentFrame = frame;
  frame.addEventListener('load', () => {
    if (frame !== currentFrame) return;
    clearTimeout(slowTimer);
    // Loading a cross-origin iframe does not confirm a live game/video stream.
    setStatus('Player opened', 'opened');
    setMessage('Tap or click inside the player to begin. For a blank or sign-in screen, use “Open in tab”.');
  });
  frame.src = url.href;
  placeholder.hidden = true;
  stage.appendChild(frame);
  disconnect.disabled = false;
  fullscreen.disabled = false;
  document.body.classList.add('player-open');
  if (window.matchMedia('(max-width: 600px)').matches && typeof viewer.scrollIntoView === 'function') {
    viewer.scrollIntoView({block: 'start', behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
  }
  slowTimer = setTimeout(() => {
    setMessage('Vérifiez que votre Ordinateur principal fonctionne et que le lien est actuel, ou choisissez « Open in tab ».');
  }, 15000);
}
form.addEventListener('submit', event => { event.preventDefault(); connect(true); });
input.addEventListener('input', () => { input.removeAttribute('aria-invalid'); message.dataset.kind = 'info'; });
disconnect.addEventListener('click', () => {
  resetPlayer(); setStatus('Disconnected');
  setMessage('Le projet reste ouvert sur votre Ordinateur principal. Reconnectez-vous quand vous le souhaitez.');
});
fullscreen.addEventListener('click', async () => {
  if (document.body.classList.contains('immersive')) { exitImmersive(); return; }
  if (document.fullscreenElement) { try { await document.exitFullscreen(); } catch (_) { exitImmersive(); } return; }
  try {
    if (!viewer.requestFullscreen) throw new Error('Native fullscreen unavailable');
    await viewer.requestFullscreen();
  } catch (_) {
    // Mobile Safari and embedded browsers can use an in-page fullscreen view.
    immersiveScroll = window.scrollY;
    document.body.classList.add('immersive');
  }
  fullscreen.setAttribute('aria-label', 'Exit fullscreen'); fullscreen.title = 'Exit fullscreen'; fullscreen.dataset.expanded = 'true';
});
document.addEventListener('fullscreenchange', () => { if (!document.fullscreenElement) exitImmersive(); });

function closeDialog() {
  if (!activeDialog) return;
  const dialog = activeDialog; activeDialog = null;
  if (typeof dialog.close === 'function') dialog.close(); else dialog.removeAttribute('open');
  dialog.classList.remove('fallback-open');
  if (dialogFocus && typeof dialogFocus.focus === 'function') dialogFocus.focus();
}
function openDialog(id, opener) {
  closeDialog();
  activeDialog = document.getElementById(id); dialogFocus = opener;
  if (typeof activeDialog.showModal === 'function') activeDialog.showModal();
  else { activeDialog.setAttribute('open', ''); activeDialog.classList.add('fallback-open'); }
  const first = activeDialog.querySelector('button'); if (first) first.focus();
}
for (const name of ['help', 'controls']) {
  const open = document.getElementById(name + '-open');
  open.addEventListener('click', () => openDialog(name + '-dialog', open));
  document.getElementById(name + '-close').addEventListener('click', closeDialog);
  const dialog = document.getElementById(name + '-dialog');
  dialog.addEventListener('cancel', event => { event.preventDefault(); closeDialog(); });
  dialog.addEventListener('click', event => {
    const r = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom)) closeDialog();
  });
}
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') { if (activeDialog) closeDialog(); else exitImmersive(); }
  if (event.key === 'Tab' && activeDialog && activeDialog.classList.contains('fallback-open')) {
    const focusable = [...activeDialog.querySelectorAll('button,a[href],input,summary')].filter(el => !el.disabled && !el.hidden);
    const first = focusable[0], last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }
});
let initial = new URLSearchParams(location.search).get('server');
if (!initial) { try { initial = localStorage.getItem('avs-player-server'); } catch (_) {} }
if (initial) { input.value = initial; connect(false); }
