<script lang="ts">
    const year = new Date().getFullYear();
</script>

<div class="tag">
    <p>© {year}, Isla Labs</p>
</div>

<style>
    .tag {
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .tag p {
        font-size: 10px;
        color: var(--color-text-muted);
    }
</style>