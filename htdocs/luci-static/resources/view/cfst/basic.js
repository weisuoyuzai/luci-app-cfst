'use strict';
'require view';
'require form';
'require poll';
'require ui';
'require cfst as cfstlib';

var SECTION_ID = 'global';

function fmtTime(epoch) {
	if (!epoch)
		return '';
	return new Date(epoch * 1000).toLocaleString();
}

/* Custom widget: a checkbox grid of curated Cloudflare colo presets plus a
 * free-text field for extra codes, all serialized into a single comma
 * separated uci option (cfst_colo). */
var CfstColoWidget = form.Value.extend({
	presetCodes: (function() {
		var map = {};
		Object.keys(cfstlib.COLO_PRESETS).forEach(function(region) {
			cfstlib.COLO_PRESETS[region].forEach(function(item) {
				map[item.code] = true;
			});
		});
		return map;
	})(),

	renderWidget: function(section_id, option_index, cfgvalue) {
		var value = (cfgvalue != null ? cfgvalue : (this.default || '')).toString();
		var selected = {};

		value.split(',').forEach(function(v) {
			v = v.trim();
			if (v)
				selected[v] = true;
		});

		var widgetId = this.cbid(section_id);
		var textInput = E('input', {
			'type': 'text',
			'id': widgetId,
			'name': widgetId,
			'value': value,
			'style': 'width:100%;margin-top:8px;box-sizing:border-box',
			'placeholder': _('Additional/custom IATA codes, comma-separated')
		});

		var presetCodes = this.presetCodes;

		var syncFromCheckboxes = function(container) {
			var codes = [];
			container.querySelectorAll('input[type="checkbox"]').forEach(function(cb) {
				if (cb.checked)
					codes.push(cb.value);
			});
			var extra = textInput.value.split(',').map(function(s) {
				return s.trim();
			}).filter(function(c) {
				return c && !presetCodes[c];
			});
			textInput.value = codes.concat(extra).join(',');
		};

		var container = E('div', { 'class': 'cbi-colo-picker' });

		Object.keys(cfstlib.COLO_PRESETS).forEach(function(region) {
			var line = E('div', { 'style': 'margin-bottom:4px' }, [
				E('strong', {}, _(region) + ': ')
			]);

			cfstlib.COLO_PRESETS[region].forEach(function(item) {
				var cb = E('input', {
					'type': 'checkbox',
					'value': item.code,
					'style': 'margin-left:8px'
				});
				if (selected[item.code])
					cb.checked = true;

				cb.addEventListener('change', function() {
					syncFromCheckboxes(container);
				});

				line.appendChild(cb);
				line.appendChild(E('span', {}, ' ' + item.code + ' (' + _(item.name) + ')'));
			});

			container.appendChild(line);
		});

		container.appendChild(textInput);

		return container;
	}
});

return view.extend({
	load: function() {
		return Promise.all([
			cfstlib.detectBackends().catch(function() { return {}; }),
			cfstlib.getArch().catch(function() { return {}; }),
			cfstlib.listNodes({}).catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var backends = data[0] || {};
		var arch = data[1] || {};
		var nodes = data[2] || {};
		var available = backends.available || [];
		var m, s, o;

		var backendLabel = function(name, title) {
			return (available.indexOf(name) >= 0) ? title : (title + ' (' + _('not detected') + ')');
		};

		m = new form.Map('cfst', _('CloudflareST'),
			_('Speed test Cloudflare IPs and automatically apply the best IP to the selected PassWall / PassWall2 / OpenClash node(s).'));

		/* ---------------- Run Now ---------------- */

		s = m.section(form.NamedSection, SECTION_ID, 'cfst', _('Run'));
		s.anonymous = true;

		o = s.option(form.Button, '_run_now', _('Run Now'));
		o.inputtitle = _('Run Now');
		o.inputstyle = 'apply';
		o.onclick = function() {
			return cfstlib.runNow().then(function(res) {
				if (res && res.started === false) {
					ui.addNotification(null, E('p', res.error || _('A run is already in progress')));
					return;
				}
				ui.addNotification(null, E('p', _('Speed test started in the background. Check the Log / Speedtest Results tabs for progress.')));
			});
		};

		o = s.option(form.DummyValue, '_run_status', _('Status'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<span id="cfst-run-status">' + _('Loading...') + '</span>';
		};

		/* ---------------- Basic Settings ---------------- */

		s = m.section(form.NamedSection, SECTION_ID, 'cfst', _('Basic Settings'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(form.ListValue, 'backend', _('Backend'));
		o.value('auto', _('Auto detect'));
		o.value('passwall2', backendLabel('passwall2', _('PassWall2')));
		o.value('passwall', backendLabel('passwall', _('PassWall')));
		o.value('openclash', backendLabel('openclash', _('OpenClash (best-effort)')));
		o.description = _('If more than one backend is installed, "Auto detect" will refuse to run and you must pick one explicitly here.');

		o = s.option(form.ListValue, 'match_mode', _('Node match mode'));
		o.value('id', _('Match by selecting node(s)'));
		o.value('keyword', _('Match by remark keyword'));

		o = s.option(form.MultiValue, 'node_id', _('Node(s)'));
		o.depends('match_mode', 'id');
		if (nodes.ok && (nodes.nodes || []).length) {
			nodes.nodes.forEach(function(n) {
				o.value(n.id, (n.remark || n.id) + ' (' + (n.address || '-') + ')');
			});
			o.description = _('Loaded from backend: %s. If you change the Backend above, click Save, then reopen this page to refresh this list.').format(nodes.backend);
		} else {
			/* LuCI's form.MultiValue renders a blank choice list as `null`
			 * rather than `{}`, which crashes ui.Dropdown's render(). Always
			 * provide at least one (disabled-looking) choice to avoid that. */
			o.value('', _('No nodes available'));
			o.description = _('Could not load the node list (%s). Save your backend selection and reopen this page, or use the keyword match mode instead.').format(nodes.error || _('unknown error'));
		}

		o = s.option(form.HiddenValue, 'node_backend');
		o.cfgvalue = function() {
			return nodes.backend || '';
		};

		o = s.option(form.Value, 'node_keyword', _('Remark keyword'));
		o.depends('match_mode', 'keyword');
		o.placeholder = 'cf优选';
		o.description = _('Any node whose remark contains this text will be updated.');

		o = s.option(form.Flag, 'bypass_local_proxy', _('Bypass local proxy while testing'));
		o.description = _('Temporarily disables the "localhost proxy" setting during the speed test so the test itself is not routed through the proxy. Only supported for PassWall / PassWall2; has no effect for OpenClash.');

		/* ---------------- Schedule ---------------- */

		s = m.section(form.NamedSection, SECTION_ID, 'cfst', _('Schedule'));
		s.anonymous = true;

		o = s.option(form.Flag, 'cron_enabled', _('Enable scheduled run'));

		o = s.option(form.Value, 'cron_time', _('Cron schedule'));
		o.depends('cron_enabled', '1');
		o.placeholder = '30 3 * * *';
		o.description = _('Standard 5-field cron expression (minute hour day month weekday).');
		o.validate = function(section_id, value) {
			if (!value)
				return _('Cron schedule is required when scheduled run is enabled');
			var parts = value.trim().split(/\s+/);
			if (parts.length !== 5)
				return _('Must be a 5-field cron expression, e.g. "30 3 * * *"');
			for (var i = 0; i < parts.length; i++) {
				if (!/^[0-9*/,-]+$/.test(parts[i]))
					return _('Invalid characters in field %d').format(i + 1);
			}
			return true;
		};

		/* ---------------- cfst Binary ---------------- */

		s = m.section(form.NamedSection, SECTION_ID, 'cfst', _('cfst Binary'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_arch', _('Detected architecture'));
		o.cfgvalue = function() {
			return arch.arch || _('unknown (unsupported architecture)');
		};

		o = s.option(form.DummyValue, '_bin_status', _('Binary status'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<span id="cfst-download-status">' +
				(arch.installed
					? _('Installed') + (arch.mtime ? ' (' + fmtTime(arch.mtime) + ')' : '')
					: _('Not installed')) +
				'</span>';
		};

		o = s.option(form.Flag, 'auto_download', _('Auto-download if missing'));
		o.description = _('Automatically download cfst on first run if the binary is not present yet.');

		o = s.option(form.Value, 'mirror_prefix', _('GitHub mirror prefix'));
		o.placeholder = 'https://ghproxy.com/';
		o.rmempty = true;
		o.description = _('Prepended to the GitHub release download URL to speed up access. Leave empty to download directly from GitHub. This field may need to be updated over time as public mirrors change.');

		o = s.option(form.Value, 'cfst_bin_url', _('Custom download URL (advanced)'));
		o.rmempty = true;
		o.description = _('If set, this exact URL is downloaded as-is, bypassing architecture detection and the mirror prefix.');

		o = s.option(form.Button, '_update_binary', _('Update cfst binary now'));
		o.inputtitle = _('Update Now');
		o.inputstyle = 'action';
		o.onclick = function() {
			var mirrorOpt = m.lookupOption('mirror_prefix', SECTION_ID)[0];
			var mirror = mirrorOpt ? (mirrorOpt.formvalue(SECTION_ID) || '') : '';

			return cfstlib.downloadBinary(mirror).then(function(res) {
				if (res && res.started === false) {
					ui.addNotification(null, E('p', res.error || _('An update is already in progress')));
					return;
				}
				ui.addNotification(null, E('p', _('Downloading cfst in the background...')));
				var pollFn = function() {
					return cfstlib.downloadStatus().then(function(st) {
						var el = document.getElementById('cfst-download-status');
						if (!el)
							return;
						if (st.state === 'running') {
							el.textContent = _('Downloading...');
						} else if (st.state === 'success') {
							el.textContent = _('Installed') + ' (' + fmtTime(st.time) + ')';
							poll.remove(pollFn);
						} else if (st.state === 'failed') {
							el.textContent = _('Update failed: %s').format(st.message || '');
							poll.remove(pollFn);
						}
					});
				};
				poll.add(pollFn, 2);
			});
		};

		/* ---------------- Speed Test Parameters ---------------- */

		s = m.section(form.NamedSection, SECTION_ID, 'cfst', _('Speed Test Parameters'));
		s.anonymous = true;

		o = s.option(form.Value, 'cfst_threads', _('Latency test threads (-n)'));
		o.datatype = 'uinteger';
		o.placeholder = '200';

		o = s.option(form.Value, 'cfst_ping_count', _('Latency test count (-t)'));
		o.datatype = 'uinteger';
		o.placeholder = '4';

		o = s.option(form.Value, 'cfst_download_count', _('Download test count (-dn)'));
		o.datatype = 'uinteger';
		o.placeholder = '10';
		o.description = _('Number of IPs to run the download speed test on. Default: 10.');

		o = s.option(form.Value, 'cfst_download_time', _('Download test duration seconds (-dt)'));
		o.datatype = 'uinteger';
		o.placeholder = '10';

		o = s.option(form.Value, 'cfst_latency_limit', _('Max average latency ms (-tl)'));
		o.datatype = 'uinteger';
		o.placeholder = '200';

		o = s.option(form.Value, 'cfst_loss_limit', _('Max packet loss rate (-tlr)'));
		o.datatype = 'ufloat';
		o.placeholder = '0.2';
		o.validate = function(section_id, value) {
			if (value === '' || value == null)
				return true;
			var f = parseFloat(value);
			if (isNaN(f) || f < 0 || f > 1)
				return _('Must be a number between 0 and 1');
			return true;
		};

		o = s.option(form.Value, 'cfst_speed_limit', _('Min download speed MB/s (-sl)'));
		o.datatype = 'ufloat';
		o.placeholder = '5';

		o = s.option(form.Value, 'cfst_result_count', _('Result count to keep (-p)'));
		o.datatype = 'uinteger';
		o.placeholder = '5';

		o = s.option(form.Value, 'ip_txt', _('Custom IP range file (advanced)'));
		o.rmempty = true;
		o.description = _('Optional path to a custom IP range file (-f). Leave empty to use CloudflareST\'s built-in ranges.');

		o = s.option(CfstColoWidget, 'cfst_colo', _('Test only these regions (-cfcolo)'));
		o.rmempty = true;
		o.description = _('Leave everything unchecked and empty to test all Cloudflare colos.');

		poll.add(function() {
			return cfstlib.runStatus().then(function(st) {
				var el = document.getElementById('cfst-run-status');
				if (!el)
					return;
				if (st.running) {
					el.textContent = _('Running...');
				} else {
					el.textContent = st.last_run
						? _('Idle - last run: %s, result: %s%s').format(
							fmtTime(st.last_run), st.last_result || '-',
							st.last_ip ? ' (' + st.last_ip + ')' : '')
						: _('Idle - no run yet');
				}
			});
		}, 3);

		return m.render();
	}
});
