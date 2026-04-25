<script lang="ts">
	import { sidebar } from '$lib/state/sidebar.svelte';
</script>

<button
	type="button"
	class="logo"
	aria-label="Open menu"
	aria-expanded={sidebar.isOpen}
	aria-controls="app-sidebar"
	onclick={() => sidebar.toggle()}
>
	<img src="/brand/icon-dark.svg" alt="Logo" />
</button>

<style>
	.logo {
		all: unset;
		position: relative;
		width: auto;
		height: 25px;
		display: flex;
		align-items: center;
		justify-content: flex-start;
		gap: 10px;
		box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
		cursor: pointer;
	}

	.logo::before {
		content: '';
		position: absolute;
		left: -8px;
		top: 50%;
		width: 2px;
		height: 12px;
		background-color: var(--color-border-strong);
		border-radius: 1px;
		opacity: 0;
		transform: translate(-2px, -50%);
		transition:
			opacity var(--transition-base),
			transform var(--transition-base);
		pointer-events: none;
		opacity: 0;
	}

	.logo:hover::before {
		opacity: 0;
		transform: translate(0, -50%);
	}

	.logo img {
		width: 25px;
		height: 25px;
		border-radius: 5px;
		border: 1px solid var(--color-border);
		transition: all var(--transition-base);
	}

	.logo:hover img {
		border: 1px solid var(--color-border-strong);
		transform: translateX(3px);
	}

	.logo:active img {
		opacity: 0.7;
	}
</style>
