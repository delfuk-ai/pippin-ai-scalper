import ccxt from 'ccxt';

async function test() {
  try {
    const exchange = new ccxt.bitget({
      apiKey: 'bad_key',
      secret: 'bad_secret',
      password: 'bad_password',
      options: { defaultType: 'swap' }
    });
    await exchange.fetchBalance();
  } catch (e) {
    console.error('Error:', e.message);
  }
  process.exit(0);
}

test();
