// End-to-end check of the two balance pages in a real browser (Edge, via playwright-core):
// difficulty table -> open targets -> rerun one battle -> stop a full run;
// supporter comparison -> rerun one battle -> jump to that battle's simulation page.
//
//   engine/bin/srpg.exe studio --no-open        (in another terminal)
//   node e2e/balance-pages.e2e.mjs [screenshot-dir]
//
// It reruns 1-1 and 2-1 on the baseline, so the stored results for those two battles are
// refreshed; nothing else is changed.
import { chromium } from 'playwright-core'
import assert from 'node:assert/strict'

const BASE = process.env.STUDIO_URL ?? 'http://127.0.0.1:8765'
const SHOTS = process.argv[2] ?? '.'
const api = async (method, path, body) => {
  const r = await fetch(BASE + path, { method, headers: { 'Content-Type': 'application/json', 'X-Actor': 'ai' }, body: body ? JSON.stringify(body) : undefined })
  return r.json()
}
const step = (msg) => console.log(`- ${msg}`)
const idle = async (path, seconds = 240) => {
  const deadline = Date.now() + seconds * 1000
  while (Date.now() < deadline) {
    const { run } = await api('GET', path)
    if (!run.running) return run
    await new Promise((r) => setTimeout(r, 400))
  }
  throw new Error(`${path} never finished`)
}

let browser
for (const channel of ['msedge', 'chrome']) { try { browser = await chromium.launch({ channel, headless: true }); break } catch { /* try the next */ } }
const page = await browser.newPage({ viewport: { width: 1680, height: 1000 } })
page.on('pageerror', (e) => { console.error('PAGE ERROR', e.message); process.exitCode = 1 })
const shot = (name) => page.screenshot({ path: `${SHOTS}/e2e-${name}.png` })

try {
  // ---- difficulty ----
  await page.goto(`${BASE}/?mode=difficulty`)
  await page.getByRole('heading', { name: '难度总表' }).waitFor()
  step('the difficulty page opens from its deep link')
  await page.locator('nav').getByText('难度', { exact: true }).waitFor()

  await page.getByRole('button', { name: '目标区间' }).click()
  await page.getByText('关卡类型').waitFor()
  const bands = await page.locator('.band-btn').count()
  assert.ok(bands >= 10, `target table lists the bands (${bands})`)
  step(`the targets panel opens with ${bands} editable bands`)
  // Open one band's editor and close it without saving: the form is there and nothing is written.
  await page.locator('.band-btn').first().click()
  await page.getByRole('button', { name: '保存目标' }).waitFor()
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: '目标区间' }).click()

  await page.getByRole('button', { name: '重跑 1-1' }).click()
  step('rerun 1-1 from its row')
  const one = await idle('/api/difficulty')
  assert.equal(one.error, '')
  assert.ok(one.cells.length > 0 && one.cells.every((c) => c.battle === '1-1'), 'only 1-1 was rerun')
  await page.locator('tr', { hasText: '1-1' }).locator('.dcell.primary b').first().waitFor()
  const shown = await page.locator('tr', { hasText: '1-1' }).locator('.dcell.primary b').first().innerText()
  assert.match(shown, /^\d+%$/)
  step(`1-1 shows ${shown} in its primary cell`)

  // A full run can be stopped from the page.
  await page.getByRole('button', { name: /全部重跑|开始判定/ }).click()
  await page.getByRole('button', { name: /停止/ }).click()
  const stopped = await idle('/api/difficulty', 60)
  assert.equal(stopped.error, '')
  step(`a full run stops when asked (after ${stopped.cells.length} cells)`)
  await page.getByRole('button', { name: /全部重跑|开始判定/ }).waitFor()
  await shot('difficulty')

  // ---- supporters ----
  await page.locator('nav').getByText('支援', { exact: true }).click()
  await page.getByRole('heading', { name: '支援对比' }).waitFor()
  step('the supporters page opens from the side bar')
  await page.getByRole('button', { name: '重跑 2-1' }).click()
  const sup = await idle('/api/supports')
  assert.equal(sup.error, '')
  assert.ok(sup.cells.length === 5 && sup.cells.every((c) => c.battle === '2-1'), `2-1 with nobody and four heroes (${sup.cells.length})`)
  assert.equal(sup.cells.filter((c) => c.usual).length, 1, 'exactly one hero is the one the difficulty was tuned for')
  const row = page.locator('tr', { hasText: '2-1' })
  await row.locator('.dcell.primary').waitFor()
  assert.equal(await row.locator('.dcell.primary').count(), 1)
  step('2-1 is rerun: five cells, one of them marked as the usual supporter')
  await shot('supports')

  await row.locator('.linklike').click()
  await page.locator('nav button[aria-current="page"]', { hasText: '模拟' }).waitFor()
  assert.ok(page.url().includes('battle=2-1'))
  step('a battle name jumps to that battle on the simulation page')
  console.log('ALL OK')
} catch (e) {
  await shot('failure').catch(() => {})
  console.error('FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
}
