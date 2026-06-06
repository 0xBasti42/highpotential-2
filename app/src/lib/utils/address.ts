/**
 * Format an Ethereum address as a short, human-readable preview using
 * an ellipsis joiner.
 *
 * Example:
 *   truncateAddress('0xA0Cf798816D4b9b9866b5330EEa46a18382f251e')
 *     -> '0xA0Cf…251e'
 *
 * `prefix` and `suffix` count characters including the leading `0x`.
 * If the address is too short to truncate meaningfully (i.e. prefix +
 * suffix + 1 ellipsis already covers the full string), the original is
 * returned unchanged so we never silently drop characters.
 */
export function truncateAddress(addr: string, prefix = 6, suffix = 4): string {
	if (!addr) return '';
	if (addr.length <= prefix + suffix + 1) return addr;
	return `${addr.slice(0, prefix)}…${addr.slice(-suffix)}`;
}

/**
 * Format an Ethereum address as a compact dash-joined ID.
 *
 * Example:
 *   formatAddressId('0xA0Cf798816D4b9b9866b5330EEa46a18382f251e')
 *     -> '0xA0-51e'
 *
 * The dash joiner (vs. ellipsis) gives the result more of an
 * "identifier" feel than a "this is a truncated thing" feel — used
 * inside the header account chip where horizontal real estate is
 * tight and the user just needs a quick visual confirmation of which
 * account they're connected as.
 */
export function formatAddressId(addr: string, prefix = 4, suffix = 3): string {
	if (!addr) return '';
	if (addr.length <= prefix + suffix + 1) return addr;
	return `${addr.slice(0, prefix)}-${addr.slice(-suffix)}`;
}
