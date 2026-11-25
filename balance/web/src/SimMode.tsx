import { Button, Chip, NumberInput, SegmentedControl, Select } from '@mantine/core'
import { IconPlayerPlay, IconPlayerStop } from '@tabler/icons-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { api, type BotResult, type Results, type StudioData, type Verdict } from './api'
import { fail } from './App'
import { BAD, fmt, GOOD, HBars, Histogram, NEUTRAL, RangeTrack, SERIES, Status } from './charts'
import { toMapUnits } from './LevelMode'
import { MapView } from './MapView'
import { useStore, type HeatLayer } from './store'

const HEAT: Record<Exclude<HeatLayer, 'none'>, { label: string; color: string; unit: string; help: string }> = {
  kills: { label: '敌人倒下', color: '#F0616D', unit: '倒下次数', help: '所有模拟局里，敌人在每一格倒下的总次数' },
  falls: { label: '敌人坠落', color: '#5B8DEF', unit: '被推落次数', help: '敌人是从哪一格被推下去的' },
  dmg: { label: '我方受伤', color: '#F0B429', unit: '每局受到伤害', help: '我方单位站在每一格时，平均每局受到的伤害' },
}
const FRESH: Record<string, string> = {
  fresh: '结果与当前数据一致',
  stale: '数据已改动，结果过期',
  unknown: '旧结果，无法确认是否对应当前数据',
  none: '还没有模拟',
}

function Verdicts({ results, battle }: { results: Results; battle: string }) {
  const qc = useQueryClient()
  const [editing, setEditing] = useState(false)
  const [ranges, setRanges] = useState<Record<string, [number, number]>>({})
  const bots = [...new Set(results.verdicts.map((v) => v.bot))]
  const judged = results.verdicts.filter((v) => v.target)
  const passed = judged.filter((v) => v.status === 'PASS').length
  const key = (v: Verdict) => `${v.bot}/${v.metric}`
  const begin = () => {
    setRanges(Object.fromEntries(results.verdicts.filter((v) => v.target).map((v) => [key(v), v.target!])))
    setEditing(true)
  }
  const save = async () => {
    const spec: any = { battle, runs_min: results.runs_min, bots: {} }
    for (const v of results.verdicts) {
      const r = ranges[key(v)]
      if (!r) continue
      const old = results.targets?.bots?.[v.bot]?.[v.metric]
      spec.bots[v.bot] ??= {}
      spec.bots[v.bot][v.metric] = old && !Array.isArray(old) ? { ...old, range: r } : r
    }
    try { await api.saveTargets(battle, spec); setEditing(false); qc.invalidateQueries({ queryKey: ['results'] }); qc.invalidateQueries({ queryKey: ['compare'] }) } catch (e) { fail(e) }
  }
  const scale = (v: Verdict) => (v.pct ? 100 : 1)
  return (
    <div className="section">
      <h3>
        设计目标
        {judged.length > 0 && <span className="count">{passed}/{judged.length} 达标</span>}
        <span style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
          {editing ? (
            <>
              <Button size="compact-xs" variant="default" onClick={() => setEditing(false)}>取消</Button>
              <Button size="compact-xs" onClick={save}>保存目标</Button>
            </>
          ) : <Button size="compact-xs" variant="default" onClick={begin}>修改目标</Button>}
        </span>
      </h3>
      {judged.some((v) => v.value !== null) && (
        <div className="score">
          <div className="pass"><b>{passed}</b><small>达标</small></div>
          <div className="edge"><b>{judged.filter((v) => v.status === 'INCONCLUSIVE').length}</b><small>贴边，无法确认</small></div>
          <div className="fail"><b>{judged.filter((v) => v.status === 'FAIL' || v.status === 'KNOWN').length}</b><small>未达标</small></div>
        </div>
      )}
      {results.verdicts.length === 0 && <p className="empty" style={{ margin: 0 }}>运行一次模拟后，这里会列出每个指标的实测值。</p>}
      {bots.map((bot) => (
        <div key={bot} className="verdicts" style={{ marginBottom: 12 }}>
          <div className="vrow head"><b>{results.bots[bot]?.label ?? bot}</b><span>{editing ? '目标范围' : '带 = 目标 · 点 = 实测'}</span><span style={{ textAlign: 'right' }}>实测</span><span /></div>
          {results.verdicts.filter((v) => v.bot === bot).map((v) => (
            <div key={v.metric} className="vrow">
              <span>{v.label}</span>
              {editing ? (
                <div className="range-edit">
                  <NumberInput size="xs" w={78} hideControls placeholder="下限" suffix={v.pct ? '%' : ''} value={ranges[key(v)] ? ranges[key(v)][0] * scale(v) : ''}
                    onChange={(n) => setRanges((r) => (n === '' ? (({ [key(v)]: _, ...rest }) => rest)(r) : { ...r, [key(v)]: [Number(n) / scale(v), r[key(v)]?.[1] ?? (v.pct ? 1 : Number(n))] }))} />
                  <span className="muted">至</span>
                  <NumberInput size="xs" w={78} hideControls placeholder="上限" suffix={v.pct ? '%' : ''} value={ranges[key(v)] ? ranges[key(v)][1] * scale(v) : ''}
                    onChange={(n) => setRanges((r) => (n === '' ? r : { ...r, [key(v)]: [r[key(v)]?.[0] ?? 0, Number(n) / scale(v)] }))} />
                </div>
              ) : <RangeTrack v={v} />}
              <span className="val">{fmt(v.value, v.pct)}<small>{v.lo !== null ? `${fmt(v.lo, v.pct)}–${fmt(v.hi, v.pct)}` : ''}</small></span>
              <Status status={v.status} />
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}

function Detail({ r }: { r: BotResult }) {
  const n = r.runs ?? 0
  return (
    <>
      <div className="section">
        <h3>战斗结果<span className="count">{n} 局</span></h3>
        <HBars
          rows={(r.outcomes ?? []).filter((o) => o.count > 0 || o.key === 'win').map((o) => ({
            key: o.key, label: o.label, value: o.share, text: `${Math.round(o.share * 100)}%`,
            color: o.key === 'win' ? GOOD : o.key === 'timeout' ? NEUTRAL : BAD,
            tip: `${o.label}：${o.count}/${n} 局，95% 区间 ${Math.round(o.lo * 100)}%–${Math.round(o.hi * 100)}%`,
          }))}
          max={1}
        />
      </div>
      <div className="section">
        <h3>战斗长度<span className="count">结束时的回合数</span></h3>
        <Histogram
          series={[{ name: '胜利', color: GOOD }, { name: '失败', color: BAD }]}
          cols={(r.rounds ?? []).map((c) => ({ label: String(c.rounds), values: [c.win, c.loss], tip: `第 ${c.rounds} 回合结束：胜 ${c.win} 局，负 ${c.loss} 局` }))}
        />
        <div className="chart" style={{ marginTop: 16 }}>
          <h4>胜局结束时我方剩余生命<small>占总生命的比例</small></h4>
          <Histogram
            series={[{ name: '胜局', color: GOOD }]}
            cols={(r.hp ?? []).map((c) => ({ label: `${Math.round(c.from * 100)}`, values: [c.count], tip: `剩余 ${Math.round(c.from * 100)}%–${Math.round(c.to * 100)}%：${c.count} 局` }))}
          />
        </div>
      </div>
      <div className="section">
        <h3>谁在输出<span className="count">占我方总伤害</span></h3>
        <HBars
          rows={(r.damage ?? []).map((d, i) => ({
            key: d.def, label: d.name, value: d.share, text: `${Math.round(d.share * 100)}%`, color: SERIES[i % SERIES.length],
            tip: `${d.name}：每局造成 ${d.dealt.toFixed(1)}，受到 ${d.taken.toFixed(1)}`,
          }))}
          max={Math.max(0.5, ...(r.damage ?? []).map((d) => d.share))}
        />
        <div className="chart" style={{ marginTop: 16 }}>
          <h4>对敌伤害来源<small>每局平均</small></h4>
          <HBars rows={(r.sources ?? []).slice(0, 10).map((x) => ({ key: x.key, label: x.label, value: x.per_battle, text: x.per_battle.toFixed(1), tip: `${x.label}：每局 ${x.per_battle.toFixed(1)} 点，占 ${Math.round(x.share * 100)}%` }))} />
        </div>
      </div>
      <div className="section">
        <h3>机制使用<span className="count">用到它的战斗比例</span></h3>
        <HBars
          rows={(r.mechanics ?? []).filter((m) => m.per_battle > 0).map((m) => ({ key: m.key, label: m.label, value: m.battles, text: `${Math.round(m.battles * 100)}%`, tip: `${m.label}：${Math.round(m.battles * 100)}% 的战斗用到，平均每局 ${m.per_battle.toFixed(1)} 次` }))}
          max={1} color={SERIES[1]}
        />
      </div>
    </>
  )
}

export function SimMode({ data }: { data: StudioData }) {
  const s = useStore()
  const qc = useQueryClient()
  const battle = data.battles[s.battleId]
  const results = useQuery({ queryKey: ['results', s.battleId, s.variant], queryFn: () => api.results(s.battleId, s.variant), enabled: !!battle })
  const jobs = useQuery({ queryKey: ['jobs'], queryFn: api.jobs })
  const [bots, setBots] = useState<string[]>(['casual', 'skilled'])
  const [runs, setRuns] = useState('400')
  const job = jobs.data?.find((j) => (j.status === 'running' || j.status === 'queued') && j.battle === s.battleId && j.variant === s.variant)
  const other = !job && jobs.data?.find((j) => j.status === 'running' || j.status === 'queued')
  const r = results.data
  const botKeys = Object.keys(r?.bots ?? {})
  useEffect(() => {
    // show a bot that actually has runs
    if (r && !r.bots[s.bot]?.runs) { const has = botKeys.find((b) => r.bots[b].runs); if (has && has !== s.bot) s.set({ bot: has }) }
  }, [r]) // eslint-disable-line react-hooks/exhaustive-deps
  const cur = r?.bots[s.bot]
  const errors = data.issues.filter((i) => i.level === 'error' && (i.where === `battles/${s.battleId}` || !i.where.startsWith('battles/')))
  const start = async () => {
    try { await api.startSim(s.battleId, s.variant, bots, Number(runs)); qc.invalidateQueries({ queryKey: ['jobs'] }) } catch (e) { fail(e) }
  }
  const heat = s.heat !== 'none' && cur?.heat ? cur.heat[s.heat] : null
  const heatEmpty = heat && Object.keys(heat).length === 0
  if (!battle) return null
  return (
    <>
      <main className="stage">
        <MapView cave={battle.cave} heights={battle.heights} terrain={battle.terrain} units={s.heat === 'none' ? toMapUnits(battle, data.units) : []} heat={heat} heatColor={s.heat !== 'none' ? HEAT[s.heat].color : undefined} heatUnit={s.heat !== 'none' ? HEAT[s.heat].unit : undefined}>
          <div className="hud-top">
            <div className="hud-title">
              <h1>{battle.title}</h1>
              <p>{s.heat === 'none' ? '起始布置' : `${HEAT[s.heat].help} · ${cur?.label ?? ''} ${cur?.runs ?? 0} 局`}</p>
            </div>
            <div className="hud-right">
              <SegmentedControl size="xs" value={s.heat} onChange={(v) => s.set({ heat: v as HeatLayer })}
                data={[{ value: 'none', label: '布置' }, ...Object.entries(HEAT).map(([k, v]) => ({ value: k, label: v.label }))]} />
            </div>
          </div>
          {s.heat !== 'none' && (!cur?.heat || heatEmpty) && (
            <div className="hud-notes"><div className="note warn"><span className="grow">{!cur?.heat ? '还没有模拟结果，先在右边运行模拟。' : '这批模拟里没有发生。'}</span></div></div>
          )}
        </MapView>
      </main>

      <aside className="side">
        <div className="section">
          <h3>运行模拟</h3>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <Chip.Group multiple value={bots} onChange={setBots}>
              <Chip size="xs" value="casual">普通机器人</Chip>
              <Chip size="xs" value="skilled">熟练机器人</Chip>
              <Chip size="xs" value="novice">新手机器人</Chip>
            </Chip.Group>
            <Select size="xs" w={104} aria-label="每个机器人的局数" allowDeselect={false} value={runs} onChange={(v) => v && setRuns(v)} data={['50', '100', '200', '400', '800'].map((n) => ({ value: n, label: `各 ${n} 局` }))} />
            {job ? (
              <Button size="xs" color="red" variant="light" leftSection={<IconPlayerStop size={15} />} onClick={() => api.cancelJob(job.id).catch(fail)}>停止</Button>
            ) : (
              <Button size="xs" leftSection={<IconPlayerPlay size={15} />} onClick={start} disabled={bots.length === 0 || errors.length > 0}>运行模拟</Button>
            )}
          </div>
          {errors.length > 0 && <p className="empty" style={{ margin: '8px 0 0', color: 'var(--bad)' }}>关卡还有 {errors.length} 个错误，先在「关卡」里修正：{errors[0].message}</p>}
          {job && (
            <div style={{ marginTop: 10 }}>
              <div style={{ height: 6, borderRadius: 3, background: 'var(--line-strong)', overflow: 'hidden' }}><div style={{ height: '100%', width: `${(100 * job.done) / job.total}%`, background: 'var(--gold)', transition: 'width .3s' }} /></div>
              <p className="empty" style={{ margin: '6px 0 0' }}>
                {job.status === 'queued' ? '排队中…' : `已完成 ${job.done}/${job.total} 局`}
                {job.done > 8 && job.elapsed > 0 ? `，大约还要 ${Math.max(1, Math.round(((job.total - job.done) * job.elapsed) / job.done / 60))} 分钟` : ''}
              </p>
            </div>
          )}
          {other && <p className="empty" style={{ margin: '8px 0 0' }}>另一个模拟（{other.battle} · {other.variant}）正在运行，新的会排在它后面。</p>}
          <div className="freshness">
            {botKeys.map((b) => {
              const x = r!.bots[b]
              return (
                <div key={b}>
                  <i className="dot" style={{ background: x.status === 'fresh' ? 'var(--good)' : x.status === 'stale' ? 'var(--bad)' : 'var(--muted)' }} />{x.label}：{FRESH[x.status]}{x.runs ? `（${x.runs} 局${x.meta?.by === 'ai' ? '，AI 运行' : ''}）` : ''}
                </div>
              )
            })}
          </div>
        </div>

        {r && <Verdicts results={r} battle={s.battleId} />}

        {r && botKeys.some((b) => r.bots[b].runs) && (
          <div className="section" style={{ borderBottom: 0, paddingBottom: 0 }}>
            <SegmentedControl fullWidth size="xs" value={s.bot} onChange={(v) => s.set({ bot: v })} data={botKeys.filter((b) => r.bots[b].runs).map((b) => ({ value: b, label: `${r.bots[b].label}的详细数据` }))} />
          </div>
        )}
        {cur?.runs ? <Detail r={cur} /> : null}
      </aside>
    </>
  )
}
