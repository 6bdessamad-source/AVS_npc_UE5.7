'use strict';
const form = document.getElementById('connect-form');
const input = document.getElementById('server');
const stage = document.getElementById('stage');
const placeholder = document.getElementById('placeholder');
const status = document.getElementById('status');
const message = document.getElementById('message');
const disconnect = document.getElementById('disconnect');
const fullscreen = document.getElementById('fullscreen');
const direct = document.getElementById('direct');
let frame = null;
let slowTimer = null;

function playerUrl(value) {
  const url = new URL(value.trim());
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new Error('Use an HTTP or HTTPS player address without a username or password.');
  }
  if (!url.pathname.endsWith('.html')) url.pathname = url.pathname.replace(/\/$/, '') + '/player.html';
  // The rig serves Epic's own player, which derives ws/wss from its origin.
  url.searchParams.delete('ss');
  url.searchParams.set('AutoConnect', 'true');
  url.searchParams.set('AutoPlayVideo', 'true');
  for (const setting of ['KeyboardInput', 'MouseInput', 'TouchInput', 'GamepadInput', 'FakeMouseWithTouches']) {
    url.searchParams.set(setting, 'true');
  }
  url.hash = '';
  return url;
}
function resetPlayer() {
  clearTimeout(slowTimer);
  if (frame) { frame.remove(); frame = null; }
  placeholder.hidden = false;
  disconnect.disabled = true;
  fullscreen.disabled = true;
  direct.hidden = true;
  document.body.classList.remove('player-open');
}
function connect() {
  resetPlayer();
  try {
    const url = playerUrl(input.value);
    try { localStorage.setItem('avs-player-server', input.value.trim()); } catch (_) {}
    const shareUrl = new URL(location.href);
    shareUrl.searchParams.set('server', input.value.trim());
    try { history.replaceState(null, '', shareUrl); } catch (_) {}
    direct.href = url.href;
    direct.hidden = false;
    if (location.protocol === 'https:' && url.protocol === 'http:') {
      status.textContent = 'Local player available';
      message.textContent = 'This is a local HTTP address. Click “Open in tab” above the viewer to play on your LAN or VPN.';
      // A deliberate click on the direct link avoids popup blockers and browser
      // mixed-content restrictions. Do not embed an HTTP iframe in HTTPS.
      return;
    }
    status.textContent = 'Opening player…';
    message.textContent = 'Loading the rig’s player. Allow playback when prompted.';
    frame = document.createElement('iframe');
    frame.title = 'AVS Unreal Engine player';
    frame.allow = 'autoplay; fullscreen; gamepad; clipboard-write';
    frame.allowFullscreen = true;
    frame.referrerPolicy = 'no-referrer';
    const activeFrame = frame;
    frame.addEventListener('load', () => {
      if (frame !== activeFrame) return;
      clearTimeout(slowTimer);
      status.textContent = 'Player opened';
      message.textContent = 'Use the player to connect and start video. If it is blank or asks you to sign in, choose “Open in tab”.';
      // An iframe load is NOT evidence of a live WebRTC stream. The official
      // cross-origin player reports actual stream status inside its own UI.
    });
    frame.src = url.href;
    placeholder.hidden = true;
    stage.appendChild(frame);
    disconnect.disabled = false;
    fullscreen.disabled = false;
    document.body.classList.add('player-open');
    slowTimer = setTimeout(() => {
      message.textContent = 'Still waiting for the player. Check that the rig and tunnel are running, or choose “Open in tab”.';
    }, 15000);
  } catch (error) {
    status.textContent = 'Check the address';
    message.textContent = error.message || 'Enter a valid player address.';
  }
}
form.addEventListener('submit', event => { event.preventDefault(); connect(); });
disconnect.addEventListener('click', () => {
  resetPlayer();
  status.textContent = 'Disconnected';
  message.textContent = 'The game keeps running on your rig. Reconnect whenever you are ready.';
});
fullscreen.addEventListener('click', async () => {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.querySelector('.viewer').requestFullscreen();
  } catch (_) { message.textContent = 'Fullscreen is unavailable here. Use “Open in tab” and the player’s fullscreen button.'; }
});
let initial = new URLSearchParams(location.search).get('server');
if (!initial) { try { initial = localStorage.getItem('avs-player-server'); } catch (_) {} }
if (initial) { input.value = initial; connect(); }
