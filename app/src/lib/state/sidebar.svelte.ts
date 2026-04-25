/**
 * Shared open/close state for the left-hand sidebar menu.
 *
 * Lives outside any component so the trigger (Logo, in the header) and the
 * panel itself (mounted at the layout root) can share a single source of truth
 * without prop drilling.
 */

let _isOpen = $state(false);

export const sidebar = {
	get isOpen() {
		return _isOpen;
	},
	open() {
		_isOpen = true;
	},
	close() {
		_isOpen = false;
	},
	toggle() {
		_isOpen = !_isOpen;
	}
};
