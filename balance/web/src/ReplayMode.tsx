import { ActionIcon, Button, NumberInput, SegmentedControl, Select, Slider } from '@mantine/core'
import { IconPlayerPause, IconPlayerPlay, IconPlayerSkipBack, IconPlayerTrackNext, IconPlayerTrackPrev } from '@tabler/icons-react'
import { useQuery } from '@tanstack/react-query'
import { useEffect, useMemo, useRef, useState } from 'react'
import { api, type StudioData } from './api'
import { MapView, type MapUnit } from './MapView'
import { useStore } from './store'

const RESULT: Record<string, string> = { win: '胜利', loss_hero: '主角倒下', loss_wipe: '全灭', timeout: '超时' }

export function ReplayMode({ data }: { data: StudioData }) {
  const s = useStore()
  const battle = data.battles[s.battleId]
  const results = useQuery({ queryKey: ['results', s.battleId, s.variant], queryFn: () => api.results(s.battleId, s.variant), enabled: !!battle })
  const bots = Object.entries(results.data?.bots ?? {})
  const table = results.data?.bots[s.bot]?.table ?? []
  const stale = results.data?.bots[s.bot]?.status === 'stale'
  useEffect(() => {
    const b = results.data?.bots
    if (b && !b[s.bot]?.runs) { const has = Object.keys(b).find((k) => b[k].runs); if (has && has !== s.bot) s.set({ bot: has }) }
  }, [results.data]) // eslint-disable-line react-hooks/exhaustive-deps
  const [filter, setFilter] = useState('all')
  const [manual, setManual] = useState<number | string>(0)
  const rows = table.filter((r) => filter === 'all' || (filter === 'win' ? r.result === 'win' : filter === 'loss' ? r.result !== 'win' : r.falls > 0))

  const seed = s.replaySeed
  const replay = useQuery({
    queryKey: ['replay', s.battleId, s.variant, s.bot, seed, data.hashes[s.battleId]],
    queryFn: () => api.replay(s.battleId, s.variant, s.bot, seed!),
    enabled: seed !== null && !!battle, staleTime: Infinity, retry: false,
  })
  const frames = replay.data?.frames ?? []
  const [at, setAt] = useState(0)
  const [playing, setPlaying] = useState(false)
  const [speed, setSpeed] = useState('1')
  useEffect(() => { setAt(0); setPlaying(false) }, [replay.data])
  useEffect(() => {
    if (!playing) return
    const t = window.setInterval(() => setAt((i) => { if (i >= frames.length - 1) { setPlaying(false); return i } return i + 1 }), 700 / Number(speed))
    return () => window.clearInterval(t)
  }, [playing, speed, frames.length])
  const current = useRef<HTMLLIElement>(null)
  useEffect(() => { current.current?.scrollIntoView({ block: 'nearest' }) }, [at])

  const frame = frames[at]
  const units: MapUnit[] = useMemo(() => {
    if (!frame) return []
    return Object.entries(frame.units).filter(([, u]) => !u.hidden).map(([id, u]) => ({
      id, name: u.name, team: u.team, pos: u.pos, size: u.size, facing: u.facing, hp: u.hp, maxHp: u.max_hp, alive: u.alive,
      marked: u.statuses.includes('marked'), held: u.grappled_by !== '',
    }))
  }, [frame])
  const name = (id: string) => frame?.units[id]?.name ?? ''
  if (!battle) return null
  return (
    <>
      <main className="stage">
        <MapView heights={battle.heights} terrain={battle.terrain} units={units} actor={frame?.actor || null} cave={frame?.cave ?? battle.cave}>
          <div className="hud-top">
            <div className="hud-title">
              <h1>{battle.title}</h1>
              <p>{replay.data ? `种子 ${replay.data.seed} · ${results.data?.bots[s.bot]?.label ?? s.bot} · ${RESULT[replay.data.result]} · 共 ${replay.data.rounds} 回合` : '回放'}</p>
            </div>
            {frame && <div className="hud-right"><span className="round-chip">第 {frame.round} 回合</span></div>}
          </div>
          <div className="hud-notes">
            {seed === null && <div className="note"><span className="grow">从右边选一局。同一个种子每次打出来都一样，可以反复看机器人和敌人每一步做了什么，判断问题出在设计还是出在机器人。</span></div>}
            {replay.isFetching && <div className="note"><span className="grow">正在用游戏规则重新打一遍这一局，约 10 秒…</span></div>}
            {replay.isError && <div className="note bad"><span className="grow">回放失败：{(replay.error as Error).message.slice(0, 300)}</span></div>}
          </div>
        </MapView>
        {frames.length > 0 && (
          <div className="transport">
            <ActionIcon variant="default" aria-label="回到开头" onClick={() => { setAt(0); setPlaying(false) }}><IconPlayerSkipBack size={16} /></ActionIcon>
            <ActionIcon variant="default" aria-label="上一步" onClick={() => setAt((i) => Math.max(0, i - 1))}><IconPlayerTrackPrev size={16} /></ActionIcon>
            <ActionIcon variant="filled" size="lg" aria-label={playing ? '暂停' : '播放'} onClick={() => { if (at >= frames.length - 1) setAt(0); setPlaying(!playing) }}>{playing ? <IconPlayerPause size={18} /> : <IconPlayerPlay size={18} />}</ActionIcon>
            <ActionIcon variant="default" aria-label="下一步" onClick={() => setAt((i) => Math.min(frames.length - 1, i + 1))}><IconPlayerTrackNext size={16} /></ActionIcon>
            <Slider style={{ flex: 1 }} min={0} max={frames.length - 1} value={at} onChange={(v) => { setAt(v); setPlaying(false) }} label={(v) => `第 ${frames[v]?.round} 回合 · 步 ${v}`} />
            <span className="mono muted" style={{ fontSize: 12 }}>{at}/{frames.length - 1}</span>
            <SegmentedControl size="xs" value={speed} onChange={setSpeed} data={[{ value: '0.5', label: '慢' }, { value: '1', label: '正常' }, { value: '3', label: '快' }]} />
          </div>
        )}
      </main>

      <aside className="side" style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div className="section">
          <h3>选一局</h3>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <Select size="xs" w={130} allowDeselect={false} value={s.bot} onChange={(v) => v && s.set({ bot: v, replaySeed: null })} data={bots.map(([k, v]) => ({ value: k, label: v.label }))} />
            <SegmentedControl size="xs" value={filter} onChange={setFilter} data={[{ value: 'all', label: '全部' }, { value: 'win', label: '胜' }, { value: 'loss', label: '负' }, { value: 'fall', label: '有坠落' }]} />
          </div>
          {stale && <p className="empty" style={{ margin: '8px 0 0', color: 'var(--bad)' }}>数据在这批模拟之后改过。回放按当前数据重打，结果可能和列表不一致；重新模拟后会对上。</p>}
        </div>
        <div style={{ flex: '0 1 240px', minHeight: 120, overflowY: 'auto', borderBottom: '1px solid var(--line)' }}>
          {table.length === 0 ? (
            <div className="section" style={{ border: 0 }}>
              <p className="empty" style={{ margin: '0 0 8px' }}>这个版本还没有模拟结果。可以先去「模拟分析」运行，或者直接指定一个种子：</p>
              <div style={{ display: 'flex', gap: 8 }}>
                <NumberInput size="xs" w={110} min={0} value={manual} onChange={setManual} aria-label="种子" />
                <Button size="xs" variant="default" onClick={() => s.set({ replaySeed: Number(manual) || 0 })}>回放这个种子</Button>
              </div>
            </div>
          ) : (
            <table className="runs">
              <thead><tr><th>种子</th><th>结果</th><th>回合</th><th>剩余生命</th><th>坠落</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.seed} aria-selected={seed === r.seed} onClick={() => s.set({ replaySeed: r.seed })} tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && s.set({ replaySeed: r.seed })}>
                    <td>{r.seed}</td>
                    <td><span className={`status ${r.result === 'win' ? 'PASS' : r.result === 'timeout' ? 'NO_DATA' : 'FAIL'}`}>{RESULT[r.result]}</span></td>
                    <td>{r.rounds}</td><td>{Math.round(r.hp * 100)}%</td><td>{r.falls || ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '10px 8px' }}>
          {frames.length === 0 ? <p className="empty" style={{ padding: '0 8px' }}>选中一局后，这里按顺序列出每一步发生了什么。点任意一步跳过去。</p> : (
            <ol className="log">
              {frames.map((f, i) => (
                <li key={i} ref={i === at ? current : undefined} aria-current={i === at} onClick={() => { setAt(i); setPlaying(false) }}>
                  <span className="rnd">{i === 0 || frames[i - 1].round !== f.round ? `R${f.round}` : ''}</span>
                  <span>
                    {i === 0 ? '起始布置' : f.lines.map((l, n) => <div key={n} className={l.startsWith('  ') ? 'sub' : undefined}>{l.trim()}</div>)}
                    {i > 0 && f.actor === '' && f.lines.length === 0 && name('')}
                  </span>
                </li>
              ))}
            </ol>
          )}
        </div>
      </aside>
    </>
  )
}
