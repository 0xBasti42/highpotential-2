<script lang="ts">
	import Status from './status/Status.svelte';
	import Tag from './tag/Tag.svelte';
</script>

<footer class="footer">
	<Status />
	<Tag />
</footer>

<style>
	.footer {
		width: 100%;
		min-height: 30px;
		border-top: 1px solid var(--color-border);
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 20px;
	}
</style>
