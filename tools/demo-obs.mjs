#!/usr/bin/env node
/*
 * demo-obs.mjs — SevenWork 演示录制用的 OBS WebSocket 控制器
 *
 * 用法（由 tools/demo-sevenwork.ps1 调用）：
 *   node tools/demo-obs.mjs setup  --root <demoRoot> --output <clipsRoot>
 *   node tools/demo-obs.mjs start  --root <demoRoot>
 *   node tools/demo-obs.mjs stop   --root <demoRoot> --chapter <folder>
 *   node tools/demo-obs.mjs teardown --root <demoRoot>
 *
 * 只使用 Node 22 自带的 WebSocket，不引第三方包。
 */

import fs from 'node:fs';
import path from 'node:path';

const WS_URL = process.env.OBS_WS_URL || 'ws://localhost:4456';
const DEMO_SCENE = 'SevenWork Demo';
const DEMO_INPUT = 'SevenWork Display';

function argOf(name, fallback = '') {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const command = () => process.argv[2] || 'status';
const ensureDir = (p) => fs.mkdirSync(p, { recursive: true });

function readJson(file, fallback = null) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJson(file, value) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, JSON.stringify(value, null, 2), 'utf8');
}

class ObsClient {
  constructor(url) {
    this.url = url;
    this.ws = null;
    this.id = 0;
    this.pending = new Map();
    this.closed = false;
  }

  connect() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url);
      this.ws = ws;
      let identified = false;
      ws.addEventListener('error', (e) => {
        if (!identified) reject(new Error('OBS WebSocket 连接失败：' + (e.message || this.url)));
      });
      ws.addEventListener('close', (e) => {
        this.closed = true;
        if (!identified) reject(new Error('OBS WebSocket 已关闭：' + e.code));
        for (const p of this.pending.values()) p.reject(new Error('OBS WebSocket 已关闭'));
        this.pending.clear();
      });
      ws.addEventListener('message', (event) => {
        let msg;
        try { msg = JSON.parse(String(event.data)); } catch { return; }
        if (msg.op === 0) {
          ws.send(JSON.stringify({
            op: 1,
            d: { rpcVersion: msg.d.rpcVersion, eventSubscriptions: 0 },
          }));
          return;
        }
        if (msg.op === 2) {
          identified = true;
          resolve();
          return;
        }
        if (msg.op !== 7) return;
        const pending = this.pending.get(msg.d.requestId);
        if (!pending) return;
        this.pending.delete(msg.d.requestId);
        if (msg.d.requestStatus.result) pending.resolve(msg.d.responseData);
        else {
          const err = new Error(msg.d.requestStatus.comment || 'OBS 请求失败');
          err.requestType = msg.d.requestType;
          err.requestData = pending.data;
          pending.reject(err);
        }
      });
    });
  }

  async request(type, data = {}, timeoutMs = 10000) {
    if (!this.ws || this.closed) throw new Error('OBS 未连接');
    const requestId = String(++this.id);
    const d = { requestType: type, requestId };
    if (data && Object.keys(data).length) d.requestData = data;
    this.ws.send(JSON.stringify({ op: 6, d }));
    return await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(new Error('OBS 请求超时：' + type));
      }, timeoutMs);
      this.pending.set(requestId, {
        data,
        resolve: (v) => { clearTimeout(timer); resolve(v); },
        reject: (e) => { clearTimeout(timer); reject(e); },
      });
    });
  }

  close() {
    try { this.ws?.close(); } catch {}
  }
}

async function removeInputByName(obs, name) {
  const items = await obs.request('GetSceneItemList', { sceneName: DEMO_SCENE });
  for (const item of items.sceneItems || []) {
    if (item.sourceName === name) {
      try { await obs.request('RemoveSceneItem', { sceneName: DEMO_SCENE, sceneItemId: item.sceneItemId }); } catch {}
    }
  }
  try { await obs.request('RemoveInput', { inputName: name }); } catch {}
}

async function probeMonitorId(obs) {
  const probe = 'SevenWork Monitor Probe';
  await removeInputByName(obs, probe);
  await obs.request('CreateInput', {
    sceneName: DEMO_SCENE,
    inputName: probe,
    inputKind: 'monitor_capture',
    sceneItemEnabled: true,
  });
  await new Promise((resolve) => setTimeout(resolve, 500));
  const props = await obs.request('GetInputPropertiesListPropertyItems', {
    inputName: probe,
    propertyName: 'monitor_id',
  });
  const monitor = (props.propertyItems || []).find(
    (i) => i.itemEnabled && i.itemValue && i.itemValue !== 'DUMMY',
  );
  await removeInputByName(obs, probe);
  return monitor?.itemValue || '';
}

async function setVideo(obs, width, height) {
  const attempts = [
    { baseWidth: width, baseHeight: height, outputWidth: width, outputHeight: height,
      fpsNumerator: 60, fpsDenominator: 1 },
    { baseWidth: width, baseHeight: height },
    { outputWidth: width, outputHeight: height },
    { fpsNumerator: 60, fpsDenominator: 1 },
  ];
  let last;
  for (const attempt of attempts) {
    try {
      await obs.request('SetVideoSettings', attempt);
      return;
    } catch (e) { last = e; }
  }
  throw last || new Error('SetVideoSettings 失败');
}

async function setup(obs, root, outputRoot) {
  const stateFile = path.join(root, 'obs-state.json');
  if (readJson(stateFile)?.demoScene) {
    console.log(JSON.stringify({ ok: true, reused: true }));
    return;
  }

  const scenes = await obs.request('GetSceneList');
  const video = await obs.request('GetVideoSettings');
  const recDir = await obs.request('GetRecordDirectory');
  const originalScene = scenes.currentProgramSceneName;

  // 不切 profile：OBS 的 SetCurrentProfile 在部分配置下会拒绝中文 profile 名。
  // 当前 profile 只用于会话；视频设置 / 录制目录会在 teardown 恢复。
  await setVideo(obs, 2560, 1600);

  const rawDir = path.join(root, 'raw');
  ensureDir(rawDir);
  await obs.request('SetRecordDirectory', { recordDirectory: rawDir });

  const sceneNames = scenes.scenes.map((s) => s.sceneName);
  if (!sceneNames.includes(DEMO_SCENE))
    await obs.request('CreateScene', { sceneName: DEMO_SCENE });

  // monitor_capture 的旧参数 monitor:0 在 OBS 32 只表示「未选择」。
  // 先用临时源拿到本机 monitor_id，再带着完整 settings 建正式源；
  // 先建源后 SetInputSettings 会让 sourceWidth 停在 0，录出来全黑。
  const monitorId = await probeMonitorId(obs);
  if (!monitorId) throw new Error('OBS 没有可用的显示器');
  await removeInputByName(obs, DEMO_INPUT);
  await obs.request('CreateInput', {
    sceneName: DEMO_SCENE,
    inputName: DEMO_INPUT,
    inputKind: 'monitor_capture',
    inputSettings: { monitor_id: monitorId, method: 1 },
    sceneItemEnabled: true,
  });

  await obs.request('SetCurrentProgramScene', { sceneName: DEMO_SCENE });
  // 让采集源完成首帧初始化，避免紧接着的截图拿到空源。
  await new Promise((resolve) => setTimeout(resolve, 1500));
  ensureDir(outputRoot);
  writeJson(stateFile, {
    originalScene,
    originalVideo: video,
    originalRecordDir: recDir.recordDirectory,
    demoScene: DEMO_SCENE,
    demoInput: DEMO_INPUT,
    outputRoot,
  });
  console.log(JSON.stringify({ ok: true, scene: DEMO_SCENE, profile: '未命名' }));
}

async function start(obs, root) {
  if (!readJson(path.join(root, 'obs-state.json')))
    throw new Error('没有 obs-state.json，先执行 setup');
  await obs.request('SetCurrentProgramScene', { sceneName: DEMO_SCENE });
  // StopRecord 返回后 OBS 还要把文件写完；下一段紧接着开始时可能仍报
  // "already recording"。先等它真正落盘，再开下一段。
  let status = await obs.request('GetRecordStatus');
  for (let i = 0; status.outputActive && i < 30; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    status = await obs.request('GetRecordStatus');
  }
  if (status.outputActive) throw new Error('OBS 已经在录制');
  await obs.request('StartRecord');
  console.log(JSON.stringify({ ok: true, started: true }));
}

async function stop(obs, root, chapter) {
  const state = readJson(path.join(root, 'obs-state.json'));
  if (!state) throw new Error('没有 obs-state.json');
  const status = await obs.request('GetRecordStatus');
  if (!status.outputActive) {
    console.log(JSON.stringify({ ok: false, reason: 'not-recording' }));
    return;
  }
  const result = await obs.request('StopRecord', {}, 20000);
  const outputPath = result.outputPath || '';
  const targetDir = path.join(state.outputRoot, chapter);
  ensureDir(targetDir);
  let finalPath = '';
  if (outputPath && fs.existsSync(outputPath)) {
    // StopRecord 的响应回来时 OBS 仍可能握着文件句柄：立刻复制会得到 0KB。
    // 等到大小非零且连续稳定 500ms 再搬。
    let lastSize = -1;
    let stable = 0;
    for (let i = 0; i < 100; i += 1) {
      let size = 0;
      try { size = fs.statSync(outputPath).size; } catch {}
      if (size > 0 && size === lastSize) stable += 1;
      else stable = 0;
      lastSize = size;
      if (stable >= 5) break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    const ext = path.extname(outputPath) || '.mkv';
    finalPath = path.join(targetDir, path.basename(outputPath, ext) + ext);
    try { fs.renameSync(outputPath, finalPath); }
    catch {
      fs.copyFileSync(outputPath, finalPath);
      try { fs.unlinkSync(outputPath); } catch {}
    }
  }
  console.log(JSON.stringify({ ok: true, source: outputPath, target: finalPath }));
}


async function cleanup(obs) {
  // 清理开发期可能残留的演示场景 / 输入，并回到用户原来的场景。
  try { await obs.request('SetCurrentProgramScene', { sceneName: 'switch' }); } catch {}
  for (const scene of ['SevenWork Demo', 'SevenWork Diag']) {
    try { await obs.request('RemoveScene', { sceneName: scene }); } catch {}
  }
  for (const input of [DEMO_INPUT, 'SevenWork Diag Color', 'SevenWork Monitor Probe']) {
    try { await obs.request('RemoveInput', { inputName: input }); } catch {}
  }
  console.log(JSON.stringify({ ok: true }));
}

async function snapshot(obs, root, chapter) {
  const state = readJson(path.join(root, 'obs-state.json'));
  if (!state) throw new Error('没有 obs-state.json');
  const targetDir = path.join(state.outputRoot, chapter);
  ensureDir(targetDir);
  const target = path.join(targetDir, 'cover.png');
  await obs.request('SaveSourceScreenshot', {
    sourceName: DEMO_INPUT,
    imageFormat: 'png',
    imageFilePath: target,
    imageWidth: 2560,
    imageHeight: 1600,
  });
  console.log(JSON.stringify({ ok: true, target }));
}

async function teardown(obs, root) {
  const stateFile = path.join(root, 'obs-state.json');
  const state = readJson(stateFile);
  if (!state) return;

  try {
    const status = await obs.request('GetRecordStatus');
    if (status.outputActive) await obs.request('StopRecord', {}, 20000);
  } catch {}
  try { await obs.request('SetCurrentProgramScene', { sceneName: state.originalScene }); } catch {}
  try { await obs.request('RemoveScene', { sceneName: DEMO_SCENE }); } catch {}
  try { await obs.request('RemoveInput', { inputName: DEMO_INPUT }); } catch {}
  try { await obs.request('SetRecordDirectory', { recordDirectory: state.originalRecordDir }); } catch {}
  try { await obs.request('SetVideoSettings', state.originalVideo); } catch {}
  try { fs.unlinkSync(stateFile); } catch {}
  console.log(JSON.stringify({ ok: true }));
}

async function main() {
  const cmd = command();
  const root = argOf('--root', path.join(process.env.TEMP || '.', 'SevenWorkDemo'));
  const outputRoot = argOf('--output', path.join(root, 'clips'));
  const chapter = argOf('--chapter', 'misc');
  const obs = new ObsClient(WS_URL);
  await obs.connect();

  if (cmd === 'setup') await setup(obs, root, outputRoot);
  else if (cmd === 'start') await start(obs, root);
  else if (cmd === 'stop') await stop(obs, root, chapter);
  else if (cmd === 'snapshot') await snapshot(obs, root, chapter);
  else if (cmd === 'cleanup') await cleanup(obs);
  else if (cmd === 'teardown') await teardown(obs, root);
  else {
    const status = await obs.request('GetRecordStatus');
    const video = await obs.request('GetVideoSettings');
    const scene = await obs.request('GetSceneList');
    console.log(JSON.stringify({ status, video, scene: scene.currentProgramSceneName }));
  }
  obs.close();
}

main().catch((e) => {
  console.error(JSON.stringify({
    ok: false,
    error: e.message,
    requestType: e.requestType || '',
    requestData: e.requestData || null,
  }));
  process.exit(1);
});

