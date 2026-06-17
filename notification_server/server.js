const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const QRCode = require('qrcode');
const os = require('os');
const path = require('path');

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
app.post('/send', (req, res) => {
  const { title, body, imageUrl } = req.body;

  if (!title?.trim() || !body?.trim()) {
    return res.status(400).json({ success: false, message: 'Title and body are required' });
  }

  const notification = {
    type: 'notification',
    id: Date.now(),
    title: title.trim(),
    body: body.trim(),
    imageUrl: imageUrl?.trim() || null,
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
