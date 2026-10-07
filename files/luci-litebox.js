'use strict';
'require view';
'require fs';
'require ui';

// LiteBox 的路由器后台页面（LuCI「服务 → LiteBox」）：填订阅、看状态、打开面板。
// 所有操作都调用 /usr/bin/litebox，权限见 /usr/share/rpcd/acl.d/luci-app-litebox.json

var LB = '/usr/bin/litebox';

function status() {
	return fs.exec(LB, [ 'luci-status' ]).then(function(r) {
		try { return JSON.parse(r.stdout); }
		catch (e) { return null; }
	}).catch(function() { return null; });
}

function bytes(n) {
	n = Number(n);
	if (!(n > 0)) return '0 B';
	var u = [ 'B', 'KB', 'MB', 'GB', 'TB' ], i = 0;
	while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
	return (i ? n.toFixed(n >= 100 ? 0 : 1) : n) + ' ' + u[i];
}

function day(sec) {
	var d = new Date(Number(sec) * 1000);
	return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
}

// 加速层状态（/tmp/litebox-fw.state，一行一项，原因里可能有空格）翻译成人话
function accel(state) {
	var t = state.trim().split(/\n/), out = [];
	t.forEach(function(x) {
		var k = x.split(':')[0], v = x.slice(k.length + 1);
		if (k === 'off') out.push('已关闭，全部流量走 TUN');
		else if (k === 'bypass') out.push('国内 IP 直连、不进内核（' + v + ' 个 IP 段）');
		else if (k === 'nobypass') out.push('国内流量仍经过内核（' + v + '）');
		else if (k === 'redir') out.push('TCP 走 iptables 转发');
		else if (k === 'tun') out.push('只用 TUN（' + v + '）');
	});
	return out.join('；') || state;
}

// 运行一条 litebox 命令，期间显示等待框，结束后弹出结果
function run(args, title) {
	ui.showModal(title, [ E('p', { 'class': 'spinning' }, '请稍候…') ]);
	return fs.exec(LB, args).then(function(r) {
		ui.hideModal();
		var out = ((r.stdout || '') + (r.stderr || '')).trim();
		ui.addNotification(null, E('p', out || '完成'), r.code === 0 ? 'info' : 'danger');
		return r.code === 0;
	}).catch(function(e) {
		ui.hideModal();
		ui.addNotification(null, E('p', '执行失败：' + e.message), 'danger');
		return false;
	});
}

return view.extend({
	load: function() {
		return status();
	},

	// 保存后内核要下载订阅，过几秒再看节点数
	waitNodes: function(view) {
		var tries = 0;
		var tick = function() {
			return status().then(function(st) {
				view.fill(st);
				if ((st && st.nodes > 0) || ++tries >= 15)
					return;
				return new Promise(function(r) { setTimeout(r, 2000); }).then(tick);
			});
		};
		return tick();
	},

	fill: function(st) {
		var box = document.getElementById('lb-status');
		if (!box) return;
		box.innerHTML = '';
		if (!st) {
			box.appendChild(E('p', { 'class': 'alert-message warning' }, '读取状态失败。如果提示没有权限，退出路由器后台重新登录一次。'));
			return;
		}
		var rows = [];
		var row = function(k, v) { rows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'style': 'width:33%' }, k), E('td', { 'class': 'td left' }, v) ])); };

		if (!st.sub)
			row('订阅', E('strong', { 'style': 'color:#c00' }, '还没有填，LiteBox 没有在工作'));
		else if (!st.running)
			row('订阅', '已填写（LiteBox 没有运行，点下面的「启用」）');
		else if (st.nodes === undefined)
			row('订阅', '已填写（路由器没有 curl，看不到节点数：opkg update && opkg install curl）');
		else if (st.nodes > 0)
			row('订阅', E('strong', { 'style': 'color:#080' }, '正常，加载了 ' + st.nodes + ' 个节点'));
		else
			row('订阅', E('strong', { 'style': 'color:#c00' }, '没有节点：订阅地址不对、过期，或还在下载（稍等再刷新）'));

		if (Number(st.sub_total) > 0) {
			var used = Number(st.sub_upload || 0) + Number(st.sub_download || 0);
			row('套餐流量', '已用 ' + bytes(used) + ' / 共 ' + bytes(st.sub_total) +
				(Number(st.sub_expire) > 0 ? '，' + day(st.sub_expire) + ' 到期' : ''));
		}
		row('运行状态', st.running ? '运行中，内存 ' + st.mem_mb + ' MB' + (st.enabled ? '' : '（没开开机自启）') : '没有运行');
		row('DNS 接管', st.dns ? '已由 LiteBox 接管' : '没有接管（局域网直连）');
		if (st.accel)
			row('流量加速', accel(st.accel));
		box.appendChild(E('table', { 'class': 'table' }, rows));
	},

	render: function(st) {
		var self = this;
		var input = E('input', {
			'type': 'text', 'class': 'cbi-input-text', 'id': 'lb-sub',
			'style': 'width:100%;font-size:15px;padding:8px',
			'placeholder': '在这里粘贴机场订阅地址，https:// 开头',
			'value': (st && st.sub) || '',
			'autocomplete': 'off', 'spellcheck': 'false'
		});

		var save = function() {
			var url = input.value.trim().replace(/^["']+|["']+$/g, '');
			if (!/^https?:\/\//.test(url)) {
				ui.addNotification(null, E('p', '订阅地址要以 https:// 或 http:// 开头。在机场网站找「复制订阅链接 / Clash 订阅」，复制后粘贴。'), 'warning');
				return;
			}
			input.value = url;
			return run([ 'sub', url, '--no-wait' ], '正在保存订阅并重启 LiteBox').then(function(ok) {
				if (ok) {
					ui.addNotification(null, E('p', '正在下载节点，十几秒后下面的状态会更新。'), 'info');
					return self.waitNodes(self);
				}
			});
		};

		var links = [];
		if (st && st.running) {
			links.push(E('a', { 'class': 'btn cbi-button cbi-button-action', 'href': st.panel, 'target': '_blank', 'rel': 'noopener' }, '打开面板（切换节点）'));
			links.push(' ');
			links.push(E('a', { 'class': 'btn cbi-button', 'href': st.overview, 'target': '_blank', 'rel': 'noopener' }, '概览和路由测试'));
			links.push(' ');
		}

		var node = E('div', {}, [
			E('h2', {}, 'LiteBox'),
			E('div', { 'class': 'cbi-map-descr' }, '轻量透明代理：家里所有设备不用设置就能分流，国内直连、AI 和常用境外服务走代理。'),

			E('div', { 'class': 'cbi-section', 'style': 'border:2px solid ' + ((st && st.sub) ? '#3a9' : '#d33') + ';border-radius:8px;padding:12px 16px' }, [
				E('h3', {}, (st && st.sub) ? '① 机场订阅地址' : '① 第一步：填机场订阅地址'),
				E('p', {}, [
					'订阅地址就是机场给你的「Clash 订阅链接」，以 https:// 开头。',
					E('br'),
					'在机场网站的「仪表盘 / 一键订阅 / 复制订阅链接」里复制，粘贴到下面，点「保存并启动」。'
				]),
				input,
				E('div', { 'style': 'margin-top:10px' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, save) }, '保存并启动'),
					' ',
					E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, function() {
						return run([ 'sub-update' ], '正在重新下载订阅').then(function() { return status().then(self.fill); });
					}) }, '更新节点')
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '② 运行状态'),
				E('div', { 'id': 'lb-status' }),
				E('div', { 'style': 'margin-top:10px' }, links.concat([
					E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(this, function() {
						return run([ 'restart' ], '正在重启 LiteBox').then(function() { return status().then(self.fill); });
					}) }, '重启'),
					' ',
					(st && st.enabled)
						? E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.createHandlerFn(this, function() {
							if (!confirm('停用 LiteBox，全部设备恢复直连上网？'))
								return;
							return run([ 'direct' ], '正在停用').then(function() { location.reload(); });
						}) }, '停用（恢复直连）')
						: E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': ui.createHandlerFn(this, function() {
							return run([ 'enable' ], '正在启用').then(function() { location.reload(); });
						}) }, '启用')
				]))
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '③ 出问题时'),
				E('p', {}, [
					'上不了网：先点上面的「停用（恢复直连）」。',
					E('br'),
					'想看哪里有问题：用 SSH 登录路由器执行 ',
					E('code', {}, 'litebox doctor'),
					'，每个失败项下面都写了怎么处理。'
				])
			])
		]);

		requestAnimationFrame(function() { self.fill(st); });
		return node;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
