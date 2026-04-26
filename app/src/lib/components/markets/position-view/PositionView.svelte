<script lang="ts">
	import Balances from './balances/Balances.svelte';
	import Positions from './positions/Positions.svelte';
	import Orders from './orders/Orders.svelte';
	import History from './history/History.svelte';

	const tabs = ['Balances', 'Positions', 'Orders', 'History'] as const;
	type Tab = (typeof tabs)[number];

	let activeTab = $state<Tab>('Balances');
</script>

<div class="position-view">
	<div class="position-view-header">
		{#each tabs as tab}
			<button
				type="button"
				class="menu-button"
				class:active={activeTab === tab}
				aria-pressed={activeTab === tab}
				onclick={() => (activeTab = tab)}
			>
				{tab}
			</button>
			<div class="divider" aria-hidden="true"></div>
		{/each}
		<!-- Extends the bottom border-line to the right of the last tab. -->
		<div class="position-view-header-spacer" aria-hidden="true"></div>
	</div>

	<div class="position-view-body">
		{#if activeTab === 'Balances'}
			<Balances />
		{:else if activeTab === 'Positions'}
			<Positions />
		{:else if activeTab === 'Orders'}
			<Orders />
		{:else if activeTab === 'History'}
			<History />
		{/if}
	</div>
</div>

<style>
	.position-view {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
	}

	.position-view-header {
		flex-shrink: 0;
		height: 35px;
		display: flex;
		flex-direction: row;
		align-items: center;
		justify-content: flex-start;
		background-color: var(--color-surface);
	}

	.position-view-body {
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
	}

	.menu-button {
		all: unset;
		box-sizing: border-box;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0 20px;
		font-size: 12px;
		font-weight: 300;
		letter-spacing: 1px;
		color: var(--color-text-muted);
		border-bottom: 1px solid var(--color-border);
		cursor: pointer;
		transition:
			background-color var(--transition-base),
			border-color var(--transition-base),
			color var(--transition-base);
	}

	.menu-button:not(.active):hover {
		background-color: #20202090;
		color: var(--color-text);
	}

	.menu-button.active {
		border-bottom-color: transparent;
		background-color: var(--color-surface-elevated);
		color: var(--color-text);
	}

	/* Vertical separator placed after each tab. Painted only when adjacent
	   to the active tab so the active tab is visually closed on both sides
	   without relying on conditionally-coloured borders. The permanent
	   `border-bottom` keeps the horizontal line continuous across the
	   divider's column even when its body is transparent. */
	.divider {
		flex-shrink: 0;
		box-sizing: border-box;
		width: 1px;
		height: 100%;
		background-color: transparent;
		border-bottom: 1px solid var(--color-border);
		transition: background-color var(--transition-base);
	}

	.menu-button.active + .divider,
	.divider:has(+ .menu-button.active) {
		background-color: var(--color-border);
	}

	.position-view-header-spacer {
		flex: 1;
		height: 100%;
		border-bottom: 1px solid var(--color-border);
	}
</style>
