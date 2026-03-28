<script lang="ts">
	import PrimaryHeaderBar from './PrimaryHeaderBar.svelte';
	import RollingText from './rolling-text/RollingText.svelte';
	import Search from './search/Search.svelte';
</script>

<div class="header">
	<RollingText />
	<PrimaryHeaderBar />
	<Search />
</div>

<style>
	.header {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		height: auto;
		width: 100%;
	}
</style>