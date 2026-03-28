<script lang="ts">
	interface Props {
		data: { section: 'vaults' };
	}

	let { data }: Props = $props();
</script>

<svelte:head>
	<title>Vaults · HighPotential</title>
</svelte:head>

<div class="vaults" data-section={data.section}>
	<!-- Vaults content -->
</div>

<style>
	.vaults {
		flex: 1;
		min-height: 200px;
	}
</style>
