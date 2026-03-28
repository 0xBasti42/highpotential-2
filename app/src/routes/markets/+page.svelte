<script lang="ts">
	import type { PageData } from './$types';
	import Markets from '$lib/components/markets/Markets.svelte';

	let { data }: { data: PageData } = $props();
</script>

<Markets {data} />
