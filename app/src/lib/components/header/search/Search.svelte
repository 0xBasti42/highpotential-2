<script lang="ts">
    import Searchbox from './searchbox/Searchbox.svelte';
</script>

<div class="search">
    <Searchbox />
</div>

<style>
	.search {
        background-color: var(--color-surface-elevated);
		border-bottom: 1px solid var(--color-border);
        height: 60px;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
	}
</style>