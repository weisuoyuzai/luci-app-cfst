'use strict';
'require view';
'require poll';
'require ui';
'require cfst as cfstlib';

function renderTable(results) {
	var rows = (results || []).map(function(r) {
		if (r.raw) {
			return E('tr', {}, [
				E('td', { 'colspan': 6 }, r.line || '')
			]);
		}
		return E('tr', {}, [
			E('td', {}, r.ip || ''),
			E('td', {}, r.sent || ''),
			E('td', {}, r.received || ''),
			E('td', {}, r.loss || ''),
			E('td', {}, r.latency || ''),
			E('td', {}, r.speed || '')
		]);
	});

	if (!rows.length)
		rows.push(E('tr', {}, [
			E('td', { 'colspan': 6 }, _('No results yet. Run a speed test from the Basic Settings tab.'))
		]));

	return E('table', { 'class': 'table cbi-section-table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('IP')),
			E('th', { 'class': 'th' }, _('Sent')),
			E('th', { 'class': 'th' }, _('Received')),
			E('th', { 'class': 'th' }, _('Loss')),
			E('th', { 'class': 'th' }, _('Latency (ms)')),
			E('th', { 'class': 'th' }, _('Speed (MB/s)'))
		])
	].concat(rows));
}

return view.extend({
	load: function() {
		return cfstlib.getResults().catch(function() { return {}; });
	},

	render: function(data) {
		var container = E('div', { 'id': 'cfst-results-container' }, [
			renderTable(data.results)
		]);

		var refresh = function() {
			return cfstlib.getResults().then(function(res) {
				var table = renderTable(res.results);
				container.replaceChild(table, container.firstChild);
			});
		};

		var pollFn = function() {
			return cfstlib.runStatus().then(function(st) {
				if (st && st.running) {
					return refresh();
				}
				poll.remove(pollFn);
				return refresh();
			});
		};
		poll.add(pollFn, 5);

		return E([], [
			E('h2', {}, _('Speedtest Results')),
			E('div', { 'class': 'cbi-section' }, [
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() { return refresh(); })
				}, _('Refresh')),
				E('div', { 'style': 'margin-top:10px' }, [ container ])
			])
		]);
	}
});
