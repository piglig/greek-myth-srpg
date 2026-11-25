import { Button, Menu, Tooltip } from '@mantine/core'
import { IconChevronDown, IconPlayerPlay, IconPlayerStop, IconRefresh } from '@tabler/icons-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Fragment } from 'react'
import { api, type SupportCell, type SupportView } from './api'
import { fail } from './App'
import { BAD, GOOD } from './charts'
import { useStore } from './store'

const KIND: Record<string, string> = { teaching: '教学', intro: '引入', normal: '普通', boss: '首领', side: '支线', late_side: '支线' }
const KIT: Record<string, string> = { typical: '一般配置', frugal: '节俭配置', rich: '富裕配置' }
const BOT: Record<string, string> = { casual: '普通玩家', novice: '新手', skilled: '熟练玩家' }
const MOVE: Record<string, string> = {
  guard: '给同伴护盾', shot: '远处点杀', sunder: '破甲', aid: '挪位并回复', break: '破势', charge: '直线冲锋',
}
const WARN = '#F0B429'
const pct = (v: number) => `${Math.round(v * 100)}%`
const key = (battle: string, support: string) => `${battle}/${support}`

function Cell({ c, band, best, stale, live, name }: { c: SupportCell; band: [number, number]; best: boolean; stale: boolean; live: boolean; name: string }) {
  const inside = c.win >= band[0] - 1e-9 && c.win <= band[1] + 1e-9
  const color = inside ? GOOD : c.usual ? BAD : WARN
  return (
    <Tooltip
      multiline w={280}
      label={`${c.battle} 带${name}：胜率 ${pct(c.win)}（${c.runs} 局），这一关的目标是 ${pct(band[0])}–${pct(band[1])}。平均 ${c.rounds.toFixed(1)} 回合${c.support === 'none' ? '' : `，每场召 ${c.calls.toFixed(1)} 次`}。${c.usual ? '难度就是按带他调的。' : ''}${stale ? '这一关的数据改过了，结果已过期。' : ''}`}
    >
      <div className={`dcell${c.usual ? ' primary' : ''}${stale ? ' stale' : ''}${live ? ' live' : ''}`}>
        <div className="dnum">
          <b style={{ color: c.usual || !inside ? color : undefined }}>{pct(c.win)}</b>
          <span style={{ color: best ? 'var(--gold)' : 'var(--muted)' }}>{best ? '这一关最好' : c.support === 'none' ? '' : `召 ${c.calls.toFixed(1)} 次`}</span>
        </div>
        <div className="track">
          <div className="axis" />
          <div className="band" style={{ left: `${band[0] * 100}%`, width: `${Math.max(1, (band[1] - band[0]) * 100)}%` }} />
          <div className="pt" style={{ left: `${c.win * 100}%`, background: color }} />
        </div>
      </div>
    </Tooltip>
  )
}

export function SupportMode() {
  const s = useStore()
  const qc = useQueryClient()
  const q = useQuery({ queryKey: ['supports', s.variant], queryFn: () => api.supports(s.variant) })
  const v: SupportView | undefined = q.data
  if (q.isError) return <main className="wide"><p className="empty">读取支援对比失败：{(q.error as Error).message}</p></main>
  if (!v) return <main className="wide"><p className="empty">正在读取…</p></main>

  const run = v.run
  const mine = run.running && run.variant === v.variant
  const stored = new Map((v.report?.cells ?? []).map((c) => [key(c.battle, c.support), c]))
  const fresh = new Map((run.variant === v.variant ? run.cells : []).map((c) => [key(c.battle, c.support), c]))
  const cellOf = (battle: string, support: string) => fresh.get(key(battle, support)) ?? stored.get(key(battle, support))
  const isStale = (battle: string) => !fresh.size && !!v.report?.hashes?.[battle] && v.report.hashes[battle] !== v.battles.find((b) => b.id === battle)?.hash
  const columns = [{ id: 'none', name: '不带', opens: 0 }, ...v.heroes.map((h) => ({ id: h.id, name: h.name, opens: h.opens }))]
  const chapters = [...new Set(v.battles.map((b) => b.chapter))]
  const nameOf = (id: string) => columns.find((c) => c.id === id)?.name ?? id

  // Per battle: who is best, and how far apart the best and the worst hero are.
  const spread = (battle: string) => {
    const hired = v.heroes.map((h) => cellOf(battle, h.id)).filter((c): c is SupportCell => !!c)
    if (hired.length < 2) return null
    const top = hired.reduce((a, b) => (b.win > a.win ? b : a))
    const low = hired.reduce((a, b) => (b.win < a.win ? b : a))
    return { top, low, gap: top.win - low.win }
  }
  const spreads = v.battles.map((b) => ({ b, sp: spread(b.id) })).filter((x) => x.sp)
  const widest = spreads.length ? spreads.reduce((a, b) => (b.sp!.gap > a.sp!.gap ? b : a)) : null

  const start = async (scope: string) => {
    try {
      await api.runSupports(s.variant, scope)
      qc.invalidateQueries({ queryKey: ['supports'] })
    } catch (e) { fail(e) }
  }
  const stop = async () => { try { await api.cancelSupports() } catch (e) { fail(e) } }

  return (
    <main className="wide">
      <div className="dhead">
        <div>
          <h2 className="h2">支援对比</h2>
          <p className="lede">
            雇来的英雄不上场，主角召他们出手一次。难度是按出战配置里带的那一位（带金边的格子）调的。这张表把每一关换着带每一位英雄各打一遍：
            看哪位在哪一关最好用，也看会挑人的玩家能比目标轻松多少。每位英雄都按刚雇来时学得起的前两步算。
          </p>
        </div>
        <div className="dactions">
          {mine ? (
            <Button color="red" variant="light" leftSection={<IconPlayerStop size={15} />} onClick={stop}>停止（{run.done}/{run.total || '…'}）</Button>
          ) : (
            <Button.Group>
              <Button leftSection={<IconPlayerPlay size={15} />} disabled={run.running} onClick={() => start('')}>{v.report ? '全部重跑' : '开始对比'}</Button>
              <Menu position="bottom-end" shadow="lg">
                <Menu.Target><Button px={8} disabled={run.running} aria-label="只跑一部分"><IconChevronDown size={15} /></Button></Menu.Target>
                <Menu.Dropdown>
                  <Menu.Label>只跑一章</Menu.Label>
                  {chapters.map((c) => <Menu.Item key={c} onClick={() => start(String(c))}>第 {c} 章</Menu.Item>)}
                </Menu.Dropdown>
              </Menu>
            </Button.Group>
          )}
        </div>
      </div>

      <div className="dsummary">
        {!widest ? (
          <span className="muted">还没有对比过。每格 {v.runs} 局；跑的时候结果一格一格出现。</span>
        ) : (
          <>
            <span>差得最多的是</span>
            <button className="chip" onClick={() => s.set({ battleId: widest.b.id, mode: 'sim' })} title="打开这一关的模拟分析">{widest.b.id}</button>
            <span>带{nameOf(widest.sp!.top.support)} <b className="mono" style={{ color: 'var(--text)' }}>{pct(widest.sp!.top.win)}</b>，带{nameOf(widest.sp!.low.support)} <b className="mono" style={{ color: 'var(--text)' }}>{pct(widest.sp!.low.win)}</b>，相差 <b className="serif" style={{ color: widest.sp!.gap > 0.2 ? WARN : GOOD }}>{Math.round(widest.sp!.gap * 100)} 个点</b></span>
            {v.report && <span className="muted" style={{ marginLeft: 'auto' }}>{v.report.by === 'ai' ? 'AI' : '你'} 于 {v.report.finished.replace('T', ' ')} 跑完</span>}
          </>
        )}
        {run.running && !mine && <span className="muted">「{run.variant}」的对比正在跑（{run.done}/{run.total}）。</span>}
        {!run.running && run.error && run.variant === v.variant && <span style={{ color: BAD }}>上一次对比失败：{run.error}</span>}
      </div>

      <div style={{ overflowX: 'auto' }}>
        <table className="grid-table dtable">
          <thead>
            <tr>
              <th>关卡</th>
              {columns.map((c) => {
                const h = v.heroes.find((x) => x.id === c.id)
                return (
                  <th key={c.id}>
                    {h ? (
                      <Tooltip multiline w={250} label={`「${h.move}」${MOVE[h.kind] ?? ''}：强度 ${h.power}，范围 ${h.range} 格，冷却 ${h.cooldown} 回合。雇金 ${h.fee}，第 ${h.opens} 章起来投。`}>
                        <span>{h.name}</span>
                      </Tooltip>
                    ) : c.name}
                    <small>{h ? `「${h.move}」· ${MOVE[h.kind] ?? h.kind}` : '没有支援'}</small>
                  </th>
                )
              })}
              <th style={{ width: 96 }}>英雄之间<small>最好 − 最差</small></th>
              <th />
            </tr>
          </thead>
          <tbody>
            {chapters.map((ch) => (
              <Fragment key={ch}>
                <tr className="group"><td colSpan={columns.length + 3}>第 {ch} 章</td></tr>
                {v.battles.filter((b) => b.chapter === ch).map((b) => {
                  const sp = spread(b.id)
                  return (
                    <tr key={b.id} className={s.battleId === b.id ? 'current' : ''}>
                      <td className="name">
                        <button className="linklike" onClick={() => s.set({ battleId: b.id, mode: 'sim' })} title="打开这一关的模拟分析">{b.title || b.id}</button>
                        <small>{KIND[b.kind] ?? b.kind}关 · {KIT[b.primary[0]]}的{BOT[b.primary[1]]}{isStale(b.id) ? ' · 已过期' : ''}</small>
                      </td>
                      {columns.map((col) => {
                        const c = cellOf(b.id, col.id)
                        if (col.opens > b.chapter) return <td key={col.id}><div className="dcell none" title="这一章他还没来投">—</div></td>
                        return (
                          <td key={col.id}>
                            {c ? <Cell c={c} band={b.band} best={!!sp && sp.gap > 0.02 && sp.top.support === c.support} stale={isStale(b.id)} live={fresh.has(key(b.id, col.id))} name={col.name} />
                              : <div className="dcell empty-cell">{mine ? '等待中' : '未对比'}</div>}
                          </td>
                        )
                      })}
                      <td>
                        <div className="dcell" style={{ display: 'grid', placeItems: 'center' }}>
                          {sp ? <b className="mono" style={{ fontSize: 15, color: sp.gap > 0.2 ? WARN : 'var(--text-2)' }}>{Math.round(sp.gap * 100)} 点</b> : <span className="muted">—</span>}
                        </div>
                      </td>
                      <td>
                        <Tooltip label={`只重跑 ${b.id}`}>
                          <button className="iconbtn" disabled={run.running} onClick={() => start(b.id)} aria-label={`重跑 ${b.id}`}><IconRefresh size={15} /></button>
                        </Tooltip>
                      </td>
                    </tr>
                  )
                })}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      <p className="empty" style={{ marginTop: 12, maxWidth: '84ch' }}>
        每格的横条是 0–100% 的胜率：蓝色一段是这一关的目标区间，圆点是带这位英雄时的实测。英雄之间差二十个点以上的关标成黄色——差距大说明"带对人"比别的准备都管用，
        也说明按固定一位英雄调出来的难度，对会挑人的玩家偏松。
      </p>
    </main>
  )
}
