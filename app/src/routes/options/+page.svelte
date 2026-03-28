<script lang="ts">
	import type { PageData } from './$types';
	import Vaults from '$lib/components/vaults/Vaults.svelte';

	let { data }: { data: PageData } = $props();
</script>

<Vaults {data} />
