<script lang="ts">
	import Trade from './trade/Trade.svelte';
	import Stake from './stake/Stake.svelte';

	let tradeActive = true;
</script>

<div class="interact">
	{#if tradeActive}
		<Trade />
	{:else}
		<Stake />
	{/if}
</div>

<style>
	.interact {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: flex-start;
		flex: 1;
		height: auto;
		padding: 0;
	}
</style>
