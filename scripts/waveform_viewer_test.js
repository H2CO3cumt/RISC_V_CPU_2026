// 波形查看器测试（由 scripts/run_waveform_viewer_test.ps1 调用）。
//
// 三件事，都要有可复现的证据，不能靠"打开浏览器看一眼"：
//   A 解析器正确性：把内嵌解析器抽出来，在 node 里跑，用**板子原始回包（.log）当基准真值**
//     对比 VCD 反解出来的采样流与触发点。
//   B 波形页数据可解析：采集脚本生成的 *.html 里嵌了 window.WAVEFORMS = [...]，
//     必须能被 JSON.parse（注入时若漏转义，页面会白屏）。
//   C 渲染器真的会画：用最小 DOM 桩执行整段脚本，统计画布绘图调用次数；
//     只有"调用数 > 0"才算波形被画出来，光"脚本没报错"不算。
const fs = require('fs');
const path = require('path');

const htmlPath = process.argv[2];
// 第三个参数可以是采集目录，也可以直接是波形页（.html）：没有板级采集时用它跑解码器测试。
const dirArg = process.argv[3];
const dirIsPage = !!dirArg && /\.html$/i.test(dirArg);
const dir = dirIsPage ? path.dirname(dirArg) : dirArg;
const modes = dirIsPage ? [] : process.argv.slice(4);

const html = fs.readFileSync(htmlPath, 'utf8');
const begin = html.indexOf('//==PARSER_BEGIN==');
const end = html.indexOf('//==PARSER_END==');
if (begin < 0 || end < 0) { console.log('TEST parser-extract FAIL'); process.exit(1); }
const parserCode = html.slice(begin, end);
// 时基换算段（//==TIMEBASE_BEGIN==）与解码段（//==DECODE_BEGIN==）都是可单独测试的纯函数。
// 没有这两段的旧页面仍按原样工作：对应测试自动 SKIP。
const tbegin = html.indexOf('//==TIMEBASE_BEGIN==');
const tend = html.indexOf('//==TIMEBASE_END==');
const hasTimebase = tbegin >= 0 && tend > tbegin;
const timebaseCode = hasTimebase ? html.slice(tbegin, tend) : '';
const dbegin = html.indexOf('//==DECODE_BEGIN==');
const dend = html.indexOf('//==DECODE_END==');
const hasDecode = dbegin >= 0 && dend > dbegin;
const decodeCode = hasDecode ? html.slice(dbegin, dend) : '';
const factory = new Function(parserCode + '\n' + timebaseCode + '\n' + decodeCode +
  '\nreturn { parseVcd: parseVcd, parseRawText: parseRawText,' +
  ' fmtNs: typeof fmtNs === "function" ? fmtNs : null, tbInfo: typeof tbInfo === "function" ? tbInfo : null,' +
  ' decodeWith: typeof decodeWith === "function" ? decodeWith : null };');
const { parseVcd, parseRawText, fmtNs, tbInfo, decodeWith } = factory();

let failures = 0;

// ---------------------------------------------------------------- 0（时基换算）
if (!hasTimebase) {
  console.log('TEST timebase-format SKIP (模板里没有 //==TIMEBASE_BEGIN== 段)');
} else {
  const tbProblems = [];
  if (fmtNs(317.46) !== '317.460 ns') tbProblems.push('fmtNs(317.46)=' + fmtNs(317.46));
  if (fmtNs(1000) !== '1.000 µs') tbProblems.push('fmtNs(1000)=' + fmtNs(1000));
  if (fmtNs(1e6) !== '1.000 ms') tbProblems.push('fmtNs(1e6)=' + fmtNs(1e6));
  // 没有时基时必须**明说未标定**，绝不能报一个编出来的采样率
  const unknown = tbInfo({ samples: new Array(256).fill(0), sample_ns: null });
  if (unknown.indexOf('未标定') < 0) tbProblems.push('未标定时没有报"未标定"：' + unknown);
  const known = tbInfo({ samples: new Array(256).fill(0), sample_ns: 317.46, sample_hz: 85e6 / 27 });
  if (known.indexOf('3.1481 MHz') < 0 || known.indexOf('81.270 µs') < 0) {
    tbProblems.push('时基换算不对：' + known);
  }
  if (tbProblems.length) { failures++; console.log('TEST timebase-format FAIL: ' + tbProblems.join('; ')); }
  else console.log('TEST timebase-format PASS 3.1481 MHz / 每点317.460 ns / 窗口81.270 µs');
}

// ---------------------------------------------------------------- 0b（解码器）
// 用**合成波形**验证解码器：帧边界必须是数据位的真实起止，字节值必须与发送值一致。
// 为什么必须测：波形页上的帧框和字节值是"软件读出了什么"的直接证据，
// 画错框比不画更坏——评委照着框去数位会发现对不上。
if (!hasDecode) {
  console.log('TEST decode-uart SKIP (模板里没有 //==DECODE_BEGIN== 段)');
} else {
  const BIT = 16;
  // 生成 UART 8N1 波形：idle 高 → 起始位 0 → 8 位数据（LSB 先）→ 停止位 1
  function makeUart(value, pre, post, withTail) {
    const seq = [];
    for (let i = 0; i < (pre == null ? 3 : pre); i++) seq.push(1);
    seq.push(0);
    for (let b = 0; b < 8; b++) seq.push((value >> b) & 1);
    seq.push(1);
    for (let i = 0; i < (post == null ? 40 : post); i++) seq.push(1);
    const samples = [];
    seq.forEach((lvl) => { for (let k = 0; k < BIT; k++) samples.push(lvl ? 0x01 : 0x00); });
    if (withTail) {
      // 尾部再补一帧，验证连续两帧都能被解出且边界互不重叠
      const second = makeUart(0x5A, 0, 0, false);
      second.forEach((s) => samples.push(s));
      for (let i = 0; i < 40; i++) samples.push(0x01);
    }
    return samples;
  }
  const cases = [
    { name: '单帧 0xA5', samples: makeUart(0xA5), want: [0xA5], wantStart: 3 * BIT, wantEnd: 13 * BIT },
    { name: '单帧 0x5A', samples: makeUart(0x5A), want: [0x5A], wantStart: 3 * BIT, wantEnd: 13 * BIT },
    { name: '连帧 A5+5A', samples: makeUart(0xA5, 3, 0, true), want: [0xA5, 0x5A], wantStart: 3 * BIT, wantEnd: 13 * BIT },
  ];
  const dProblems = [];
  for (const c of cases) {
    const r = decodeWith({ protocol: 'uart', channel: 0, bit_samples: BIT, which: 1 }, c.samples);
    if (!r) { dProblems.push(`${c.name}: 没有解出结果`); continue; }
    const got = r.bytes.map((v) => v.toString(16)).join(',');
    const want = c.want.map((v) => v.toString(16)).join(',');
    if (got !== want) { dProblems.push(`${c.name}: 字节 ${got} != ${want}`); continue; }
    const f = r.frames[0];
    if (f.start !== c.wantStart || f.end !== c.wantEnd) {
      dProblems.push(`${c.name}: 帧边界 [${f.start},${f.end}] != [${c.wantStart},${c.wantEnd}]（start 必须落在起始位、end 在停止位之后）`);
    }
    if (r.pickedIndex !== 0) dProblems.push(`${c.name}: which=1 应框第 0 个字节，实际 ${r.pickedIndex}`);
    if (r.active.join(',') !== '0') dProblems.push(`${c.name}: 参与通道应为 ch0，实际 ${r.active.join(',')}`);
  }
  // 窗口相位偏移：把波形整体左移，让第一个下降沿落在**数据位内部**——
  // 这正是 logic_analyzer.py 里那段注释讲的坑，解码器不许在这里记假错误或错帧
  {
    const whole = makeUart(0xA5);
    const shifted = whole.slice(BIT);            // 切掉第一个空闲比特，帧起点不再对齐
    const r = decodeWith({ protocol: 'uart', channel: 0, bit_samples: BIT, which: 1 }, shifted);
    if (!r || !r.bytes.length || r.bytes[0] !== 0xA5) {
      dProblems.push(`相位偏移窗口：应仍能解出 a5，实际 ${r ? r.bytes.map((v) => v.toString(16)).join(',') : 'null'}`);
    }
  }
  // SPI mode 0：CS 低 → 每次 SCLK 上升沿采 MOSI（MSB 先）
  // 两个变体都要测，因为真实板级波形与"理想 SPI"在这点上不同：
  //   变体 1（CS 翻转）：窗口内 CS 由高变低 → 帧起点取 CS 拉低那一拍
  //   变体 2（CS 恒低）：**本工程 ch2 就是这样**，每帧切换一次、远慢于窗口，
  //                     所以窗口里看不到 CS 翻转 → 退回"该字节第一个时钟上升沿"，
  //                     绝不把窗口开头的空闲并进帧宽（那会让框比真实传输长一截）
  {
    const problems = [];
    const sBits = [];
    for (let b = 7; b >= 0; b--) sBits.push((0x3C >> b) & 1);
    // 通道分配：ch0=SCLK(bit0)、ch1=MOSI(bit1)、ch2=CS(bit2)。
    // MOSI 只跟数据位走，**不能**顺手把时钟位或进去——否则 MOSI 会跟着时钟一起跳，
    // 上升沿采到的永远全是 1（本轮就这么错过两次，字节解成 0xFF）。
    const MOSI = (bit) => (bit ? 0x02 : 0x00);
    const SCLK = 0x01;
    const CS_HI = 0x04;
    function makeSpi(csPulse) {
      const s = [];
      for (let i = 0; i < 6; i++) s.push(csPulse ? CS_HI : 0x00);   // 前缀：变体 1 拉高 CS，变体 2 保持低
      if (csPulse) s.push(0x00);                                    // CS 拉低 = 变体 1 的传输起点
      sBits.forEach((bit) => {
        s.push(MOSI(bit));                                          // SCLK 低，摆好 MOSI
        s.push(MOSI(bit) | SCLK);                                   // SCLK 上升沿（解码器在这一拍采 MOSI）
        s.push(MOSI(bit));                                          // SCLK 回到低
      });
      s.push(CS_HI | MOSI(sBits[sBits.length - 1]));                // CS 拉高，MOSI 保持
      return s;
    }
    const variants = [
      { name: 'CS 翻转', samples: makeSpi(true) },
      { name: 'CS 恒低', samples: makeSpi(false) },
    ];
    variants.forEach((v) => {
      const r = decodeWith({ protocol: 'spi', clock: 0, mosi: 1, cs: 2, which: 1 }, v.samples);
      if (!r || r.bytes.length !== 1) { problems.push(`${v.name}: 应解出 1 个字节，实际 ${r ? r.bytes.length : 'null'}`); return; }
      if (r.bytes[0] !== 0x3C) problems.push(`${v.name}: 字节 ${r.bytes[0].toString(16)} != 3c`);
      if (r.active.join(',') !== '0,1,2') problems.push(`${v.name}: 参与通道应为 0,1,2，实际 ${r.active.join(',')}`);
      // 不硬编码"起点该在第几拍"——那属于实现细节，硬编码只会让测试跟着实现一起漂移。
      // 要守的是这几条**不变量**（它们才是"画出来的框对不对"的判据）：
      const f = r.frames[0];
      const rises = [];
      for (let i = 1; i < v.samples.length; i++) {
        if (!(v.samples[i - 1] & 0x01) && (v.samples[i] & 0x01)) rises.push(i);
      }
      if (f.end !== rises[rises.length - 1]) {
        problems.push(`${v.name}: 帧终点 ${f.end} 应等于最后一个时钟上升沿 ${rises[rises.length - 1]}`);
      }
      if (f.start > rises[0]) {
        problems.push(`${v.name}: 帧起点 ${f.start} 不应晚于第一个时钟上升沿 ${rises[0]}（否则框不住整帧）`);
      }
      if (f.start >= f.end) problems.push(`${v.name}: 帧起点 ${f.start} 必须早于终点 ${f.end}`);
      // 前缀是 6 拍 CS 高（或 6 拍 CS 低），起点只能落在这个前缀附近：6~10
      if (f.start < 6 || f.start > 10) {
        problems.push(`${v.name}: 帧起点 ${f.start} 落在 CS 前缀之外（前缀 6 拍，合理范围 6~10）`);
      }
    });
    if (problems.length) dProblems.push('SPI ' + problems.join('; '));
  }
  if (dProblems.length) { failures++; console.log('TEST decode-uart FAIL: ' + dProblems.join(' | ')); }
  else console.log(`TEST decode-uart PASS 单帧/连帧/相位偏移 + SPI mode0 帧边界 [${3 * BIT},${13 * BIT})`);
}

// ---------------------------------------------------------------- A（VCD 反解）
for (const mode of modes) {
  const logPath = path.join(dir, mode, mode + '_00.log');
  const vcdPath = path.join(dir, mode, mode + '_00.vcd');
  if (!fs.existsSync(logPath) || !fs.existsSync(vcdPath)) {
    console.log(`TEST waveform-viewer-${mode} SKIP (missing log/vcd)`);
    continue;
  }
  const truth = parseRawText(fs.readFileSync(logPath, 'utf8'), 8);
  const got = parseVcd(fs.readFileSync(vcdPath, 'utf8'), 8);
  const problems = [];
  if (!truth || !truth.samples.length) problems.push('log 里解析不出 LA RAW 样本');
  if (!got.samples.length) problems.push('VCD 里解析不出采样点');
  if (truth && got.samples.length !== truth.samples.length) {
    problems.push(`样本数不一致 log=${truth.samples.length} vcd=${got.samples.length}`);
  }
  if (truth && got.trigger !== truth.trigger) problems.push(`触发点不一致 log=${truth.trigger} vcd=${got.trigger}`);
  if (truth && got.samples.length === truth.samples.length) {
    for (let i = 0; i < truth.samples.length; i++) {
      if (truth.samples[i] !== got.samples[i]) {
        problems.push(`第 ${i} 个采样点不一致 log=0x${truth.samples[i].toString(16)} vcd=0x${got.samples[i].toString(16)}`);
        break;
      }
    }
  }
  if (problems.length) { failures++; console.log(`TEST waveform-viewer-${mode} FAIL: ${problems.join('; ')}`); }
  else console.log(`TEST waveform-viewer-${mode} PASS samples=${got.samples.length} trigger=${got.trigger}`);
}

// ---------------------------------------------------------------- B + C
function makeStub() {
  const calls = { draw: 0 };
  const ctx = new Proxy({}, {
    get(_t, prop) {
      if (prop === 'canvas') return {};
      return function () { calls.draw++; };
    },
    set() { return true; }
  });
  function element(id) {
    return {
      id: id,
      style: {}, classList: { add() {}, remove() {} },
      addEventListener(ev, fn) { (this.handlers[ev] = this.handlers[ev] || []).push(fn); },
      handlers: {},
      fire(ev, arg) { (this.handlers[ev] || []).forEach((f) => f(arg)); },
      appendChild() {},
      getContext() { return ctx; },
      getBoundingClientRect() { return { left: 0, top: 0, width: 1200, height: 600 }; },
      clientWidth: 1200, clientHeight: 600, width: 1200, height: 600,
      textContent: '', innerHTML: '', onclick: null, files: []
    };
  }
  const elements = {};
  const doc = {
    getElementById(id) { return elements[id] || (elements[id] = element(id)); },
    createElement: element,
    addEventListener() {}
  };
  const win = {
    devicePixelRatio: 1, addEventListener() {},
    WAVEFORMS: null,
    FileReader: function () { this.readAsText = function () {}; }
  };
  return { doc, win, calls, elements };
}

const generated = [];
if (fs.existsSync(dir)) {
  for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    // 单窗口页 `<模式>_00.html` 与分段长波形页 `<模式>_segNN.html` 都要测：
    // 分段页正是"深度突破 256 点"的产物，漏掉它等于没测这个功能。
    for (const f of fs.readdirSync(path.join(dir, d.name))) {
      if (/^.+_(00|seg\d+)\.html$/.test(f)) generated.push(path.join(dir, d.name, f));
    }
  }
  // 总览页（评委双击的就是它，必须一起测）
  for (const name of ['波形预览.html', 'waveform_preview.html']) {
    const p = path.join(dir, name);
    if (fs.existsSync(p)) generated.push(p);
  }
}

if (!generated.length) {
  console.log('TEST waveform-page-smoke SKIP (no generated *.html under captures dir)');
} else {
  for (const page of generated) {
    const mode = path.basename(page).replace(/\.html$/, '');
    const text = fs.readFileSync(page, 'utf8');
    const m = /window\.WAVEFORMS\s*=\s*(\[[\s\S]*?\]);/.exec(text);
    if (!m) { failures++; console.log(`TEST waveform-page-${mode} FAIL: 页面里找不到嵌入数据`); continue; }
    let data;
    try { data = JSON.parse(m[1]); }
    catch (e) { failures++; console.log(`TEST waveform-page-${mode} FAIL: 嵌入数据不是合法 JSON (${e.message})`); continue; }
    if (!data.length) { failures++; console.log(`TEST waveform-page-${mode} FAIL: 嵌入数据是空的`); continue; }
    const scriptMatch = /<script>([\s\S]*)<\/script>/.exec(text);
    if (!scriptMatch) { failures++; console.log(`TEST waveform-page-${mode} FAIL: 页面里没有脚本`); continue; }
    const stub = makeStub();
    try {
      const run = new Function('window', 'document', 'alert', 'FileReader',
        scriptMatch[1] + '\n//# sourceURL=waveform-page.js');
      run(stub.win, stub.doc, function () {}, stub.win.FileReader);
    } catch (e) {
      failures++;
      console.log(`TEST waveform-page-${mode} FAIL: 渲染脚本抛异常 (${e.message})`);
      continue;
    }
    const drew = stub.calls.draw;
    if (drew <= 0) { failures++; console.log(`TEST waveform-page-${mode} FAIL: 渲染脚本没有产生任何绘图调用`); continue; }
    // C2 测量光标必须真的能放下去并算出 Δt：只验证"页面不报错"是不够的，
    // 而且要验证**没点时不许出现 Δ 读数**（否则就是把没测的量报成了测量值）。
    const cvEl = stub.elements['cv'];
    if (!cvEl || !cvEl.handlers || !(cvEl.handlers['mousedown'] || []).length) {
      failures++;
      console.log(`TEST waveform-page-${mode} FAIL: 画布上没有绑定 mousedown（光标放不下去）`);
      continue;
    }
    const stats0 = String(stub.elements['stats'].textContent || '');
    if (stats0.indexOf('Δ') >= 0) {
      failures++;
      console.log(`TEST waveform-page-${mode} FAIL: 还没放光标就报出了 Δ 读数：${stats0}`);
      continue;
    }
    const ev = (clientX, ctrl) => ({ button: 2, clientX: clientX, ctrlKey: !!ctrl, preventDefault() {} });
    const before = stub.calls.draw;
    cvEl.fire('mousedown', ev(400));                       // 右键 → 光标 A
    cvEl.fire('mousedown', ev(900, true));                 // Ctrl+右键 → 光标 B
    const stats1 = String(stub.elements['stats'].textContent || '');
    if (stub.calls.draw <= before) {
      failures++;
      console.log(`TEST waveform-page-${mode} FAIL: 放光标没有触发重绘`);
      continue;
    }
    if (stats1.indexOf('光标A') < 0 || stats1.indexOf('光标B') < 0 || stats1.indexOf('Δ') < 0) {
      failures++;
      console.log(`TEST waveform-page-${mode} FAIL: 两根光标没有算出 Δ：${stats1}`);
      continue;
    }
    if (/sample_ns|sample_hz/.test(m[1]) === true && stats1.indexOf(' ns') < 0) {
      failures++;
      console.log(`TEST waveform-page-${mode} FAIL: 嵌入数据有时基，但 Δ 只报了采样点没报时间：${stats1}`);
      continue;
    }
    // 分段长波形：数据里必须带 segments，且**解码必须按段进行**——
    // 跨段的两个采样点在真实时间里隔了几十毫秒，拼帧会解不出字节或解出假字节。
    // 总览页里第一个数据集是 static（没有 decode 信息），所以要挑一个**带解码的分段数据集**来验，
    // 不能想当然地取 data[0]（本轮实测就是这么误报的）。
    const segSets = data.filter((d) => d.segments && d.segments.length > 1);
    if (segSets.length) {
      const seg = segSets.find((d) => d.decode) || segSets[0];
      if (seg.decode) {
        const dec = decodeWith(seg.decode, seg.samples, seg.segments);
        if (!dec || !dec.perSegment || dec.perSegment.length !== seg.segments.length) {
          failures++;
          console.log(`TEST waveform-page-${mode} FAIL: 解码没有按段进行（perSegment=${dec ? dec.perSegment : 'null'}）`);
          continue;
        }
        // 段边界处**不该**出现跨段的字节：整条不解分段去解，字节数不得多于逐段之和
        const merged = decodeWith(seg.decode, seg.samples, null);
        const perSegTotal = dec.perSegment.reduce((n, arr) => n + arr.length, 0);
        if (merged && merged.bytes.length > perSegTotal) {
          failures++;
          console.log(`TEST waveform-page-${mode} FAIL: 跨段拼出了 ${merged.bytes.length} 个字节，` +
                      `而逐段只有 ${perSegTotal} 个（多出来的是跨段假帧）`);
          continue;
        }
        console.log(`TEST waveform-page-${mode} 分段信息：段数=${seg.segments.length} ` +
                    `每段字节数=[${dec.perSegment.map((a) => a.length).join(',')}] ` +
                    `gap_ns=${seg.gap_ns}`);
      } else {
        console.log(`TEST waveform-page-${mode} 分段信息：段数=${seg.segments.length}（无解码信息）`);
      }
    }
    const total = data.reduce((n, d) => n + d.samples.length, 0);
    console.log(`TEST waveform-page-${mode} PASS 波形数=${data.length} 嵌入样本=${total} 绘图调用=${stub.calls.draw} 光标Δ=${/Δ[^|]*/.exec(stats1)[0].trim()}`);
  }
}

if (failures) { console.log(`TEST SUMMARY FAIL count=${failures}`); process.exit(1); }
console.log('ALL TEST PASS');
