'use strict';
'require baseclass';
'require rpc';

var callDetectBackends = rpc.declare({
	object: 'luci.cfst',
	method: 'detect_backends',
	expect: { available: [] }
});

var callListNodes = rpc.declare({
	object: 'luci.cfst',
	method: 'list_nodes',
	params: [ 'backend' ],
	expect: { nodes: [] }
});

var callGetArch = rpc.declare({
	object: 'luci.cfst',
	method: 'get_arch',
	expect: {}
});

var callDownloadBinary = rpc.declare({
	object: 'luci.cfst',
	method: 'download_binary',
	params: [ 'mirror_prefix' ],
	expect: {}
});

var callDownloadStatus = rpc.declare({
	object: 'luci.cfst',
	method: 'download_status',
	expect: {}
});

var callRunNow = rpc.declare({
	object: 'luci.cfst',
	method: 'run_now',
	expect: {}
});

var callRunStatus = rpc.declare({
	object: 'luci.cfst',
	method: 'run_status',
	expect: {}
});

var callGetLog = rpc.declare({
	object: 'luci.cfst',
	method: 'get_log',
	params: [ 'lines' ],
	expect: { lines: [] }
});

var callClearLog = rpc.declare({
	object: 'luci.cfst',
	method: 'clear_log',
	expect: {}
});

var callGetResults = rpc.declare({
	object: 'luci.cfst',
	method: 'get_results',
	expect: { results: [] }
});

/* Curated, non-exhaustive list of common Cloudflare colo IATA codes,
 * grouped by region, for the region-selection UI. Cloudflare operates
 * 300+ colos; users can always add custom codes via the free-text field. */
var COLO_PRESETS = {
	'Asia': [
		{ code: 'HKG', name: 'Hong Kong' },
		{ code: 'NRT', name: 'Tokyo' },
		{ code: 'ICN', name: 'Seoul' },
		{ code: 'SIN', name: 'Singapore' },
		{ code: 'TPE', name: 'Taipei' },
		{ code: 'KUL', name: 'Kuala Lumpur' },
		{ code: 'BKK', name: 'Bangkok' },
		{ code: 'MNL', name: 'Manila' },
		{ code: 'CGK', name: 'Jakarta' },
		{ code: 'BOM', name: 'Mumbai' }
	],
	'North America': [
		{ code: 'LAX', name: 'Los Angeles' },
		{ code: 'SJC', name: 'San Jose' },
		{ code: 'SEA', name: 'Seattle' },
		{ code: 'ORD', name: 'Chicago' },
		{ code: 'DFW', name: 'Dallas' },
		{ code: 'IAD', name: 'Ashburn' },
		{ code: 'EWR', name: 'Newark' },
		{ code: 'ATL', name: 'Atlanta' },
		{ code: 'MIA', name: 'Miami' },
		{ code: 'YVR', name: 'Vancouver' },
		{ code: 'YYZ', name: 'Toronto' }
	],
	'Europe': [
		{ code: 'LHR', name: 'London' },
		{ code: 'FRA', name: 'Frankfurt' },
		{ code: 'AMS', name: 'Amsterdam' },
		{ code: 'CDG', name: 'Paris' },
		{ code: 'MAD', name: 'Madrid' },
		{ code: 'MXP', name: 'Milan' },
		{ code: 'ARN', name: 'Stockholm' },
		{ code: 'WAW', name: 'Warsaw' }
	],
	'Oceania': [
		{ code: 'SYD', name: 'Sydney' },
		{ code: 'MEL', name: 'Melbourne' },
		{ code: 'AKL', name: 'Auckland' }
	],
	'South America': [
		{ code: 'GRU', name: 'Sao Paulo' },
		{ code: 'EZE', name: 'Buenos Aires' },
		{ code: 'SCL', name: 'Santiago' }
	],
	'Middle East / Africa': [
		{ code: 'DXB', name: 'Dubai' },
		{ code: 'TLV', name: 'Tel Aviv' },
		{ code: 'JNB', name: 'Johannesburg' }
	]
};

return baseclass.extend({
	detectBackends: callDetectBackends,
	listNodes: callListNodes,
	getArch: callGetArch,
	downloadBinary: callDownloadBinary,
	downloadStatus: callDownloadStatus,
	runNow: callRunNow,
	runStatus: callRunStatus,
	getLog: callGetLog,
	clearLog: callClearLog,
	getResults: callGetResults,
	COLO_PRESETS: COLO_PRESETS
});
