import type { CandlestickData, UTCTimestamp } from 'lightweight-charts';

// Seeded pseudo-random number generator (mulberry32) so the mock chart
// renders the same candles on every page load. Keeps styling iteration stable.
function createPrng(seed: number): () => number {
	let state = seed >>> 0;
	return () => {
		state = (state + 0x6d2b79f5) >>> 0;
		let t = state;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

const CANDLE_COUNT = 180;
const HOUR_SECONDS = 60 * 60;

function generateCandles(): CandlestickData<UTCTimestamp>[] {
	const rand = createPrng(0xc0ffee);

	// Anchor the series so the latest candle lands on the most recent whole hour.
	const nowSeconds = Math.floor(Date.now() / 1000);
	const latestHour = nowSeconds - (nowSeconds % HOUR_SECONDS);
	const firstHour = latestHour - (CANDLE_COUNT - 1) * HOUR_SECONDS;

	const candles: CandlestickData<UTCTimestamp>[] = [];

	// Random walk around ~1 GBP with mean reversion so prices don't drift off-screen.
	let price = 1;
	const meanPrice = 1;
	const meanReversion = 0.02;
	const volatility = 0.012;

	for (let i = 0; i < CANDLE_COUNT; i++) {
		const time = (firstHour + i * HOUR_SECONDS) as UTCTimestamp;

		const drift = (meanPrice - price) * meanReversion;
		const shock = (rand() - 0.5) * 2 * volatility;
		const open = price;
		const close = Math.max(0.05, open * (1 + drift + shock));

		const intrabarRange = Math.abs(close - open) + open * volatility * (0.4 + rand() * 0.8);
		const high = Math.max(open, close) + intrabarRange * rand() * 0.6;
		const low = Math.min(open, close) - intrabarRange * rand() * 0.6;

		candles.push({
			time,
			open: round(open),
			high: round(high),
			low: round(Math.max(0.01, low)),
			close: round(close)
		});

		price = close;
	}

	return candles;
}

function round(value: number): number {
	return Math.round(value * 10_000) / 10_000;
}

export const mockCandleData: CandlestickData<UTCTimestamp>[] = generateCandles();
