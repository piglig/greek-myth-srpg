import { Button, Menu, NumberInput, Popover, Tooltip } from '@mantine/core'
import { IconChevronDown, IconPlayerPlay, IconPlayerStop, IconRefresh, IconTargetArrow } from '@tabler/icons-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Fragment, useState } from 'react'
import { api, type DifficultyCell, type DifficultyView } from './api'
import { fail } from './App'
import { BAD, GOOD } from './charts'
import { useStore } from './store'

const KIND: Record<string, string> = { teaching: '教学', intro: '引入', normal: '普通', boss: '首领', side: '支线', late_side: '支线' }
const KIND_HELP: Record<string, string> = {
  teaching: '教学关：不该输',
  intro: '每章第一场正式战斗：刚接触新东西，比后面的普通关松一档',
  normal: '普通关',
  boss: '首领关：这一章里最难的一场',
  side: '可选的支线：比同章的普通关略松',
  late_side: '只有没拿到某位同伴的玩家才会遇到的支线，按那种玩家的配置验收',
}
const KIT: Record<string, string> = { typical: '一般配置', frugal: '节俭配置', rich: '富裕配置' }
const KIT_HELP: Record<string, string> = {
  typical: '卖材料、做到一半的可选目标、打可选战的玩家打到这一关时的队伍',
  frugal: '只花通关酬金、不卖战利品、不打可选战的玩家',
  rich: '全拿全卖的玩家',
}
const BOT: Record<string, string> = { casual: '普通玩家', novice: '新手', skilled: '熟练玩家' }
const WARN = '#F0B429'
const pct = (v: number) => `${Math.round(v * 100)}%`
const key = (c: { battle: string; kit: string; bot: string }) => `${c.battle}/${c.kit}/${c.bot}`

/** One cell: the target range as a band on a 0–100% axis, the measured win rate as a dot. */
function Cell({ c, primary, stale, live }: { c: DifficultyCell; primary: boolean; stale: boolean; live: boolean }) {
  const color = c.verdict === 'ok' ? GOOD : primary ? BAD : WARN
  const word = c.verdict === 'ok' ? '达标' : c.verdict === 'easy' ? '偏易' : '偏难'
  return (
    <Tooltip
      multiline w={270}
      label={`${c.battle} · ${KIT[c.kit]} · ${BOT[c.bot]}：胜率 ${pct(c.win)}（${c.runs} 局），目标 ${pct(c.lo)}–${pct(c.hi)}，${word}。平均 ${c.rounds.toFixed(1)} 回合，结束时队伍平均剩 ${pct(c.hp_left)} 生命${c.timeouts > 0.005 ? `，${pct(c.timeouts)} 的局打到回合上限` : ''}。${stale ? '这一关的数据改过了，结果已过期。' : ''}`}
    >
      <div className={`dcell${primary ? ' primary' : ''}${stale ? ' stale' : ''}${live ? ' live' : ''}`}>
        <div className="dnum">
          <b style={{ color: primary || c.verdict !== 'ok' ? color : undefined }}>{pct(c.win)}</b>
          <span style={{ color }}>{c.verdict === 'easy' ? '偏易 ↑' : c.verdict === 'hard' ? '偏难 ↓' : '达标'}</span>
        </div>
        <div className="track">
          <div className="axis" />
          <div className="band" style={{ left: `${c.lo * 100}%`, width: `${Math.max(1, (c.hi - c.lo) * 100)}%` }} />
          <div className="pt" style={{ left: `${c.win * 100}%`, background: color }} />
        </div>
        {primary && <div className="dsub">{c.rounds.toFixed(1)} 回合 · 剩 {pct(c.hp_left)} 生命</div>}
      </div>
    </Tooltip>
  )
}

function BandEditor({ kind, kit, bot, band }: { kind: string; kit: string; bot: string; band: [number, number] }) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [lo, setLo] = useState<number>(Math.round(band[0] * 100))
  const [hi, setHi] = useState<number>(Math.round(band[1] * 100))
  const save = async () => {
    try {
      await api.setDifficultyBand(kind, kit, bot, lo / 100, hi / 100)
      setOpen(false)
      qc.invalidateQueries({ queryKey: ['difficulty'] })
    } catch (e) { fail(e) }
  }
  return (
    <Popover opened={open} onChange={setOpen} position="bottom" withArrow shadow="lg" width={250}>
      <Popover.Target>
        <button className="band-btn mono" onClick={() => { setLo(Math.round(band[0] * 100)); setHi(Math.round(band[1] * 100)); setOpen(!open) }} title="改这一格的目标区间">
          {pct(band[0])}–{pct(band[1])}
        </button>
      </Popover.Target>
      <Popover.Dropdown>
        <p className="empty" style={{ marginBottom: 10 }}>{KIND[kind]}关 · {KIT[kit]} · {BOT[bot]} 的目标胜率。改完后已有结果按新区间重新判定，不用重跑。</p>
        <div className="two">
          <NumberInput size="xs" label="下限 %" min={0} max={100} value={lo} onChange={(v) => setLo(Number(v) || 0)} />
          <NumberInput size="xs" label="上限 %" min={0} max={100} value={hi} onChange={(v) => setHi(Number(v) || 0)} />
        </div>
        <Button size="xs" fullWidth mt={12} onClick={save} disabled={lo > hi}>保存目标</Button>
      </Popover.Dropdown>
    </Popover>
  )
}

export function DifficultyMode() {
  const s = useStore()
  const qc = useQueryClient()
  const q = useQuery({ queryKey: ['difficulty', s.variant], queryFn: () => api.difficulty(s.variant) })
  const [showTargets, setShowTargets] = useState(false)
  const v: DifficultyView | undefined = q.data
  if (q.isError) return <main className="wide"><p className="empty">读取难度总表失败：{(q.error as Error).message}</p></main>
  if (!v) return <main className="wide"><p className="empty">正在读取…</p></main>

  const run = v.run
  const mine = run.running && run.variant === v.variant
  const stored = new Map((v.report?.cells ?? []).map((c) => [key(c), c]))
  const fresh = new Map((run.variant === v.variant ? run.cells : []).map((c) => [key(c), c]))
  const cellOf = (battle: string, kit: string, bot: string) => fresh.get(`${battle}/${kit}/${bot}`) ?? stored.get(`${battle}/${kit}/${bot}`)
  const isStale = (battle: string) => !fresh.size && !!v.report?.hashes?.[battle] && v.report.hashes[battle] !== v.battles.find((b) => b.id === battle)?.hash
  const chapters = [...new Set(v.battles.map((b) => b.chapter))]
  const primaries = v.battles.map((b) => ({ b, c: cellOf(b.id, b.primary[0], b.primary[1]) }))
  const judged = primaries.filter((p) => p.c)
  const passed = judged.filter((p) => p.c!.verdict === 'ok').length
  const anyStale = v.battles.some((b) => isStale(b.id))
  const KIND_ORDER = ['teaching', 'intro', 'normal', 'boss', 'side', 'late_side']
  const kinds = Object.keys(v.spec.bands).sort((a, b) => (KIND_ORDER.indexOf(a) + 99) % 99 - (KIND_ORDER.indexOf(b) + 99) % 99)

  const start = async (scope: string) => {
    try {
      await api.runDifficulty(s.variant, scope)
      qc.invalidateQueries({ queryKey: ['difficulty'] })
    } catch (e) { fail(e) }
  }
  const stop = async () => { try { await api.cancelDifficulty() } catch (e) { fail(e) } }

  return (
    <main className="wide">
      <div className="dhead">
        <div>
          <h2 className="h2">难度总表</h2>
          <p className="lede">
            每一关，用玩家打到那里时该有的队伍去打，看胜率落不落在目标区间里。主要看带金边的那一格——{KIT[v.spec.primary[0]]}的{BOT[v.spec.primary[1]]}；
            其余几格用来看两头：熟练的会不会毫无压力，不花钱的还能不能走。
          </p>
        </div>
        <div className="dactions">
          {mine ? (
            <Button color="red" variant="light" leftSection={<IconPlayerStop size={15} />} onClick={stop}>停止（{run.done}/{run.total || '…'}）</Button>
          ) : (
            <Button.Group>
              <Button leftSection={<IconPlayerPlay size={15} />} disabled={run.running} onClick={() => start('')}>{v.report ? '全部重跑' : '开始判定'}</Button>
              <Menu position="bottom-end" shadow="lg">
                <Menu.Target><Button px={8} disabled={run.running} aria-label="只跑一部分"><IconChevronDown size={15} /></Button></Menu.Target>
                <Menu.Dropdown>
                  <Menu.Label>只跑一章</Menu.Label>
                  {chapters.map((c) => <Menu.Item key={c} onClick={() => start(String(c))}>第 {c} 章</Menu.Item>)}
                </Menu.Dropdown>
              </Menu>
            </Button.Group>
          )}
          <Button variant={showTargets ? 'light' : 'default'} leftSection={<IconTargetArrow size={15} />} onClick={() => setShowTargets(!showTargets)}>目标区间</Button>
        </div>
      </div>

      <div className="dsummary">
        {judged.length === 0 ? (
          <span className="muted">还没有判定过。每格 {v.spec.runs} 局，全部跑完要几分钟；跑的时候结果一格一格出现。</span>
        ) : (
          <>
            <b className="serif" style={{ color: passed === judged.length ? GOOD : BAD }}>{passed} / {judged.length}</b>
            <span>关的主要验收格达标</span>
            {primaries.filter((p) => p.c && p.c.verdict !== 'ok').map((p) => (
              <button key={p.b.id} className="chip" onClick={() => s.set({ battleId: p.b.id, mode: 'sim' })} title="打开这一关的模拟分析">
                {p.b.id} {p.c!.verdict === 'easy' ? '偏易' : '偏难'} <span className="mono">{pct(p.c!.win)}</span>
              </button>
            ))}
            {v.report && <span className="muted" style={{ marginLeft: 'auto' }}>{v.report.by === 'ai' ? 'AI' : '你'} 于 {v.report.finished.replace('T', ' ')} 跑完{anyStale ? ' · 有的关之后改过数据' : ''}</span>}
          </>
        )}
        {run.running && !mine && <span className="muted">「{run.variant}」的判定正在跑（{run.done}/{run.total}），结束后才能开始新的。</span>}
        {!run.running && run.error && run.variant === v.variant && <span style={{ color: BAD }}>上一次判定失败：{run.error}</span>}
      </div>

      {showTargets && (
        <div style={{ overflowX: 'auto', marginBottom: 22 }}>
          <table className="grid-table cmp">
            <thead>
              <tr><th>关卡类型</th>{v.columns.map(([kit, bot]) => <th key={kit + bot}>{KIT[kit]} · {BOT[bot]}</th>)}</tr>
            </thead>
            <tbody>
              {kinds.map((kind) => (
                <tr key={kind}>
                  <td className="name">{KIND[kind] ?? kind}关<small>{(v.spec.kinds[kind] ?? []).join('、') || '其余各关'}</small></td>
                  {v.columns.map(([kit, bot]) => {
                    const band = v.spec.bands[kind]?.[kit]?.[bot]
                    return <td key={kit + bot} className="v">{band ? <BandEditor kind={kind} kit={kit} bot={bot} band={band} /> : <span className="muted">—</span>}</td>
                  })}
                </tr>
              ))}
            </tbody>
          </table>
          <p className="empty" style={{ marginTop: 8 }}>点一格的数字改目标。目标写在 balance/difficulty.yaml，命令行的 srpg difficulty 用的是同一份。</p>
        </div>
      )}

      <div style={{ overflowX: 'auto' }}>
        <table className="grid-table dtable">
          <thead>
            <tr>
              <th>关卡</th>
              {v.columns.map(([kit, bot]) => (
                <th key={kit + bot} className={kit === v.spec.primary[0] && bot === v.spec.primary[1] ? 'primary' : ''}>
                  <Tooltip label={KIT_HELP[kit]} multiline w={240}><span>{KIT[kit]}</span></Tooltip>
                  <small>{BOT[bot]}</small>
                </th>
              ))}
              <th />
            </tr>
          </thead>
          <tbody>
            {chapters.map((ch) => (
              <Fragment key={ch}>
                <tr className="group"><td colSpan={v.columns.length + 2}>第 {ch} 章</td></tr>
                {v.battles.filter((b) => b.chapter === ch).map((b) => (
                  <tr key={b.id} className={s.battleId === b.id ? 'current' : ''}>
                    <td className="name">
                      <button className="linklike" onClick={() => s.set({ battleId: b.id, mode: 'sim' })} title="打开这一关的模拟分析">{b.title || b.id}</button>
                      <small><Tooltip label={KIND_HELP[b.kind]} multiline w={240}><span>{KIND[b.kind] ?? b.kind}关</span></Tooltip>{isStale(b.id) ? ' · 已过期' : ''}</small>
                    </td>
                    {v.columns.map(([kit, bot]) => {
                      const c = cellOf(b.id, kit, bot)
                      const has = !!v.spec.bands[b.kind]?.[kit]?.[bot]
                      const primary = b.primary[0] === kit && b.primary[1] === bot
                      return (
                        <td key={kit + bot}>
                          {c ? <Cell c={c} primary={primary} stale={isStale(b.id)} live={fresh.has(key(c))} />
                            : has ? <div className={`dcell empty-cell${primary ? ' primary' : ''}`}>{mine ? '等待中' : '未判定'}</div>
                            : <div className="dcell none" title="这类关卡不看这一格">—</div>}
                        </td>
                      )
                    })}
                    <td>
                      <Tooltip label={`只重跑 ${b.id}`}>
                        <button className="iconbtn" disabled={run.running} onClick={() => start(b.id)} aria-label={`重跑 ${b.id}`}><IconRefresh size={15} /></button>
                      </Tooltip>
                    </td>
                  </tr>
                ))}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      <p className="empty" style={{ marginTop: 12, maxWidth: '80ch' }}>
        每格的横条是 0–100% 的胜率：蓝色一段是目标区间，圆点是实测。机器人不会学习，每一局都是第一次打；真人输过一次会换打法，实际会比这里的数字好打一些。
      </p>
    </main>
  )
}
