import ccxt from 'ccxt';

async function test() {
  try {
    const exchange = new ccxt.pro.bitget();
    await exchange.loadMarkets();
    console.log('Markets loaded');
    const ob = await exchange.watchOrderBook('BTC/USDT:USDT');
    console.log('Orderbook received');
  } catch (e) {
    console.error('Error:', e.message);
  }
  process.exit(0);
}

test();
