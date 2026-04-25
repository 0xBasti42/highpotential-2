<script lang="ts">
	import { browser } from '$app/environment';
	import { tick } from 'svelte';

	const tabs = ['Balances', 'Positions', 'Orders', 'History'] as const;
	type Tab = (typeof tabs)[number];

	let activeTab = $state<Tab>('Balances');

	let headerEl = $state<HTMLDivElement | undefined>();
	let indicatorLeft = $state(0);
	let indicatorWidth = $state(0);

	function syncIndicator() {
		if (!browser || !headerEl) return;
		const active = headerEl.querySelector<HTMLElement>('button.active');
		if (!active) {
			indicatorWidth = 0;
			return;
		}
		const c = headerEl.getBoundingClientRect();
		const a = active.getBoundingClientRect();
		indicatorLeft = a.left - c.left;
		indicatorWidth = a.width;
	}

	$effect(() => {
		activeTab;
		headerEl;
		if (!browser || !headerEl) return;
		tick().then(syncIndicator);
	});

	$effect(() => {
		if (!browser || !headerEl) return;
		const ro = new ResizeObserver(() => syncIndicator());
		ro.observe(headerEl);
		tick().then(syncIndicator);
		return () => ro.disconnect();
	});
</script>

<div class="position-view">
	<div class="position-view-header" bind:this={headerEl}>
		{#each tabs as tab}
			<button
				type="button"
				class="menu-button"
				class:active={activeTab === tab}
				onclick={() => (activeTab = tab)}
			>
				{tab}
			</button>
		{/each}
		<!-- Animated underline; position/width follow the active tab -->
		<div
			class="tab-indicator"
			class:tab-indicator--hidden={indicatorWidth <= 0}
			style:left="{indicatorLeft}px"
			style:width="{indicatorWidth}px"
			aria-hidden="true"
		></div>
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
		position: relative;
		height: 35px;
		display: flex;
		align-items: center;
		justify-content: flex-start;
		padding: 0 20px;
		border-bottom: 1px solid var(--color-border-light);
		gap: 30px;
	}

	.menu-button {
		all: unset;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 5px;
		font-size: 12px;
		font-weight: 300;
		letter-spacing: 1px;
		color: var(--color-text-muted);
		transition: all var(--transition-base);
		cursor: pointer;
	}

	.menu-button:hover {
		color: var(--color-text);
	}

	.menu-button:active {
		opacity: 0.8;
	}

	.menu-button.active {
		color: var(--color-text);
	}

	.tab-indicator {
		position: absolute;
		bottom: -1px;
		left: 0;
		height: 1px;
		border-radius: 1px;
		background: radial-gradient(circle at 50% 35%, var(--color-primary) 0%, var(--color-primary-light) 65%);
		transition:
			left 0.32s cubic-bezier(0.22, 1, 0.36, 1),
			width 0.32s cubic-bezier(0.22, 1, 0.36, 1),
			opacity 0.2s ease;
		pointer-events: none;
		will-change: left, width;
	}

	.tab-indicator--hidden {
		opacity: 0;
	}
</style>
