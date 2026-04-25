<script lang="ts">
	import Chart from './chart/Chart.svelte';
	import PositionView from './position-view/PositionView.svelte';

	interface Props {
		data: { section: 'markets' };
	}

	let { data }: Props = $props();
</script>

<svelte:head>
	<title>EPL | dRICE-GBP</title>
</svelte:head>

<div class="markets" data-section={data.section}>
	<Chart />
	<PositionView />
</div>

<style>
	.markets {
		flex: 1;
		min-height: 200px;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}
</style>
