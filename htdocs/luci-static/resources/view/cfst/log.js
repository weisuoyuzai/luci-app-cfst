'use strict';
'require view';
'require poll';
'require ui';
'require cfst as cfstlib';

return view.extend({
	load: function() {
		return cfstlib.getLog(500).catch(function() { return {}; });
	},

	render: function(data) {
		var pre = E('pre', {
			'id': 'cfst-log-pre',
			'style': 'height:500px;overflow:auto;white-space:pre-wrap;word-break:break-all'
		}, (data.lines || []).join('\n'));

		var scrollToEnd = function() {
			pre.scrollTop = pre.scrollHeight;
		};

		var refresh = function() {
			return cfstlib.getLog(500).then(function(res) {
				pre.textContent = (res.lines || []).join('\n');
				scrollToEnd();
			});
		};

		var clear = function() {
			return cfstlib.clearLog().then(function() {
				return refresh();
			});
		};

		var pollFn = function() {
			return refresh();
		};
		poll.add(pollFn, 5);

		setTimeout(scrollToEnd, 0);

		return E([], [
			E('h2', {}, _('Log')),
			E('div', { 'class': 'cbi-section' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() { return refresh(); })
				}, _('Refresh')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': ui.createHandlerFn(this, function() { return clear(); })
				}, _('Clear Log')),
				E('div', { 'style': 'margin-top:10px' }, [ pre ])
			])
		]);
	}
});
