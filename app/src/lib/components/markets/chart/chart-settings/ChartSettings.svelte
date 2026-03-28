<script lang="ts">
	const timeframes = [
		{ label: '5m', value: '5m' },
		{ label: '15m', value: '15m' },
		{ label: '1H', value: '1H' },
		{ label: '12H', value: '12H' }
	];
</script>

<div class="chart-settings">
	<div class="timeframe-container">
		{#each timeframes as timeframe}
			<div class="timeframe">
				<p>{timeframe.label}</p>
			</div>
		{/each}
		<div class="more-timeframes">
			<i class="fa-solid fa-chevron-down"></i>
		</div>
	</div>

	<div class="chart-type-container">
		<img src="/icons/candles.svg" alt="Candlestick chart" class="chart-type-icon" />
	</div>

	<div class="indicator-container">
		<p>ƒ×</p>
		<p>Indicators</p>
	</div>
</div>

<style>
	.chart-settings {
		height: 60px;
		width: 100%;
		background-color: var(--color-surface-muted);
		display: flex;
		align-items: center;
		justify-content: flex-start;
	}

	.timeframe-container,
	.chart-type-container,
	.indicator-container {
		height: 60%;
		display: flex;
		align-items: center;
		border-right: 1px solid var(--color-border);
	}

	.timeframe-container {
		justify-content: flex-start;
		gap: 10px;
		padding: 0 20px;
	}

	.chart-type-container {
		justify-content: center;
		padding: 0 10px;
	}

	.indicator-container {
		justify-content: center;
		gap: 8px;
		padding: 0 20px;
	}

	.timeframe {
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0 5px;
		cursor: pointer;
	}

	.timeframe:hover p {
		color: var(--color-text);
	}

	.timeframe:active {
		background-color: var(--color-surface-elevated);
	}

	.more-timeframes {
		display: flex;
		align-items: center;
		justify-content: center;
		margin-left: 10px;
		cursor: pointer;
	}

	.more-timeframes i {
		margin-bottom: 2px;
		font-size: 12px;
		color: #565656;
		transition:
			color var(--transition-base),
			opacity var(--transition-base),
			transform var(--transition-base);
	}

	.more-timeframes:hover i {
		color: var(--color-text-muted);
		transform: rotate(180deg);
	}

	.more-timeframes:active i {
		opacity: 0.7;
	}

	.chart-type-icon {
		width: 20px;
		height: 20px;
	}

	.indicator-container p:first-child {
		font-size: 18px;
		color: var(--color-text-muted);
	}
</style>
