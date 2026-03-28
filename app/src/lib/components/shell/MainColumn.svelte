<script lang="ts">
	let { children } = $props();
</script>

<div class="main">
	{@render children?.()}
</div>

<style>
	.main {
		display: flex;
		flex-direction: column;
		flex: 1;
		height: 1224px;
		width: 64%;
		border-right: 1px solid var(--color-border);
	}
</style>
