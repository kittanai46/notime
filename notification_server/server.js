const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const QRCode = require('qrcode');
const os = require('os');
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

const localIP = getLocalIP();
const PORT = 3000;

// Image proxy cache
const imgDir = path.join(__dirname, 'public', 'img');
if (!fs.existsSync(imgDir)) fs.mkdirSync(imgDir, { recursive: true });

const FETCH_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (compatible; Notime/1.0)',
  'Accept': 'image/*,*/*',
};

// Extract actual image URL from wrappers like reddit.com/media?url=...
function unwrapUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    const embedded = parsed.searchParams.get('url');
    if (embedded) return decodeURIComponent(embedded);
  } catch {}
  return rawUrl;
}

// Pull og:image from an HTML string
function extractOgImage(html) {
  const m = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)
    || html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
  return m ? m[1] : null;
}

async function fetchImageBuffer(url) {
  const res = await fetch(url, { headers: FETCH_HEADERS });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);

  const ct = res.headers.get('content-type') || '';
  if (ct.includes('text/html')) {
    const html = await res.text();
    const ogUrl = extractOgImage(html);
    if (!ogUrl) throw new Error('URL returned HTML with no og:image');
    console.log(`[IMG] og:image found → ${ogUrl}`);
    const imgRes = await fetch(ogUrl, { headers: FETCH_HEADERS });
    if (!imgRes.ok) throw new Error(`og:image HTTP ${imgRes.status}`);
    return Buffer.from(await imgRes.arrayBuffer());
  }

  return Buffer.from(await res.arrayBuffer());
}

async function proxyImageAsJpeg(imageUrl) {
  const resolvedUrl = unwrapUrl(imageUrl);
  if (resolvedUrl !== imageUrl) console.log(`[IMG] Unwrapped → ${resolvedUrl}`);

  const buffer = await fetchImageBuffer(resolvedUrl);
  const filename = `img_${Date.now()}.jpg`;
  await sharp(buffer).jpeg({ quality: 85 }).toFile(path.join(imgDir, filename));

  // Keep only last 50 cached images
  const files = fs.readdirSync(imgDir).filter(f => f.startsWith('img_')).sort();
  if (files.length > 50) {
    files.slice(0, files.length - 50).forEach(f => {
      try { fs.unlinkSync(path.join(imgDir, f)); } catch {}
    });
  }

  return `http://${localIP}:${PORT}/img/${filename}`;
}

// Track connected mobile clients
const mobileClients = new Set();
const notificationHistory = [];

wss.on('connection', (ws) => {
  mobileClients.add(ws);
  console.log(`[+] Mobile connected — Total: ${mobileClients.size}`);

  ws.send(JSON.stringify({ type: 'connected', serverTime: Date.now() }));

  ws.on('close', () => {
    mobileClients.delete(ws);
    console.log(`[-] Mobile disconnected — Total: ${mobileClients.size}`);
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
    mobileClients.delete(ws);
  });
});

// API: QR code SVG for the WebSocket URL
app.get('/qr', async (req, res) => {
  try {
    const svg = await QRCode.toString(`ws://${localIP}:${PORT}`, {
      type: 'svg',
      margin: 2,
      color: { dark: '#6366F1', light: '#1A1D27' },
      width: 220,
    });
    res.setHeader('Content-Type', 'image/svg+xml');
    res.send(svg);
  } catch (err) {
    res.status(500).json({ error: 'QR generation failed' });
  }
});

// API: Server info (IP, port, ws URL)
app.get('/info', (req, res) => {
  res.json({
    ip: localIP,
    port: PORT,
    wsUrl: `ws://${localIP}:${PORT}`,
    connectedDevices: mobileClients.size,
  });
});

// API: Connected device count
app.get('/devices', (req, res) => {
  res.json({ count: mobileClients.size });
});

// API: Notification history
app.get('/history', (req, res) => {
  res.json({ notifications: notificationHistory.slice(-20) });
});

// API: Send notification to all connected mobile clients
app.post('/send', async (req, res) => {
  const { title, body, imageUrl } = req.body;

  if (!title?.trim() || !body?.trim()) {
    return res.status(400).json({ success: false, message: 'Title and body are required' });
  }

  let proxyImageUrl = null;
  if (imageUrl?.trim()) {
    try {
      proxyImageUrl = await proxyImageAsJpeg(imageUrl.trim());
      console.log(`[IMG] Proxied → ${proxyImageUrl}`);
    } catch (err) {
      console.warn(`[IMG] Proxy failed (${err.message}) — sending without image`);
    }
  }

  const notification = {
    type: 'notification',
    id: Date.now(),
    title: title.trim(),
    body: body.trim(),
    imageUrl: proxyImageUrl,
    timestamp: new Date().toISOString(),
  };

  let sent = 0;
  const payload = JSON.stringify(notification);

  mobileClients.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(payload);
      sent++;
    }
  });

  // Save to history
  notificationHistory.push({ ...notification, sent });
  if (notificationHistory.length > 50) notificationHistory.shift();

  console.log(`[SEND] "${title}" → ${sent}/${mobileClients.size} devices`);
  res.json({ success: true, sent, total: mobileClients.size });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('┌─────────────────────────────────────────┐');
  console.log('│       Notime Notification Server         │');
  console.log('├─────────────────────────────────────────┤');
  console.log(`│  Dashboard : http://localhost:${PORT}        │`);
  console.log(`│  Network   : http://${localIP}:${PORT}  │`);
  console.log(`│  WebSocket : ws://${localIP}:${PORT}    │`);
  console.log('└─────────────────────────────────────────┘');
  console.log('');
  console.log('→ Copy WebSocket URL into your Flutter app');
  console.log('');
});
