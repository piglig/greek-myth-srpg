import { Button } from '@mantine/core'
import { useQuery } from '@tanstack/react-query'
import { api, type StudioData, type Verdict } from './api'
import { fmt, Status } from './charts'
import { useStore } from './store'

export function CompareMode({ data }: { data: StudioData }) {
  const s = useStore()
  const battle = data.battles[s.battleId]
  const cmp = useQuery({ queryKey: ['compare', s.battleId], queryFn: () => api.compare(s.battleId), enabled: !!battle })
  const variants = useQuery({ queryKey: ['variants'], queryFn: api.variants })
  const cols = cmp.data ?? []
  const rows: Verdict[] = []
  for (const c of cols) for (const v of c.verdicts) if (!rows.some((r) => r.bot === v.bot && r.metric === v.metric)) rows.push(v)
  const cell = (variant: string, r: Verdict) => cols.find((c) => c.variant === variant)?.verdicts.find((v) => v.bot === r.bot && v.metric === r.metric)
  const base = cols.find((c) => c.variant === 'baseline')
  const botLabel: Record<string, string> = { casual: '普通', skilled: '熟练', novice: '新手' }
  if (!battle) return null
  return (
    <main className="wide">
      <h2 className="h2">{battle.title}：各版本对比</h2>
      <p className="lede">每一列是一个版本在同一套设计目标下的实测结果。箭头表示相对基线的变化。看中某个变体，就打开它继续改，或者直接采用为基线。</p>
      {cmp.isLoading && <p className="empty">正在读取…</p>}
      {cols.length > 0 && rows.length === 0 && <p className="empty">这个关卡还没有任何模拟结果。去「模拟分析」运行一次。</p>}
      {rows.length > 0 && (
        <div style={{ overflowX: 'auto' }}>
          <table className="grid-table cmp">
            <thead>
              <tr>
                <th>指标</th><th>目标</th>
                {cols.map((c) => {
                  const meta = variants.data?.find((v) => v.name === c.variant)
                  const n = Math.max(0, ...Object.values(c.bots).map((b) => b.runs))
                  const stale = Object.values(c.bots).some((b) => b.status === 'stale')
                  return (
                    <th key={c.variant} className={`variant${s.variant === c.variant ? ' current' : ''}`}>
                      {c.variant === 'baseline' ? '基线' : c.variant}
                      <small>{n ? `${n} 局${stale ? ' · 已过期' : ''}` : '未模拟'}{meta?.note ? ` · ${meta.note}` : ''}</small>
                    </th>
                  )
                })}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={`${r.bot}/${r.metric}`}>
                  <td className="name">{r.label}<small>{botLabel[r.bot] ?? r.bot}机器人</small></td>
                  <td className="v muted">{r.target ? `${fmt(r.target[0], r.pct)}–${fmt(r.target[1], r.pct)}` : '—'}</td>
                  {cols.map((c) => {
                    const v = cell(c.variant, r)
                    const b = base && c !== base ? cell('baseline', r) : undefined
                    const delta = v?.value != null && b?.value != null ? v.value - b.value : null
                    const shown = delta !== null && Math.abs(delta) >= (r.pct ? 0.005 : 0.05)
                    return (
                      <td key={c.variant} className="v">
                        {v && v.value !== null ? (
                          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                            <span style={{ minWidth: 44 }}>{fmt(v.value, r.pct)}</span>
                            <span className="muted" style={{ minWidth: 58, fontSize: 11 }}>{shown ? `${delta! > 0 ? '↑' : '↓'} ${r.pct ? `${Math.abs(Math.round(delta! * 100))} 点` : Math.abs(delta!).toFixed(1)}` : ''}</span>
                            <Status status={v.status} />
                          </div>
                        ) : <span className="muted">—</span>}
                      </td>
                    )
                  })}
                </tr>
              ))}
              <tr className="total">
                <td className="name">达标数</td><td />
                {cols.map((c) => {
                  const judged = c.verdicts.filter((v) => v.target && v.value !== null)
                  return <td key={c.variant} className="v">{judged.length ? `${judged.filter((v) => v.status === 'PASS').length} / ${judged.length}` : '—'}</td>
                })}
              </tr>
              <tr>
                <td /><td />
                {cols.map((c) => (
                  <td key={c.variant}>
                    <Button size="compact-xs" variant={s.variant === c.variant ? 'filled' : 'default'} onClick={() => s.set({ variant: c.variant, mode: 'sim' })}>{s.variant === c.variant ? '当前版本' : '打开'}</Button>
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      )}
    </main>
  )
}
