import WebSocket from 'ws';

const ws = new WebSocket('wss://ws.bitget.com/v2/ws/public', {
  headers: {
    Origin: 'http://weird-origin.com'
  }
});

ws.on('open', () => {
  console.log('Connected');
  ws.close();
});

ws.on('error', (err) => {
  console.error('Error:', err.message);
});

ws.on('unexpected-response', (req, res) => {
  console.log('Unexpected response:', res.statusCode, res.statusMessage);
  res.on('data', (chunk) => {
    console.log('Body:', chunk.toString());
  });
});
