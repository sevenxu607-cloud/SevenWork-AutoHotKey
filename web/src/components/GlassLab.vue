<script setup lang="ts">
/* ═══════════════════════════════════════════════════════════════════════
   GlassLab.vue —— 材质样板（S0）
   · 目的：在浏览器里把「琉璃 · 极光霜」的六层材质立起来，验收后再推广。
   · 不接 AHK、不读写任何状态 —— 纯静态页，`?view=lab` 进入。
   · 调参栏的三档 + 五个滑杆，是把「材质语言」定型的工具：
     调到你满意，把右下角 JSON 抄给开发写死成主题默认值。
   ═══════════════════════════════════════════════════════════════════════ */
import { computed, ref } from 'vue'

type Tier = 'soft' | 'mid' | 'deep'

/* 三档预设。数值只落在**材质参数**上，不碰色板 —— 色板归 ThemeService。
   ⚠ 三档都必须清透：白层过 0.06 就从"琉璃"掉成"乳白磨砂塑料"（实测过）。 */
const TIERS: Record<Tier, Record<string, number>> = {
  soft: { blur: 14, sat: 135, tint: 0.03, edge: 0.4, frost: 0.02, spec: 0.7 },
  mid: { blur: 22, sat: 150, tint: 0.045, edge: 0.7, frost: 0.035, spec: 1 },
  deep: { blur: 34, sat: 175, tint: 0.075, edge: 0.95, frost: 0.055, spec: 1.2 },
}

const tier = ref<Tier>('mid')
const blur = ref(22) // 玻璃模糊半径 px
const sat = ref(150) // 饱和度增益 %
const tint = ref(0.045) // 白层浓度（玻璃有多“白”）
const edge = ref(0.7) // 冰棱亮度
const frost = ref(0.035) // 霜（噪点）强度
const spec = ref(1) // 反光强度

function applyTier(t: Tier) {
  tier.value = t
  const v = TIERS[t]
  blur.value = v.blur
  sat.value = v.sat
  tint.value = v.tint
  edge.value = v.edge
  frost.value = v.frost
  spec.value = v.spec
}

/* 参数全部落到 .lab 的 CSS 变量上，靠继承传给每一块 .gl ——
   ⚠ 不要在 .gl 上再写一组同名变量，那会盖掉内联值、滑杆就“拖动没反应”。 */
const labStyle = computed(() => ({
  '--g-blur': `${blur.value}px`,
  '--g-sat': `${sat.value}%`,
  '--g-tint': String(tint.value),
  '--g-edge': String(edge.value),
  '--g-spec': String(spec.value),
  '--lab-frost': String(frost.value),
}))

/* specular：只有主玻璃板跟鼠标。坐标写成百分比，radial-gradient 按自身尺寸取。 */
const heroEl = ref<HTMLElement>()

function onHeroMove(e: PointerEvent) {
  const el = heroEl.value
  if (!el) return
  const r = el.getBoundingClientRect()
  el.style.setProperty('--spec-x', `${((e.clientX - r.left) / r.width) * 100}%`)
  el.style.setProperty('--spec-y', `${((e.clientY - r.top) / r.height) * 100}%`)
}

/* 定型用：把当前参数吐成一行 JSON，直接抄进 ThemeService 的 material 字段 */
const dump = computed(() =>
  JSON.stringify({
    tier: tier.value,
    blur: blur.value,
    sat: sat.value,
    tint: Number(tint.value.toFixed(3)),
    edge: Number(edge.value.toFixed(2)),
    frost: Number(frost.value.toFixed(3)),
    spec: Number(spec.value.toFixed(2)),
  }),
)

/* 面板预演用的假数据：就是 Alt+S 面板未来的长相 */
const navItems = [
  { name: '全部热键', n: 42 },
  { name: '笔记', n: 27 },
  { name: '键位', n: 1 },
  { name: '外部程序', n: 2 },
  { name: '文件夹', n: 3 },
  { name: '文本', n: 7 },
]
const hotkeys = [
  { g: '笔记', k: 'Alt+Z', line: '呼出 / 收起笔记窗口' },
  { g: '笔记', k: 'Alt+1..5', line: '打开对应文件夹槽位' },
  { g: '平台', k: 'Alt+S', line: '打开设置面板' },
  { g: '平台', k: 'Alt+T', line: '切换主题' },
  { g: '文本', k: 'Alt+P', line: '提示词库' },
]

/* ── 约定 ────────────────────────────────────────────────────────────────
   sliders 用 v-model.number 直接绑 ref：range 不会产生 NaN，无需守卫；
   所有材质数值只在这一处定义，调完把右侧 JSON 抄走即可。 */
</script>

<template>
  <div class="lab" :style="labStyle">
    <!-- ① 光雾：5 个独立光团（容器统一模糊）。不在最底层铺光，上面所有玻璃都无从谈起。 -->
    <div class="lab__aurora">
      <span
        class="lab__orb"
        style="--c: var(--lab-teal); width: 72vmin; height: 72vmin; left: -8vmin; top: -12vmin; --dur: 44s; --dx: 5vmin; --dy: 4vmin"
      />
      <span
        class="lab__orb"
        style="--c: var(--lab-indigo); width: 64vmin; height: 64vmin; right: -10vmin; top: -6vmin; opacity: 0.85; --dur: 58s; --delay: -11s; --dx: -6vmin; --dy: 5vmin"
      />
      <span
        class="lab__orb"
        style="--c: var(--lab-ice); width: 60vmin; height: 60vmin; right: 0; bottom: -12vmin; --dur: 51s; --delay: -23s; --dx: 4vmin; --dy: -6vmin"
      />
      <span
        class="lab__orb"
        style="--c: var(--lab-violet); width: 54vmin; height: 54vmin; left: -4vmin; bottom: -14vmin; opacity: 0.8; --dur: 66s; --delay: -31s; --dx: -5vmin; --dy: -4vmin"
      />
      <span
        class="lab__orb"
        style="--c: var(--lab-warm); width: 30vmin; height: 30vmin; left: 44%; top: 4%; opacity: 0.45; --dur: 72s; --delay: -16s; --dx: 3vmin; --dy: 7vmin"
      />
    </div>


    <header class="gl gl--fixed lab__bar">
      <strong style="font-size: 14px">SevenWork · 材质样板</strong>
      <span class="lab__k" style="margin: 0">S0 · 只验观感，不接 AHK</span>
      <span class="lab__k" style="margin-left: auto">拖动右侧滑杆调参</span>
    </header>

    <div class="lab__wrap">
      <div class="lab__col">
        <!-- ③④⑤⑥ 主玻璃板：这块就是「材质」的全部证据 -->
        <section ref="heroEl" class="gl lab__hero" @pointermove="onHeroMove">
          <h2 class="lab__title">琉璃 · 极光霜</h2>
          <p class="lab__sub">
            这不是一块深色矩形。底下是缓慢漂移的光雾，板面把它冻住；边缘走着一圈冰棱；
            表面浮着一层霜；鼠标划过会亮。六层里少任何一层，就会掉回「换了个颜色」。
          </p>

          <div style="display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 14px">
            <button class="gl-btn gl-btn--primary">主按钮</button>
            <button class="gl-btn">次按钮</button>
            <button class="gl-btn gl-btn--on">选中态</button>
          </div>

          <input class="gl-input" placeholder="在玻璃上打字 —— 看字会不会被光吃掉" />

          <div class="gl lab__nest" style="margin-top: 16px">
            <p class="lab__h" style="margin-bottom: 6px">嵌套玻璃</p>
            <p class="lab__note" style="margin: 0">
              backdrop-filter 在板内再糊一层、比外层更浓 —— 层叠感来自这里，不是靠把颜色加深。
            </p>
          </div>
        </section>

        <!-- 要素卡片：把「六层」点名，验收时逐条对 -->
        <div class="lab__grid">
          <div class="gl gl--fixed lab__card">
            <p class="lab__k">① 光雾</p>
            <p class="lab__v">48s / 67s 反向漂移</p>
            <p class="lab__note">青 · 靛 · 冰蓝 · 紫 + 一点暖橙</p>
          </div>
          <div class="gl gl--fixed lab__card">
            <p class="lab__k">② 霜</p>
            <p class="lab__v">feTurbulence · overlay</p>
            <p class="lab__note">铺在玻璃之上，放底层只是脏</p>
          </div>
          <div class="gl gl--fixed lab__card">
            <p class="lab__k">③ 玻璃</p>
            <p class="lab__v">blur + saturate + 白层</p>
            <p class="lab__note">三段渐变白层，不是平铺一个 rgba</p>
          </div>
          <div class="gl gl--fixed lab__card">
            <p class="lab__k">④ 厚度</p>
            <p class="lab__v">上沿反光 · 下沿落影</p>
            <p class="lab__note">成对 1px 内阴影 + 三层投影</p>
          </div>
          <div class="gl gl--fixed lab__card">
            <p class="lab__k">⑤ 冰棱</p>
            <p class="lab__v">conic-gradient 渐变边</p>
            <p class="lab__note">mask 挖空中心；border-image 不吃圆角</p>
          </div>
          <div class="gl gl--fixed lab__card">
            <p class="lab__k">⑥ 反光</p>
            <p class="lab__v">plus-lighter 加光</p>
            <p class="lab__note">鼠标坐标驱动，不是贴一张高光图</p>
          </div>
        </div>

        <!-- 面板预演：这就是 Alt+S 未来的长相（现在还是 AHK 原生 ListView） -->
        <section class="gl gl--fixed lab__card">
          <p class="lab__h">面板预演 · 将来 Alt+S 的样子</p>
          <div class="lab__preview">
            <div class="lab__preview-nav">
              <div
                v-for="(it, i) in navItems"
                :key="it.name"
                class="gl-row"
                :class="{ 'is-on': i === 0 }"
              >
                <span>{{ it.name }}</span>
                <span class="gl-row__tag">{{ it.n }}</span>
              </div>
            </div>
            <div class="lab__preview-list">
              <div v-for="h in hotkeys" :key="h.k" class="gl-row">
                <span class="gl-row__tag" style="margin: 0">{{ h.g }}</span>
                <span class="lab__key">{{ h.k }}</span>
                <span>{{ h.line }}</span>
              </div>
            </div>
          </div>
          <p class="lab__note">
            左侧导航的选中态用「发光」不用「加深」—— 在玻璃上加深色会被看成挖了个洞。
          </p>
        </section>
      </div>

      <!-- 调参栏：把材质语言调到这里为止 -->
      <aside class="gl gl--fixed lab__tune">
        <p class="lab__h">材质参数</p>

        <div class="lab__tiers">
          <button
            v-for="t in ['soft', 'mid', 'deep'] as Tier[]"
            :key="t"
            class="gl-btn"
            :class="{ 'gl-btn--on': tier === t }"
            @click="applyTier(t)"
          >
            {{ t === 'soft' ? '柔和' : t === 'mid' ? '适中' : '浓烈' }}
          </button>
        </div>

        <label class="lab__slider">
          <span>模糊 <b>{{ blur }}px</b></span>
          <input v-model.number="blur" type="range" min="0" max="64" step="1" />
        </label>
        <label class="lab__slider">
          <span>饱和度 <b>{{ sat }}%</b></span>
          <input v-model.number="sat" type="range" min="100" max="280" step="5" />
        </label>
        <label class="lab__slider">
          <span>白层 <b>{{ tint.toFixed(3) }}</b></span>
          <input v-model.number="tint" type="range" min="0" max="0.26" step="0.005" />
        </label>
        <label class="lab__slider">
          <span>霜 <b>{{ frost.toFixed(3) }}</b></span>
          <input v-model.number="frost" type="range" min="0" max="0.2" step="0.005" />
        </label>
        <label class="lab__slider">
          <span>冰棱 <b>{{ edge.toFixed(2) }}</b></span>
          <input v-model.number="edge" type="range" min="0" max="1.2" step="0.02" />
        </label>
        <label class="lab__slider">
          <span>反光 <b>{{ spec.toFixed(2) }}</b></span>
          <input v-model.number="spec" type="range" min="0" max="2" step="0.05" />
        </label>

        <p class="lab__k" style="margin: 16px 0 0">定型结论（复制给开发）</p>
        <textarea class="lab__dump" readonly :value="dump" />
      </aside>
    </div>

    <!-- ② 霜：铺在最上层，覆盖整块玻璃表面。z-index 高于一切内容。 -->
    <div class="lab__grain" />
  </div>
</template>

<!-- 材质样板的全套材质规则：只在 `?view=lab` 时随本组件异步加载。
     ⚠ 别搬回 style.css —— 那是生产页面的主样式表，lab 的三百行只服务开发验收。 -->
<style src="../theme/lab.css"></style>

<style scoped>
/* 只放「结构」不放进 lab.css 的少数布局钩子，材质一律在 lab.css */
.lab__preview {
  display: grid;
  grid-template-columns: 196px minmax(0, 1fr);
  gap: 14px;
}

.lab__preview-nav,
.lab__preview-list {
  display: grid;
  gap: 2px;
  align-content: start;
}

.lab__key {
  min-width: 84px;
  font-family: 'Cascadia Mono', Consolas, monospace;
  font-size: 12px;
  color: rgba(242 242 242 / 0.86);
}

@media (max-width: 620px) {
  .lab__preview {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>


