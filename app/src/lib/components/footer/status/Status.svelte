<script lang="ts">
    let status = $state('Operational');
</script>

<div class="status">
    <div class="status-icon"></div>
    <div class="status-text">
        <p>{status}</p>
    </div>
</div>

<style>
    .status {
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .status-icon {
        width: 5px;
        height: 5px;
        background: linear-gradient(to right, var(--color-primary-light), var(--color-primary));
        border-radius: 1px;
    }
    
    .status-text p {
        font-size: 10px;
        color: var(--color-text-muted);
    }
</style>