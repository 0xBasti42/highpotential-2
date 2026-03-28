<script lang="ts">
    import BrowseHeader from './browse-header/BrowseHeader.svelte';
    import PlayerList from './player-list/PlayerList.svelte';
</script>

<div class="browse">
    <BrowseHeader />
    <PlayerList />
</div>

<style>
	.browse {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		flex: 1;
		min-height: 600px;
		width: 100%;
		background-color: var(--color-surface-elevated);
        padding: 0;
	}
</style>