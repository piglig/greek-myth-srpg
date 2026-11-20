import { Button, SegmentedControl } from '@mantine/core'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { api, type StudioData } from './api'
import { fail } from './App'
import { glyph } from './MapView'
import { isBaseline, useStore } from './store'

const LABELS: Record<string, string> = {
  hp: '生命', max_hp: '生命上限', str: '力量', div: '神性', def: '防御', wil: '意志', move: '移动', jump: '跳跃', size: '体型',
  stagger_max: '破势槽', actions: '行动数', mult: '倍率', min_range: '最小射程', max_range: '最大射程',
  cooldown: '冷却', knockback: '击退', stagger: '破势值', aoe: '范围',
}
const ORDER = ['hp', 'str', 'div', 'def', 'wil', 'move', 'jump', 'size', 'mult', 'min_range', 'max_range', 'cooldown', 'knockback', 'stagger']

function NumTable({ table, rows, base, locked, onChange }: {
  table: string; rows: Record<string, any>; base: Record<string, any>; locked: boolean
  onChange: (id: string, key: string, value: number) => void
}) {
  const keys = [...new Set(Object.values(rows).flatMap((r) => Object.keys(r).filter((k) => typeof r[k] === 'number')))]
    .sort((a, b) => (ORDER.indexOf(a) + 100) % 100 - (ORDER.indexOf(b) + 100) % 100 || a.localeCompare(b))
  return (
    <div style={{ overflowX: 'auto' }}>
      <table className="grid-table">
        <thead><tr><th>{table === 'units' ? '单位' : '技能'}</th>{keys.map((k) => <th key={k} title={k}>{LABELS[k] ?? k}</th>)}</tr></thead>
        <tbody>
          {Object.entries(rows).map(([id, r]) => (
            <tr key={id}>
              <td className="name"><div className="name-cell">{table === 'units' && <span className="pawn">{glyph(r.name ?? id)}</span>}<div>{r.name ?? id}<small>{id}</small></div></div></td>
              {keys.map((k) => {
                const was = base[id]?.[k]
                const changed = typeof r[k] === 'number' && was !== r[k]
                return (
                  <td key={k}>
                    {typeof r[k] === 'number' ? (
                      <input
                        className={`cell-num${changed ? ' changed' : ''}`} type="number" step="any" disabled={locked} key={`${id}.${k}.${r[k]}`} defaultValue={r[k]}
                        title={changed ? `基线是 ${was ?? '无'}` : undefined} aria-label={`${r.name ?? id} ${LABELS[k] ?? k}`}
                        onBlur={(e) => { const v = Number(e.currentTarget.value); if (e.currentTarget.value !== '' && !Number.isNaN(v) && v !== r[k]) onChange(id, k, v); else e.currentTarget.value = String(r[k]) }}
                        onKeyDown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
                      />
                    ) : null}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function TablesMode({ data, onNewVariant }: { data: StudioData; onNewVariant: () => void }) {
  const s = useStore()
  const qc = useQueryClient()
  const [tab, setTab] = useState<'units' | 'skills'>('units')
  const baseline = useQuery({ queryKey: ['data', 'baseline'], queryFn: () => api.data('baseline') })
  const locked = isBaseline(s.variant)
  const rows = data[tab] as Record<string, any>
  const base = (baseline.data?.[tab] ?? rows) as Record<string, any>
  const change = async (id: string, key: string, value: number) => {
    const next = { ...rows, [id]: { ...rows[id], [key]: value } }
    try {
      await api.saveTable(s.variant, tab, next, `${rows[id].name ?? id} 的${LABELS[key] ?? key} ${rows[id][key]} → ${value}`)
      await qc.invalidateQueries({ queryKey: ['data', s.variant] })
      qc.invalidateQueries({ queryKey: ['variants'] })
    } catch (e) { fail(e); qc.invalidateQueries({ queryKey: ['data', s.variant] }) }
  }
  const issues = data.issues.filter((i) => i.where === tab)
  return (
    <main className="wide">
      <h2 className="h2">数值表</h2>
      <p className="lede">所有关卡共用这些数值。改完一格按回车或点别处就会保存到当前变体；和基线不同的格子带底色，鼠标停上去能看到基线值。</p>
      {locked && (
        <div className="note" style={{ maxWidth: 760 }}>
          <span className="grow">基线只读。新建一个变体再改数值。</span>
          <Button size="xs" onClick={onNewVariant}>新建变体</Button>
        </div>
      )}
      <SegmentedControl mb={16} mt={4} value={tab} onChange={(v) => setTab(v as 'units' | 'skills')} data={[{ value: 'units', label: `单位（${Object.keys(data.units).length}）` }, { value: 'skills', label: `技能（${Object.keys(data.skills).length}）` }]} />
      {issues.map((i, n) => <div key={n} className="note bad" style={{ maxWidth: 760 }}><span className="grow">{i.message}</span></div>)}
      <NumTable table={tab} rows={rows} base={base} locked={locked} onChange={change} />
    </main>
  )
}
