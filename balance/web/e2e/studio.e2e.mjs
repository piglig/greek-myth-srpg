// End-to-end check of the whole loop in a real browser (Edge, via playwright-core):
// new variant -> paint heights -> drag a unit -> undo -> edit a stat -> simulate -> heatmap -> replay -> compare.
//
//   engine/bin/srpg.exe studio --no-open        (in another terminal)
//   node e2e/studio.e2e.mjs [screenshot-dir]
import { chromium } from 'playwright-core'
import assert from 'node:assert/strict'

const BASE = process.env.STUDIO_URL ?? 'http://127.0.0.1:8765'
const SHOTS = process.argv[2] ?? '.'
const VARIANT = 'e2e-check'
const api = async (method, path, body) => {
  const r = await fetch(BASE + path, { method, headers: { 'Content-Type': 'application/json', 'X-Actor': 'ai' }, body: body ? JSON.stringify(body) : undefined })
  return r.json()
}
const step = (msg) => console.log(`- ${msg}`)

await api('DELETE', `/api/variants/${VARIANT}`)
const browser = await chromium.launch({ channel: 'msedge', headless: true })
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } })
page.on('pageerror', (e) => { console.error('PAGE ERROR', e.message); process.exitCode = 1 })
const shot = (name) => page.screenshot({ path: `${SHOTS}/e2e-${name}.png` })
/** Screen position of the centre of map cell (x, y). */
const cell = (x, y) => page.evaluate(([cx, cy]) => window.__studioMap.cellToScreen(cx, cy), [x, y])
const drag = async (from, to) => {
  const [ax, ay] = await cell(...from)
  const [bx, by] = await cell(...to)
  await page.mouse.move(ax, ay)
  await page.mouse.down()
  await page.mouse.move((ax + bx) / 2, (ay + by) / 2, { steps: 4 })
  await page.mouse.move(bx, by, { steps: 4 })
  await page.mouse.up()
}
const saved = async () => { await page.waitForTimeout(250); await page.getByText('已保存').waitFor({ timeout: 10_000 }) }
const battle = async () => (await api('GET', `/api/data?variant=${VARIANT}`)).battles['1-4']

try {
  await page.goto(`${BASE}/?mode=level&battle=1-4`)
  await page.locator('.map-svg').waitFor()

  step('create a variant from the header')
  await page.getByRole('button', { name: '新建变体' }).first().click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('名称').fill(VARIANT)
  await dialog.getByRole('button', { name: '新建变体' }).click()
  await dialog.waitFor({ state: 'hidden' })
  await page.getByText('已保存').waitFor()
  await page.waitForTimeout(400)

  step('paint three cells to height 2 with one stroke')
  await page.keyboard.press('h')
  await page.keyboard.press('2')
  await drag([4, 5], [6, 5])
  await saved()
  assert.equal((await battle()).heights[5].slice(4, 7), '222')

  step('drag wolf_3 from (5,1) to (5,2)')
  await page.keyboard.press('v')
  await drag([5, 1], [5, 2])
  await saved()
  assert.deepEqual((await battle()).units.find((u) => u.id === 'wolf_3').pos, [5, 2])
  await shot('level')

  step('undo puts the wolf back')
  await page.keyboard.press('Control+z')
  await saved()
  assert.deepEqual((await battle()).units.find((u) => u.id === 'wolf_3').pos, [5, 1])

  step('an overlap is flagged and blocks simulation')
  await drag([5, 1], [5, 12])
  await saved()
  await page.getByText('wolf_3 与 hero 重叠').waitFor()
  await page.keyboard.press('Control+z')
  await saved()
  await page.getByText('没有问题，可以去模拟。').waitFor()

  step('change a stat in the tables')
  await page.locator('.nav').getByText('数值', { exact: true }).click()
  const hp = page.getByLabel('野狼 生命')
  await hp.fill('15')
  await hp.press('Enter')
  await page.locator('.cell-num.changed').waitFor()
  assert.equal((await api('GET', `/api/data?variant=${VARIANT}`)).units.wolf.hp, 15)
  await shot('tables')

  step('wait for any running simulation, then run 50 novice battles from the UI')
  for (;;) {
    const jobs = await api('GET', '/api/jobs')
    if (!jobs.some((j) => j.status === 'running' || j.status === 'queued')) break
    await page.waitForTimeout(5000)
  }
  await page.locator('.nav').getByText('模拟', { exact: true }).click()
  await page.getByText('熟练机器人', { exact: true }).first().click() // untick skilled
  await page.getByRole('combobox', { name: '每个机器人的局数' }).click()
  await page.getByRole('option', { name: '各 50 局' }).click()
  await page.getByRole('button', { name: '运行模拟' }).click()
  await page.getByText(/已完成 \d+\/50 局|排队中/).first().waitFor({ timeout: 30_000 })
  await shot('sim-running')
  await page.getByText('结果与当前数据一致').waitFor({ timeout: 600_000 })
  await page.getByText('敌人倒下', { exact: true }).click()
  await page.locator('.map-heat').first().waitFor()
  await shot('sim-heat')

  step('replay the first run and step through it')
  await page.locator('.nav').getByText('回放', { exact: true }).click()
  await page.locator('.runs tbody tr').first().click()
  await page.locator('.log li').nth(3).waitFor({ timeout: 120_000 })
  await page.getByRole('button', { name: '下一步' }).click()
  await page.getByRole('button', { name: '下一步' }).click()
  await page.locator('.log li').nth(12).click()
  await shot('replay')

  step('compare lists the baseline and the variant')
  await page.locator('.nav').getByText('对比', { exact: true }).click()
  await page.getByRole('columnheader', { name: new RegExp(VARIANT) }).waitFor()
  await shot('compare')
  console.log('E2E OK')
} catch (err) {
  await shot('failure')
  console.error('E2E FAILED:', err.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await api('DELETE', `/api/variants/${VARIANT}`)
}
