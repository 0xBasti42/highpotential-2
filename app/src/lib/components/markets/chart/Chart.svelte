<script lang="ts">
	import TokenInfo from './token-info/TokenInfo.svelte';
	import ChartSettings from './chart-settings/ChartSettings.svelte';
	import ChartTools from './chart-tools/ChartTools.svelte';
	import PriceChart from './price-chart/PriceChart.svelte';
	import Indicators from './indicators/Indicators.svelte';
</script>

<div class="chart">
	<TokenInfo />
	<ChartSettings />
	<div class="chart-container">
		<div class="chart-tools-container">
			<ChartTools />
		</div>
		<div class="price-chart-container">
			<PriceChart />
			<Indicators />
		</div>
	</div>
</div>

<style>
	.chart {
		border-bottom: 1px solid var(--color-border);
		height: auto;
        width: 100%;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
	}

	.chart-container {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		width: 100%;
	}

	.chart-tools-container {
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-start;
		width: 5%;
		height: 100%;
		background-color: var(--color-surface-muted);
	}

	.price-chart-container {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		width: 95%;
		height: 100%;
	}
</style>
