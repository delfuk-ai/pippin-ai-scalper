import express from "express";
import { createServer as createViteServer } from "vite";
import path from "path";
import { fileURLToPath } from "url";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import { initEngine } from "./server/engine.js";
import dotenv from "dotenv";
import ccxt from "ccxt";
import { createProxyMiddleware } from "http-proxy-middleware";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function startServer() {
  const app = express();
  const PORT = 3000;

  const server = createServer(app);
  app.use(express.json());
  
  // Bitget WebSocket Proxy
  const bitgetWsProxy = createProxyMiddleware({
    target: "wss://ws.bitget.com",
    changeOrigin: true,
    ws: true,
    pathRewrite: {
      "^/bitget-ws": "/v2/ws/public",
    },
    on: {
      proxyReqWs: (proxyReq, req, socket, options, head) => {
        console.log('proxyReqWs called, removing Origin header');
        proxyReq.removeHeader('Origin');
      }
    }
  });
  app.use("/bitget-ws", bitgetWsProxy);

  // Specify a path for our WebSocket server to avoid conflicts with Vite's HMR
  const wss = new WebSocketServer({ 
    noServer: true,
    verifyClient: () => true // Allow all origins
  });
  
  server.on('upgrade', (request, socket, head) => {
    const origin = request.headers.origin;
    console.log(`Upgrade request for ${request.url} from origin: ${origin}`);

    if (request.url?.startsWith('/bitget-ws')) {
      // Set origin for Bitget proxy to avoid "Origin not allowed" from Bitget
      request.headers.origin = 'https://www.bitget.com';
      request.headers['sec-websocket-origin'] = 'https://www.bitget.com';
      // @ts-ignore
      bitgetWsProxy.upgrade(request, socket, head);
    } else if (request.url?.startsWith('/ws')) {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    }
  });

  // API routes FIRST
  app.get("/api/health", (req, res) => {
    res.json({ status: "ok" });
  });

  // API Route: Get Balance
  app.post("/api/balance", async (req, res) => {
    try {
      const { apiKey, secret, password, paperTrading } = req.body;
      if (paperTrading) {
        return res.json({ balance: 10000.00 }); // Simulated 10k USDT for paper trading
      }
      if (!apiKey || !secret) {
        return res.json({ balance: 0 });
      }
      const exchange = new ccxt.bitget({
        apiKey,
        secret,
        password,
        options: { defaultType: 'swap' },
        enableRateLimit: true,
      });
      const balance = await exchange.fetchBalance();
      res.json({ balance: balance.USDT?.total || 0 });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // API Route: Get Price
  app.post("/api/price", async (req, res) => {
    try {
      const { symbol } = req.body;
      const exchange = new ccxt.bitget({ options: { defaultType: 'swap' } });
      const ticker = await exchange.fetchTicker(symbol);
      res.json({ 
        price: ticker.last, 
        bid: ticker.bid, 
        ask: ticker.ask,
        change24h: ticker.percentage,
        timestamp: ticker.timestamp
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // API Route: Get Positions
  app.post("/api/positions", async (req, res) => {
    try {
      const { apiKey, secret, password, symbol } = req.body;
      if (!apiKey || !secret || !password) {
        return res.json([]); // Return empty if no creds
      }
      const exchange = new ccxt.bitget({
        apiKey,
        secret,
        password,
        options: { defaultType: 'swap' }
      });
      const positions = await exchange.fetchPositions([symbol]);
      res.json(positions);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // API Route: Execute Trade
  app.post("/api/trade", async (req, res) => {
    try {
      const { apiKey, secret, password, symbol, side, amount, type, price, paperTrading, leverage, reduceOnly, positionSide } = req.body;

      if (paperTrading) {
        // Simulate trade execution
        const exchange = new ccxt.bitget({ options: { defaultType: 'swap' } });
        const ticker = await exchange.fetchTicker(symbol);
        const execPrice = side === 'buy' ? ticker.ask : ticker.bid;
        
        return res.json({
          id: 'sim_' + Date.now(),
          symbol,
          side,
          amount,
          price: execPrice,
          status: 'closed',
          simulated: true,
          timestamp: Date.now()
        });
      }

      // Real trade execution
      const exchange = new ccxt.bitget({
        apiKey,
        secret,
        password,
        options: { 
          defaultType: 'swap'
        },
        enableRateLimit: true,
      });

      await exchange.loadMarkets();

      if (leverage) {
        try {
          await exchange.setLeverage(leverage, symbol);
        } catch (e: any) {
          console.log('Leverage set error (might already be set):', e.message);
        }
      }

      const params: any = {};
      if (reduceOnly) {
        params.reduceOnly = true;
      }

      // Format amount to exchange precision
      const formattedAmount = exchange.amountToPrecision(symbol, amount);

      let order;
      try {
        // Try Hedge Mode first
        const hedgeParams = { ...params, hedged: true };
        order = await exchange.createOrder(symbol, type, side, parseFloat(formattedAmount), price ? parseFloat(price) : undefined, hedgeParams);
      } catch (e: any) {
        if (e.message.includes('40774') || e.message.includes('unilateral') || e.message.includes('position mode')) {
          console.log('Hedge mode failed, retrying with One-way mode...');
          // Retry with One-way Mode
          const oneWayParams = { ...params, hedged: false };
          order = await exchange.createOrder(symbol, type, side, parseFloat(formattedAmount), price ? parseFloat(price) : undefined, oneWayParams);
        } else {
          throw e;
        }
      }
      
      res.json(order);
    } catch (error: any) {
      console.error('Trade Error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  // Initialize the trading engine
  const engine = await initEngine(wss);

  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), "dist");
    app.use(express.static(distPath));
    app.get("*", (req, res) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }

  server.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
