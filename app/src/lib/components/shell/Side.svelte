<script lang="ts">
	import Interact from './interact/Interact.svelte';
	import Browse from './browse/Browse.svelte';
</script>

<div class="side">
	<Interact />
	<Browse />
</div>

<style>
	.side {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		justify-content: flex-start;
		flex: 0.33;
		height: 896px;
		background-color: var(--color-surface-elevated);
	}
</style>
